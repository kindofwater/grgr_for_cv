// 페이지 title·meta description 문자열 조립(순수 함수). DOM 반영은 components/PageMeta.jsx 담당.
export const SITE_NAME = '근로고래'
export const DEFAULT_TITLE = '근로고래 — 근로장학생 근무지 리뷰·추천'
// ⚠️ index.html의 정적 <meta name="description">와 같은 문구 유지(문구 바꾸면 양쪽 함께)
export const DEFAULT_DESCRIPTION =
  '근로장학생을 위한 근무지 리뷰·추천 서비스 근로고래. 실제 근무 후기로 나에게 맞는 근무지를 찾아보세요.'

// 페이지 이름 → 문서 제목. 이름 없으면 기본 타이틀(홈·데이터 로딩 전 폴백).
export function pageTitle(name) {
  return name ? `${name} — ${SITE_NAME}` : DEFAULT_TITLE
}

function worksiteName(ws) {
  const name = [ws?.organization_name, ws?.workplace_name].filter(Boolean).join(' ')
  return name || null
}

// 근무지 상세 title 조각("기관명 근무지명 리뷰"). 데이터 없으면 null → pageTitle이 기본 타이틀 폴백.
export function worksiteTitle(ws) {
  const name = worksiteName(ws)
  return name ? `${name} 리뷰` : null
}

// 근무지 상세 meta description. 데이터 없으면 null → PageMeta가 기본 설명 폴백.
export function worksiteDescription(ws) {
  const name = worksiteName(ws)
  return name ? `${name}의 근로장학생 근무 후기·평점을 근로고래에서 확인하세요.` : null
}
