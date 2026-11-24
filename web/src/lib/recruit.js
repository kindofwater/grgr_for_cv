// 모집 상태 판정 — 정확한 시각(recruit_until_at) → 날짜(recruit_until) → is_active 순.
// lib 규칙: 순수·결정적(now 주입). 날짜 비교는 KST 달력일 문자열 사전순(zero-pad 고정이라 안전).
const KST = 'Asia/Seoul'
const YMD = /^\d{4}-\d{2}-\d{2}$/

// 포매터는 재사용 — 생성이 비싼 쪽이라 호출마다 만들면 목록(수천 행) 렌더에서 쌓인다.
const KST_YMD = new Intl.DateTimeFormat('en-CA', {
  timeZone: KST, year: 'numeric', month: '2-digit', day: '2-digit',
})

// 오늘 날짜 'YYYY-MM-DD' (KST 달력일)
export function kstToday(now = new Date()) {
  return KST_YMD.format(now)
}

// ⚠️ NULL 폴백 필수: 레거시(교외 6,647건 등)는 recruit_until이 NULL —
//    폴백 없으면 전부 '모집완료'로 뒤집힌다(spec §2).
export function effectiveActive(posting, now = new Date()) {
  if (!posting) return false

  // 시각 마감은 해당 순간부터 모집완료다. PostgREST가 timestamptz를 ISO 문자열로
  // 반환하므로 Date.parse로 비교하고, 잘못된 값이면 레거시 날짜/불리언으로 안전하게 폴백한다.
  const untilAt = posting.recruit_until_at
  if (typeof untilAt === 'string' && untilAt.trim() !== '') {
    const deadlineMs = Date.parse(untilAt)
    if (Number.isFinite(deadlineMs)) return now.getTime() < deadlineMs
  }

  const until = posting.recruit_until
  // 'YYYY-MM-DD' 모양이 아니면(NULL·빈값·Date 객체 등) 판정 불가 → 폴백.
  // 모양까지 보는 이유: 사전순 비교는 zero-pad 고정에서만 성립하고,
  // Date 객체가 섞여 들어오면 'Fri Jan 01…' > '2026-…'이 참이라 영구 모집중으로 샌다.
  if (typeof until !== 'string' || !YMD.test(until)) return !!posting.is_active
  return until >= kstToday(now)
}
