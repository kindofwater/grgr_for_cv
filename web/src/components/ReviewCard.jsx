import { formatDate } from '../lib/dates'
import { ratingBarColor } from '../lib/scores'

function authorLabel(r) {
  if (r.is_anonymous) return '익명'      // 익명 제출 리뷰 → 닉네임·근로학기 숨김 (회의 #18·#19). 익명 선택은 작성/수정 시.
  if (!r.author) return '탈퇴한 사용자'
  return r.author.nickname ? `${r.author.nickname}님` : '익명'     // 기본=닉네임 노출(익명 해제)는 PM 결정 (회의 #17·#110)
}

// 점수 숫자 색: 다른 페이지 게이지(lib/scores의 ratingBarColor)와 동일한 기준·색 — 파랑≥4.0 / 노랑≥3.0 / 빨강
const SCORE_TEXT = { 'fill-blue': 'sc-blue', 'fill-yellow': 'sc-yellow', 'fill-red': 'sc-red' }
function scoreTextClass(v) {
  return SCORE_TEXT[ratingBarColor(v)] || ''
}
function ScoreItem({ label, value }) {
  const n = Number(value) || 0
  return (
    <span className="rev-score">{label}<span className={`rev-score-num ${scoreTextClass(value)}`}>{n.toFixed(1)}</span></span>
  )
}

export default function ReviewCard({ review, isMine, onEdit, onDelete, onHelpful, onReport, helpfulActive }) {
  const r = review
  // 블라인드 처리된 리뷰: 서버(list_worksite_reviews)가 내용·점수·작성자를 이미 null 마스킹함.
  // 여기선 원문 대신 안내 슬롯만 렌더. is_blinded 미도입(마이그레이션 전)엔 undefined → 일반 렌더(하위호환).
  if (r.is_blinded) {
    return (
      <div className="review-card" style={{ textAlign: 'center', color: 'var(--text-muted)', padding: '28px 20px' }}>
        <div style={{ fontSize: 14, fontWeight: 600 }}>블라인드 처리된 리뷰입니다</div>
        <div style={{ fontSize: 12, marginTop: 6 }}>운영정책에 따라 가려진 리뷰예요.</div>
      </div>
    )
  }
  // 별 표시: 채운 별 = 1점, 속 빈 별 = 0.5점, 회색 별 = 0점.
  // 예전엔 Math.round로 정수 개수만 그려서 4.5가 별 5개(만점처럼) 보였다 — 숫자(4.5)와 어긋났다.
  // 0.5 단위로 반올림해 반개를 속 빈 별로 표현한다. (반쪽 별 문자 U+2BE8은 ★와 크기·정렬이
  //  안 맞아 깨진 별처럼 보여서 쓰지 않는다 — 실제로 그려 확인함)
  const recScore = Math.max(0, Math.min(5, Number(r.score_recommend) || 0))
  const recHalves = Math.round(recScore * 2)       // 0..10 (0.5점 단위)
  const recFull = Math.floor(recHalves / 2)
  const recHalf = recHalves % 2                    // 0 또는 1
  const recEmpty = 5 - recFull - recHalf
  return (
    <div className="review-card" style={isMine ? { borderColor: 'var(--primary-mid)' } : undefined}>
      <div className="rev-head">
        <div className="rev-head-left">
          <div className="rev-rec">
            {(!r.is_anonymous || isMine) && (
              <span className="rev-period">{r.work_year}년 {r.work_semester}</span>
            )}
            <span className="rev-rec-label">추천점수</span>
            <span className={`rev-rec-num ${scoreTextClass(r.score_recommend)}`}>{Number(r.score_recommend).toFixed(1)}</span>
            <span className="rev-stars" aria-hidden="true">
              <span className="star-on">{'★'.repeat(recFull)}</span>{recHalf ? <span className="star-half">☆</span> : null}<span className="star-off">{'★'.repeat(recEmpty)}</span>
            </span>
          </div>
          <div className="rev-scores">
            <ScoreItem label="업무" value={r.score_work} />
            <ScoreItem label="자기계발" value={r.score_growth} />
            <ScoreItem label="분위기" value={r.score_vibe} />
            <ScoreItem label="시간 유연성" value={r.score_flex} />
          </div>
        </div>
        <div className="rev-head-right">
          <div className="rev-who-line">
            <strong className="rev-who">{isMine ? '내 리뷰' : authorLabel(r)}</strong>
            {isMine && r.is_anonymous && <span className="rev-anon-tag">익명</span>}
          </div>
          {(!r.is_anonymous || isMine) && (
            <div className="rev-meta-sub">
              <span className="rev-date">{formatDate(r.created_at)}</span>
            </div>
          )}
        </div>
      </div>
      <div className="rev-section">
        <div className="rev-section-label">실제 업무</div>
        <div className="rev-section-text">{r.work_content}</div>
      </div>
      <div className="rev-section">
        <div className="rev-section-label">코멘트</div>
        <div className="rev-section-text">{r.opinion}</div>
      </div>
      <div className="rev-actions">
        <button className="btn-helpful" onClick={onHelpful} disabled={isMine} aria-pressed={helpfulActive}>
          도움됐어요 ({r.helpful_count ?? 0})
        </button>
        {isMine ? (
          <>
            <button className="btn-edit-review" onClick={onEdit} title="수정" aria-label="수정">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="var(--primary)" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7" /><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z" /></svg>
            </button>
            <button className="btn-delete-review" onClick={onDelete} title="삭제" aria-label="삭제">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="var(--danger)" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><polyline points="3 6 5 6 21 6" /><path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6" /><path d="M10 11v6" /><path d="M14 11v6" /><path d="M9 6V4a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2" /></svg>
            </button>
          </>
        ) : (
          <button className="btn-report" onClick={onReport}>신고</button>
        )}
      </div>
    </div>
  )
}
