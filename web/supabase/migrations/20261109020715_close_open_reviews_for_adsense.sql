-- 목적: 애드센스 재심 결과가 나와 리뷰 한시 전면 공개를 조기 종료 — 종료시각을 2027-01-01 → 2026-11-09 00:00 KST로 당긴다
-- 날짜: 2026-11-09 · 담당: 배경록

-- 배경: 20261007102907이 "재심 결과가 나올 때까지" 연 공개를 PM 결정(2026-11-09)으로 닫는다.
-- 방식: 20261007102907과 본문 동일, where 절의 종료시각 한 줄만 바꿈. 이미 지난 시각이라 적용 즉시 잠긴다.
--   시그니처 불변(create or replace, DROP 불필요). 프론트 web/src/config.js REVIEWS_OPEN_UNTIL 과 같은 값.
--   anon grant는 그대로 둔다. 기간이 지나 anon은 0행만 받는다(20260927090000 종료 때와 같은 상태).

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
      now() < timestamptz '2026-11-09 00:00:00+09'                        -- 한시 전면 공개 종료(애드센스 재심 결과, 2026-11-09)
      or exists (select 1 from users me
                  where me.id = auth.uid() and me.pass_expires_at > now())  -- 열람권 보유
      or r.user_id = auth.uid()                                             -- 또는 본인 리뷰
    )
  order by r.created_at desc;
$$;  -- user_id를 반환하지 않음 → 익명 신원 노출 차단 (기존 유지)

revoke execute on function list_worksite_reviews(int) from public;
grant  execute on function list_worksite_reviews(int) to anon, authenticated;
