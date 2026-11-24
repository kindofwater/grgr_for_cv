// 서버 timestamp 처리 (표시는 한국시간 KST 고정). lib 규칙: 순수·결정적.
// DB 전환: timestamp(naive, UTC 벽시계) → timestamptz(offset 붙음). parseServerDate 가 둘 다 안전 처리.
const KST = 'Asia/Seoul'

// 서버 타임스탬프 문자열 → Date(절대시각).
// offset(Z / +09:00)이 있으면 그대로, 없으면(레거시 naive = UTC 저장) UTC로 간주한다.
export function parseServerDate(ts) {
  if (!ts) return null
  const s = String(ts).trim()
  const hasTz = /([zZ]|[+-]\d{2}:?\d{2})$/.test(s)
  const d = new Date(hasTz ? s : s.replace(' ', 'T') + 'Z')
  return isNaN(d.getTime()) ? null : d
}

// A notice's initial updated_at is populated by the DB default, so only a
// timestamp later than created_at represents an actual edit.
export function noticeActivityAt(createdAt, updatedAt) {
  const created = parseServerDate(createdAt)
  const updated = parseServerDate(updatedAt)
  if (updated && (!created || updated > created)) return updatedAt
  return createdAt
}

// timestamp → "YYYY.MM.DD" (KST)
export function formatDate(ts) {
  const d = parseServerDate(ts)
  if (!d) return ''
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: KST, year: 'numeric', month: '2-digit', day: '2-digit',
  }).format(d).replaceAll('-', '.')
}

// timestamp → "YYYY.MM.DD HH:mm" (KST, 24시간)
export function formatDateTime(ts) {
  const d = parseServerDate(ts)
  if (!d) return ''
  const p = new Intl.DateTimeFormat('en-CA', {
    timeZone: KST, year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
  }).formatToParts(d).reduce((o, x) => { o[x.type] = x.value; return o }, {})
  return `${p.year}.${p.month}.${p.day} ${p.hour}:${p.minute}`
}

// timestamp → 상대 표기(KST 달력일 기준). now 주입 가능(테스트용, 기본=현재).
// 0일=오늘 · 1~6일="N일 전" · 7~27일="N주 전"(floor/7) · 28일(4주)~="N달 전"(floor/30, 최소 1 → "4주 전"은 건너뜀)
export function formatRelativeDate(ts, now = new Date()) {
  const d = parseServerDate(ts)
  if (!d) return ''
  const kstDay = (x) =>
    Math.floor(Date.parse(
      new Intl.DateTimeFormat('en-CA', { timeZone: KST, year: 'numeric', month: '2-digit', day: '2-digit' })
        .format(x) + 'T00:00:00Z'
    ) / 86400000)
  const days = kstDay(now) - kstDay(d)
  if (days <= 0) return '오늘'
  if (days <= 6) return `${days}일 전`
  if (days <= 27) return `${Math.floor(days / 7)}주 전`
  return `${Math.max(1, Math.floor(days / 30))}달 전`
}
