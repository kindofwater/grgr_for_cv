-- 목적: 리뷰 블라인드 처리 — reviews.is_blinded 플래그. true면 목록에 placeholder로 마스킹 노출 + 평균/추천/리뷰수 집계에서 제외.
-- 날짜: 2026-07-08 · 담당: 배경록(작성) / 현수(검토·db push)
-- 비고:
--   · 블라인드는 관리자 UI 없이 팀이 Supabase에서 reviews.is_blinded 를 직접 true로 set/false로 해제한다.
--   · deleted_at(삭제)과 별개 — 블라인드는 목록에 '블라인드 처리된 리뷰입니다' 슬롯으로 남되 내용·점수·작성자만 서버에서 가린다.
--   · list_worksite_reviews 는 반환 컬럼(is_blinded) 추가로 시그니처 변경 → DROP 먼저(규칙4). 나머지 집계 RPC는 시그니처 동일 → create or replace 만.
--   · 로컬 db reset(Docker) 불가 가능성 → SQL 리뷰 후 현수가 db push(규칙3 §3). push 전 디스코드 공유.

-- ── 1) 플래그 컬럼 ───────────────────────────────────────────────
alter table reviews add column if not exists is_blinded boolean not null default false;

-- ── 2) 리뷰 목록 RPC: is_blinded 반환 + 블라인드면 내용·점수·작성자·학기 서버 마스킹(원문 유출 차단) ──
--    비블라인드 행 동작은 기존과 100% 동일. work_year 는 정렬 안정성 위해 유지(민감정보 아님).
drop function if exists list_worksite_reviews(int);
create or replace function list_worksite_reviews(p_worksite_id int)
returns table (id int, work_year int, work_semester text, score_recommend numeric,
               score_work numeric, score_growth numeric, score_vibe numeric, score_flex numeric,
               work_content text, opinion text, is_anonymous boolean, helpful_count int,
               author_nickname text, created_at timestamptz, is_blinded boolean)
language sql security definer set search_path = public as $$
  select r.id, r.work_year,
         case when r.is_blinded or r.is_anonymous then null else r.work_semester end,
         case when r.is_blinded then null else r.score_recommend end,
         case when r.is_blinded then null else r.score_work end,
         case when r.is_blinded then null else r.score_growth end,
         case when r.is_blinded then null else r.score_vibe end,
         case when r.is_blinded then null else r.score_flex end,
         case when r.is_blinded then null else r.work_content end,
         case when r.is_blinded then null else r.opinion end,
         r.is_anonymous,
         case when r.is_blinded then 0 else r.helpful_count end,
         case when r.is_blinded then null
              when r.is_anonymous then '익명'
              else u.nickname end,
         r.created_at,
         r.is_blinded
  from reviews r left join users u on u.id = r.user_id
  where r.worksite_id = p_worksite_id and r.deleted_at is null
  order by r.created_at desc;
$$;  -- user_id를 반환하지 않음 → 익명 신원 노출 차단 (기존 유지)

revoke execute on function list_worksite_reviews(int) from anon, public;
grant  execute on function list_worksite_reviews(int) to authenticated;

-- ── 3) 집계 RPC 3개: 블라인드 리뷰를 평균/추천율/리뷰수에서 제외 (and not is_blinded 추가) ──

-- 3-1) 홈 리뷰 집계 (avg_score만)
create or replace function get_review_stats(worksite_ids int[])
returns table(
  worksite_id   int,
  avg_score     numeric,
  review_count  bigint
)
language sql
security definer
set search_path = public
as $$
  select
    worksite_id,
    round(avg(score_recommend)::numeric, 1) as avg_score,
    count(*)                                as review_count
  from reviews
  where worksite_id = any(worksite_ids)
    and deleted_at is null
    and not is_blinded
  group by worksite_id;
$$;

grant execute on function get_review_stats(int[]) to anon, authenticated;

-- 3-2) 근장찾기 카드용 항목별 평점·추천율 집계
create or replace function get_worksite_score_cards(worksite_ids int[])
returns table(
  worksite_id    int,
  review_count   bigint,
  avg_recommend  numeric,
  avg_work       numeric,
  avg_growth     numeric,
  avg_vibe       numeric,
  avg_flex       numeric,
  recommend_rate int
)
language sql
security definer
as $$
  select
    worksite_id,
    count(*)                                 as review_count,
    round(avg(score_recommend)::numeric, 1)  as avg_recommend,
    round(avg(score_work)::numeric, 1)       as avg_work,
    round(avg(score_growth)::numeric, 1)     as avg_growth,
    round(avg(score_vibe)::numeric, 1)       as avg_vibe,
    round(avg(score_flex)::numeric, 1)       as avg_flex,
    round(100.0 * count(*) filter (where score_recommend >= 4.0) / count(*))::int as recommend_rate
  from reviews
  where worksite_id = any(worksite_ids)
    and deleted_at is null
    and not is_blinded
  group by worksite_id;
$$;

grant execute on function get_worksite_score_cards(int[]) to anon, authenticated;

-- 3-3) 검색 카드 RPC (stats CTE에만 and not is_blinded 추가, 나머지 본문·시그니처 동일)
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
