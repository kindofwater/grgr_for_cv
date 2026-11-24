import { ratingBarColor } from '../lib/scores'

function Bar({ label, value }) {
  const pct = value ? (value / 5) * 100 : 0
  return (
    <div className="sum-row">
      <span className="sum-lbl">{label}</span>
      <div className="sum-track"><div className={`sum-fill ${ratingBarColor(value)}`} style={{ width: `${pct}%` }} /></div>
      <span className="sum-val" style={{ color: 'var(--primary-dark)' }}>{value ? value.toFixed(1) : '-'}</span>
    </div>
  )
}

// publicOnly = 잠금(비로그인·무열람권): 개수·추천율만. 세부 별점은 DOM에도 없음.
// (예전 locked prop = 실점수를 DOM에 넣고 CSS 마스킹만 = debt#3 → 제거. 잠금은 이제 publicOnly 하나로 통일)
export default function ScoreSummary({ summary, publicOnly }) {
  if (summary.count === 0) {
    return (
      <div className="summary-card">
        <div style={{ textAlign: 'center', padding: '20px 0', color: 'var(--text-muted)', fontSize: 13 }}>
          아직 리뷰가 없어서 집계할 수 없어요.
        </div>
      </div>
    )
  }
  // 비로그인 공개(soft-wall): 개수·추천율만. 세부 별점(overall·항목별)은 렌더하지 않음(DOM에도 없음).
  if (publicOnly) {
    return (
      <div className="summary-card locked-summary">
        <div className="public-rec">리뷰 {summary.count}개 · <strong>{summary.recommendRate}%</strong>가 이 근무지를 추천합니다</div>
      </div>
    )
  }

  const bars = (
    <>
      <Bar label="업무" value={summary.work} />
      <Bar label="자기계발" value={summary.growth} />
      <Bar label="분위기" value={summary.vibe} />
      <Bar label="시간 유연성" value={summary.flex} />
    </>
  )

  return (
    <div className="summary-card">
      <div className="overall">
        <div className="overall-num">{summary.overall.toFixed(1)}</div>
        <div className="overall-sub">리뷰 {summary.count}개 · 추천율 {summary.recommendRate}%</div>
      </div>
      {bars}
    </div>
  )
}
