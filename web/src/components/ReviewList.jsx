import ReviewCard from './ReviewCard'

// 잠금(비로그인·무열람권) = 서버가 최신 리뷰 '첫 줄'만 준다(get_worksite_review_teaser).
// 예전엔 리뷰카드 2장을 그대로 렌더하고 CSS 블러만 씌웠음(debt#3) → 서버 게이팅으로 교체, 전문이 DOM에 없음.
// 잠금이면 목록이 0행이므로 헤더 개수는 서버 집계(totalCount)를 쓴다.
export default function ReviewList({
  reviews = [], myReviewIds, locked, teaser, totalCount, isAnon,
  onWrite, onUnlock, handlers,
}) {
  // 블라인드 리뷰는 헤더 카운트에서 제외 → 홈/검색 카드 집계·상세 점수요약과 일치
  const reviewCount = locked ? (totalCount ?? 0) : reviews.filter((r) => !r.is_blinded).length
  return (
    <div>
      <div className="review-head">
        <h3>리뷰 {reviewCount}개</h3>
        <button className="btn-review-write" onClick={onWrite}>리뷰 쓰기</button>
      </div>

      {reviewCount === 0 ? (
        <div style={{ textAlign: 'center', padding: '60px 20px', color: 'var(--text-muted)' }}>
          <div style={{ fontSize: 15, fontWeight: 600, color: 'var(--text)', marginBottom: 8 }}>아직 작성된 리뷰가 없어요</div>
          <div style={{ fontSize: 13 }}>첫 번째 리뷰를 남겨 다른 학생들에게 도움을 주세요!</div>
        </div>
      ) : locked ? (
        <div className="review-teaser">
          {teaser?.teaser && (
            <>
              <div className="review-teaser-head">최근 리뷰</div>
              {/* 서버가 이미 60자로 자른 값 — 여기서 더 자르지 않는다(자를 게 없음) */}
              <p className="review-teaser-text">{teaser.teaser}{teaser.is_truncated ? '…' : ''}</p>
            </>
          )}
          {/* 첫 줄 아래 = 블러 + 해제 안내. 채우는 건 CSS 도형(빈 span)뿐 —
              가짜 리뷰 문장을 넣지 않는다. 넣으면 6672개 페이지에 같은 텍스트가 박혀
              검색·애드센스에 중복/저품질 신호가 된다(/search 더미 별점과 같은 실수). */}
          <div className="review-locked-rest">
            {/* ReviewCard의 골격(점수·별점·항목점수·본문 두 단락)만 도형으로 흉내낸다.
                블러는 형태와 색이 있어야 '리뷰가 가려졌다'로 읽힌다 — 밋밋한 회색 막대만 흐리면
                그냥 빈 카드로 보임. 텍스트는 여전히 0자. */}
            <div className="review-locked-fill" aria-hidden="true">
              {[0, 1].map((i) => (
                <div className="rlf-card" key={i}>
                  <div className="rlf-head">
                    <div className="rlf-num" />
                    <div className="rlf-stars" />
                    <div className="rlf-who" />
                  </div>
                  <div className="rlf-scores"><span /><span /><span /><span /></div>
                  <div className="rlf-line rlf-w95" />
                  <div className="rlf-line rlf-w78" />
                </div>
              ))}
            </div>
            <div className="review-locked-overlay">
              <div className="unlock-box">
                <p>
                  {isAnon
                    ? <>리뷰 전체는 로그인하고 볼 수 있어요.</>
                    : <>열람권이 있어야 리뷰를 볼 수 있어요.<br />포인트로 열람권을 교환해 보세요.</>}
                </p>
                <button className="btn-unlock" onClick={onUnlock}>
                  {isAnon ? '로그인하고 리뷰 보기' : '열람권 교환하기'}
                </button>
              </div>
            </div>
          </div>
        </div>
      ) : (
        reviews.map((r) => (
          <ReviewCard key={r.id} review={r} isMine={myReviewIds.has(r.id)} {...handlers(r)} />
        ))
      )}
    </div>
  )
}
