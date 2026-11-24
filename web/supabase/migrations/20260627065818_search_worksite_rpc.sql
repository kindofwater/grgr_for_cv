-- 목적: 근장찾기 서버측 검색·정렬·페이징 RPC (worksite 단위 dedup + 점수집계 + 총개수). 드롭다운 제안 RPC 동봉.
-- 날짜: 2026-06-27 · 담당: <작업자 이름 기입>
-- 비고: 신규 함수 → DROP 불필요. recommend_rate는 score_recommend>=4.0 비율(get_worksite_score_cards와 동일 규칙).

create or replace function search_worksite_cards(
  p_query  text default null,
  p_sort   text default 'recommend',   -- 'recommend' | 'reviews'
  p_limit  int  default 20,
  p_offset int  default 0
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
  with rep as (                       -- 대표공고 1개/worksite (active 우선 → 최신)
    select distinct on (p.worksite_id)
      p.worksite_id, p.preferred_track, p.eligible_degree,
      p.eligible_status, p.work_duration_type
    from postings p
    where p.deleted_at is null
    order by p.worksite_id, p.is_active desc, p.created_at desc
  ),
  ws_active as (                       -- active 롤업(공고 하나라도 active면 true)
    select worksite_id, bool_or(is_active) as is_active
    from postings where deleted_at is null group by worksite_id
  ),
  stats as (                          -- 점수 집계
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
    join rep r           on r.worksite_id = w.id   -- 공고 있는 worksite만
    left join ws_active a on a.worksite_id = w.id
    left join stats s    on s.worksite_id = w.id
    where w.deleted_at is null
      and ( p_query is null or p_query = '' or
            w.organization_name ilike '%'||p_query||'%' or
            w.workplace_name    ilike '%'||p_query||'%' )
  )
  select *, count(*) over() as total_count
  from joined
  order by
    case when p_sort='reviews'   then review_count end desc nulls last,
    case when p_sort='recommend' then avg_recommend end desc nulls last,
    worksite_id                       -- tie-breaker: offset 페이징 경계 안정(행 중복/누락 방지)
  limit p_limit offset p_offset;
$$;

create or replace function search_worksite_suggestions(
  p_query text, p_limit int default 8
)
returns table(
  worksite_id int, organization_name varchar, workplace_name varchar,
  address text, region varchar
)
language sql
security definer
as $$
  select w.id, w.organization_name, w.workplace_name, w.address, w.region
  from worksites w
  where w.deleted_at is null
    and exists (select 1 from postings p
                where p.worksite_id = w.id and p.deleted_at is null)
    and ( w.organization_name ilike '%'||p_query||'%' or
          w.workplace_name    ilike '%'||p_query||'%' )
  order by w.organization_name, w.workplace_name
  limit p_limit;
$$;

grant execute on function search_worksite_cards(text, text, int, int) to authenticated;
grant execute on function search_worksite_suggestions(text, int) to authenticated;
