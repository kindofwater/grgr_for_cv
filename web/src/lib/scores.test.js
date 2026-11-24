// web/src/lib/scores.test.js
import { describe, it, expect } from 'vitest'
import { computeScoreSummary, formatWage, dash, eligibleDegreeLabel, eligibleStatusLabel, formatMinGrade, ratingBarColor } from './scores'

const r = (recommend, work, growth, vibe, flex) => ({
  score_recommend: recommend, score_work: work, score_growth: growth, score_vibe: vibe, score_flex: flex,
})

describe('computeScoreSummary', () => {
  it('리뷰 0개면 count 0, 나머지 null', () => {
    expect(computeScoreSummary([])).toEqual({
      count: 0, overall: null, work: null, growth: null, vibe: null, flex: null, recommendRate: null,
    })
  })

  it('평균과 추천율을 계산한다', () => {
    const reviews = [r(5.0, 5.0, 4.0, 5.0, 4.0), r(4.0, 4.0, 5.0, 4.0, 5.0), r(3.0, 3.0, 3.0, 3.0, 3.0)]
    const s = computeScoreSummary(reviews)
    expect(s.count).toBe(3)
    expect(s.overall).toBeCloseTo(4.0, 5)
    expect(s.work).toBeCloseTo(4.0, 5)
    expect(s.recommendRate).toBe(67)
  })
})

describe('formatWage', () => {
  it('정수면 천단위 콤마 + 원', () => {
    expect(formatWage(11270)).toBe('11,270원')
  })
  it('null/문자열 등 정수가 아니면 "별도 확인"', () => {
    expect(formatWage(null)).toBe('별도 확인')
    expect(formatWage('교외 기준')).toBe('별도 확인')
    expect(formatWage(undefined)).toBe('별도 확인')
  })
})

describe('dash', () => {
  it('값이 없으면 "-", 있으면 그대로', () => {
    expect(dash(null)).toBe('-')
    expect(dash('')).toBe('-')
    expect(dash('서울')).toBe('서울')
  })
})

describe('formatMinGrade', () => {
  it('null이면 상관없음', () => expect(formatMinGrade(null)).toBe('상관없음'))
  it('1이면 상관없음 (1학년 이상 = 제한 없음)', () => expect(formatMinGrade(1)).toBe('상관없음'))
  it('2 이상이면 n학년 이상', () => {
    expect(formatMinGrade(2)).toBe('2학년 이상')
    expect(formatMinGrade(4)).toBe('4학년 이상')
  })
})

describe('eligible labels', () => {
  it('degree 0/1/2/3', () => {
    expect(eligibleDegreeLabel(0)).toBe('학부생')
    expect(eligibleDegreeLabel(1)).toBe('대학원생')
    expect(eligibleDegreeLabel(2)).toBe(null)
    expect(eligibleDegreeLabel(3)).toBe(null)
  })
  it('status 0/1/2/3', () => {
    expect(eligibleStatusLabel(0)).toBe('재학생')
    expect(eligibleStatusLabel(1)).toBe('휴학생')
    expect(eligibleStatusLabel(2)).toBe(null)
    expect(eligibleStatusLabel(3)).toBe(null)
  })
})

describe('ratingBarColor (≥4.0 파랑 / ≥3.0 노랑 / 그 외 빨강)', () => {
  it('>=4.0 → fill-blue', () => {
    expect(ratingBarColor(4.0)).toBe('fill-blue')
    expect(ratingBarColor(4.5)).toBe('fill-blue')
    expect(ratingBarColor(5.0)).toBe('fill-blue')
  })
  it('3.0~3.9 → fill-yellow', () => {
    expect(ratingBarColor(3.0)).toBe('fill-yellow')
    expect(ratingBarColor(3.9)).toBe('fill-yellow')
  })
  it('<3.0 → fill-red', () => {
    expect(ratingBarColor(2.5)).toBe('fill-red')
    expect(ratingBarColor(0.5)).toBe('fill-red')
  })
  it('null → 빈 문자열', () => {
    expect(ratingBarColor(null)).toBe('')
  })
})
