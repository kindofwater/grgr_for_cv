-- 목적: 로그인 사용자의 근무지 조회를 KST 일자별 1회로 제한하고 최근 30일·7일 반감기 인기도를 도입한다.
-- 날짜: 2026-07-31 · 담당: 배경록
-- 근무지 조회를 사용자·근무지·KST 날짜별 1회만 인정하고,
-- 홈의 '많이 찾아본 근장'을 최근 30일·7일 반감기 점수로 정렬한다.
-- 기존 worksites.view_count는 누적 고유 일일 조회수 표시와 동점 정렬용으로 유지한다.

begin;

create table if not exists public.worksite_view_events (
  user_id uuid not null references public.users(id) on delete cascade,
  worksite_id integer not null references public.worksites(id) on delete cascade,
  viewed_on date not null,
  viewed_at timestamptz not null default now(),
  primary key (user_id, worksite_id, viewed_on)
);

create index if not exists worksite_view_events_recent_idx
  on public.worksite_view_events (viewed_at desc, worksite_id);

alter table public.worksite_view_events enable row level security;
revoke all on table public.worksite_view_events from public, anon, authenticated;
grant select, delete on table public.worksite_view_events to service_role;

create or replace function public.increment_worksite_view(p_worksite_id int)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_inserted integer;
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  -- 같은 사용자가 같은 근무지를 새로고침하거나 재방문해도 KST 하루 1회만 기록한다.
  insert into public.worksite_view_events (
    user_id,
    worksite_id,
    viewed_on,
    viewed_at
  )
  select
    v_uid,
    w.id,
    (now() at time zone 'Asia/Seoul')::date,
    now()
  from public.worksites w
  where w.id = p_worksite_id
    and w.deleted_at is null
  on conflict (user_id, worksite_id, viewed_on) do nothing;

  get diagnostics v_inserted = row_count;

  if v_inserted = 1 then
    update public.worksites
    set view_count = coalesce(view_count, 0) + 1,
        updated_at = now()
    where id = p_worksite_id
      and deleted_at is null;
  end if;
end
$$;

revoke execute on function public.increment_worksite_view(int)
  from public, anon;
grant execute on function public.increment_worksite_view(int)
  to authenticated;

