// 근무지 상세: 공고 배열에서 대표/목록 선별 + 최근 공고 제한 + 직무 요약.
// Fable #3: 대표/목록 규칙은 여기 한 곳(서버는 폴백 분기 없이 배열만 준다).

const RECENT_POSTING_LIMIT = 5

// '다른 공고' 목록을 최신순 최대 N개로 제한(호출자가 활성→최신 순으로 넘긴 배열 기준).
// 대표 공고는 호출자가 목록 밖에서 항상 표시한다.
export function limitRecentPostings(postings, limit = RECENT_POSTING_LIMIT) {
  const list = Array.isArray(postings) ? postings : []
  return list.slice(0, Math.max(0, limit))
}

// 대표 = 비-placeholder 첫째(활성→최신 순은 호출자가 정렬해 넘김).
// 비-placeholder가 하나도 없으면(국가근로 껍데기만) 배열 첫 원소를 대표로 폴백, 목록은 빔.
export function selectPostings(postings) {
  const list = Array.isArray(postings) ? postings : []
  const nonPh = list.filter((p) => p && !p.is_placeholder)
  if (nonPh.length > 0) return { representative: nonPh[0], others: nonPh.slice(1) }
  return { representative: list[0] ?? null, others: [] }
}

// 직무 텍스트 없는 공고는 목록에서 제외 — 접힌 줄 라벨이 "(직무 미상)"뿐이라 사용자에게 정보가 없다.
// (옛 KUPID 파싱 실패분 포함. DB엔 유지 — SSC 재크롤·Opus 파싱이 직무를 채우면 자연히 살아남는다.)
export function hasJobDescription(posting) {
  return typeof posting?.job_description === 'string' && posting.job_description.trim() !== ''
}

const DEFAULT_MAX = 40
// 접힌 줄 라벨. 제목 컬럼이 없어 job_description을 요약(공고명 title은 SSC 크롤러 후속).
export function summarizeJob(posting, max = DEFAULT_MAX) {
  const raw = posting?.job_description
  const text = typeof raw === 'string' ? raw.replace(/\s+/g, ' ').trim() : ''
  if (!text) return '(직무 미상)'
  return text.length > max ? text.slice(0, max) + '…' : text
}
