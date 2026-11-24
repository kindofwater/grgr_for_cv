-- 목적: 비로그인·무열람권에게 최신 리뷰 '첫 줄'만 서버에서 잘라 공개(티저) + list_worksite_reviews 서버 열람권 게이팅(debt#3)
-- 날짜: 2026-07-16 · 담당: 배경록

-- 배경: 지금 비로그인은 리뷰가 0자(로그인 유도 문구만) → 애드센스 "too little text".
--   무열람권 로그인 사용자는 반대로 본문 전체가 DOM에 실린 뒤 CSS 블러만 걸림(debt#3 = 마스킹 연극).
--   이 마이그레이션으로 둘 다 "서버가 첫 줄만 준다"로 통일한다. 절단은 반드시 서버에서 — 프론트에서
--   자르면 전체 본문이 DOM에 남아 애드센스에도 무의미하고 유료화도 뚫린다.

-- ── 1) 티저 RPC (신규 · anon 허용) ────────────────────────────────
-- 최신 비블라인드 리뷰 1건의 '첫 줄'만 60자로 절단해 반환. 그 외(점수·작성자·나머지 본문)는 일절 미반환.
-- 첫 줄 = 첫 개행 전까지. 개행이 없으면 본문 전체가 후보가 되므로 반드시 left()로 한 번 더 절단한다.
drop function if exists get_worksite_review_teaser(int);
create or replace function get_worksite_review_teaser(p_worksite_id int)
returns table (teaser text, is_truncated boolean)
language sql stable security definer set search_path = public as $$
  with latest as (
    -- work_content(업무 내용)가 카드 첫 섹션. 비어 있으면 opinion으로 폴백.
    select coalesce(nullif(btrim(r.work_content), ''), nullif(btrim(r.opinion), '')) as body
    from reviews r
    where r.worksite_id = p_worksite_id
      and r.deleted_at is null
      and not r.is_blinded
      and coalesce(nullif(btrim(r.work_content), ''), nullif(btrim(r.opinion), '')) is not null
    order by r.created_at desc
    limit 1
  ),
  firstline as (
    select body,
           btrim(split_part(replace(body, E'\r\n', E'\n'), E'\n', 1)) as line
    from latest
  )
  select
    left(line, 60) as teaser,
    -- 첫 줄이 60자를 넘었거나(=잘림), 첫 줄 뒤에 더 있는 경우(=다른 줄/섹션 존재)
    (length(line) > 60 or length(body) > length(line)) as is_truncated
  from firstline;
$$;

revoke execute on function get_worksite_review_teaser(int) from public;
grant  execute on function get_worksite_review_teaser(int) to anon, authenticated;

-- ── 2) list_worksite_reviews 서버 게이팅 (debt#3) ─────────────────
-- 반환 컬럼·인자 동일 → 시그니처 불변이라 DROP 불필요(규칙4 해당 없음). 본문 로직만 교체.
-- 열람권(users.pass_expires_at > now())이 없으면 0행. 단 본인이 쓴 리뷰는 열람권과 무관하게 보임
-- (마이페이지 수정 진입·본인 글 확인 경로 보존). 비블라인드 행의 기존 마스킹 규칙은 그대로 유지.
-- ⚠️ 배포 순서: 이 RPC가 먼저 올라가고 프론트가 아직 옛 버전이면, 무열람권 로그인 사용자의 상세에서
--   블러 리뷰 대신 '리뷰 없음'이 잠깐 보인다. db push와 prod 프론트 배포를 같이 할 것.
create or replace function list_worksite_reviews(p_worksite_id int)
returns table (id int, work_year int, work_semester text, score_recommend numeric,
               score_work numeric, score_growth numeric, score_vibe numeric, score_flex numeric,
               work_content text, opinion text, is_anonymous boolean, helpful_count int,
               author_nickname text, created_at timestamptz, is_blinded boolean)
language sql stable security definer set search_path = public as $$
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
    and (
      exists (select 1 from users me
               where me.id = auth.uid() and me.pass_expires_at > now())   -- 열람권 보유
      or r.user_id = auth.uid()                                          -- 또는 본인 리뷰
    )
  order by r.created_at desc;
$$;  -- user_id를 반환하지 않음 → 익명 신원 노출 차단 (기존 유지)

revoke execute on function list_worksite_reviews(int) from anon, public;
grant  execute on function list_worksite_reviews(int) to authenticated;
