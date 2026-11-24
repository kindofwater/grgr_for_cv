import { useEffect, useRef, useState } from 'react'
import { Link, useLocation, useNavigate, useSearchParams } from 'react-router-dom'
import { searchWorksiteCards } from '../data/worksiteQueries'
import { sortKeyToParam } from '../lib/searchCards'
import { ratingBarColor } from '../lib/scores'
import { buildSearchFilters, countSelectedFilters } from '../lib/searchFilters'
import AdvancedSearch from '../components/AdvancedSearch'
import SearchSuggest from '../components/SearchSuggest'
import { canViewReviews } from '../lib/passes'
import { useAuth } from '../components/AuthContext'
import SkeletonSearch from '../components/SkeletonSearch'
import Pagination from '../components/Pagination'
import Dropdown from '../components/Dropdown'
import { PUBLIC_BROWSE, REVIEWS_OPEN_UNTIL } from '../config'
import { useLoginPrompt } from '../components/LoginPromptContext'
import CardTags from '../components/CardTags'
import PageMeta from '../components/PageMeta'
import './Search.css'

// 게이지 숨는 좁은 폭(≤660px)에서 숫자에 점수색을 입히는 클래스 (CSS는 그 미디어쿼리에서만 색 적용).
// 색 기준은 lib/scores의 ratingBarColor 하나가 정본 — 예전엔 여기 barColor 사본이 따로 있어 기준 변경 시 이중 수정이 필요했다.
const NUM_CLASS = { 'fill-blue': 'num-blue', 'fill-yellow': 'num-yellow', 'fill-red': 'num-red' }
function numColorClass(value) {
  return NUM_CLASS[ratingBarColor(value)] || ''
}

function RatingBar({ label, value, locked }) {
  const pct = value != null ? (value / 5) * 100 : 0
  return (
    <div className="rb-item">
      <div className="rb-label">
        {label}
        <span className={`${numColorClass(value)}${locked ? ' score-blur' : ''}`}>{value != null ? value.toFixed(1) : '-'}</span>
      </div>
      <div className={`rb-track${locked ? ' score-blur' : ''}`}><div className={`rb-fill ${ratingBarColor(value)}`} style={{ width: `${pct}%` }} /></div>
    </div>
  )
}

