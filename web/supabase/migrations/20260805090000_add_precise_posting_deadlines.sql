-- 날짜만 있던 모집 마감에 선택적인 정확한 시각을 추가한다.
-- 기존 공고는 recruit_until_at=NULL이므로 기존 KST 날짜 판정이 그대로 유지된다.

begin;

alter table public.postings
  add column if not exists recruit_until_at timestamptz;

comment on column public.postings.recruit_until_at is
  '정확한 모집 마감 순간. NULL이면 recruit_until(date) 또는 is_active로 폴백한다.';

-- postings는 테이블 SELECT를 회수하고 공개 가능한 컬럼만 따로 허용한다.
grant select (recruit_until_at) on table public.postings to anon, authenticated;

-- 3인자 레거시 함수는 기존 마이그레이션·호출자 호환을 위해 유지하고,
-- 시각을 받는 4인자 함수를 새 정본으로 사용한다.
create or replace function public.posting_effective_active(
  p_source_closed_at date,
  p_recruit_until date,
  p_recruit_until_at timestamptz,
  p_is_active boolean
)
returns boolean
language sql stable
set search_path = public
as $$
  select case
    when p_source_closed_at is not null then false
    when p_recruit_until_at is not null then now() < p_recruit_until_at
    when p_recruit_until is not null
      then p_recruit_until >= (now() at time zone 'Asia/Seoul')::date
    else coalesce(p_is_active, false)
  end
$$;

revoke all on function public.posting_effective_active(date, date, timestamptz, boolean)
  from public, anon, authenticated;

create or replace function public.posting_effective_active(
  p_source_closed_at date,
  p_recruit_until date,
  p_is_active boolean
)
returns boolean
language sql stable
set search_path = public
as $$
  select public.posting_effective_active(
    p_source_closed_at, p_recruit_until, null::timestamptz, p_is_active
  )
$$;

revoke all on function public.posting_effective_active(date, date, boolean)
  from public, anon, authenticated;

-- 공개 상세도 같은 서버 시각 판정을 사용하고 클라이언트에 정확한 마감 시각을 전달한다.
create or replace function public.get_worksite_public_detail(p_worksite_id int)
returns table (worksite jsonb, postings jsonb)
language sql security definer set search_path = public
as $$
  with ps as (
    select ranked.*
    from (
      select p.*,
             public.posting_effective_active(
               p.source_closed_at, p.recruit_until, p.recruit_until_at, p.is_active
             ) as effective_active
      from public.postings p
      where p.worksite_id = p_worksite_id
        and p.deleted_at is null
    ) ranked
    order by ranked.effective_active desc, ranked.created_at desc
    limit 30
  )
  select
    jsonb_build_object(
      'organization_name', w.organization_name,
      'workplace_name',    w.workplace_name,
      'type',              w.type,
      'location_type',     w.location_type,
      'address',           w.address,
      'region',            w.region
    ) as worksite,
    coalesce(
      (select jsonb_agg(
         jsonb_build_object(
           'id',                      ps.id,
           'source',                  ps.source,
           'title',                   ps.title,
           'is_active',               ps.effective_active,
           'is_placeholder',          ps.is_placeholder,
           'recruit_until',           ps.recruit_until,
           'recruit_until_at',        ps.recruit_until_at,
           'recruit_until_estimated', ps.recruit_until_estimated,
           'preferred_track',         ps.preferred_track,
           'min_grade',               ps.min_grade,
           'eligible_degree',         ps.eligible_degree,
           'eligible_status',         ps.eligible_status,
           'recruitment_period_text', ps.recruitment_period_text,
           'recruit_count',           ps.recruit_count,
           'hourly_wage',             ps.hourly_wage,
           'work_period_text',        ps.work_period_text,
           'work_time_text',          ps.work_time_text,
           'work_location',           ps.work_location,
           'job_description',         ps.job_description,
           'preference_notes',        ps.preference_notes,
           'extra_notes',             ps.extra_notes,
           'source_url',              ps.source_url
         )
         order by ps.effective_active desc, ps.created_at desc
       ) from ps),
      '[]'::jsonb
    ) as postings
  from public.worksites w
  where w.id = p_worksite_id and w.deleted_at is null;
$$;

revoke execute on function public.get_worksite_public_detail(int) from public;
grant execute on function public.get_worksite_public_detail(int)
  to anon, authenticated;

