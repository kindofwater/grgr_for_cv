-- 목적: 애드센스 재심사용 리뷰 한시 전면 공개 재개·연장 — 종료시각을 2026-10-05 → 2027-01-01 00:00 KST(= 2026-12-31까지)로
-- 날짜: 2026-10-07 · 담당: 배경록

-- 배경: 20260927090000의 일주일 공개(~10/4)가 끝나 리뷰가 다시 잠겼는데, 그 뒤 애드센스 '가치 낮은 콘텐츠' 반려가 또 옴.
--   지금 재심을 넣으면 심사관(비로그인)은 다시 잠긴 사이트를 보게 된다.
--   PM 결정(2026-10-07): 재심 결과가 나올 때까지 연다. 결과가 나오면 수동으로 닫는다.
--   2027-01-01은 닫는 걸 잊었을 때를 대비한 안전망이다.
-- 방식: 20260927090000과 본문 동일, where 절의 종료시각 한 줄만 바꿈. 시그니처 불변(create or replace, DROP 불필요).
--   종료시각은 프론트 web/src/config.js REVIEWS_OPEN_UNTIL 과 반드시 같은 값으로 유지한다(서버가 정본).
-- 조기 종료(재심 결과 후): 새 마이그레이션에서 이 시각을 닫는 시점으로 바꾸고 config.js도 같은 값으로 → db push 먼저, 그다음 prod 배포.
--   anon grant는 공개 기간이 끝나면 0행만 돌려주므로 그대로 둬도 안전하다(정리하려면 revoke 한 줄).

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
      now() < timestamptz '2027-01-01 00:00:00+09'                        -- 한시 전면 공개(애드센스 재심사, 재심 결과까지 · 안전망 ~2026-12-31 KST)
      or exists (select 1 from users me
                  where me.id = auth.uid() and me.pass_expires_at > now())  -- 열람권 보유
      or r.user_id = auth.uid()                                             -- 또는 본인 리뷰
    )
  order by r.created_at desc;
$$;  -- user_id를 반환하지 않음 → 익명 신원 노출 차단 (기존 유지)

revoke execute on function list_worksite_reviews(int) from public;
grant  execute on function list_worksite_reviews(int) to anon, authenticated;
