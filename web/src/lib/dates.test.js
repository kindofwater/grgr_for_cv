import { describe, it, expect } from 'vitest'
import { formatDate, formatDateTime, parseServerDate, formatRelativeDate } from './dates'

describe('parseServerDate (offset 있으면 그대로, 없으면 UTC로 간주)', () => {
  it('naive(오프셋 없음)는 UTC instant 로 파싱', () => {
    expect(parseServerDate('2026-06-13T03:38:03').toISOString()).toBe('2026-06-13T03:38:03.000Z')
  })
  it('Z / +00:00 도 같은 instant', () => {
    expect(parseServerDate('2026-06-13T03:38:03Z').toISOString()).toBe('2026-06-13T03:38:03.000Z')
    expect(parseServerDate('2026-06-13T03:38:03+00:00').toISOString()).toBe('2026-06-13T03:38:03.000Z')
  })
  it('공백 구분 timestamp 도 처리', () => {
    expect(parseServerDate('2026-06-13 03:38:03').toISOString()).toBe('2026-06-13T03:38:03.000Z')
  })
  it('null/빈값/이상값은 null', () => {
    expect(parseServerDate(null)).toBeNull()
    expect(parseServerDate('')).toBeNull()
    expect(parseServerDate('nope')).toBeNull()
  })
})

describe('formatDate (timestamp → "YYYY.MM.DD", KST 고정)', () => {
  it('낮 시간은 그 날짜 그대로', () => {
    expect(formatDate('2026-06-11T09:30:00')).toBe('2026.06.11')
  })
  it('공백 구분 timestamp도 처리', () => {
    expect(formatDate('2026-01-05 14:00:00')).toBe('2026.01.05')
  })
  it('UTC 늦은 시각은 KST로 다음 날 (UTC 16시 = KST 익일 01시)', () => {
    expect(formatDate('2026-06-11T16:00:00')).toBe('2026.06.12')
    expect(formatDate('2026-06-11T16:00:00Z')).toBe('2026.06.12')
  })
  it('null/undefined/빈값은 빈 문자열', () => {
    expect(formatDate(null)).toBe('')
    expect(formatDate(undefined)).toBe('')
    expect(formatDate('')).toBe('')
  })
})

describe('formatDateTime (timestamp → "YYYY.MM.DD HH:mm", KST 24시간)', () => {
  it('UTC 03:38 → KST 12:38', () => {
    expect(formatDateTime('2026-06-13T03:38:03Z')).toBe('2026.06.13 12:38')
    expect(formatDateTime('2026-06-13T03:38:03')).toBe('2026.06.13 12:38')
  })
  it('자정 경계: UTC 15:00 → KST 익일 00:00', () => {
    expect(formatDateTime('2026-06-12T15:00:00Z')).toBe('2026.06.13 00:00')
  })
  it('빈값은 빈 문자열', () => {
    expect(formatDateTime(null)).toBe('')
  })
})

describe('formatRelativeDate (KST 달력일 기준 상대표기)', () => {
  const now = new Date('2026-07-08T12:00:00+09:00')          // KST 정오 고정
  const ago = (n) => new Date(now.getTime() - n * 86400000).toISOString()  // n KST일 전 (KST=DST 없음)

  it('오늘 / 1~6일', () => {
    expect(formatRelativeDate(ago(0), now)).toBe('오늘')
    expect(formatRelativeDate(ago(1), now)).toBe('1일 전')
    expect(formatRelativeDate(ago(6), now)).toBe('6일 전')
  })
  it('7~27일 = 주 단위(floor/7)', () => {
    expect(formatRelativeDate(ago(7), now)).toBe('1주 전')
    expect(formatRelativeDate(ago(13), now)).toBe('1주 전')
    expect(formatRelativeDate(ago(14), now)).toBe('2주 전')
    expect(formatRelativeDate(ago(21), now)).toBe('3주 전')
    expect(formatRelativeDate(ago(27), now)).toBe('3주 전')
  })
  it('28일(4주)~ = 달 단위, "4주 전"은 건너뜀', () => {
    expect(formatRelativeDate(ago(28), now)).toBe('1달 전')
    expect(formatRelativeDate(ago(59), now)).toBe('1달 전')
    expect(formatRelativeDate(ago(60), now)).toBe('2달 전')
  })
  it('미래는 오늘로, 빈값은 빈 문자열', () => {
    expect(formatRelativeDate(ago(-1), now)).toBe('오늘')
    expect(formatRelativeDate(null, now)).toBe('')
  })
})
