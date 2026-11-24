-- 목적: 최근 인기도를 매시간 사전 계산해 홈 요청이 원본 조회 로그를 반복 집계하지 않게 한다.
-- 날짜: 2026-07-31 · 담당: 배경록
-- 최근 인기도를 홈 요청마다 계산하지 않고 매시간 사전 계산한다.
-- 원본 worksite_view_events는 중복 방지·재계산용으로 유지하고,
-- get_home_feed는 근무지별 캐시 점수 한 행만 읽는다.

begin;

create table if not exists public.worksite_popularity_scores (
  worksite_id integer primary key
    references public.worksites(id) on delete cascade,
  recent_view_score double precision not null default 0,
  calculated_at timestamptz not null default now(),
  check (recent_view_score >= 0)
);

alter table public.worksite_popularity_scores enable row level security;
revoke all on table public.worksite_popularity_scores
  from public, anon, authenticated;
grant select on table public.worksite_popularity_scores to service_role;

create or replace function public.refresh_worksite_popularity_scores()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_refreshed integer;
begin
  insert into public.worksite_popularity_scores (
    worksite_id,
    recent_view_score,
    calculated_at
  )
  select
    v.worksite_id,
    sum(power(
      0.5::double precision,
      extract(epoch from (now() - v.viewed_at)) / 604800.0
    )),
    now()
  from public.worksite_view_events v
  join public.worksites w on w.id = v.worksite_id
  where v.viewed_at >= now() - interval '30 days'
    and w.deleted_at is null
  group by v.worksite_id
  on conflict (worksite_id) do update
  set recent_view_score = excluded.recent_view_score,
      calculated_at = excluded.calculated_at;

  get diagnostics v_refreshed = row_count;

  -- 최근 30일 조회가 모두 만료됐거나 근무지가 삭제된 캐시만 제거한다.
  delete from public.worksite_popularity_scores s
  where not exists (
    select 1
    from public.worksite_view_events v
    join public.worksites w on w.id = v.worksite_id
    where v.worksite_id = s.worksite_id
      and v.viewed_at >= now() - interval '30 days'
      and w.deleted_at is null
  );

  return v_refreshed;
end
$$;

revoke execute on function public.refresh_worksite_popularity_scores()
  from public, anon, authenticated;
grant execute on function public.refresh_worksite_popularity_scores()
  to service_role;

-- 마이그레이션 적용 즉시 현재 조회 기록으로 캐시를 채운다.
select public.refresh_worksite_popularity_scores();

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
  left join public.worksite_popularity_scores v on v.worksite_id = w.id
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

-- 매시간 5분에 점수를 갱신한다. 홈 인기 순위의 최대 지연은 약 1시간이다.
select cron.schedule(
  'refresh-worksite-popularity-scores',
  '5 * * * *',
  $$select public.refresh_worksite_popularity_scores()$$
);

commit;
