function hasReviewText(review) {
  return Boolean(
    review?.opinion?.trim()
    || review?.work_content?.trim(),
  )
}

function teaserAsReview(teaser) {
  if (!teaser?.teaser?.trim()) return []
  return [{
    opinion: teaser.teaser.trim() + (teaser.is_truncated ? '…' : ''),
  }]
}

// 홈 상단 추천카드용 리뷰 미리보기.
// 무열람권 사용자는 전체 리뷰 RPC를 거치지 않고 서버가 잘라 준 티저만 받는다.
// 열람권 사용자의 리뷰 목록에 표시할 내용이 없을 때도 티저로 폴백한다.
export async function loadFeaturedReviewPreviews({
  worksiteId,
  hasActivePass,
  fetchReviews,
  fetchReviewTeaser,
}) {
  if (!hasActivePass) {
    return teaserAsReview(await fetchReviewTeaser(worksiteId))
  }

  try {
    const reviews = (await fetchReviews(worksiteId)).filter(hasReviewText)
    if (reviews.length > 0) return reviews
  } catch {
    // 전체 리뷰 호출이 실패해도 공개 티저로 한 번 더 복구한다.
  }

  return teaserAsReview(await fetchReviewTeaser(worksiteId))
}