-- 최종 검색 정렬(20260804140000)은 유지하고 모집 상태 계산만 시각 대응으로 교체한다.
create or replace function public.search_worksite_cards(
  p_query text default null, p_sort text default 'priority', p_limit int default 20, p_offset int default 0,
  p_types text[] default null, p_locations text[] default null, p_regions text[] default null,
  p_durations text[] default null, p_tracks text[] default null, p_degrees int[] default null,
  p_statuses int[] default null, p_actives boolean[] default null
)
returns table(
  worksite_id int, organization_name varchar, workplace_name varchar, region varchar, address text,
  type worksite_type_e, location_type location_type_e, view_count int, is_active boolean, recruit_until date,
  preferred_track varchar, eligible_degree smallint, eligible_status smallint, work_duration_type duration_type_e,
  review_count bigint, avg_recommend numeric, avg_work numeric, avg_growth numeric, avg_vibe numeric,
  avg_flex numeric, recommend_rate int, total_count bigint
)
language sql security definer
set search_path = public
as $$
  with rep as (
    select distinct on (p.worksite_id)
      p.worksite_id, p.preferred_track, p.eligible_degree,
      p.eligible_status, p.work_duration_type
    from public.postings p
    where p.deleted_at is null
    order by p.worksite_id,
      public.posting_effective_active(
        p.source_closed_at, p.recruit_until, p.recruit_until_at, p.is_active
      ) desc,
      p.created_at desc
  ),
  ws_active as (
    select p.worksite_id,
      bool_or(public.posting_effective_active(
        p.source_closed_at, p.recruit_until, p.recruit_until_at, p.is_active
      )) as is_active,
      case when bool_or(p.recruit_until_at is not null)
        then null
        when bool_or(
          p.source_closed_at is null and p.recruit_until is null
          and coalesce(p.is_active, false)
        )
        then null
        else max(p.recruit_until) filter (where p.source_closed_at is null)
      end as recruit_until
    from public.postings p
    where p.deleted_at is null
    group by p.worksite_id
  ),
  stats as (
    select worksite_id, count(*) as review_count,
      round(avg(score_recommend)::numeric, 1) as avg_recommend,
      round(avg(score_work)::numeric, 1) as avg_work,
      round(avg(score_growth)::numeric, 1) as avg_growth,
      round(avg(score_vibe)::numeric, 1) as avg_vibe,
      round(avg(score_flex)::numeric, 1) as avg_flex,
      round(100.0 * count(*) filter (where score_recommend >= 4.0) / count(*))::int as recommend_rate
    from public.reviews
    where deleted_at is null and not is_blinded
    group by worksite_id
  ),
  ranked as (
    select w.id as worksite_id, w.organization_name, w.workplace_name,
      w.region, w.address, w.type, w.location_type, w.view_count,
      coalesce(a.is_active, false) as is_active, a.recruit_until,
      r.preferred_track, r.eligible_degree, r.eligible_status, r.work_duration_type,
      coalesce(s.review_count, 0) as review_count,
      s.avg_recommend, s.avg_work, s.avg_growth, s.avg_vibe, s.avg_flex, s.recommend_rate,
      coalesce(pop.recent_view_score, 0.0) as recent_view_score,
      case when w.type = 'national' and w.national_work_term = 'vacation'
             and w.location_type = 'off_campus' then 1 else 0 end as vacation_national_offcampus_tiebreak
    from public.worksites w
    join rep r on r.worksite_id = w.id
    left join ws_active a on a.worksite_id = w.id
    left join stats s on s.worksite_id = w.id
    left join public.worksite_popularity_scores pop on pop.worksite_id = w.id
    where w.deleted_at is null
      and (auth.uid() is null or w.university_id = 0 or w.university_id = (
        select u.university_id from public.users u where u.id = auth.uid()
      ))
      and (p_query is null or p_query = '' or w.organization_name ilike '%' || p_query || '%'
        or w.workplace_name ilike '%' || p_query || '%')
      and (p_actives is null or coalesce(a.is_active, false) = any(p_actives))
      and (p_types is null or w.type = any(p_types::worksite_type_e[]))
      and (p_locations is null or w.location_type = any(p_locations::location_type_e[]))
      and (p_regions is null or w.location_type = 'on_campus' or w.region = any(p_regions))
      and (p_durations is null or r.work_duration_type = any(p_durations::duration_type_e[]))
      and (p_tracks is null or r.preferred_track = any(p_tracks))
      and (p_degrees is null or r.eligible_degree::int = any(p_degrees))
      and (p_statuses is null or r.eligible_status::int = any(p_statuses))
  )
  select worksite_id, organization_name, workplace_name, region, address,
    type, location_type, view_count, is_active, recruit_until,
    preferred_track, eligible_degree, eligible_status, work_duration_type,
    review_count, avg_recommend, avg_work, avg_growth, avg_vibe, avg_flex,
    recommend_rate, count(*) over() as total_count
  from ranked
  order by
    case when p_sort = 'priority' then view_count end desc nulls last,
    case when p_sort = 'reviews' then review_count end desc nulls last,
    case when p_sort = 'recommend' then avg_recommend end desc nulls last,
    case when p_sort in ('reviews', 'recommend') then recent_view_score end desc nulls last,
    vacation_national_offcampus_tiebreak,
    worksite_id
  limit least(greatest(coalesce(p_limit, 20), 0), 50)
  offset least(greatest(coalesce(p_offset, 0), 0), 10000);
