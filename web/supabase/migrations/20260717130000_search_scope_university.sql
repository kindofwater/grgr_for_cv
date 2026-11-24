-- 목적: 근장찾기 검색을 소속 대학으로 스코핑 — 로그인 유저는 자기 university_id 또는 0(공용)인
--       worksite만, 비로그인(anon)은 전체(PUBLIC_BROWSE — 소속이 없으므로 필터 불가).
--       university_id=0 공용 근무지는 아직 없지만 미리 허용해 둔다(추가 시 마이그레이션 불필요).
-- 날짜: 2026-07-17 · 담당: (푸시 담당자 기입)
-- 비고: search_worksite_cards 본문은 현행 최신(20260716180000 — location_type 지역 판정 + limit 상한)을
--       그대로 재현 + 대학 스코프 한 줄 추가. suggestions는 20260713172824판 + 같은 조건.
--       시그니처 동일 → create or replace(DROP 불필요), 기존 grant(cards: authenticated+anon /
--       suggestions: authenticated) 유지됨. security definer라 users 조회는 RLS 무관.
--       스코프 서브쿼리는 비상관이라 쿼리당 1회만 평가된다.

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
      -- 대학 스코프: 비로그인은 전체, 로그인은 자기 대학 + 공용(university_id=0)
      and ( auth.uid() is null
            or w.university_id = 0
            or w.university_id = (select u.university_id from public.users u where u.id = auth.uid()) )
      and ( p_query is null or p_query = '' or
            w.organization_name ilike '%'||p_query||'%' or
            w.workplace_name    ilike '%'||p_query||'%' )
      and (p_actives   is null or coalesce(a.is_active,false) = any(p_actives))
      and (p_types     is null or w.type          = any(p_types::worksite_type_e[]))
      and (p_locations is null or w.location_type = any(p_locations::location_type_e[]))
      and (p_regions   is null or w.location_type = 'on_campus' or w.region = any(p_regions))
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

-- ── 검색창 제안(자동완성)도 같은 스코프 — 같은 페이지의 같은 목록 개념 ──
-- 본문은 현행(20260713172824: limit 상한 + 최소 쿼리 길이 2) 그대로 + 스코프 한 줄.
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
    and ( auth.uid() is null
          or w.university_id = 0
          or w.university_id = (select u.university_id from public.users u where u.id = auth.uid()) )
    and exists (select 1 from postings p
                where p.worksite_id = w.id and p.deleted_at is null)
    and ( w.organization_name ilike '%'||p_query||'%' or
          w.workplace_name    ilike '%'||p_query||'%' )
  order by w.organization_name, w.workplace_name
  limit least(greatest(coalesce(p_limit, 8), 0), 20);
$$;