create or replace function public.get_home_feed(
  p_types text[] default null,
  p_actives boolean[] default null
)
returns jsonb language sql security definer set search_path = public
as $$
with
me as (
  select viewer.user_id, u.university_id, u.degree_program::text as degree,
         u.academic_status::text as status, u.grade, u.track,
         c.name as college, d.name as department, u.region
  from (select auth.uid() as user_id) viewer
  left join public.users u on u.id = viewer.user_id
  left join public.colleges c on c.id = u.college_id
  left join public.departments d on d.id = u.department_id
),
rep as (
  select distinct on (p.worksite_id)
         p.worksite_id, p.preferred_track, p.preferred_college,
         p.preferred_dept, p.min_grade, p.eligible_degree,
         p.eligible_status, p.work_duration_type
  from public.postings p
  where p.deleted_at is null
  order by p.worksite_id,
    public.posting_effective_active(
      p.source_closed_at, p.recruit_until, p.is_active
    ) desc,
    p.created_at desc
),
ws_active as (
  select p.worksite_id,
         bool_or(public.posting_effective_active(
           p.source_closed_at, p.recruit_until, p.is_active
         )) as is_active
  from public.postings p
  where p.deleted_at is null
  group by p.worksite_id
),
stats as (
  select worksite_id, count(*) as review_count,
         round(avg(score_recommend)::numeric, 1) as avg_score
  from public.reviews
  where deleted_at is null and not is_blinded
  group by worksite_id
),
recent_views as (
  select v.worksite_id,
         sum(power(
           0.5::double precision,
           extract(epoch from (now() - v.viewed_at)) / 604800.0
         )) as recent_view_score
  from public.worksite_view_events v
  where v.viewed_at >= now() - interval '30 days'
  group by v.worksite_id
),
joined as (
  select w.id as worksite_id, w.organization_name, w.workplace_name,
         w.region, w.type, w.location_type, w.view_count,
         coalesce(v.recent_view_score, 0.0) as recent_view_score,
         w.national_work_term, coalesce(a.is_active, false) as is_active,
         r.preferred_track, r.preferred_college, r.preferred_dept,
         r.min_grade, r.work_duration_type,
         r.eligible_degree, r.eligible_status,
         coalesce(s.review_count, 0) as review_count, s.avg_score
  from public.worksites w
  join rep r on r.worksite_id = w.id
  left join ws_active a on a.worksite_id = w.id
  left join stats s on s.worksite_id = w.id
  left join recent_views v on v.worksite_id = w.id
  where w.deleted_at is null
    and (
      (select user_id from me) is null or w.university_id = 0
      or w.university_id = (select university_id from me)
    )
),
carded as (
  select j.*,
    case when j.type = 'national' and j.national_work_term = 'vacation'
      then 2 else 1 end as category_rank,
    jsonb_build_object(
      'worksite_id', j.worksite_id,
      'organization_name', j.organization_name,
      'workplace_name', j.workplace_name,
      'region', j.region, 'type', j.type,
      'location_type', j.location_type, 'view_count', j.view_count,
      'is_active', j.is_active, 'preferred_track', j.preferred_track,
      'preferred_college', j.preferred_college,
      'preferred_dept', j.preferred_dept,
      'work_duration_type', j.work_duration_type,
      'eligible_degree', j.eligible_degree,
      'eligible_status', j.eligible_status,
      'review_count', j.review_count, 'avg_score', j.avg_score
    ) as card
  from joined j
),
filtered as (
  select * from carded
  where (p_types is null or type = any(p_types::worksite_type_e[]))
    and (p_actives is null or is_active = any(p_actives))
),
hero_matched as (
  select c.*,
         (
           m.university_id is null or (
             not (m.degree = 'undergrad' and c.eligible_degree = 1)
             and not (m.degree = 'graduate' and c.eligible_degree = 0)
             and not (m.status = 'enrolled' and c.eligible_status = 1)
             and not (m.status = 'leave' and c.eligible_status = 0)
             and not (c.min_grade is not null and m.grade < c.min_grade)
           )
         ) as eligible,
         case
           when c.preferred_dept = m.department then 0.3
           when c.preferred_college = m.college then 0.2
           when c.preferred_track = m.track then 0.1
           else 0
         end
         + case when c.region = m.region then 0.1 else 0 end
         as match_bonus
  from carded c
  cross join me m
  where m.user_id is not null
),
hero_scored as (
  select h.*,
         case
           when h.avg_score is null then null
           else h.avg_score + h.match_bonus
         end as composite_score
  from hero_matched h
),
hero_candidates as (
  select *
  from hero_scored
  where eligible is not false
    and (avg_score is null or composite_score >= 4.0)
)
select jsonb_build_object(
  'hero', (select card from hero_candidates
    order by is_active desc,
             (avg_score is null),
             composite_score desc nulls last,
             case when avg_score is null then match_bonus end desc nulls last,
             review_count desc,
             view_count desc,
             worksite_id
    limit 1),
  'top_score', coalesce((select jsonb_agg(t.card order by t.category_rank,
      t.avg_score desc nulls last, t.review_count desc, t.view_count desc,
      t.worksite_id)
    from (select * from filtered order by category_rank,
      avg_score desc nulls last, review_count desc, view_count desc,
      worksite_id limit 10) t), '[]'::jsonb),
  'popular', coalesce((select jsonb_agg(t.card order by t.category_rank,
      t.recent_view_score desc, t.view_count desc, t.worksite_id)
    from (select * from filtered order by category_rank,
      recent_view_score desc, view_count desc, worksite_id limit 10) t),
      '[]'::jsonb),
  'most_reviewed', coalesce((select jsonb_agg(t.card order by t.category_rank,
      t.review_count desc, t.avg_score desc nulls last, t.view_count desc,
      t.worksite_id)
    from (select * from filtered order by category_rank, review_count desc,
      avg_score desc nulls last, view_count desc, worksite_id limit 10) t),
      '[]'::jsonb)
);
$$;

grant execute on function public.get_home_feed(text[], boolean[])
  to authenticated, anon;

-- 점수 계산에는 30일만 사용한다. 실험·감사를 위한 여유를 두고 90일 후 원본을 파기한다.
select cron.schedule(
  'purge-worksite-view-events',
  '45 4 * * *',
  $$delete from public.worksite_view_events where viewed_at < now() - interval '90 days'$$
);

commit;
