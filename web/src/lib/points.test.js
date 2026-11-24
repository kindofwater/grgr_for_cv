import { describe, it, expect } from 'vitest'
import {
  computeRunningBalance,
  reviewPoints,
  PUBLIC_REVIEW_POINTS,
  ANONYMOUS_REVIEW_POINTS,
} from './points'

describe('computeRunningBalance (오래된 순 입력 → 각 행에 누적 잔액 부여)', () => {
  it('빈 배열은 빈 배열', () => {
    expect(computeRunningBalance([])).toEqual([])
  })
  it('+/- 혼합 누적', () => {
    const asc = [{ amount: 15 }, { amount: 5 }, { amount: -20 }]
    expect(computeRunningBalance(asc)).toEqual([
      { amount: 15, balance: 15 },
      { amount: 5, balance: 20 },
      { amount: -20, balance: 0 },
    ])
  })
  it('원본 객체 필드는 보존', () => {
    const asc = [{ amount: 10, reason: 'ad_view' }]
    expect(computeRunningBalance(asc)[0]).toEqual({ amount: 10, reason: 'ad_view', balance: 10 })
  })
})

describe('reviewPoints', () => {
  it('닉네임 공개 리뷰는 30P', () => {
    expect(reviewPoints(false)).toBe(30)
    expect(PUBLIC_REVIEW_POINTS).toBe(30)
  })

  it('익명 리뷰는 20P', () => {
    expect(reviewPoints(true)).toBe(20)
    expect(ANONYMOUS_REVIEW_POINTS).toBe(20)
  })

  it('isAnonymous가 undefined/null이면 닉네임 공개로 본다', () => {
    expect(reviewPoints(undefined)).toBe(30)
    expect(reviewPoints(null)).toBe(30)
  })

  it('실명과 익명의 차이는 10P', () => {
    expect(PUBLIC_REVIEW_POINTS - ANONYMOUS_REVIEW_POINTS).toBe(10)
  })
})
