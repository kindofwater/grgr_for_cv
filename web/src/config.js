// 앱 전역 피처 플래그.
// PUBLIC_BROWSE: 비로그인에게 근무지 정보 + 리뷰 개수·추천율 공개(soft-wall). AdSense/SEO용.
//   다학교 확장 시 false + anon RPC 권한 회수(닫기 런북, spec §5)로 함께 닫는다.
export const PUBLIC_BROWSE = true

// REVIEWS_OPEN_UNTIL: 애드센스 재심사용 한시 전면 공개 종료시각(exclusive). 이 시각 전엔 비로그인·무열람권도
//   리뷰 전문·세부점수를 본다(PM 결정 2026-09-27 일주일 → 2026-10-07 재심 결과까지로 연장 → 2026-11-09 재심 결과로 종료).
//   서버 정본은 migrations/20261109020715_close_open_reviews_for_adsense.sql 의 list_worksite_reviews 본문
//   — 두 값은 반드시 같아야 한다(프론트만 열면 RPC가 0행, 서버만 열면 화면이 잠금).
//   기간이 지나면 코드 수정 없이 자동으로 기존 게이팅(열람권)으로 복귀한다. 다시 열려면 두 곳을 같은 값으로(서버 먼저).
export const REVIEWS_OPEN_UNTIL = '2026-11-09T00:00:00+09:00'
