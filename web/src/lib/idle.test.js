import { describe, it, expect } from 'vitest'
import { IDLE_TIMEOUT_MS, parseLastActive, isExpired } from './idle'

const UID = 'user-1'
const NOW = 1_800_000_000_000

describe('parseLastActive', () => {
  it('부재 → null', () => {
    expect(parseLastActive(null)).toBe(null)
    expect(parseLastActive('')).toBe(null)
  })

  it('JSON이 아니면 → invalid', () => {
    expect(parseLastActive('abc')).toBe('invalid')
  })

  it('필드 누락·형 불일치 → invalid', () => {
    expect(parseLastActive('{"uid":"user-1"}')).toBe('invalid')       // ts 없음
    expect(parseLastActive('{"ts":123}')).toBe('invalid')             // uid 없음
    expect(parseLastActive('{"uid":1,"ts":123}')).toBe('invalid')     // uid가 문자열 아님
    expect(parseLastActive('{"uid":"user-1","ts":"x"}')).toBe('invalid')
    expect(parseLastActive('null')).toBe('invalid')
  })

  it('정상 → { uid, ts }', () => {
    expect(parseLastActive('{"uid":"user-1","ts":123}')).toEqual({ uid: 'user-1', ts: 123 })
  })
})

describe('isExpired', () => {
  it('29분 59초 → false', () => {
    const entry = { uid: UID, ts: NOW - (IDLE_TIMEOUT_MS - 1000) }
    expect(isExpired(entry, UID, NOW)).toBe(false)
  })

  it('30분 정각 → false (초과해야 만료)', () => {
    const entry = { uid: UID, ts: NOW - IDLE_TIMEOUT_MS }
    expect(isExpired(entry, UID, NOW)).toBe(false)
  })

  it('30분 1초 → true', () => {
    const entry = { uid: UID, ts: NOW - (IDLE_TIMEOUT_MS + 1000) }
    expect(isExpired(entry, UID, NOW)).toBe(true)
  })

  it('부재(null) → false — 무장 시 시딩되므로 진짜 신규 세션뿐', () => {
    expect(isExpired(null, UID, NOW)).toBe(false)
  })

  it("가비지('invalid') → true (fail-closed)", () => {
    expect(isExpired('invalid', UID, NOW)).toBe(true)
  })

  it('미래 타임스탬프(skew 초과) → true — 시계 조작/오류 신뢰 불가', () => {
    const entry = { uid: UID, ts: NOW + 120_000 }
    expect(isExpired(entry, UID, NOW)).toBe(true)
  })

  it('미세한 미래(skew 이내) → false', () => {
    const entry = { uid: UID, ts: NOW + 10_000 }
    expect(isExpired(entry, UID, NOW)).toBe(false)
  })

  it('uid 불일치 → false (다른 계정 값은 무시 — 호출부가 재시딩)', () => {
    const entry = { uid: 'other-user', ts: NOW - 10 * 60 * 60 * 1000 }
    expect(isExpired(entry, UID, NOW)).toBe(false)
  })

  it('timeout 인자로 임계값을 주입할 수 있다', () => {
    const entry = { uid: UID, ts: NOW - 5000 }
    expect(isExpired(entry, UID, NOW, 3000)).toBe(true)
    expect(isExpired(entry, UID, NOW, 10_000)).toBe(false)
  })
})
