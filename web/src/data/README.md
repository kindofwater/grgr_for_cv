# data/ — 데이터 접근 계층

## (a) 역할
바깥 세계(**Supabase DB**)와 대화하는 유일한 곳. 네트워크 I/O 담당.
테이블 조회/삽입/수정, RPC 함수 호출을 함수로 감싸 제공한다.
페이지·컴포넌트는 SQL/쿼리 세부를 몰라도 여기 함수만 부르면 됨.

## (b) 무엇이 들어가나
- `supabase.from(...).select/insert/...` 쿼리를 감싼 함수.
- `supabase.rpc('함수명', 인자)` 호출을 감싼 함수 (DB에 등록된 RPC와 짝).
- 반환은 가공된 데이터(또는 `{ data, error }`). **UI(JSX)·화면 로직은 금지.**
- 가능하면 화면이 쓰기 좋은 형태로 정리해서 반환.

## (c) 무엇을 참조(import)하나
- `../supabase` — Supabase 클라이언트 싱글톤 (여기서만 직접 만질 것)
- 필요 시 `../lib/*` 순수 함수로 응답 후처리 가능
- ❌ components / pages 를 import 하지 않는다 (역방향 의존 금지)

> 관련: DB쪽 RPC 정의 SQL은 코드 밖 `web/supabase/migrations/`에 있음 (레거시는 `DB/`, `web/supabase/README.md` 참고).
> `.rpc('이름', {인자})`의 이름·인자는 그 SQL의 함수 시그니처와 **정확히 일치**해야 함.

## (d) 현재 파일
| 파일 | 역할 |
|------|------|
| `worksiteQueries.js` | 근무지/리뷰 관련 모든 쿼리·RPC. `fetchWorksite`, `fetchReviews`(`list_worksite_reviews` rpc — 마스킹 목록, 평문 `author_nickname`·`user_id` 미반환·익명이면 닉네임/학기 숨김. 서버가 열람권 게이팅 — `config.REVIEWS_OPEN_UNTIL` 전까지는 한시 전면 공개로 비로그인도 호출 가능, 2026-11-09 종료로 지금은 anon 0행), `write_review_with_points`/`update_review_with_points`/`delete_review_with_rollback`/`toggle_helpful`/`report_review`/`increment_worksite_view`(rpc, 신원은 전부 auth.uid() — 클라가 user_id 안 넘김), `get_review_stats`(rpc) 등 + 홈 목록용 `fetchHomePostings(profile)`(**후보 수집 = 추천 품질의 상한**. 프로필 받아 ⓐ학교근장=내 대학+공용(0) 스코프 ⓑ국가근장 교내(region NULL 계약) ⓒ국가근장 교외=내 거주지역 ⓓ선호매칭(계열·학과·학년)을 병렬 조회 후 공고 id로 dedup. ⚠️프로필 값은 `.or()` 필터 **문자열로 조립하지 않고** `.eq()` 개별 쿼리로 분리 — 이스케이프·인젝션 차단. 2026-07-20 이전엔 국가근장 20+20을 정렬만 걸어 임의로 자르고 학교근장은 대학 구분 없이 전량이라, 추천이 구조적으로 학교근장에 쏠리고 타 대학 근무지가 섞였다)·`getWorksiteScoreCards`(`get_worksite_score_cards` rpc 래퍼 — 카드 항목별 평점·추천율, Home에서 사용) + 근장찾기용 `searchWorksiteCards`(`search_worksite_cards` rpc — worksite 단위 dedup+이름 부분일치+추천순/리뷰순 정렬+limit/offset+총개수, flat 행을 ResultCard 모양으로 변환)·`searchWorksiteSuggestions`(`search_worksite_suggestions` rpc — 검색창 드롭다운 이름+주소 제안). 내 리뷰류(`fetchMyReviewIds`/`fetchMyReviewById`/`fetchMyReviewForPeriod`/`fetchMyHelpfulIds`)는 RLS 본인범위 select(`user_id` 조건 없음). **비로그인 공개(soft-wall)용:** `fetchWorksitePublicDetail`(`get_worksite_public_detail` rpc — InfoCard 필드만 화이트리스트, 리뷰·contact_name 제외)·`fetchWorksiteScoreCard`(`get_worksite_score_cards` rpc — 개수·추천율만). |
| `authQueries.js` | 로그인·회원가입·프로필. `fetchUniversities`, `signIn`(Supabase Auth signInWithPassword), `sendPasswordReset`(입력 이메일 재설정)·`sendPasswordResetToCurrentUser`(세션 이메일 재설정), `signUpUser`(Supabase Auth signUp+metadata, handle_new_user 트리거와 짝), `checkNicknameExists`(닉네임 중복 보조검사 — ⚠️ anon은 RLS상 users 못 읽어 가입 시 항상 false, 실질 차단은 트리거 NICKNAME_TAKEN), `updateProfile`(`update_profile` rpc — auth.uid() 사용) |
| `profileQueries.js` | 세션 사용자 프로필+지갑 하이드레이션. `fetchMe`(users RLS 본인 행 + `_wallet` rpc 결과 합산). AuthContext가 호출. |
| `exchangeQueries.js` | 지갑 조회 + 열람권 교환/사용/환불 RPC. `fetchWallet`, `purchasePass`/`refundPass`/`activatePass` (`watchAdReward` 제거 — 광고는 `adQueries`+`AdModal` 사용) |
| `mypageQueries.js` | 마이페이지 조회. `fetchPointHistory`(points+근장명), `fetchMyReviews`(내 리뷰 전체) |
| `noticeQueries.js` | 공지사항 조회. `fetchNotices`(목록·고정우선/최신순, 본문 제외), `fetchNoticeContents(ids)`(목록 현재 페이지 본문 일괄 prefetch), `fetchNoticeById`(상세) |
| `adQueries.js` | 광고(교환센터 `AdModal`) RPC 래퍼 + Storage URL. `startAdView`(start_ad_view rpc — 광고+토큰), `claimAdReward`(claim_ad_reward rpc — 토큰 적립), `logAdClick`(log_ad_click rpc), `adMediaUrl`(ad-media 버킷 공개 URL) |
