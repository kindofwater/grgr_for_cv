-- 목적: 근장찾기 모집상태를 저장 시점 is_active가 아니라 현재 마감일 기준으로 판정
-- 정책: recruit_until이 있으면 KST 오늘까지 모집중, 없으면 레거시 is_active로 폴백.
-- 배경: 2026-07-26 기준 Student Success Center가 7/24 마감 후에도 is_active=true라
--       '모집중만' 검색에 포함됐다. 홈 피드는 이미 같은 날짜 기준을 사용한다.

create or replace function search_worksite_cards(
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
    from postings p
    where p.deleted_at is null
    order by
      p.worksite_id,
      case
        when p.recruit_until is not null
          then p.recruit_until >= (now() at time zone 'Asia/Seoul')::date
        else coalesce(p.is_active, false)
      end desc,
      p.created_at desc
  ),
  ws_active as (
    select
      p.worksite_id,
      bool_or(
        case
          when p.recruit_until is not null
            then p.recruit_until >= (now() at time zone 'Asia/Seoul')::date
          else coalesce(p.is_active, false)
        end
      ) as is_active,
      -- recruit_until=NULL인 레거시 활성 공고가 하나라도 있으면 반환도 NULL로 두어
      -- 프론트 effectiveActive가 같은 is_active 폴백을 사용하게 한다.
      case
        when bool_or(p.recruit_until is null and coalesce(p.is_active, false)) then null
        else max(p.recruit_until)
      end as recruit_until
    from postings p
    where p.deleted_at is null
    group by p.worksite_id
  ),
  stats as (
    select worksite_id, count(*) as review_count,
           round(avg(score_recommend)::numeric,1) as avg_recommend,
           round(avg(score_work)::numeric,1) as avg_work, round(avg(score_growth)::numeric,1) as avg_growth,
           round(avg(score_vibe)::numeric,1) as avg_vibe, round(avg(score_flex)::numeric,1) as avg_flex,
           round(100.0 * count(*) filter (where score_recommend >= 4.0) / count(*))::int as recommend_rate
    from reviews
    where deleted_at is null and not is_blinded
    group by worksite_id
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
      and (
        auth.uid() is null
        or w.university_id = 0
        or w.university_id = (
          select u.university_id from public.users u where u.id = auth.uid()
        )
      )
      and (
        p_query is null or p_query = ''
        or w.organization_name ilike '%' || p_query || '%'
        or w.workplace_name ilike '%' || p_query || '%'
      )
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
           view_count desc nulls last,
           worksite_id
  limit least(greatest(coalesce(p_limit, 20), 0), 50)
  offset least(greatest(coalesce(p_offset, 0), 0), 10000);
$$;

grant execute on function search_worksite_cards(
  text,text,int,int,text[],text[],text[],text[],text[],int[],int[],boolean[]
) to authenticated, anon;
