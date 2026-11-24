// 유휴 로그아웃 — 순수 판정 로직.
// lib 계약: 의존성 0 · ❌ DOM/스토리지 · 시간은 인자(now)로 주입받는다.
//
// 만료 판정의 유일한 진실원천은 '벽시계'(now - lastActive)다.
// 인메모리 타이머는 절전·탭 freeze·bfcache·모바일 백그라운드에서 흐르지 않으므로
// 판정 근거로 쓸 수 없다. 타이머는 '확인하러 깨워주는' 수단일 뿐.
// 설계: docs/superpowers/specs/2026-07-14-idle-logout-design.md

export const IDLE_TIMEOUT_MS = 30 * 60 * 1000   // 30분 무활동 → 로그아웃
export const POLL_INTERVAL_MS = 15 * 1000       // 15초마다 만료 확인(30분 정책에 15초 오차는 무의미)
export const SKEW_MS = 60 * 1000                // 시계 오차 허용치

// localStorage 원문 → { uid, ts } | null(부재) | 'invalid'(가비지)
export function parseLastActive(raw) {
  if (raw == null || raw === '') return null
  let obj
  try {
    obj = JSON.parse(raw)
  } catch {
    return 'invalid'
  }
  if (!obj || typeof obj !== 'object') return 'invalid'
  const { uid, ts } = obj
  if (typeof uid !== 'string' || uid === '') return 'invalid'
  if (typeof ts !== 'number' || !Number.isFinite(ts)) return 'invalid'
  return { uid, ts }
}

// 만료 여부. 판단이 불가능하면 만료로 본다(fail-closed).
export function isExpired(entry, uid, now, timeout = IDLE_TIMEOUT_MS) {
  if (entry === null) return false        // 부재 = 만료 아님 (시딩으로 처리되므로 신규 세션뿐)
  if (entry === 'invalid') return true    // 가비지 = 만료 (fail-closed)
  if (entry.uid !== uid) return false     // 다른 계정 값 = 무시 (호출부가 재시딩)
  const elapsed = now - entry.ts
  if (elapsed < -SKEW_MS) return true     // 미래 타임스탬프 = 신뢰 불가 → 만료
  return elapsed > timeout                // 정각(===)은 만료 아님. 초과해야 만료
}