// SECURITY-DEBT(auth): 블러는 CSS 마스킹일 뿐 실 점수가 DOM에 존재. Auth 후 서버 게이팅. (debt #3)
function ResultCard({ card, locked, onWrite }) {
  const ws = card.worksite
  const p = card.posting
  const s = card.stats
  const has = !!(s && s.review_count > 0)
  // 열람권 O + 리뷰 O → 실점수. 잠금이면 실 stats 미사용(더미) → DOM에 실점수 안 박힘(비침/노출 차단)
  const showReal = has && !locked
  // 잠금 시 점수바 더미 폭(자연스러운 들쭉, 어차피 블러). 값은 가짜라 노출돼도 무의미.
  const DUMMY = { work: 3.5, growth: 2.8, vibe: 4.0, flex: 3.3, recommend: 4.5 }

  const typeTag = ws.type === 'national' ? '국가근장' : '학교근장'
  // 근장찾기는 2줄 공간이 넉넉 → 교내/교외 둘 다 표시(홈은 좁아서 교외만).
  const locTag = ws.type === 'school' ? null : (ws.location_type === 'off_campus' ? '교외' : (ws.location_type === 'on_campus' ? '교내' : null))   // 학교근장은 전부 교내라 태그 생략 / 국가근장만 교내·교외
  const degreeTag = ws.type === 'national' ? null : { 0: '학부생만', 1: '대학원생만' }[p?.eligible_degree]  // 국가근장은 항상 학부생만 → 생략
  const statusTag = ws.type === 'national' ? null : { 0: '재학생만', 1: '휴학생만' }[p?.eligible_status]  // 국가근장은 항상 재학생만 → 생략
  const trackTag = p?.preferred_track ? `${p.preferred_track}우대` : null  // 목업톤: 계열우대 파랑 강조
  const durationTag = p?.work_duration_type === 'short' ? '단기' : null  // 장기는 기본이라 생략, 단기만 표시(국가근장은 항상 장기라 안 뜸 — 학교근장에서만 의미)

  // 1층: 유형(학교/국가)·교내외(교외만)·지역·기간(단기만) / 2층: 우대·학위·학적
  // 2층은 태그 0개여도 .tag-row(min-height 22px)가 한 줄 예약 → 태그 수와 무관하게 카드 높이 동일(2줄 고정)
  const row1Tags = [
    { label: typeTag, cls: ws.type === 'national' ? 'tag-national' : 'tag-school' },
    locTag && { label: locTag, cls: 'tag-loc' },
    ws.type === 'national' && ws.region && { label: ws.region, cls: 'tag-region' },
    durationTag && { label: durationTag, cls: 'tag-dur' },
  ].filter(Boolean)
  const row2Tags = [
    trackTag && { label: trackTag, cls: 'tag-blue' },
    degreeTag && { label: degreeTag, cls: 'tag-gray' },
    statusTag && { label: statusTag, cls: 'tag-gray' },
  ].filter(Boolean)

  const bars = (
    <div className="rating-bars">
      <RatingBar label="업무" value={showReal ? Number(s.avg_work) : (locked ? DUMMY.work : null)} locked={locked} />
      <RatingBar label="자기계발" value={showReal ? Number(s.avg_growth) : (locked ? DUMMY.growth : null)} locked={locked} />
      <RatingBar label="분위기" value={showReal ? Number(s.avg_vibe) : (locked ? DUMMY.vibe : null)} locked={locked} />
      <RatingBar label="시간 유연성" value={showReal ? Number(s.avg_flex) : (locked ? DUMMY.flex : null)} locked={locked} />
    </div>
  )
  const bigNum = showReal ? Number(s.avg_recommend).toFixed(1) : (locked ? DUMMY.recommend.toFixed(1) : '-')
  const blurScores = locked  // 잠금이면 리뷰 유무 무관 항상 블러(통일성) — 밑바탕은 더미
  const reviewBtn = (
    <button className="btn-review-write" onClick={(e) => { e.stopPropagation(); onWrite(ws.id) }}>리뷰 쓰기</button>
  )

  return (
    <article
      className={`result-card ${card.is_active ? 'status-open' : 'status-closed'}`}
    >
      <Link
        className="result-card-detail-link"
        to={`/worksite/${ws.id}`}
        aria-label={`${ws.organization_name} ${ws.workplace_name} 상세 보기`}
        title={ws.workplace_name}
      />
      <div>
        <div className="rc-org" title={ws.organization_name}>{ws.organization_name}</div>
        <div className="rc-name" title={ws.workplace_name}>{ws.workplace_name}</div>
        {ws.type === 'school' ? (
          // 학교근장: 층 구분 없이 순서대로 흘림(교내 태그가 없어 1층이 [학교근장] 하나로 비는 것 방지).
          // 2행 높이(min-height 48px)는 예약 유지 → 국가근로 2행 카드와 높이 정합.
          <div className="tag-rows-flow">
            <CardTags tags={[...row1Tags, ...row2Tags]} />
          </div>
        ) : (
          <div className="tag-rows">
            <div className="tag-row">
              <CardTags tags={row1Tags} />
            </div>
            <div className="tag-row">
              <CardTags tags={row2Tags} />
            </div>
          </div>
        )}
      </div>

      <div className="rc-mid">
        {bars}
        <div className="rec-text">
          {has
            ? <>리뷰 {s.review_count}개 · <strong>{s.recommend_rate}%</strong>가 이 근무지를 추천합니다</>
            : '아직 리뷰가 없어요'}
        </div>
      </div>

      {blurScores ? (
        // 잠금(블러): 점수만 블러, 버튼은 wrapper로 빼서 클릭 가능 — 목업 블러 카드 구조
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 0, justifySelf: 'end' }}>
          <div className="rc-right rc-right-locked">
            <div className="big-num score-blur">{bigNum}</div>
            <div className="big-label">추천 점수</div>
          </div>
          {reviewBtn}
        </div>
      ) : (
        // 기본: 버튼이 .rc-right 안 — 목업 기본 카드 구조
        <div className="rc-right">
          <div className="big-num">{bigNum}</div>
          <div className="big-label">추천 점수</div>
          {reviewBtn}
        </div>
      )}
    </article>
  )
}

