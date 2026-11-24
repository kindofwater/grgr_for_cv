-- 목적: 애드센스 재심사용 한시 전면 공개 — 2026-10-04(KST)까지 비로그인·무열람권도 리뷰 전문을 볼 수 있게 list_worksite_reviews 게이팅에 기간 예외 + anon 실행 허용
-- 날짜: 2026-09-27 · 담당: 배경록

-- 배경: 애드센스 심사관은 비로그인으로 본다. 리뷰(핵심 콘텐츠)가 열람권 뒤에 있어 "가치 낮은 콘텐츠"로 반려됨.
--   PM 결정(2026-09-27): 일주일간(~10/4) 누구에게나 리뷰 전문 공개. 이후엔 자동으로 기존 게이팅으로 복귀.
-- 방식: 본문 where 절에 `now() < 종료시각` 예외 한 줄 + anon grant. 반환 컬럼·인자 동일 → 시그니처 불변(DROP 불필요).
--   종료시각은 프론트 web/src/config.js REVIEWS_OPEN_UNTIL 과 반드시 같은 값으로 유지한다(서버가 정본).
-- 종료 후: 이 함수는 anon에게 0행을 돌려주므로 그대로 둬도 안전하다. 정리하고 싶으면 별도 마이그레이션에서
--   `revoke execute on function list_worksite_reviews(int) from anon;` 만 하면 된다(본문은 기간이 지나면 자동 닫힘).

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
      now() < timestamptz '2026-10-05 00:00:00+09'                        -- 한시 전면 공개(애드센스 재심사, ~10/4 KST)
      or exists (select 1 from users me
                  where me.id = auth.uid() and me.pass_expires_at > now())  -- 열람권 보유
      or r.user_id = auth.uid()                                             -- 또는 본인 리뷰
    )
  order by r.created_at desc;
$$;  -- user_id를 반환하지 않음 → 익명 신원 노출 차단 (기존 유지)

revoke execute on function list_worksite_reviews(int) from public;
grant  execute on function list_worksite_reviews(int) to anon, authenticated;
