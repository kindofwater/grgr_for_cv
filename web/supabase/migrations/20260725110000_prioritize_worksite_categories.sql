-- 목적: 방학 교외 국가근로가 목록 상단을 과도하게 차지하지 않도록 국가근로 모집 시기를 명시한다.
-- 상위 그룹: 학교근로 + 국가근로 학기 중(교내 포함). 하위 그룹: 국가근로 방학 교외.

alter table public.worksites
  add column if not exists national_work_term text;

alter table public.worksites
  drop constraint if exists worksites_national_work_term_check;

alter table public.worksites
  add constraint worksites_national_work_term_check
  check (
    national_work_term is null
    or (type = 'national' and national_work_term in ('semester', 'vacation'))
  );

-- 현재 교외 국가근로는 모두 방학형(C), 교내 국가근로는 학기 중형(B)으로 확정한다.
update public.worksites
set national_work_term = case
  when type = 'national' and location_type = 'off_campus' then 'vacation'
  when type = 'national' then 'semester'
  else null
end
where national_work_term is distinct from case
  when type = 'national' and location_type = 'off_campus' then 'vacation'
  when type = 'national' then 'semester'
  else null
end;

drop function if exists search_worksite_cards(text,text,int,int,text[],text[],text[],text[],text[],int[],int[],boolean[]);

