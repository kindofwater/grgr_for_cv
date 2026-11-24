-- 목적: 근장찾기 고급검색에 모집상태(모집중/모집완료) 필터 추가 — search_worksite_cards에 p_actives boolean[] 인자
-- 날짜: 2026-06-30 · 담당: <이름>
-- 비고: 시그니처 변경(인자 추가) → 옛 11인자 함수 DROP 먼저. p_actives는 is_active 롤업(공고 하나라도 active면 모집중) 기준. null이면 무시.

drop function if exists search_worksite_cards(text, text, int, int, text[], text[], text[], text[], text[], int[], int[]);

create or replace function search_worksite_cards(
  p_query  text default null,
  p_sort   text default 'recommend',
  p_limit  int  default 20,
  p_offset int  default 0,
  p_types     text[] default null,
  p_locations text[] default null,
  p_regions   text[] default null,
  p_durations text[] default null,
  p_tracks    text[] default null,
  p_degrees   int[]  default null,
  p_statuses  int[]  default null,
  p_actives   boolean[] default null
)
returns table(
  worksite_id        int,
  organization_name  varchar,
  workplace_name     varchar,
  region             varchar,
  address            text,
  type               worksite_type_e,
  location_type      location_type_e,
  view_count         int,
  is_active          boolean,
  preferred_track    varchar,
  eligible_degree    smallint,
  eligible_status    smallint,
  work_duration_type duration_type_e,
  review_count       bigint,
  avg_recommend      numeric,
  avg_work           numeric,
  avg_growth         numeric,
  avg_vibe           numeric,
  avg_flex           numeric,
  recommend_rate     int,
  total_count        bigint
)
language sql
security definer
as $$
  with rep as (
    select distinct on (p.worksite_id)
      p.worksite_id, p.preferred_track, p.eligible_degree,
      p.eligible_status, p.work_duration_type
    from postings p
    where p.deleted_at is null
    order by p.worksite_id, p.is_active desc, p.created_at desc
  ),
  ws_active as (
    select worksite_id, bool_or(is_active) as is_active
    from postings where deleted_at is null group by worksite_id
  ),
  stats as (
    select worksite_id,
           count(*) as review_count,
           round(avg(score_recommend)::numeric,1) as avg_recommend,
           round(avg(score_work)::numeric,1)      as avg_work,
           round(avg(score_growth)::numeric,1)    as avg_growth,
           round(avg(score_vibe)::numeric,1)      as avg_vibe,
           round(avg(score_flex)::numeric,1)      as avg_flex,
           round(100.0*count(*) filter (where score_recommend>=4.0)/count(*))::int as recommend_rate
    from reviews where deleted_at is null group by worksite_id
  ),
  joined as (
    select w.id as worksite_id, w.organization_name, w.workplace_name,
           w.region, w.address, w.type, w.location_type, w.view_count,
           coalesce(a.is_active,false) as is_active,
           r.preferred_track, r.eligible_degree, r.eligible_status, r.work_duration_type,
           coalesce(s.review_count,0) as review_count,
           s.avg_recommend, s.avg_work, s.avg_growth, s.avg_vibe, s.avg_flex, s.recommend_rate
    from worksites w
    join rep r           on r.worksite_id = w.id
    left join ws_active a on a.worksite_id = w.id
    left join stats s    on s.worksite_id = w.id
    where w.deleted_at is null
      and ( p_query is null or p_query = '' or
            w.organization_name ilike '%'||p_query||'%' or
            w.workplace_name    ilike '%'||p_query||'%' )
      and (p_actives   is null or coalesce(a.is_active,false) = any(p_actives))
      and (p_types     is null or w.type          = any(p_types::worksite_type_e[]))
      and (p_locations is null or w.location_type = any(p_locations::location_type_e[]))
      and (p_regions   is null or w.region        = any(p_regions))
      and (p_durations is null or r.work_duration_type = any(p_durations::duration_type_e[]))
      and (p_tracks    is null or r.preferred_track     = any(p_tracks))
      and (p_degrees   is null or r.eligible_degree::int = any(p_degrees))
      and (p_statuses  is null or r.eligible_status::int = any(p_statuses))
  )
  select *, count(*) over() as total_count
  from joined
  order by
    case when p_sort='reviews'   then review_count end desc nulls last,
    case when p_sort='recommend' then avg_recommend end desc nulls last,
    worksite_id
  limit p_limit offset p_offset;
$$;

grant execute on function search_worksite_cards(text,text,int,int,text[],text[],text[],text[],text[],int[],int[],boolean[]) to authenticated;
