// web/src/lib/searchCards.test.js
import { describe, it, expect } from 'vitest'
import { escapeLike, sortKeyToParam, toCard, suggestionAddress } from './searchCards'

describe('escapeLike', () => {
  it('%, _, 백슬래시를 이스케이프한다', () => {
    expect(escapeLike('a%b_c\\d')).toBe('a\\%b\\_c\\\\d')
  })
  it('null/undefined는 빈 문자열', () => {
    expect(escapeLike(null)).toBe('')
    expect(escapeLike(undefined)).toBe('')
  })
})

describe('sortKeyToParam', () => {
  it('리뷰 많은 순 → reviews', () => {
    expect(sortKeyToParam('리뷰 많은 순')).toBe('reviews')
  })
  it('그 외(추천순 포함) → recommend', () => {
    expect(sortKeyToParam('추천순')).toBe('recommend')
    expect(sortKeyToParam('아무거나')).toBe('recommend')
  })
})

describe('toCard', () => {
  const baseRow = {
    worksite_id: 7, organization_name: '고려대', workplace_name: '도서관',
    region: '서울', address: '안암로 1', type: 'school', location_type: 'on_campus',
    view_count: 12, is_active: true,
    preferred_track: '이공계열', eligible_degree: 0, eligible_status: 2, work_duration_type: 'short',
    review_count: 3, avg_recommend: 4.2, avg_work: 4.0, avg_growth: 3.5, avg_vibe: 4.1, avg_flex: 3.9,
    recommend_rate: 67, total_count: 50,
  }
  it('flat 행을 {worksite,posting,stats,is_active}로 변환한다', () => {
    const c = toCard(baseRow)
    expect(c.is_active).toBe(true)
    expect(c.worksite).toEqual({
      id: 7, organization_name: '고려대', workplace_name: '도서관', region: '서울',
      address: '안암로 1', type: 'school', location_type: 'on_campus', view_count: 12,
    })
    expect(c.posting).toEqual({
      preferred_track: '이공계열', eligible_degree: 0, eligible_status: 2, work_duration_type: 'short',
    })
    expect(c.stats.review_count).toBe(3)
    expect(c.stats.avg_recommend).toBe(4.2)
    expect(c.stats.recommend_rate).toBe(67)
  })
  it('리뷰 0개면 stats는 null', () => {
    const c = toCard({ ...baseRow, review_count: 0, avg_recommend: null })
    expect(c.stats).toBeNull()
  })
  it('서버가 계산한 is_active를 그대로 사용한다', () => {
    const c = toCard({ ...baseRow, is_active: false, recruit_until: '2026-07-17' })
    expect(c.is_active).toBe(false)
  })
  it('recruit_until 없으면(구 RPC/레거시) is_active 폴백', () => {
    expect(toCard({ ...baseRow, is_active: true }).is_active).toBe(true)
  })
})

describe('suggestionAddress', () => {
  it('address 있으면 address', () => {
    expect(suggestionAddress({ address: '안암로 1', region: '서울' })).toBe('안암로 1')
  })
  it('address 비면 region 폴백', () => {
    expect(suggestionAddress({ address: '', region: '서울' })).toBe('서울')
    expect(suggestionAddress({ address: null, region: '충남' })).toBe('충남')
  })
  it('둘 다 없으면 빈 문자열', () => {
    expect(suggestionAddress({})).toBe('')
  })
})
