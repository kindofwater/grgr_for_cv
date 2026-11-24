import { useEffect, useState, useCallback, useRef } from 'react'
import PinIcon from '../components/PinIcon'
import { fetchNotices, fetchNoticeById, fetchNoticeContents } from '../data/noticeQueries'
import { useSearchParams } from 'react-router-dom'

const PER_PAGE = 10
import { formatDate, noticeActivityAt } from '../lib/dates'
import Pagination from '../components/Pagination'
import PageMeta from '../components/PageMeta'
import './Notice.css'

export default function Notice() {
  const [list, setList] = useState(null)   // null = 로딩 중, 배열 = 로드 완료
  const [error, setError] = useState(null)
  const [openId, setOpenId] = useState(null)        // 펼친 공지 id (1개만 열림)
  const [bodies, setBodies] = useState({})          // id → { content } | { error } (없으면 로딩 중)
  const [page, setPage] = useState(1)               // 목록 페이지 (10개씩)
  const prefetchedRef = useRef(new Set())           // prefetch 요청한 id (중복 요청 방지)
  const [searchParams, setSearchParams] = useSearchParams()   // 홈 등에서 ?open=:id 로 진입
  const appliedOpenRef = useRef(false)              // ?open 적용 1회만

  const load = useCallback(() => {
    fetchNotices()
      .then((data) => setList(data))
      .catch((err) => setError(err.message))
  }, [])

  useEffect(() => { load() }, [load])

  // 현재 페이지의 10개 본문을 한 번에 미리 받아 캐시 → 펼칠 때 즉시 표시(전체는 안 받음).
  // dedup 표시(prefetchedRef)는 fetch '성공 후'에 찍는다 — 미리 찍으면 StrictMode 2회 실행 시
  // 1차가 표시만 해두고 버려지고 2차가 스킵돼 bodies가 안 채워진다(dev 한정 버그).
  useEffect(() => {
    if (!list || list.length === 0) return
    const tp = Math.max(1, Math.ceil(list.length / PER_PAGE))
    const sp = Math.min(page, tp)
    const ids = list
      .slice((sp - 1) * PER_PAGE, sp * PER_PAGE)
      .map((n) => n.id)
      .filter((id) => !prefetchedRef.current.has(id))
    if (ids.length === 0) return
    let alive = true
    fetchNoticeContents(ids)
      .then((rows) => {
        if (!alive) return
        rows.forEach((r) => prefetchedRef.current.add(r.id))   // 성공한 것만 dedup 표시
        setBodies((b) => {
          const next = { ...b }
          for (const r of rows) next[r.id] = { content: r.content ?? '' }
          return next
        })
      })
      .catch(() => { /* 실패 시 표시 안 함 → 다음 진입/펼칠 때 재시도(폴백) */ })
    return () => { alive = false }
  }, [list, page])

  // 홈 등에서 ?open=:id 로 들어오면 해당 공지가 있는 페이지로 이동 + 펼침(아코디언 통일). 최초 1회.
  // 본문은 직접 로드 — prefetch 타이밍/StrictMode에 의존하지 않게(폴백 없이도 바로 보이도록).
  useEffect(() => {
    if (appliedOpenRef.current || !list) return
    const id = Number(searchParams.get('open'))
    if (!id) return
    const idx = list.findIndex((n) => n.id === id)
    if (idx === -1) return
    appliedOpenRef.current = true
    setPage(Math.floor(idx / PER_PAGE) + 1)
    setSearchParams({}, { replace: true })   // URL의 ?open 제거 → 새로고침 시 재오픈 방지(딥링크 1회성)
    // 본문을 먼저 확보한 뒤 openId 설정 → 닫힌 상태가 먼저 그려지고, 내용이 있는 채로 펼쳐져
    // grid 0fr→1fr 트랜지션이 정상 재생(본문 로드 전에 열면 빈 채로 트랜지션이 끝나 애니메이션이 안 보임).
    if (bodies[id]?.content !== undefined || bodies[id]?.error) {
      setOpenId(id)
    } else {
      fetchNoticeById(id)
        .then((data) => { setBodies((b) => (b[id] ? b : { ...b, [id]: { content: data?.content ?? '' } })); setOpenId(id) })
        .catch((e) => { setBodies((b) => (b[id] ? b : { ...b, [id]: { error: e.message } })); setOpenId(id) })
    }
  }, [list, searchParams, setSearchParams])

  const retry = () => {
    setError(null)
    setList(null)
    load()
  }

  // 카드 클릭: 펼치기/접기. 본문은 펼칠 때 지연 로드(전체를 미리 받지 않아 공지 많아져도 가벼움).
  function toggle(id) {
    const next = openId === id ? null : id
    setOpenId(next)
    if (next !== null && !bodies[id]) {
      fetchNoticeById(id)
        .then((data) => setBodies((b) => ({ ...b, [id]: { content: data?.content ?? '' } })))
        .catch((e) => setBodies((b) => ({ ...b, [id]: { error: e.message } })))
    }
  }

  // 로딩 중(list===null)엔 스켈레톤 없이 빈 영역 → 로드되면 목록 표시(카드 높이 정합이 애매해 스켈레톤 생략)
  const totalPages = Math.max(1, Math.ceil((list?.length ?? 0) / PER_PAGE))
  const safePage = Math.min(page, totalPages)
  const pageList = (list ?? []).slice((safePage - 1) * PER_PAGE, safePage * PER_PAGE)

  return (
    <div className="notice-wrap">
      <PageMeta title="공지사항" />
      <div className="notice-page">
        {error && (
          <div className="notice-state">
            <p>공지를 불러오지 못했어요.</p>
            <button className="notice-retry" onClick={retry}>다시 시도</button>
          </div>
        )}

        {!error && list !== null && list.length === 0 && (
          <p className="notice-state">등록된 공지가 없습니다.</p>
        )}

        {!error && list !== null && list.length > 0 && (
          <ul className="notice-list">
            {pageList.map((n) => {
              const open = openId === n.id
              const body = bodies[n.id]
              return (
                <li
                  key={n.id}
                  className={['notice-card', open && 'is-open'].filter(Boolean).join(' ')}
                >
                  <button className="notice-card-head" onClick={() => toggle(n.id)} aria-expanded={open}>
                    <div className="notice-card-main">
                      <div className="notice-card-top">
                        {n.is_pinned && <PinIcon />}
                        <span className="notice-date">{formatDate(noticeActivityAt(n.created_at, n.updated_at))}</span>
                      </div>
                      <div className="notice-card-title">
                        {n.title}
                      </div>
                    </div>
                    <span className="notice-chevron" aria-hidden="true">▾</span>
                  </button>

                  {/* 펼침 애니메이션: 래퍼는 항상 렌더, is-open이 grid-rows 0fr↔1fr로 높이 전환 */}
                  <div className="notice-card-bodywrap">
                    <div className="notice-card-bodyinner">
                      {(body?.content !== undefined || body?.error) && (
                        <div className="notice-card-body">
                          {body.error ? (
                            <div className="notice-body-state">본문을 불러오지 못했어요.</div>
                          ) : (
                            <div className="notice-body-text">{body.content || '내용이 없습니다.'}</div>
                          )}
                        </div>
                      )}
                    </div>
                  </div>
                </li>
              )
            })}
          </ul>
        )}

        {/* 공지가 10개 이하(1페이지)여도 페이지네이션을 항상 노출 */}
        {!error && list !== null && list.length > 0 && (
          <Pagination
            page={safePage}
            totalPages={totalPages}
            onPage={(p) => { setPage(p); setOpenId(null) }}
          />
        )}
      </div>
    </div>
  )
}
