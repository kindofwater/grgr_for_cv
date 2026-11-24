import { describe, expect, it, vi } from 'vitest'
import { loadFeaturedReviewPreviews } from './homeReviewPreview'

describe('loadFeaturedReviewPreviews', () => {
  it('무열람권이면 전체 리뷰를 요청하지 않고 티저만 반환한다', async () => {
    const fetchReviews = vi.fn()
    const fetchReviewTeaser = vi.fn().mockResolvedValue({
      teaser: '업무를 차근차근 배울 수 있었어요',
      is_truncated: true,
    })

    const result = await loadFeaturedReviewPreviews({
      worksiteId: 6748,
      hasActivePass: false,
      fetchReviews,
      fetchReviewTeaser,
    })

    expect(fetchReviews).not.toHaveBeenCalled()
    expect(fetchReviewTeaser).toHaveBeenCalledWith(6748)
    expect(result).toEqual([{ opinion: '업무를 차근차근 배울 수 있었어요…' }])
  })

  it('열람권이 있으면 내용이 있는 전체 리뷰를 사용한다', async () => {
    const reviews = [{ opinion: '전체 리뷰', helpful_count: 2 }]
    const fetchReviews = vi.fn().mockResolvedValue(reviews)
    const fetchReviewTeaser = vi.fn()

    const result = await loadFeaturedReviewPreviews({
      worksiteId: 6748,
      hasActivePass: true,
      fetchReviews,
      fetchReviewTeaser,
    })

    expect(result).toEqual(reviews)
    expect(fetchReviewTeaser).not.toHaveBeenCalled()
  })

  it('전체 리뷰 행에 표시할 내용이 없으면 티저로 폴백한다', async () => {
    const fetchReviews = vi.fn().mockResolvedValue([
      { opinion: null, work_content: null, is_blinded: true },
    ])
    const fetchReviewTeaser = vi.fn().mockResolvedValue({
      teaser: '공개 가능한 첫 줄',
      is_truncated: false,
    })

    const result = await loadFeaturedReviewPreviews({
      worksiteId: 6748,
      hasActivePass: true,
      fetchReviews,
      fetchReviewTeaser,
    })

    expect(result).toEqual([{ opinion: '공개 가능한 첫 줄' }])
  })

  it('공개할 티저가 없으면 빈 목록을 반환한다', async () => {
    const result = await loadFeaturedReviewPreviews({
      worksiteId: 6748,
      hasActivePass: false,
      fetchReviews: vi.fn(),
      fetchReviewTeaser: vi.fn().mockResolvedValue(null),
    })

    expect(result).toEqual([])
  })
})
