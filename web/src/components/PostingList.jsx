import { useState } from 'react'
import { effectiveActive } from '../lib/recruit'
import { summarizeJob } from '../lib/postings'
import { PostingFields } from './InfoCard'
import './PostingList.css'

function PostingRow({ posting, isNational }) {
  const [open, setOpen] = useState(false)
  const isOpen = effectiveActive(posting)
  return (
    <div className={`posting-item ${isOpen ? 'status-open' : 'status-closed'}`}>
      {/* 접힌 줄 = 요약 + 마감일만. 모집중/완료는 카드 좌측 테두리 색(status-open 파랑/closed 회색)이 담당.
          날짜는 recruit_until(마감일) — created_at은 크롤 적재일이라 '올라온 날짜'가 아니다(일괄 적재분 전부 같은 날). */}
      <button className="posting-row" onClick={() => setOpen((v) => !v)} aria-expanded={open}>
        <span className="posting-summary">{summarizeJob(posting)}</span>
        {posting?.recruit_until && (
          <span className="posting-date">마감{posting.recruit_until_estimated ? '(추정)' : ''} {posting.recruit_until}</span>
        )}
        <span className="posting-caret" aria-hidden>{open ? '▲' : '▼'}</span>
      </button>
      {open && (
        <div className="posting-body">
          <PostingFields posting={posting} isNational={isNational} />
        </div>
      )}
    </div>
  )
}

// 근무지의 '다른 공고' 목록. 목록이 비면(국가근로·공고 1개뿐) 아무것도 렌더 안 함.
export default function PostingList({ postings, worksite }) {
  if (!postings || postings.length === 0) return null
  const isNational = worksite?.type === 'national'
  return (
    <div className="posting-list">
      <h3 className="posting-list-head">이 근무지의 최근 공고 {postings.length}개</h3>
      {postings.map((p) => (
        <PostingRow key={p.id} posting={p} isNational={isNational} />
      ))}
    </div>
  )
}
