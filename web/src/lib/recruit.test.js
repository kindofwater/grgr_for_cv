import { describe, it, expect } from 'vitest'
import { effectiveActive, kstToday } from './recruit'

const NOW = new Date('2026-07-17T03:00:00+09:00')  // KST 2026-07-17 새벽

// ⚠️ 이 테스트들이 시간대 버그를 잡는 건 러너 TZ가 UTC로 고정돼 있기 때문(vite.config.js test.env.TZ).
//    개발/CI 머신이 KST면 로컬시간 == KST라, 로컬시간으로 날짜를 구하는 잘못된 구현도 통과해버린다.
describe('kstToday', () => {
  it('KST 달력일 YYYY-MM-DD', () => {
    expect(kstToday(NOW)).toBe('2026-07-17')
    // UTC로는 전날 18시여도 KST 기준 오늘 (UTC 러너에서 로컬시간 구현이면 '2026-07-16'이 나와 실패)
    expect(kstToday(new Date('2026-07-16T18:00:00Z'))).toBe('2026-07-17')
  })

  it('한 자리 월/일도 zero-pad — 사전순 비교의 전제', () => {
    // '2026-7-9'였다면 '2026-7-9' > '2026-07-17'(사전순)이라 마감 판정이 뒤집힌다
    expect(kstToday(new Date('2026-07-09T12:00:00+09:00'))).toBe('2026-07-09')
  })
})

describe('effectiveActive (recruit_until 우선, NULL이면 is_active 폴백)', () => {
  it('recruit_until_at은 정확한 마감 시각 전까지만 모집중', () => {
    const posting = {
      recruit_until_at: '2026-08-12T18:00:00+09:00',
      recruit_until: '2026-08-12',
      is_active: true,
    }
    expect(effectiveActive(posting, new Date('2026-08-12T17:59:59+09:00'))).toBe(true)
    expect(effectiveActive(posting, new Date('2026-08-12T18:00:00+09:00'))).toBe(false)
  })
  it('recruit_until_at이 있으면 같은 날 날짜 마감보다 우선', () => {
    expect(effectiveActive({
      recruit_until_at: '2026-08-12T09:00:00Z',
      recruit_until: '2026-08-12',
      is_active: true,
    }, new Date('2026-08-12T09:00:01Z'))).toBe(false)
  })
  it('잘못된 recruit_until_at은 레거시 날짜 판정으로 폴백', () => {
    expect(effectiveActive({
      recruit_until_at: 'not-a-date',
      recruit_until: '2026-07-17',
      is_active: false,
    }, NOW)).toBe(true)
  })
  it('마감일 당일까지 모집중(경계 포함)', () => {
    expect(effectiveActive({ recruit_until: '2026-07-17', is_active: false }, NOW)).toBe(true)
  })
  it('마감일 지나면 is_active=true여도 모집완료(낡은 스냅숏 무시)', () => {
    expect(effectiveActive({ recruit_until: '2026-07-16', is_active: true }, NOW)).toBe(false)
  })
  it('recruit_until NULL이면 is_active 폴백 — 레거시 교외 6,647건이 뒤집히면 안 된다', () => {
    expect(effectiveActive({ recruit_until: null, is_active: true }, NOW)).toBe(true)
    expect(effectiveActive({ recruit_until: null, is_active: false }, NOW)).toBe(false)
    expect(effectiveActive({ is_active: true }, NOW)).toBe(true)  // 키 자체가 없어도(구 RPC 행) 폴백
  })
  it('posting이 없으면 false', () => {
    expect(effectiveActive(null, NOW)).toBe(false)
    expect(effectiveActive(undefined, NOW)).toBe(false)
  })

  it('YYYY-MM-DD가 아닌 값은 판정 불가로 보고 폴백 — 영구 모집중으로 새지 않는다', () => {
    // Date 객체가 섞여 들어오면 'Fri Jan…' >= '2026-07-17'이 참이라 조용히 모집중이 된다
    expect(effectiveActive({ recruit_until: new Date('2026-01-01'), is_active: false }, NOW)).toBe(false)
    // 빈 문자열은 '' >= today가 거짓이라 반대로 모집완료로 샌다 → 둘 다 폴백이 맞다
    expect(effectiveActive({ recruit_until: '', is_active: true }, NOW)).toBe(true)
  })
})
