import './Pagination.css'

// 윈도우식 페이지 목록: 1 … (현재±1) … 마지막. 7페이지 이하면 전부.
function pageItems(current, total) {
  const out = []
  if (total <= 7) {
    for (let i = 1; i <= total; i++) out.push(i)
    return out
  }
  out.push(1)
  if (current > 3) out.push('…')
  const start = Math.max(2, current - 1)
  const end = Math.min(total - 1, current + 1)
  for (let i = start; i <= end; i++) out.push(i)
  if (current < total - 2) out.push('…')
  out.push(total)
  return out
}

// 공용 페이지네이션 — 근장찾기·공지 등 목록 페이지에서 재사용.
// props: page(현재), totalPages(전체 페이지 수), onPage(번호 클릭 콜백)
export default function Pagination({ page, totalPages, onPage }) {
  return (
    <div className="pagination">
      <button className="pg-btn pg-arrow" disabled={page <= 1} onClick={() => onPage(page - 1)} aria-label="이전 페이지">‹</button>
      {pageItems(page, totalPages).map((it, i) =>
        it === '…' ? (
          <span key={`e${i}`} className="pg-ellipsis">…</span>
        ) : (
          <button key={it} className={`pg-btn${it === page ? ' active' : ''}`} onClick={() => onPage(it)}>{it}</button>
        )
      )}
      <button className="pg-btn pg-arrow" disabled={page >= totalPages} onClick={() => onPage(page + 1)} aria-label="다음 페이지">›</button>
    </div>
  )
}
