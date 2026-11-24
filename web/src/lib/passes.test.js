import { describe, it, expect } from 'vitest'
import { passPrice, passLabel, passDuration, nextExpiry, PASS_DAYS, isPassActive, canViewReviews } from './passes'

describe('passPrice (2026-07-31 개편)', () => {
  it('1시간(0)=5P, 7일=20P, 30일=35P', () => {
    expect(passPrice(0)).toBe(5)
    expect(passPrice(7)).toBe(20)
    expect(passPrice(30)).toBe(35)
  })
  it('잘못된 일수는 INVALID_DAYS throw', () => {
    expect(() => passPrice(14)).toThrow('INVALID_DAYS')
    expect(() => passPrice(1)).toThrow('INVALID_DAYS')
  })
})

describe('PASS_DAYS', () => {
  it('지원 종류는 0(1시간권), 7, 30', () => {
    expect(PASS_DAYS).toEqual([0, 7, 30])
  })
})

describe('passLabel / passDuration', () => {
  it('0은 1시간 표기, 나머지는 N일 표기', () => {
    expect(passLabel(0)).toBe('1시간 열람권')
    expect(passLabel(7)).toBe('7일 열람권')
    expect(passDuration(0)).toBe('1시간')
    expect(passDuration(30)).toBe('30일')
  })
  it('잘못된 일수는 throw', () => {
    expect(() => passLabel(3)).toThrow('INVALID_DAYS')
  })
})

describe('nextExpiry (활성화 시 새 만료일 = max(now, 현재만료) + 기간)', () => {
  const NOW = new Date('2026-06-08T00:00:00')
  it('만료 없으면 now + days', () => {
    expect(nextExpiry(null, 7, NOW)).toEqual(new Date('2026-06-15T00:00:00'))
  })
  it('활성 중이면 현재만료 + days (연장)', () => {
    expect(nextExpiry(new Date('2026-06-20T00:00:00'), 30, NOW))
      .toEqual(new Date('2026-07-20T00:00:00'))
  })
  it('만료 지났으면 now 기준 + days', () => {
    expect(nextExpiry(new Date('2026-06-01T00:00:00'), 7, NOW))
      .toEqual(new Date('2026-06-15T00:00:00'))
  })
  it('1시간권(0)은 +1시간', () => {
    expect(nextExpiry(null, 0, NOW)).toEqual(new Date('2026-06-08T01:00:00'))
  })
  it('1시간권도 활성 중이면 현재만료 + 1시간 (연장)', () => {
    expect(nextExpiry(new Date('2026-06-20T00:00:00'), 0, NOW))
      .toEqual(new Date('2026-06-20T01:00:00'))
  })
})

describe('isPassActive (만료시각 > now 면 활성)', () => {
  const now = new Date('2026-06-12T00:00:00Z')
  it('만료가 미래면 true', () => {
    expect(isPassActive('2026-06-20T00:00:00Z', now)).toBe(true)
  })
  it('만료가 과거면 false', () => {
    expect(isPassActive('2026-06-01T00:00:00Z', now)).toBe(false)
  })
  it('정확히 now면 false (strictly greater)', () => {
    expect(isPassActive('2026-06-12T00:00:00Z', now)).toBe(false)
  })
  it('null/undefined면 false', () => {
    expect(isPassActive(null, now)).toBe(false)
    expect(isPassActive(undefined, now)).toBe(false)
  })
})

describe('isPassActive — naive(오프셋 없는) 서버값은 UTC로 간주 (DB가 UTC 저장)', () => {
  // now = 2026-06-12 05:00 UTC (= KST 14:00)
  const now = new Date('2026-06-12T05:00:00Z')
  it('naive 만료가 now 이후면 활성 (UTC 해석)', () => {
    // 08:00(UTC) > 05:00(UTC) → 활성. (구버전은 naive를 KST로 오인해 만료 처리하던 버그)
    expect(isPassActive('2026-06-12T08:00:00', now)).toBe(true)
  })
  it('naive 만료가 now 이전이면 비활성', () => {
    expect(isPassActive('2026-06-12T02:00:00', now)).toBe(false)
  })
})

describe('minutes 인자 (2026-08-08 대학별 정책)', () => {
  it('기본값 60이면 기존 표기 그대로 (회귀)', () => {
    expect(passLabel(0)).toBe('1시간 열람권')
    expect(passDuration(0)).toBe('1시간')
    expect(passLabel(7)).toBe('7일 열람권')
  })

  it('minutes=5면 5분 표기', () => {
    expect(passLabel(0, 5)).toBe('5분 열람권')
    expect(passDuration(0, 5)).toBe('5분')
  })

  it('60의 배수면 시간 단위로 표기', () => {
    expect(passLabel(0, 120)).toBe('2시간 열람권')
    expect(passDuration(0, 60)).toBe('1시간')
  })

  it('60의 배수가 아니면 분 단위로 표기', () => {
    expect(passLabel(0, 90)).toBe('90분 열람권')
  })

  it('일 단위 권은 minutes를 무시한다', () => {
    expect(passLabel(7, 5)).toBe('7일 열람권')
    expect(passDuration(30, 5)).toBe('30일')
  })

  it('nextExpiry는 minutes만큼 더한다', () => {
    const now = new Date('2026-08-08T00:00:00Z')
    expect(nextExpiry(null, 0, now, 5).toISOString()).toBe('2026-08-08T00:05:00.000Z')
    expect(nextExpiry(null, 0, now).toISOString()).toBe('2026-08-08T01:00:00.000Z')
  })

  it('nextExpiry는 활성 중이면 현재만료 기준으로 minutes를 더한다', () => {
    const now = new Date('2026-08-08T00:00:00Z')
    const cur = new Date('2026-08-08T02:00:00Z')
    expect(nextExpiry(cur, 0, now, 5).toISOString()).toBe('2026-08-08T02:05:00.000Z')
  })

  it('일 단위 권의 만료 계산은 minutes에 영향받지 않는다', () => {
    const now = new Date('2026-08-08T00:00:00Z')
    expect(nextExpiry(null, 7, now, 5).toISOString()).toBe(nextExpiry(null, 7, now).toISOString())
  })
})

describe('canViewReviews (열람권 ∪ 한시 전면 공개)', () => {
  const now = new Date('2026-09-28T00:00:00Z')
  const openUntil = '2026-10-05T00:00:00+09:00'
  it('열람권 활성이면 공개 기간과 무관하게 true', () => {
    expect(canViewReviews('2026-10-10T00:00:00Z', null, now)).toBe(true)
    expect(canViewReviews('2026-10-10T00:00:00Z', openUntil, now)).toBe(true)
  })
  it('열람권 없어도 공개 종료 전이면 true (비로그인 = expiresAt undefined 포함)', () => {
    expect(canViewReviews(undefined, openUntil, now)).toBe(true)
    expect(canViewReviews('2026-09-01T00:00:00Z', openUntil, now)).toBe(true)
  })
  it('공개 종료 시각 이후엔 열람권 없으면 false', () => {
    const after = new Date('2026-10-04T15:00:00Z')   // = 10/5 00:00 KST
    expect(canViewReviews(undefined, openUntil, after)).toBe(false)
    expect(canViewReviews('2026-09-01T00:00:00Z', openUntil, after)).toBe(false)
    expect(canViewReviews('2026-10-10T00:00:00Z', openUntil, after)).toBe(true)
  })
  it('openUntil이 없거나 파싱 불가면 열람권만 본다', () => {
    expect(canViewReviews(undefined, null, now)).toBe(false)
    expect(canViewReviews(undefined, 'garbage', now)).toBe(false)
  })
})
