// 열람권 가격·만료 계산 (순수 함수). 서버 RPC(web/supabase/migrations의 pass_price 등)와 동일 규칙 유지.
// 0 = 최소 상품 센티널 — 서버 pass_price(p_days)와 동일 규칙(키·시그니처는 계속 '일' 단위).
// 이 상품의 실제 지속시간은 대학마다 다르다(university_point_policy.hour_pass_minutes) —
// 서버 _wallet()이 hour_pass_minutes로 내려주고, 화면이 그 값을 아래 함수들에 넘긴다.
// 값을 안 넘기면 기본 60분이라 옛 호출부는 그대로 동작한다.
export const PASS_DAYS = [0, 7, 30]

export function passPrice(days) {
  if (days === 0) return 5
  if (days === 7) return 20
  if (days === 30) return 35
  throw new Error(`INVALID_DAYS: ${days}`)
}

// 최소 상품(days=0)의 기간 문구: 60의 배수면 시간, 아니면 분
function minuteText(minutes) {
  return minutes % 60 === 0 ? `${minutes / 60}시간` : `${minutes}분`
}

// 화면 공용 라벨: '1시간 열람권' / '5분 열람권' / 'N일 열람권'
export function passLabel(days, minutes = 60) {
  passPrice(days) // days 유효성 검증
  return days === 0 ? `${minuteText(minutes)} 열람권` : `${days}일 열람권`
}

// 문장 속 기간 표기: '1시간' / '5분' / 'N일'
export function passDuration(days, minutes = 60) {
  passPrice(days)
  return days === 0 ? minuteText(minutes) : `${days}일`
}

// 활성화 시 새 만료일: max(now, 현재만료) + 기간(최소 상품은 minutes분)
export function nextExpiry(current, days, now = new Date(), minutes = 60) {
  passPrice(days) // days 유효성 검증 (잘못되면 throw)
  const cur = current ? new Date(current) : null
  const base = cur && cur > now ? cur : now
  const result = new Date(base)
  if (days === 0) result.setTime(result.getTime() + minutes * 60 * 1000)
  else result.setDate(result.getDate() + days)
  return result
}

// 열람권 활성 여부 — 만료시각(절대시각)이 현재보다 미래면 true. (WorksiteDetail·Search·AccountMenu 공용 단일 진실)
// 서버값에 offset(Z/+09:00)이 없으면(레거시 naive=UTC 저장) UTC로 간주.
// lib는 의존성 0 규칙이라 dates.parseServerDate 로직을 여기 동일 복제(둘이 어긋나면 안 됨).
export function isPassActive(expiresAt, now = new Date()) {
  if (!expiresAt) return false
  const s = String(expiresAt).trim()
  const hasTz = /([zZ]|[+-]\d{2}:?\d{2})$/.test(s)
  const d = new Date(hasTz ? s : s.replace(' ', 'T') + 'Z')
  return !isNaN(d.getTime()) && d > now
}

// 리뷰 열람 가능 여부 = 열람권 활성 ∪ 한시 전면 공개 기간(openUntil 전). openUntil이 없으면 열람권만 본다.
// 상세·검색·홈이 같은 판정을 쓴다. openUntil 값은 config.REVIEWS_OPEN_UNTIL(서버 RPC와 동일 시각).
export function canViewReviews(expiresAt, openUntil, now = new Date()) {
  if (isPassActive(expiresAt, now)) return true
  if (!openUntil) return false
  const end = new Date(openUntil)
  return !isNaN(end.getTime()) && now < end
}
