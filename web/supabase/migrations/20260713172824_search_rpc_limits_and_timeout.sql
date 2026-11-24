-- 목적: 보안점검 M1 부분 조치(3·4) — 검색 RPC의 p_limit/p_offset 서버측 상한 + 제안 RPC 최소 쿼리 길이,
--       anon/authenticated 역할 statement_timeout(폭주 쿼리 강제 종료). 사전집계·pg_trgm(1·2)은 데이터 증가 시 후속.
-- 날짜: 2026-07-14 · 담당: (푸시 담당자 기입)

-- ── 1. statement_timeout — API 역할의 모든 쿼리에 3초 상한 ──
-- PostgREST가 역할 전환 시 role 설정을 적용하므로 REST/RPC 전부에 걸린다.
-- 검색뿐 아니라 해당 역할의 모든 쿼리에 적용되니, 느린 정상 쿼리가 생기면 이 값부터 의심할 것.
alter role anon          set statement_timeout = '3s';
alter role authenticated set statement_timeout = '3s';

-- ── 2. search_worksite_cards — limit/offset 서버 상한 ──
-- 본문은 현행(20260708110000_region_filter_national_only) 그대로, 마지막 limit/offset 한 줄만 변경.
-- 상한 근거: 클라 perPage 최대 50(Search.jsx 드롭다운). null 방어 필수 — limit null = 전체 반환.
-- 빈 검색어(전체 목록 브라우징)는 정상 기능이라 최소 쿼리 길이는 걸지 않는다(1글자 검색도 전체 목록보다 비싸지 않음).
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
    from reviews where deleted_at is null and not is_blinded group by worksite_id
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
      and (p_regions   is null or w.type <> 'national' or w.region = any(p_regions))
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
  limit  least(greatest(coalesce(p_limit, 20), 0), 50)
  offset least(greatest(coalesce(p_offset, 0), 0), 10000);
$$;

-- ── 3. search_worksite_suggestions — limit 상한 + 최소 쿼리 길이 2 ──
-- 본문은 현행(20260627065818) 그대로 + 두 줄 변경. 클라(SearchSuggest MIN_QUERY_LEN=2)와 동작 일치 —
-- 2글자 미만은 빈 결과(에러 아님). 클라 limit 8, 상한 20.
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
  where length(trim(coalesce(p_query,''))) >= 2
    and w.deleted_at is null
    and exists (select 1 from postings p
                where p.worksite_id = w.id and p.deleted_at is null)
    and ( w.organization_name ilike '%'||p_query||'%' or
          w.workplace_name    ilike '%'||p_query||'%' )
  order by w.organization_name, w.workplace_name
  limit least(greatest(coalesce(p_limit, 8), 0), 20);
$$;
