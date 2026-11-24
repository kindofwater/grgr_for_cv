// sitemap 생성 순수 함수 — I/O 없음(fetch·fs는 generate-sitemap.mjs 담당). 테스트: sitemap.test.mjs
export const ORIGIN = 'https://grgr.kr'

// 공개 정적 라우트 — public/sitemap.xml(정적 폴백)과 같은 목록 유지
export const STATIC_PATHS = ['/home', '/search', '/notice', '/privacy', '/terms', '/contact']

function escapeXml(s) {
  return s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')
}

// 검색 RPC flat 행(worksite_id) → '/worksite/:id' 경로 목록. 중복 제거 + id 오름차순(안정된 diff).
export function worksitePaths(rows) {
  const ids = new Set()
  for (const r of rows ?? []) {
    const id = Number(r?.worksite_id)
    if (Number.isInteger(id) && id > 0) ids.add(id)
  }
  return [...ids].sort((a, b) => a - b).map((id) => `/worksite/${id}`)
}

// 페이징 수집. fetchPage(offset) → 행 배열을 받아 빈 배치가 나올 때까지 이어붙인다.
// ⚠️ offset은 '실제로 받은 개수'만큼만 전진 — 서버가 요청 limit보다 적게 잘라 반환해도
//    (search RPC는 50개 캡) 누락 없이 수집된다. 예전엔 요청 개수(200)만큼 건너뛰어
//    4분의 1만 담기는 버그(1,750개)가 있었다. 회귀 테스트: sitemap.test.mjs
// opts.stopWhen(batch): 참을 반환하면 그 배치까지 수집하고 종료(정렬된 목록의 조기 중단용).
// opts.maxPages: 고장난 서버(offset 무시)로 인한 무한 루프 방지 상한. 기본 300페이지.
export async function collectRows(fetchPage, { stopWhen, maxPages = 300 } = {}) {
  const rows = []
  let offset = 0
  for (let page = 0; page < maxPages; page++) {
    const batch = await fetchPage(offset)
    if (!batch?.length) break
    rows.push(...batch)
    offset += batch.length
    if (stopWhen && stopWhen(batch)) break
  }
  return rows
}

// 리뷰가 1개 이상 달린 행만. 레거시 교외 국가근장(6,700여 곳) 중 실사용 흔적 있는 곳만 sitemap에 담는 용도.
export function filterReviewed(rows) {
  return (rows ?? []).filter((r) => Number(r?.review_count) > 0)
}

// 경로 목록 → sitemap 프로토콜 XML. 항목 포맷은 기존 정적 sitemap.xml과 동일(<url><loc> 한 줄).
export function buildSitemapXml(paths) {
  const urls = paths.map((p) => `  <url><loc>${escapeXml(ORIGIN + p)}</loc></url>`).join('\n')
  return `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls}\n</urlset>\n`
}