create function search_worksite_cards(
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
as $$
  with rep as (
    select distinct on (p.worksite_id)
      p.worksite_id, p.preferred_track, p.eligible_degree, p.eligible_status, p.work_duration_type
    from postings p where p.deleted_at is null
    order by p.worksite_id, p.is_active desc, p.created_at desc
  ),
  ws_active as (
    select worksite_id, bool_or(is_active) as is_active, max(recruit_until) as recruit_until
    from postings where deleted_at is null group by worksite_id
  ),
  stats as (
    select worksite_id, count(*) as review_count,
           round(avg(score_recommend)::numeric,1) as avg_recommend,
           round(avg(score_work)::numeric,1) as avg_work, round(avg(score_growth)::numeric,1) as avg_growth,
           round(avg(score_vibe)::numeric,1) as avg_vibe, round(avg(score_flex)::numeric,1) as avg_flex,
           round(100.0 * count(*) filter (where score_recommend >= 4.0) / count(*))::int as recommend_rate
    from reviews where deleted_at is null and not is_blinded group by worksite_id
  ),
  ranked as (
    select w.id as worksite_id, w.organization_name, w.workplace_name, w.region, w.address,
           w.type, w.location_type, w.view_count, coalesce(a.is_active, false) as is_active, a.recruit_until,
           r.preferred_track, r.eligible_degree, r.eligible_status, r.work_duration_type,
           coalesce(s.review_count, 0) as review_count,
           s.avg_recommend, s.avg_work, s.avg_growth, s.avg_vibe, s.avg_flex, s.recommend_rate,
           case when w.type = 'national' and w.national_work_term = 'vacation' then 2 else 1 end as category_rank
    from worksites w
    join rep r on r.worksite_id = w.id
    left join ws_active a on a.worksite_id = w.id
    left join stats s on s.worksite_id = w.id
    where w.deleted_at is null
      and (auth.uid() is null or w.university_id = 0 or w.university_id = (
        select u.university_id from public.users u where u.id = auth.uid()
      ))
      and (p_query is null or p_query = '' or w.organization_name ilike '%' || p_query || '%' or w.workplace_name ilike '%' || p_query || '%')
      and (p_actives is null or coalesce(a.is_active, false) = any(p_actives))
      and (p_types is null or w.type = any(p_types::worksite_type_e[]))
      and (p_locations is null or w.location_type = any(p_locations::location_type_e[]))
      and (p_regions is null or w.location_type = 'on_campus' or w.region = any(p_regions))
      and (p_durations is null or r.work_duration_type = any(p_durations::duration_type_e[]))
      and (p_tracks is null or r.preferred_track = any(p_tracks))
      and (p_degrees is null or r.eligible_degree::int = any(p_degrees))
      and (p_statuses is null or r.eligible_status::int = any(p_statuses))
  )
  select worksite_id, organization_name, workplace_name, region, address, type, location_type, view_count,
         is_active, recruit_until, preferred_track, eligible_degree, eligible_status, work_duration_type,
         review_count, avg_recommend, avg_work, avg_growth, avg_vibe, avg_flex, recommend_rate,
         count(*) over() as total_count
  from ranked
  order by category_rank,
           case when p_sort = 'priority' then view_count end desc nulls last,
           case when p_sort = 'reviews' then review_count end desc nulls last,
           case when p_sort = 'recommend' then avg_recommend end desc nulls last,
           view_count desc nulls last, worksite_id
  limit least(greatest(coalesce(p_limit, 20), 0), 50)
  offset least(greatest(coalesce(p_offset, 0), 0), 10000);
$$;

grant execute on function search_worksite_cards(text,text,int,int,text[],text[],text[],text[],text[],int[],int[],boolean[]) to authenticated, anon;

create or replace function get_home_feed(p_types text[] default null, p_actives boolean[] default null)
returns jsonb language sql security definer set search_path = public
as $$
with
me as (
  select u.university_id, u.degree_program::text as degree, u.academic_status::text as status,
         u.grade, u.track, c.name as college, d.name as department, u.region
  from users u left join colleges c on c.id = u.college_id left join departments d on d.id = u.department_id
  where u.id = auth.uid()
),
rep as (
  select distinct on (p.worksite_id) p.worksite_id, p.preferred_track, p.preferred_college, p.preferred_dept,
         p.min_grade, p.eligible_degree, p.eligible_status, p.work_duration_type
  from postings p where p.deleted_at is null order by p.worksite_id, p.is_active desc, p.created_at desc
),
ws_active as (
  select p.worksite_id,
         bool_or(case when p.recruit_until is not null then p.recruit_until >= (now() at time zone 'Asia/Seoul')::date else coalesce(p.is_active, false) end) as is_active
  from postings p where p.deleted_at is null group by p.worksite_id
),
stats as (
  select worksite_id, count(*) as review_count, round(avg(score_recommend)::numeric, 1) as avg_score
  from reviews where deleted_at is null and not is_blinded group by worksite_id
),
joined as (
  select w.id as worksite_id, w.organization_name, w.workplace_name, w.region, w.type, w.location_type,
         w.view_count, w.national_work_term, coalesce(a.is_active, false) as is_active,
         r.preferred_track, r.preferred_college, r.preferred_dept, r.work_duration_type,
         r.eligible_degree, r.eligible_status, coalesce(s.review_count, 0) as review_count, s.avg_score,
         (
           m.university_id is null or (
             not (m.degree = 'undergrad' and r.eligible_degree = 1)
             and not (m.degree = 'graduate' and r.eligible_degree = 0)
             and not (m.status = 'enrolled' and r.eligible_status = 1)
             and not (m.status = 'leave' and r.eligible_status = 0)
             and not (r.min_grade is not null and m.grade < r.min_grade)
             and not (r.preferred_track is not null and r.preferred_track <> '' and r.preferred_track is distinct from m.track)
             and not (r.preferred_college is not null and r.preferred_college <> '' and r.preferred_college is distinct from m.college)
             and not (r.preferred_dept is not null and r.preferred_dept <> '' and r.preferred_dept is distinct from m.department)
             and not (w.region is not null and w.region <> '' and w.region is distinct from m.region)
           )
         ) as eligible,
         (case when r.preferred_dept is not null and r.preferred_dept = m.department then 3 else 0 end
          + case when r.preferred_college is not null and r.preferred_college = m.college then 2 else 0 end
          + case when r.preferred_track is not null and r.preferred_track = m.track then 2 else 0 end
          + case when w.region is not null and w.region = m.region then 1 else 0 end) as match_score
  from worksites w join rep r on r.worksite_id = w.id
  left join ws_active a on a.worksite_id = w.id left join stats s on s.worksite_id = w.id left join me m on true
  where w.deleted_at is null
    and (auth.uid() is null or w.university_id = 0 or w.university_id = (select university_id from me))
),
carded as (
  select j.*, case when j.type = 'national' and j.national_work_term = 'vacation' then 2 else 1 end as category_rank,
    jsonb_build_object(
      'worksite_id', j.worksite_id, 'organization_name', j.organization_name, 'workplace_name', j.workplace_name,
      'region', j.region, 'type', j.type, 'location_type', j.location_type, 'view_count', j.view_count,
      'is_active', j.is_active, 'preferred_track', j.preferred_track, 'preferred_college', j.preferred_college,
      'preferred_dept', j.preferred_dept, 'work_duration_type', j.work_duration_type,
      'eligible_degree', j.eligible_degree, 'eligible_status', j.eligible_status,
      'review_count', j.review_count, 'avg_score', j.avg_score
    ) as card
  from joined j
),
filtered as (
  select * from carded where (p_types is null or type = any(p_types::worksite_type_e[])) and (p_actives is null or is_active = any(p_actives))
),
hero_candidates as (
  select * from carded where avg_score is null or avg_score >= 4.0
)
select jsonb_build_object(
  'hero', (select card from hero_candidates order by category_rank, is_active desc, eligible desc, match_score desc, avg_score desc nulls last, view_count desc, worksite_id limit 1),
  'top_score', coalesce((select jsonb_agg(t.card order by t.category_rank, t.avg_score desc nulls last, t.review_count desc, t.view_count desc, t.worksite_id)
    from (select * from filtered order by category_rank, avg_score desc nulls last, review_count desc, view_count desc, worksite_id limit 10) t), '[]'::jsonb),
  'popular', coalesce((select jsonb_agg(t.card order by t.category_rank, t.view_count desc nulls last, t.worksite_id)
    from (select * from filtered order by category_rank, view_count desc nulls last, worksite_id limit 10) t), '[]'::jsonb),
  'most_reviewed', coalesce((select jsonb_agg(t.card order by t.category_rank, t.review_count desc, t.avg_score desc nulls last, t.view_count desc, t.worksite_id)
    from (select * from filtered order by category_rank, review_count desc, avg_score desc nulls last, view_count desc, worksite_id limit 10) t), '[]'::jsonb)
);
$$;

grant execute on function get_home_feed(text[], boolean[]) to authenticated, anon;