$$;

-- 최종 홈 정렬(20260804140000)도 그대로 두고 상태 판정만 교체한다.
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
    p.worksite_id, p.preferred_track, p.preferred_college, p.preferred_dept,
    p.min_grade, p.eligible_degree, p.eligible_status, p.work_duration_type
  from public.postings p
  where p.deleted_at is null
  order by p.worksite_id,
    public.posting_effective_active(
      p.source_closed_at, p.recruit_until, p.recruit_until_at, p.is_active
    ) desc,
    p.created_at desc
),
ws_active as (
  select p.worksite_id,
    bool_or(public.posting_effective_active(
      p.source_closed_at, p.recruit_until, p.recruit_until_at, p.is_active
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
    coalesce(a.is_active, false) as is_active,
    r.preferred_track, r.preferred_college, r.preferred_dept, r.min_grade,
    r.work_duration_type, r.eligible_degree, r.eligible_status,
    coalesce(s.review_count, 0) as review_count, s.avg_score,
    case when w.type = 'national' and w.national_work_term = 'vacation'
           and w.location_type = 'off_campus' then 1 else 0 end as vacation_national_offcampus_tiebreak
  from public.worksites w
  join rep r on r.worksite_id = w.id
  left join ws_active a on a.worksite_id = w.id
  left join stats s on s.worksite_id = w.id
  left join public.worksite_popularity_scores v on v.worksite_id = w.id
  where w.deleted_at is null
    and ((select user_id from me) is null or w.university_id = 0
      or w.university_id = (select university_id from me))
),
carded as (
  select j.*, jsonb_build_object(
    'worksite_id', j.worksite_id,
    'organization_name', j.organization_name,
    'workplace_name', j.workplace_name,
    'region', j.region, 'type', j.type,
    'location_type', j.location_type, 'view_count', j.view_count,
    'is_active', j.is_active, 'preferred_track', j.preferred_track,
    'preferred_college', j.preferred_college, 'preferred_dept', j.preferred_dept,
    'work_duration_type', j.work_duration_type,
    'eligible_degree', j.eligible_degree, 'eligible_status', j.eligible_status,
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
    (m.university_id is null or (
      not (m.degree = 'undergrad' and c.eligible_degree = 1)
      and not (m.degree = 'graduate' and c.eligible_degree = 0)
      and not (m.status = 'enrolled' and c.eligible_status = 1)
      and not (m.status = 'leave' and c.eligible_status = 0)
      and not (c.min_grade is not null and m.grade < c.min_grade)
    )) as eligible,
    case when c.preferred_dept = m.department then 0.3
      when c.preferred_college = m.college then 0.2
      when c.preferred_track = m.track then 0.1 else 0 end
    + case when c.region = m.region then 0.1 else 0 end as match_bonus
  from carded c
  cross join me m
  where m.user_id is not null
),
hero_scored as (
  select h.*, case when h.avg_score is null then null else h.avg_score + h.match_bonus end as composite_score
  from hero_matched h
),
hero_candidates as (
  select * from hero_scored
  where eligible is not false and (avg_score is null or composite_score >= 4.0)
)
select jsonb_build_object(
  'hero', (select card from hero_candidates
    order by is_active desc, (avg_score is null), composite_score desc nulls last,
      case when avg_score is null then match_bonus end desc nulls last,
      review_count desc, view_count desc, vacation_national_offcampus_tiebreak, worksite_id
    limit 1),
  'top_score', coalesce((select jsonb_agg(t.card order by t.avg_score desc nulls last,
      t.review_count desc, t.view_count desc, t.vacation_national_offcampus_tiebreak, t.worksite_id)
    from (select * from filtered order by avg_score desc nulls last, review_count desc,
      view_count desc, vacation_national_offcampus_tiebreak, worksite_id limit 10) t), '[]'::jsonb),
  'popular', coalesce((select jsonb_agg(t.card order by t.recent_view_score desc,
      t.view_count desc, t.vacation_national_offcampus_tiebreak, t.worksite_id)
    from (select * from filtered order by recent_view_score desc, view_count desc,
      vacation_national_offcampus_tiebreak, worksite_id limit 10) t), '[]'::jsonb),
  'most_reviewed', coalesce((select jsonb_agg(t.card order by t.review_count desc,
      t.avg_score desc nulls last, t.view_count desc, t.vacation_national_offcampus_tiebreak, t.worksite_id)
    from (select * from filtered order by review_count desc, avg_score desc nulls last,
      view_count desc, vacation_national_offcampus_tiebreak, worksite_id limit 10) t), '[]'::jsonb)
);
$$;

grant execute on function public.search_worksite_cards(
  text,text,int,int,text[],text[],text[],text[],text[],int[],int[],boolean[]
) to authenticated, anon;

grant execute on function public.get_home_feed(text[], boolean[])
  to authenticated, anon;

commit;