export default function Search() {
  const navigate = useNavigate()
  const { user: authUser } = useAuth()
  const { promptLogin } = useLoginPrompt()
  const [searchParams] = useSearchParams()
  const location = useLocation()

  // 홈 검색어는 navigation state로 옴(주소창에 안 남음). ?q=는 옛 링크·북마크 호환용 폴백.
  const initialQRef = useRef(location.state?.q ?? searchParams.get('q') ?? '')
  const initialQ = initialQRef.current
  const [query, setQuery] = useState(initialQ)              // 검색창 입력값
  const [submittedQuery, setSubmittedQuery] = useState(initialQ) // 실제 검색에 쓰는 확정 검색어
  const [sortKey, setSortKey] = useState('추천순')
  const [perPage, setPerPage] = useState(20)
  const [page, setPage] = useState(1)

  const [cards, setCards] = useState([])
  const [total, setTotal] = useState(0)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  const boxRef = useRef(null)
  const suggestRef = useRef(null)   // SearchSuggest.close() 호출용(제출 시 닫기)
  // 제안 드롭다운 열림 여부(SearchSuggest가 통지) — 열렸을 때만 검색창+드롭다운을 한 덩어리로 붙임
  const [suggestOpen, setSuggestOpen] = useState(false)

  // 고급검색
  const [showAdvanced, setShowAdvanced] = useState(false)
  const EMPTY_FILTER = {
    recruit: [],
    type: [],
    location: [],
    region: [],
    duration: [],
    track: [],
    degree: [],
    status: [],
  }
  const [appliedFilters, setAppliedFilters] = useState(EMPTY_FILTER)
  const [draftFilters, setDraftFilters] = useState(EMPTY_FILTER)
  // 패널에서 고른 값을 즉시 표시한다. 실제 결과에는 검색 버튼을 누를 때 함께 적용된다.
  const filterCount = countSelectedFilters(draftFilters)

  const isAnon = !authUser                                 // 비로그인 공개(PUBLIC_BROWSE) — locked로 취급됨
  const locked = !canViewReviews(authUser?.pass_expires_at, REVIEWS_OPEN_UNTIL)   // 한시 전면 공개 기간엔 비로그인도 unlocked
  // 잠금 상태면 점수가 가려져 점수 정렬이 무의미 → 추천순 고정
  const effectiveSort = locked ? '추천순' : sortKey

  // 로그인 가드 (PUBLIC_BROWSE면 비로그인 통과 — 검색 공개)
  useEffect(() => {
    if (!authUser && !PUBLIC_BROWSE) navigate('/login', { replace: true })   // 인증 바운스는 replace
  }, [authUser, navigate])

  // 홈/옛 ?q= 링크에서 받은 검색어는 첫 렌더에서만 소비하고 히스토리에는 남기지 않는다.
  // 그래야 상세 등으로 이동했다가 뒤로 와도 예전 검색어·제안 드롭다운이 되살아나지 않는다.
  useEffect(() => {
    const hasStateQuery = location.state && Object.prototype.hasOwnProperty.call(location.state, 'q')
    if (hasStateQuery || searchParams.has('q')) {
      navigate(location.pathname, { replace: true, state: null })
    }
  }, [location.pathname, location.state, navigate, searchParams])

  // 카드 결과: 검색어/정렬/페이지/perPage 변하면 서버 호출 (프론트 재정렬·필터 없음)
  useEffect(() => {
    if (!authUser && !PUBLIC_BROWSE) return
    let alive = true
    ;(async () => {
      setLoading(true)
      try {
        const { cards: rows, total: t } = await searchWorksiteCards({
          query: submittedQuery,
          sort: sortKeyToParam(effectiveSort),
          page,
          perPage,
          filters: buildSearchFilters(appliedFilters),
        })
        if (!alive) return
        // 빈 페이지인데 page>1 → 데이터 축소 등으로 범위 초과. 1페이지로 재요청.
        if (rows.length === 0 && page > 1) { setPage(1); return }
        setCards(rows); setTotal(t); setLoading(false)
      } catch (e) {
        if (alive) { setError(e.message); setLoading(false) }
      }
    })()
    return () => { alive = false }
  }, [authUser, submittedQuery, effectiveSort, page, perPage, appliedFilters])

  // 제안 드롭다운(입력 중 fetch·매칭강조·바깥클릭·붙는모양)은 SearchSuggest 컴포넌트가 담당.

  // Enter/상단 검색버튼: 입력값과 현재 고급검색 선택을 함께 확정하고 1페이지부터
  function runSearch() {
    setSubmittedQuery(query.trim())
    setAppliedFilters(draftFilters)
    setPage(1)
    suggestRef.current?.close()   // 제출 시 제안 드롭다운 닫기(결과가 가려지지 않게)
  }

  // 고급검색 반영: 현재 검색창 값과 선택 필터를 함께 확정.
  // 검색창을 지운 뒤 필터 검색을 눌러도 이전 submittedQuery가 남지 않게 한다.
  function applyFilters(selection) {
    setSubmittedQuery(query.trim())
    setDraftFilters(selection)
    setAppliedFilters(selection)
    setPage(1)
    suggestRef.current?.close()
  }
  // 초기화: 필터 + 검색어 전부 비우고 전체 결과로
  function resetAll() {
    setAppliedFilters(EMPTY_FILTER)
    setDraftFilters(EMPTY_FILTER)
    setQuery('')
    setSubmittedQuery('')
    setPage(1)
  }

  const totalPages = Math.max(1, Math.ceil(total / perPage))
  const safePage = Math.min(page, totalPages)
  function handlePageChange(nextPage) {
    const normalizedPage = Math.max(1, Math.min(nextPage, totalPages))
    if (normalizedPage !== page) setPage(normalizedPage)
    window.requestAnimationFrame(() => {
      window.scrollTo({ top: 0, behavior: 'smooth' })
    })
  }

  return (
    <div className="search-page">
      <PageMeta title="근장찾기" />
      <div className="search-head">
        <div className={`search-bar-md${suggestOpen ? ' is-suggest-open' : ''}`} ref={boxRef}>
          <input
            type="text"
            placeholder="근장 이름, 위치로 검색하세요"
            autoComplete="off"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter') runSearch() }}
          />
          <button aria-label="검색" type="button" onClick={runSearch}>
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 28 28" fill="none" stroke="white" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
              <circle cx="11" cy="11" r="8" /><line x1="24" y1="24" x2="16.66" y2="16.66" />
            </svg>
          </button>
          <SearchSuggest ref={suggestRef} query={query} containerRef={boxRef} onOpenChange={setSuggestOpen} />
        </div>
        <div className="filter-toggle-btn">
          <button type="button" onClick={() => setShowAdvanced((v) => !v)}>
            고급검색{filterCount ? ` (${filterCount})` : ''} {showAdvanced ? '▴' : '▾'}
          </button>
        </div>
        {showAdvanced && (
          <AdvancedSearch
            key={JSON.stringify(appliedFilters)}
            initial={draftFilters}
            onChange={setDraftFilters}
            onApply={applyFilters}
            onReset={resetAll}
          />
        )}
      </div>

      {/* 검색 헤더는 항상 즉시 렌더(네이버식). 아래 결과 영역만 로딩/에러/결과 분기 */}
      {/* 스켈레톤은 첫 로딩(결과가 아직 없을 때)에만. 재검색/정렬/페이지 변경 땐 기존 결과를 유지했다가
          새 결과가 오면 자리에서 교체 → 결과바·리스트가 통째로 스켈레톤으로 깜빡이던 '전체 울렁' 제거 */}
      {error ? (
        <div className="search-error">에러: {error}</div>
      ) : loading && cards.length === 0 ? (
        <SkeletonSearch />
      ) : (
      <>
      {locked && (
        <div className="lock-banner">
          <span className="lock-banner-text">
            <span className="lock-banner-icon">
              <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                <rect x="5" y="11" width="14" height="9" rx="2" /><path d="M8.5 11V8a3.5 3.5 0 0 1 7 0v3" />
              </svg>
            </span>
            {isAnon ? '로그인하면 점수와 리뷰 내용을 확인할 수 있어요' : '열람권이 있으면 점수와 리뷰 내용을 확인할 수 있어요'}
          </span>
          {isAnon
            ? <button onClick={() => navigate('/login')} className="lock-banner-cta">로그인하고 보기 →</button>
            : <button onClick={() => navigate('/exchange')} className="lock-banner-cta">열람권 교환하러 가기 →</button>}
        </div>
      )}

      <div className="results-bar">
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <div style={{ width: 100 }}>
            <Dropdown size="sm" value={String(perPage)} ariaLabel="페이지당 개수"
              onChange={(v) => { setPerPage(Number(v)); setPage(1) }}
              options={[
                { value: '10', label: '10개씩' },
                { value: '20', label: '20개씩' },
                { value: '30', label: '30개씩' },
                { value: '50', label: '50개씩' },
              ]} />
          </div>
          <span className="results-count">전체 근장 <strong>{total}개</strong></span>
        </div>
        <div className="status-legend">
          <span className="legend-item"><span className="legend-dot dot-green"></span>모집중</span>
          <span className="legend-item"><span className="legend-dot dot-red"></span>모집완료</span>
        </div>
        <div style={{ width: 135, marginLeft: 20 }}>
          <Dropdown size="sm" value={effectiveSort} disabled={locked} ariaLabel="정렬"
            onChange={(v) => { setSortKey(v); setPage(1) }}
            options={locked ? ['추천순'] : ['추천순', '리뷰 많은 순']} />
        </div>
      </div>

      <div className="result-list">
        {cards.length === 0 ? (
          <div className="search-empty">{submittedQuery ? '검색 결과가 없어요.' : '표시할 근장이 없어요.'}</div>
        ) : (
          cards.map((card) => (
            <ResultCard
              key={card.worksite.id}
              card={card}
              locked={locked}
              onWrite={(id) => isAnon ? promptLogin() : navigate(`/worksite/${id}/review`)}
            />
          ))
        )}
      </div>

      {cards.length > 0 && totalPages > 1 && (
        <Pagination page={safePage} totalPages={totalPages} onPage={handlePageChange} />
      )}
      </>
      )}
    </div>
  )
}
