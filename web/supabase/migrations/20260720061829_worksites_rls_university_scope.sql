-- 목적: 상세 열람도 대학 스코프 적용 — worksites RLS를 '로그인 유저는 내 대학 + 공용(0)'으로
-- 날짜: 2026-07-20 · 담당: 배경록

-- 배경: /worksite/:id 로 URL만 바꾸면 타 대학 근무지 상세를 볼 수 있었다.
--   리뷰 '작성'은 20260720060234로 막았지만 '열람'은 그대로였다.
--
-- 정책 선택(A안): **비로그인은 지금처럼 전부 열람 가능**, 로그인 유저만 대학 스코프를 적용한다.
--   비로그인 개방(PUBLIC_BROWSE soft-wall)은 유입·AdSense 심사와 엮여 있어 유지한다.
--   비로그인까지 막는 B안은 대학 수가 늘어난 뒤에 재검토(2026-07-20 결정).
--   → `auth.uid() is null`이면 통과시키는 게 이 정책의 핵심이다. 이 줄을 빼면 B안이 된다.
--
-- ⚠️ 왜 UI 가드가 아니라 RLS인가: worksites는 클라가 직접 select하는 테이블이라(fetchWorksite)
--   화면에서만 가리면 데이터는 그대로 나간다. 실제 경계는 여기다.
--
-- ⚠️ 검색·홈은 영향 없음: search_worksite_cards·get_home_feed·get_worksite_public_detail은
--   전부 security definer라 RLS를 우회하고, 각자 안에서 이미 같은 대학 스코프를 적용하고 있다.
--   (비로그인 상세는 get_worksite_public_detail 경로라 이 정책과 무관하게 계속 열린다.)
--   worksites를 직접 읽는 곳은 web/src/data/worksiteQueries.js의 fetchWorksite 하나뿐임을 확인함.

drop policy if exists worksites_read on worksites;

create policy worksites_read on worksites
  for select to anon, authenticated
  using (
    auth.uid() is null                      -- 비로그인: 전부 열람(A안 — 유지)
    or university_id = 0                    -- 공용(전국 공통) 근무지
    or university_id = (select u.university_id from public.users u where u.id = auth.uid())
  );
