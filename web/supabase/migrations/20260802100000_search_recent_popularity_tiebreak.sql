-- 목적: 근장찾기의 추천순·리뷰 많은 순 동점을 홈과 같은 최근 인기도로 정렬한다.
-- 날짜: 2026-08-02 · 담당: Codex
-- 주 정렬(category/recommend/reviews)은 유지하고 누적 조회수 보조 정렬만
-- 최근 30일·7일 반감기 캐시 점수로 교체한다. 최근 인기도까지 같으면 ID 순이다.

begin;

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
        p.source_closed_at, p.recruit_until, p.is_active
      ) desc,
      p.created_at desc
  ),
  ws_active as (
    select
      p.worksite_id,
      bool_or(public.posting_effective_active(
        p.source_closed_at, p.recruit_until, p.is_active
      )) as is_active,
      case
        when bool_or(
          p.source_closed_at is null
          and p.recruit_until is null
          and coalesce(p.is_active, false)
        ) then null
        else max(p.recruit_until) filter (where p.source_closed_at is null)
      end as recruit_until
    from public.postings p
    where p.deleted_at is null
    group by p.worksite_id
  ),
  stats as (
    select worksite_id, count(*) as review_count,
           round(avg(score_recommend)::numeric,1) as avg_recommend,
           round(avg(score_work)::numeric,1) as avg_work,
           round(avg(score_growth)::numeric,1) as avg_growth,
           round(avg(score_vibe)::numeric,1) as avg_vibe,
           round(avg(score_flex)::numeric,1) as avg_flex,
           round(100.0 * count(*) filter (where score_recommend >= 4.0)
             / count(*))::int as recommend_rate
    from public.reviews
    where deleted_at is null and not is_blinded
    group by worksite_id
  ),
  ranked as (
    select w.id as worksite_id, w.organization_name, w.workplace_name,
           w.region, w.address, w.type, w.location_type, w.view_count,
           coalesce(a.is_active, false) as is_active, a.recruit_until,
           r.preferred_track, r.eligible_degree, r.eligible_status,
           r.work_duration_type, coalesce(s.review_count, 0) as review_count,
           s.avg_recommend, s.avg_work, s.avg_growth, s.avg_vibe,
           s.avg_flex, s.recommend_rate,
           coalesce(pop.recent_view_score, 0.0) as recent_view_score,
           case when w.type = 'national' and w.national_work_term = 'vacation'
             then 2 else 1 end as category_rank
    from public.worksites w
    join rep r on r.worksite_id = w.id
    left join ws_active a on a.worksite_id = w.id
    left join stats s on s.worksite_id = w.id
    left join public.worksite_popularity_scores pop on pop.worksite_id = w.id
    where w.deleted_at is null
      and (
        auth.uid() is null or w.university_id = 0
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
  select worksite_id, organization_name, workplace_name, region, address,
         type, location_type, view_count, is_active, recruit_until,
         preferred_track, eligible_degree, eligible_status, work_duration_type,
         review_count, avg_recommend, avg_work, avg_growth, avg_vibe, avg_flex,
         recommend_rate, count(*) over() as total_count
  from ranked
  order by category_rank,
           case when p_sort = 'priority' then view_count end desc nulls last,
           case when p_sort = 'reviews' then review_count end desc nulls last,
           case when p_sort = 'recommend' then avg_recommend end desc nulls last,
           case when p_sort in ('reviews', 'recommend') then recent_view_score end desc nulls last,
           worksite_id
  limit least(greatest(coalesce(p_limit, 20), 0), 50)
  offset least(greatest(coalesce(p_offset, 0), 0), 10000);
$$;

grant execute on function public.search_worksite_cards(
  text,text,int,int,text[],text[],text[],text[],text[],int[],int[],boolean[]
) to authenticated, anon;

commit;
