// web/src/lib/scores.js

function avg(nums) {
  if (nums.length === 0) return null
  return nums.reduce((a, b) => a + b, 0) / nums.length
}

export function computeScoreSummary(reviews) {
  const count = reviews.length
  if (count === 0) {
    return { count: 0, overall: null, work: null, growth: null, vibe: null, flex: null, recommendRate: null }
  }
  const num = (k) => reviews.map((r) => Number(r[k]))
  const recommends = num('score_recommend')
  const recommendCount = recommends.filter((v) => v >= 4.0).length
  return {
    count,
    overall: avg(recommends),
    work: avg(num('score_work')),
    growth: avg(num('score_growth')),
    vibe: avg(num('score_vibe')),
    flex: avg(num('score_flex')),
    recommendRate: Math.round((recommendCount / count) * 100),
  }
}

export function formatWage(wage) {
  return typeof wage === 'number' && Number.isFinite(wage)
    ? `${wage.toLocaleString()}원`
    : '별도 확인'
}

export function dash(value) {
  return value === null || value === undefined || value === '' ? '-' : value
}

export function eligibleDegreeLabel(n) {
  return { 0: '학부생', 1: '대학원생' }[n] ?? null  // 2(둘 다 가능)=null → 태그/행 생략
}

export function eligibleStatusLabel(n) {
  return { 0: '재학생', 1: '휴학생' }[n] ?? null  // 2(둘 다 가능)=null
}

export function formatMinGrade(minGrade) {
  if (minGrade == null || minGrade <= 1) return '상관없음'
  return `${minGrade}학년 이상`
}

// 평점 값에 따른 막대 색 클래스(전역). ≥4.0 파랑 / ≥3.0 노랑 / 그 외 빨강
export function ratingBarColor(value) {
  if (value == null) return ''
  if (value >= 4.0) return 'fill-blue'
  if (value >= 3.0) return 'fill-yellow'
  return 'fill-red'
}
