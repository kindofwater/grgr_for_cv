import { forwardRef, useEffect, useImperativeHandle, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { searchWorksiteSuggestions } from '../data/worksiteQueries'
import './SearchSuggest.css'

// 최소 검색 글자 수 — 이 미만이면 RPC도 안 날리고 드롭다운도 안 연다(1글자는 매칭 너무 넓음).
const MIN_QUERY_LEN = 2

// 제안 항목에서 입력어와 일치하는 글자만 <span.ss-hl>로 강조(대소문자 무시).
// text.slice는 문자열(텍스트 노드)로 렌더 → dangerouslySetInnerHTML 없음(XSS 안전).
function highlightMatch(text, q) {
  const query = (q ?? '').trim()
  if (!query) return text
  const lower = text.toLowerCase()
  const lq = query.toLowerCase()
  const parts = []
  let i = 0
  let idx = lower.indexOf(lq)
  let key = 0
  while (idx !== -1) {
    if (idx > i) parts.push(text.slice(i, idx))
    parts.push(<span className="ss-hl" key={key++}>{text.slice(idx, idx + query.length)}</span>)
    i = idx + query.length
    idx = lower.indexOf(lq, i)
  }
  if (i < text.length) parts.push(text.slice(i))
  return parts
}

// 검색어 입력 → 근무지 제안 드롭다운(부분일치·매칭 강조, 클릭 시 상세 이동). 홈·근장찾기 공용.
// 데이터(searchWorksiteSuggestions) 직접 사용은 AdModal과 같은 '연결형 위젯' 예외(입력 중 fetch).
// UX: 검색바에 포커스가 있는 동안 입력하면 박스를 '먼저' 열어 모양을 바꾸고 → 결과는 디바운스 후 채운다.
// props:
//   query        : 현재 입력 문자열(부모가 소유하는 검색창 값)
//   containerRef : 검색바 래퍼 ref — 바깥클릭 닫힘 + 포커스 복귀 재오픈(입력창 클릭은 안 닫힘)
//   enabled      : false면 비활성(예: 홈 비로그인). 기본 true
//   onOpenChange : 열림 여부 통지 → 부모가 래퍼에 is-suggest-open 토글('붙는 모양'). 결과 유무와 무관.
// ref.close()    : 제출(Enter/검색버튼) 시 부모가 드롭다운을 닫는 용도
const SearchSuggest = forwardRef(function SearchSuggest({ query, containerRef, enabled = true, onOpenChange }, ref) {
  const navigate = useNavigate()
  const [suggestions, setSuggestions] = useState([])
  const [open, setOpen] = useState(false)
  const openRef = useRef(null)
  const debounceRef = useRef(null)

  useImperativeHandle(ref, () => ({ close: () => setOpen(false) }), [])

  // 입력창을 실제로 만지는 중이면 박스를 먼저 열고(모양 변경), 결과는 디바운스(200ms) 후 채움.
  // 홈에서 검색 페이지로 넘어온 초기 검색어처럼 focus 없이 주입된 값은 드롭다운을 자동으로 열지 않는다.
  // setState는 전부 타이머 콜백 안 — effect 본문 동기 setState 회피.
  useEffect(() => {
    const q = enabled ? (query ?? '').trim() : ''
    const hasSearchFocus = () => containerRef?.current?.contains?.(document.activeElement)
    if (openRef.current) clearTimeout(openRef.current)
    if (debounceRef.current) clearTimeout(debounceRef.current)
    openRef.current = setTimeout(() => {
      if (q.length < MIN_QUERY_LEN) { setOpen(false); setSuggestions([]) }
      else if (hasSearchFocus()) setOpen(true)
    }, 0)
    if (q.length >= MIN_QUERY_LEN) {
      debounceRef.current = setTimeout(async () => {
        try {
          const rows = await searchWorksiteSuggestions(q)
          setSuggestions(rows)
        } catch { /* 제안 실패는 무시 */ }
      }, 200)
    }
    return () => {
      if (openRef.current) clearTimeout(openRef.current)
      if (debounceRef.current) clearTimeout(debounceRef.current)
    }
  }, [query, enabled, containerRef])

  // 바깥 클릭 닫기 + 검색바 포커스 복귀 시(입력어 있으면) 재오픈. 래퍼=입력창+드롭다운 포함.
  useEffect(() => {
    const el = containerRef?.current
    const hasQuery = enabled && (query ?? '').trim().length >= MIN_QUERY_LEN
    function onDoc(e) { if (el && !el.contains(e.target)) setOpen(false) }
    function onFocusIn() { if (hasQuery) setOpen(true) }
    document.addEventListener('mousedown', onDoc)
    el?.addEventListener('focusin', onFocusIn)
    return () => {
      document.removeEventListener('mousedown', onDoc)
      el?.removeEventListener('focusin', onFocusIn)
    }
  }, [containerRef, query, enabled])

  // 열림 여부 통지(붙는 모양 토글) — 박스 모양은 결과와 무관하게 'open'에 따라.
  useEffect(() => { onOpenChange?.(open) }, [open, onOpenChange])

  if (!open) return null
  return (
    <ul className="search-suggest">
      {suggestions.map((s) => (
        <li key={s.worksite_id} onClick={() => navigate(`/worksite/${s.worksite_id}`)}>
          <span className="ss-name">{highlightMatch(`${s.organization_name} - ${s.workplace_name}`, query)}</span>
        </li>
      ))}
    </ul>
  )
})

export default SearchSuggest
