import { useEffect, useLayoutEffect, useRef, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { fetchHomeFeed, getWorksiteScoreCards, fetchReviews, fetchReviewTeaser } from '../data/worksiteQueries'
import { fetchNotices } from '../data/noticeQueries'
import { formatRelativeDate, noticeActivityAt } from '../lib/dates'
import { loadFeaturedReviewPreviews } from '../lib/homeReviewPreview'
import { canViewReviews } from '../lib/passes'
import { REVIEWS_OPEN_UNTIL } from '../config'
import { ratingBarColor } from '../lib/scores'
import { useAuth } from '../components/AuthContext'
import Dropdown from '../components/Dropdown'
import SearchSuggest from '../components/SearchSuggest'
import CardTags from '../components/CardTags'
import PageMeta from '../components/PageMeta'
import './Home.css'

// ── 로딩 스켈레톤 조각: 실제 레이아웃과 같은 클래스/크기 → 콘텐츠 swap 시 레이아웃 시프트 0 ──
const Sbox = ({ w = '100%', h = 16, mb = 8, br = 6 }) => (
  <div className="skeleton-box" style={{ width: w, height: h, marginBottom: mb, borderRadius: br }} />
)

// 실제 PlaceCard와 동일 구조/클래스(200px·name-box·score-box·tag-box)로 맞춰 카드 크기 일치
function CardSkeleton() {
  // 박스 높이를 실제 요소 높이에 맞춤(pname16·pplace24·pbig36·psub14·tag22), mb=0 → 간격은 .name-box/.score-box/.place-card-sm의 gap이 담당.
  // tag-box는 CSS에서 height:82px 고정이라 자동 일치 → 카드 총높이 = 실제와 동일(시프트 0).
  return (
    <div className="place-card-sm">
      <div className="name-box">
        <Sbox w="60%" h={16} mb={0} />
        <Sbox w="88%" h={24} mb={0} />
      </div>
      <div className="score-box">
        <Sbox w={56} h={36} mb={0} />
        <Sbox w="72%" h={14} mb={0} />
      </div>
      <div className="tag-box">
        <div className="tag-row">
          <Sbox w={52} h={22} mb={0} br={5} />
          <Sbox w={36} h={22} mb={0} br={5} />
        </div>
        <div className="tag-row tag-row-wrap">
          <Sbox w={96} h={22} mb={0} br={5} />
        </div>
      </div>
    </div>
  )
}

function PlaceCard({ p }) {
  const ws = p.worksite
  if (!ws) return null
  const typeTag = ws.type === 'national' ? '국가근장' : '학교근장'
  const locTag = ws.type === 'school' ? null : (ws.location_type === 'off_campus' ? '교외' : (ws.location_type === 'on_campus' ? '교내' : null))   // 학교근장은 전부 교내라 태그 생략 / 국가근장만 교내·교외 표시(Search·InfoCard 정합)
  const trackTag = p.preferred_track ? `${p.preferred_track}우대` : null
  const durationTag = p.work_duration_type === 'short' ? '단기' : null  // 장기는 기본이라 생략, 단기만 표시(국가근장은 항상 장기 → 학교근장에서만 뜸)

  // 국가근장은 항상 학부생만·재학생만 → 태그가 중복 노이즈라 생략(학교근장만 표시)
  const degreeTag = ws.type === 'national' ? null : { 0: '학부생만', 1: '대학원생만' }[p.eligible_degree]  // 2(둘 다)=생략
  const statusTag = ws.type === 'national' ? null : { 0: '재학생만', 1: '휴학생만' }[p.eligible_status]  // 2(둘 다)=생략

  const tags = [
    { label: typeTag, cls: ws.type === 'national' ? 'tag-national' : 'tag-school' },
    locTag && { label: locTag, cls: 'tag-loc' },
    ws.type === 'national' && ws.region && { label: ws.region, cls: 'tag-region' },
    durationTag && { label: durationTag, cls: 'tag-dur' },
    trackTag && { label: trackTag, cls: 'tag-blue' },
    degreeTag && { label: degreeTag, cls: 'tag-gray' },
    statusTag && { label: statusTag, cls: 'tag-gray' },
  ].filter(Boolean)

  return (
    <Link
      to={`/worksite/${ws.id}`}
      className={`place-card-sm ${p.is_active ? 'status-open' : 'status-closed'}`}
    >
      <div className="pc-row1">
        <div className="pc-left">
          <div className="pname" title={ws.organization_name}>{ws.organization_name}</div>
          <div className="pplace" title={ws.workplace_name}>{ws.workplace_name}</div>
        </div>
        <div className="pc-right">
          <div className="pbig" style={!p.avg_score ? { color: 'var(--text-muted)' } : undefined}>
            {p.avg_score != null ? Number(p.avg_score).toFixed(1) : '-'}
          </div>
          <div className="psub">
            리뷰 {p.review_count > 0 ? `${p.review_count}개` : '없음'}
          </div>
        </div>
      </div>
      <div className="tag-box">
        <div className="tag-row">
          <CardTags tags={tags} max={3} />
        </div>
      </div>
    </Link>
  )
}

function CardSection({ title, list, showLegend, loading, filterKey }) {
  const scrollRef = useRef(null)
  const [atStart, setAtStart] = useState(true)
  const [atEnd, setAtEnd] = useState(true)   // 오버플로 없으면 화살표 안 뜸

  function updateArrows() {
    const el = scrollRef.current
    if (!el) return
    setAtStart(el.scrollLeft <= 1)
    setAtEnd(el.scrollLeft + el.clientWidth >= el.scrollWidth - 1)
  }

  // 데이터 로드/리사이즈 시 화살표 노출 여부 재계산
  useEffect(() => {
    updateArrows()
    window.addEventListener('resize', updateArrows)
    return () => window.removeEventListener('resize', updateArrows)
  }, [list])

  // 필터 바뀌면 선반을 맨 앞(왼쪽 처음)으로 리셋 — 필터 변경 시에만. 데이터 갱신엔 유지.
  //
  // ⚠️ filterKey 변화 시점에 바로 scrollLeft=0 하면 안 된다(예전 버그): 필터가 바뀌어도 loading이
  //    다시 true가 되지 않아 선반 DOM이 언마운트되지 않는다. 그래서 리셋이 '옛 카드 목록' 위에서
  //    먼저 실행되고, 다음 커밋에서 카드가 교체되면 Chrome이 scroll-snap 재스냅으로 '이전에 스냅돼
  //    있던 카드'를 되살려 스크롤을 원위치시킨다(측정: 516 → 0 → 다시 516).
  //    → 리셋을 예약해뒀다가 list가 실제로 바뀐 뒤에 실행한다. 순서를 뒤집으면 0이 유지된다.
  //    (scroll-snap을 끄는 것도 방법이지만 카드 정렬감을 잃는다 — 순서만 고치면 스냅은 그대로 둘 수 있다)
  const pendingResetRef = useRef(false)
  useLayoutEffect(() => { pendingResetRef.current = true }, [filterKey])
  // 화면에 그려지기 전(useLayoutEffect)에 되돌려야 잘못된 위치가 한 프레임 비치지 않는다.
  useLayoutEffect(() => {
    if (!pendingResetRef.current) return
    pendingResetRef.current = false
    const el = scrollRef.current
    if (el) el.scrollLeft = 0
    updateArrows()
  }, [list])

  function scrollCards(dir) {
    const el = scrollRef.current
    if (el) el.scrollBy({ left: dir * el.clientWidth * 0.8, behavior: 'smooth' })
  }

  return (
    <div className="section">
      <div className="section-title-row">
        <div className="section-title">{title}</div>
        {showLegend && (
          <div className="status-legend">
            <span className="legend-item"><span className="legend-dot dot-green"></span>모집중</span>
            <span className="legend-item"><span className="legend-dot dot-red"></span>모집완료</span>
          </div>
        )}
      </div>
      {loading ? (
        <div className="card-scroll">
          {[0, 1, 2, 3, 4].map((i) => <CardSkeleton key={i} />)}
        </div>
      ) : list.length === 0 ? (
        <div className="card-empty">현재 보여줄 수 있는 카드가 없어요.</div>
      ) : (
        <div className="card-scroll-wrap">
          {!atStart && (
            <button className="card-scroll-arrow left" onClick={() => scrollCards(-1)} aria-label="이전 근장 보기">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="M15 18l-6-6 6-6" /></svg>
            </button>
          )}
          <div className="card-scroll" ref={scrollRef} onScroll={updateArrows}>
            {/* key = 근무지 id. 서버 피드로 전환하며 카드가 근무지 단위가 됐다(예전엔 공고 p.id). */}
            {list.map(p => <PlaceCard key={p.worksite.id} p={p} />)}
          </div>
          {!atEnd && (
            <button className="card-scroll-arrow right" onClick={() => scrollCards(1)} aria-label="다음 근장 보기">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="M9 18l6-6-6-6" /></svg>
            </button>
          )}
        </div>
      )}
    </div>
  )
}

// (홈 모바일 필터 드롭다운은 공용 <Dropdown size="sm" label dotClass>로 통일 — FilterDropdown 제거)

// ── 근로고래 추천 근장 1곳 (상세 카드) ──
// 세부점수(업무/자기계발/분위기/유연) 막대 포함. 버튼 없이 카드 전체 클릭 → 상세로.
// 점수·후기는 로그인 게이팅(비로그인은 '-' + 클릭 시 로그인 모달) — 홈의 다른 카드와 동일 정책.
function FeaturedRec({ p, stats, reviews = [], statsLoading, heading, isLoggedIn }) {
  const ws = p.worksite
  const typeTag = ws.type === 'national' ? '국가근장' : '학교근장'
  const locTag = ws.type === 'school' ? null : (ws.location_type === 'off_campus' ? '교외' : (ws.location_type === 'on_campus' ? '교내' : null))   // 학교근장은 전부 교내라 태그 생략 / 국가근장만 교내·교외 표시(Search·InfoCard 정합)
  const trackTag = p.preferred_track ? `${p.preferred_track}우대` : null
  const durationTag = p.work_duration_type === 'short' ? '단기' : null  // 장기는 기본이라 생략, 단기만 표시(국가근장은 항상 장기 → 학교근장에서만 뜸)
  const degreeTag = ws.type === 'national' ? null : { 0: '학부생만', 1: '대학원생만' }[p.eligible_degree]  // 국가근장은 항상 학부생만 → 생략
  const statusTag = ws.type === 'national' ? null : { 0: '재학생만', 1: '휴학생만' }[p.eligible_status]  // 국가근장은 항상 재학생만 → 생략

  const tags = [
    { label: typeTag, cls: ws.type === 'national' ? 'tag-national' : 'tag-school' },
    locTag && { label: locTag, cls: 'tag-loc' },
    ws.type === 'national' && ws.region && { label: ws.region, cls: 'tag-region' },
    durationTag && { label: durationTag, cls: 'tag-dur' },
    trackTag && { label: trackTag, cls: 'tag-blue' },
    degreeTag && { label: degreeTag, cls: 'tag-gray' },
    statusTag && { label: statusTag, cls: 'tag-gray' },
  ].filter(Boolean)

  const has = isLoggedIn && stats && Number(stats.review_count) > 0
  const reviewCount = isLoggedIn ? (has ? Number(stats.review_count) : (p.review_count ?? 0)) : null
  const rating = has ? Number(stats.avg_recommend) : null
  // 세부점수 4개 (2×2)
  const subStats = [
    { label: '업무', value: has ? Number(stats.avg_work) : null },
    { label: '자기계발', value: has ? Number(stats.avg_growth) : null },
    { label: '분위기', value: has ? Number(stats.avg_vibe) : null },
    { label: '시간유연성', value: has ? Number(stats.avg_flex) : null },
  ]

  const reviewSnippets = isLoggedIn
    ? reviews.map((rv) => rv.opinion?.trim() || rv.work_content?.trim() || '').filter(Boolean).slice(0, 1)
    : []

  return (
    <Link
      to={`/worksite/${ws.id}`}
      className="home-featured"
    >
      {heading && <div className="hf-head">{heading}</div>}
      <div className="hf-body">
        <div className="hf-main">
          <div className="hf-titlerow">
            <div className="hf-titlewrap">
              <div className="hf-org" title={ws.organization_name}>{ws.organization_name}</div>
              <div className="hf-name" title={ws.workplace_name}>{ws.workplace_name}</div>
            </div>
            <span className={`hf-status ${p.is_active ? 'is-open' : 'is-closed'}`}>
              <span className="hf-status-dot" />{p.is_active ? '모집중' : '모집완료'}
            </span>
          </div>
          <div className="hf-tags">
            <CardTags tags={tags} max={3} />
          </div>
        </div>
        {/* 오른쪽: 옛 점수칸 자리 → 제일 도움된 코멘트 */}
        <div className="hf-comment">
          {reviewSnippets.length > 0 ? (
            <>
              <div className="hf-comment-icon" aria-hidden="true">💬</div>
              {reviewSnippets.map((s, i) => (
                <div className="hf-comment-text" key={i}>“{s}”</div>
              ))}
              {reviewCount ? <div className="hf-comment-meta">리뷰 {reviewCount}개</div> : null}
            </>
          ) : (
            <div className="hf-comment-text hf-comment-empty">
              {isLoggedIn ? '아직 등록된 후기가 없어요.' : '로그인하면 점수와 후기를 볼 수 있어요.'}
            </div>
          )}
        </div>
      </div>

      {/* 하단: 평점(별도·크게·게이지 없음) + 세부점수 2×2 (색 막대) */}
      <div className="hf-scores-row">
        <div className="hf-rating">
          <span className="hf-rating-val" style={!has ? { color: 'var(--text-muted)' } : undefined}>
            {statsLoading ? '·' : (rating ? rating.toFixed(1) : '-')}
          </span>
          <span className="hf-rating-lbl">추천 점수</span>
        </div>
        <div className="hf-substats">
          {statsLoading ? (
            [0, 1, 2, 3].map((i) => (
              <div className="hf-substat" key={i}>
                <div className="hf-substat-top">
                  <span className="skeleton-box" style={{ display: 'inline-block', width: 44, height: '0.8em', borderRadius: 4 }} />
                  <span className="skeleton-box" style={{ display: 'inline-block', width: 18, height: '0.8em', borderRadius: 4 }} />
                </div>
                <span className="hf-substat-track"><span className="skeleton-box" style={{ display: 'block', width: '60%', height: '100%', borderRadius: 2 }} /></span>
              </div>
            ))
          ) : subStats.map((s) => (
            <div className="hf-substat" key={s.label}>
              <div className="hf-substat-top">
                <span className="hf-substat-lbl">{s.label}</span>
                <span className="hf-substat-val">{s.value ? s.value.toFixed(1) : '-'}</span>
              </div>
              <span className="hf-substat-track">
                <span className={`hf-substat-fill ${ratingBarColor(s.value)}`} style={{ width: `${s.value ? (s.value / 5) * 100 : 0}%` }} />
              </span>
            </div>
          ))}
        </div>
      </div>
    </Link>
  )
}

// ── 비로그인(게스트) 추천 자리 카드 ──
// 로그아웃이면 학교·선호를 알 수 없어 특정 근장을 '추천'할 수 없다 → 특정 근무지 대신 로그인 유도.
// 홈의 다른 잠긴 요소와 동일하게 클릭 시 LoginPromptModal(onLogin). 데이터 대기 없이 즉시 렌더.
function GuestRecCard({ onLogin }) {
  return (
    <div
      className="home-featured is-invite"
      onClick={onLogin}
      role="button"
      tabIndex={0}
      onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); onLogin() } }}
    >
      <div className="hf-invite-icon" aria-hidden="true">🐳</div>
      <div className="hf-invite-title">로그인하고 나에게 맞는 근장을 추천받아 보세요</div>
      <div className="hf-invite-sub">내 학과·조건에 맞는 근무지 추천과 실제 후기를 볼 수 있어요</div>
      <button className="hf-invite-btn" onClick={(e) => { e.stopPropagation(); onLogin() }}>
        로그인 / 회원가입
      </button>
    </div>
  )
}

function Home() {
  const navigate = useNavigate()
  const { user: authUser } = useAuth()
  // 홈 피드 = 서버(get_home_feed)가 조립한 히어로 + 선반 3종. 프런트는 정렬·dedup을 하지 않는다.
  const [feed, setFeed] = useState({ hero: null, topScore: [], popular: [], mostReviewed: [] })
  const [loading, setLoading] = useState(true)            // 근무지 카드 로딩
  const [noticesLoading, setNoticesLoading] = useState(true)  // 공지 로딩(근무지와 독립)
  const [error, setError] = useState(null)
  const [typeFilter, setTypeFilter] = useState('all') // all | national | school
  const [statusFilter, setStatusFilter] = useState('all') // all | open | closed
  const isLoggedIn = !!authUser                        // 로그인 여부 = AuthContext 유저 존재
  const hasActivePass = canViewReviews(authUser?.pass_expires_at, REVIEWS_OPEN_UNTIL)   // 열람권 ∪ 한시 전면 공개
  const [notices, setNotices] = useState([])
  // 추천 2곳의 세부점수·대표후기 (worksite_id 문자열 키로 매핑)
  const [featuredStatsMap, setFeaturedStatsMap] = useState({})
  const [featuredReviewMap, setFeaturedReviewMap] = useState({})
  const [featuredStatsLoading, setFeaturedStatsLoading] = useState(false)
  const [featuredStatsKey, setFeaturedStatsKey] = useState(null)  // 점수 로딩이 끝난 recIdsKey (B: 점수 준비 전엔 통스켈레톤 유지, 안쪽 스켈레톤·팝 없음)

  const [homeQuery, setHomeQuery] = useState('')
  const searchBoxRef = useRef(null)                 // 검색바 래퍼(제안 드롭다운 바깥클릭·붙는모양 기준)
  const [suggestOpen, setSuggestOpen] = useState(false)  // 제안 열림 여부(SearchSuggest 통지)
  // 홈 검색 → 근장찾기로 이동(검색어 전달). URL ?q= 대신 navigation state로 —
  // ?q=는 주소창에 박혀 이후 페이지 안 검색에도 계속 남았다(안 검색은 URL을 안 건드림 → 표기 불일치).
  const goSearch = () => {
    const q = homeQuery.trim()
    navigate('/search', q ? { state: { q } } : undefined)
  }

  // AuthContext에서 가져온 학생 정보 (fetchMe가 세션 시 로드 — 별도 fetchUserProfile 불필요).
  // ⚠️ mergeUser 등으로 authUser '객체'만 새로 만들어져도 재요청·재계산되지 않도록,
  //   실제로 쓰는 필드만 뽑아 문자열 키로 안정화하고 그 키로만 메모한다.
  //   (예전엔 매 렌더 새 객체 → 추천 useMemo가 [postings]만 보느라 프로필이 늦게 오면 개인화가 영영 반영 안 됐다.)
  const profileKey = authUser ? JSON.stringify({
    university_id: authUser.university_id ?? null,
    degree: authUser.degree_program ?? null,
    status: authUser.academic_status ?? null,
    grade: authUser.grade ?? null,
    track: authUser.track ?? null,
    college: authUser.college?.name ?? null,
    department: authUser.department?.name ?? null,
    region: authUser.region ?? null,
  }) : ''

  // 필터 조합별 응답 캐시. 필터는 9가지(유형3×상태3)뿐이고 홈 데이터는 자주 안 바뀌므로,
  //   한 번 본 조합은 재요청 없이 즉시 되돌려 준다(왕복을 UX에서 감춤 — react-query 없이 Map으로 충분).
  //   로그인 상태가 바뀌면 개인화·대학 스코프 결과가 달라지므로 통째로 버린다.
  const feedCache = useRef(new Map())
  useEffect(() => { feedCache.current.clear() }, [profileKey])

  // 홈 피드: 서버가 히어로+선반 3종을 조립해 준다. 필터는 인자로 넘겨 왕복 1회로 끝낸다.
  //   profileKey가 의존성인 이유 = 로그인/프로필 변경 시 개인화·대학 스코프가 달라져 다시 받아야 함.
  //   (프로필 값 자체는 안 넘긴다 — 서버가 auth.uid()로 직접 읽는다.)
  useEffect(() => {
    let alive = true   // 필터 연타로 겹친 응답이 순서 뒤바뀌어 옛 결과로 덮어쓰는 것 방지
    const key = `${typeFilter}|${statusFilter}`
    const cached = feedCache.current.get(key)
    if (cached) { setFeed(cached); setLoading(false); return }
    ;(async () => {
      try {
        const next = await fetchHomeFeed({ type: typeFilter, status: statusFilter })
        if (!alive) return
        feedCache.current.set(key, next)
        setFeed(next)
      } catch (err) {
        if (alive) setError(err.message)
      } finally {
        if (alive) setLoading(false)   // 근무지 카드만 — 공지는 아래 별도 effect에서 독립 로딩
      }
    })()
    return () => { alive = false }
  }, [typeFilter, statusFilter, profileKey])

  // 공지: 근무지와 독립으로 병렬 fetch → 도착하는 대로 채움(스켈레톤이 자리 유지 → 시프트 X, 네이버식 점진)
  useEffect(() => {
    let alive = true
    fetchNotices({ limit: 5 })
      .then((rows) => { if (alive) setNotices(rows) })
      .catch(() => { /* 공지 못 불러와도 홈은 정상 */ })
      .finally(() => { if (alive) setNoticesLoading(false) })
    return () => { alive = false }
  }, [])

  // 480px 이상으로 넘어가면(데스크톱 전환) 데스크톱이 표현 못 하는 'closed'를 'all'로 리셋.
  // 리스너 콜백 안에서만 setState → set-state-in-effect 안전.
  useEffect(() => {
    const mq = window.matchMedia('(min-width: 480px)')
    const onChange = (e) => { if (e.matches) setStatusFilter(s => (s === 'closed' ? 'all' : s)) }
    mq.addEventListener('change', onChange)
    return () => mq.removeEventListener('change', onChange)
  }, [])

  // 히어로·선반은 서버가 이미 골라 보냈다(필터도 서버 적용) — 프런트 재정렬 없음.
  const hero = feed.hero
  const recIds = hero?.worksite?.id ? [hero.worksite.id] : []
  const recIdsKey = recIds.join(',')
  useEffect(() => {
    // 로그아웃은 추천카드(GuestRecCard)에 점수를 안 쓰므로 fetch 생략 — 불필요 요청·anon 점수 노출 방지.
    // 상태를 건드리지 않는 순수 early-return → 로그인 전환(auth 늦은 하이드레이션) 시에도 B(점수 준비 후 一괄 표시) 유지.
    if (!isLoggedIn) return
    // 추천이 사라진 렌더에서는 이전 추천의 점수·후기 캐시를 즉시 비워야 stale 카드가 다시 나타나지 않는다.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    if (recIds.length === 0) { setFeaturedStatsMap({}); setFeaturedReviewMap({}); setFeaturedStatsKey(recIdsKey); return }
    let alive = true
    setFeaturedStatsLoading(true)
    Promise.all([
      getWorksiteScoreCards(recIds).catch(() => []),
      // 무열람권이면 전체 리뷰를 요청하지 않고 서버가 자른 60자 티저만 받는다.
      // 열람권이 있어도 표시 가능한 리뷰가 없으면 티저로 폴백한다.
      Promise.all(recIds.map((id) => loadFeaturedReviewPreviews({
        worksiteId: id,
        hasActivePass,
        fetchReviews,
        fetchReviewTeaser,
      }).catch(() => []))),
    ]).then(([cards, reviewLists]) => {
      if (!alive) return
      const sMap = {}
      for (const c of cards ?? []) sMap[String(c.worksite_id)] = c
      const rMap = {}
      recIds.forEach((id, i) => {
        rMap[String(id)] = (reviewLists[i] ?? [])
          .filter((r) => (r.opinion && r.opinion.trim()) || (r.work_content && r.work_content.trim()))
          .sort((a, b) => (b.helpful_count ?? 0) - (a.helpful_count ?? 0))
          .slice(0, 2)
      })
      setFeaturedStatsMap(sMap)
      setFeaturedReviewMap(rMap)
    }).finally(() => { if (alive) { setFeaturedStatsLoading(false); setFeaturedStatsKey(recIdsKey) } })
    return () => { alive = false }
    // recIds는 recIdsKey로 안정화 — 추천 id 목록이 같으면 재요청하지 않음
    // isLoggedIn: 로그인 전환 시 재실행(로그아웃→로그인이면 점수 fetch 시작)
    // hasActivePass: 열람권 활성화·만료로 전체 리뷰/티저 경로가 바뀌면 재요청
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [recIdsKey, isLoggedIn, hasActivePass])

  // B: 추천카드는 점수까지 준비된 뒤 한 번에 표시 — 점수 로딩이 끝난 키와 현재 키가 같을 때만 ready
  // (단순 boolean은 effect 지연으로 카드→스켈레톤→카드 깜빡임 발생 → 키 비교로 race 제거)
  const featuredReady = featuredStatsKey === recIdsKey

  // 선반 3종 — 서버가 필터 적용 후 전수 기준 상위 10개를 뽑아 보낸 결과 그대로.
  //   예전엔 브라우저가 받아온 후보 안에서 정렬했는데, 후보가 상한에 잘려 있어
  //   "추천 점수 높은 근장"이 실제로는 '받아온 것 중 top 10'이었다(진짜 1등이 누락 가능).
  const topScoreList = feed.topScore
  const popularList = feed.popular
  const mostReviewedList = feed.mostReviewed

  return (
    <div className="home-wrap">
      <PageMeta />
      <div className="home-hero">
        <div className={`search-bar-wrap${suggestOpen ? ' is-suggest-open' : ''}`} ref={searchBoxRef}>
          <input
            type="text"
            placeholder="근무지 이름으로 검색하세요"
            autoComplete="off"
            value={homeQuery}
            onChange={(e) => setHomeQuery(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter') goSearch() }}
          />
          <button aria-label="검색" onClick={goSearch}>
            <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 28 28" fill="none" stroke="white" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
              <circle cx="11" cy="11" r="8" />
              <line x1="24" y1="24" x2="16.66" y2="16.66" />
            </svg>
          </button>
          {/* 입력 중 근무지 제안(로그인 시만). 클릭→상세, Enter는 위 goSearch가 근장찾기로 이동 */}
          <SearchSuggest query={homeQuery} containerRef={searchBoxRef} enabled={isLoggedIn} onOpenChange={setSuggestOpen} />
        </div>
      </div>

      {/* 히어로(검색바)는 항상 즉시. 그 아래 본문만 로딩/에러/결과 분기 (네이버식) */}
      {error ? (
        <div className="body-wrap"><div className="home-main"><div className="card-empty">불러오지 못했어요: {error}</div></div></div>
      ) : (
      <div className="body-wrap">
        {/* 상단 row: 날바독님께 추천하는 근장 (2곳, 세로) + 공지·광고 (오른쪽) */}
        <div className="home-toprow">
          <div className="section home-rec2">
            <div className="home-rec2-grid">
              {!isLoggedIn ? (
                // 로그아웃: 학교·선호를 모르니 특정 근장 대신 로그인 유도(데이터 대기 없이 즉시)
                <GuestRecCard onLogin={() => navigate('/login')} />
              ) : loading || !featuredReady ? (
                // 로딩 중엔 회색 스켈레톤 대신 카드 자리(305px)만 투명 예약 → 회색 안 보이고 레이아웃 밀림도 방지. 점수까지 준비되면 완성카드 한 번에
                <div className="home-featured" style={{ visibility: 'hidden' }} aria-hidden="true" />
              ) : !hero ? (
                <div className="card-empty">추천할 근장을 준비 중이에요.</div>
              ) : (
                <FeaturedRec
                  p={hero}
                  stats={featuredStatsMap[String(hero.worksite?.id)] ?? null}
                  reviews={featuredReviewMap[String(hero.worksite?.id)] ?? []}
                  statsLoading={featuredStatsLoading}
                  heading={`🐳 ${authUser?.nickname ?? '회원'}님께 추천하는 근장`}
                  isLoggedIn={isLoggedIn}
                />
              )}
            </div>
          </div>

          <aside className="home-sidebar">
            <div className="notice-box">
              <div className="notice-head">
                <span>공지사항</span>
                <span
                  className="notice-more"
                  onClick={() => navigate('/notice')}
                  style={{ cursor: 'pointer' }}
                >더보기 ›</span>
              </div>
              {noticesLoading ? (
                [0, 1, 2, 3, 4].map((i) => (
                  // 실제와 같은 p/span 안에 바를 넣어 줄높이·여백이 자동으로 일치(공지 카드 높이 고정)
                  <div className="notice-item" key={i}>
                    <p><span className="skeleton-box" style={{ display: 'inline-block', width: '72%', height: '0.85em', borderRadius: 6, verticalAlign: 'middle' }} /></p>
                    <span><span className="skeleton-box" style={{ display: 'inline-block', width: '38%', height: '0.85em', borderRadius: 6, verticalAlign: 'middle' }} /></span>
                  </div>
                ))
              ) : notices.length === 0 ? (
                <div className="notice-item"><p style={{ color: 'var(--text-muted)' }}>등록된 공지가 없습니다.</p></div>
              ) : (
                notices.map((n) => (
                  <div
                    key={n.id}
                    className="notice-item"
                    onClick={() => navigate(`/notice?open=${n.id}`)}
                    style={{ cursor: 'pointer' }}
                  >
                    <p>{n.title}</p>
                    <span>{formatRelativeDate(noticeActivityAt(n.created_at, n.updated_at))}</span>
                  </div>
                ))
              )}
            </div>
          </aside>
        </div>

        {/* 하단: 선반 (전체폭) */}
        <div className="home-main">
          {isLoggedIn && (
            <div className="filter-bar-wrap">
              <div className="home-filter-bar">
                <button className={`home-filter-pill ${typeFilter === 'all' ? 'active' : ''}`} onClick={() => setTypeFilter('all')}>전체</button>
                <button className={`home-filter-pill ${typeFilter === 'national' ? 'active' : ''}`} onClick={() => setTypeFilter('national')}>국가근장</button>
                <button className={`home-filter-pill ${typeFilter === 'school' ? 'active' : ''}`} onClick={() => setTypeFilter('school')}>학교근장</button>
                <button className={`home-filter-pill ${statusFilter === 'open' ? 'active' : ''}`} onClick={() => setStatusFilter(s => (s === 'open' ? 'all' : 'open'))}>모집중만</button>
              </div>
              <div className="status-legend">
                <span className="legend-item"><span className="legend-dot dot-green"></span>모집중</span>
                <span className="legend-item"><span className="legend-dot dot-red"></span>모집완료</span>
              </div>
              <div className="home-filter-mobile">
                <div style={{ flex: 1, minWidth: 0 }}>
                  <Dropdown
                    size="sm"
                    label="유형"
                    value={typeFilter}
                    onChange={setTypeFilter}
                    ariaLabel="근장 종류 필터"
                    options={[
                      { value: 'all', label: '전체' },
                      { value: 'national', label: '국가근장' },
                      { value: 'school', label: '학교근장' },
                    ]}
                  />
                </div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <Dropdown
                    size="sm"
                    label="모집상태"
                    value={statusFilter}
                    onChange={setStatusFilter}
                    ariaLabel="모집 상태 필터"
                    options={[
                      { value: 'all', label: '전체' },
                      { value: 'open', label: '모집중', dotClass: 'dot-green' },
                      { value: 'closed', label: '모집완료', dotClass: 'dot-red' },
                    ]}
                  />
                </div>
              </div>
            </div>
          )}

          <CardSection title="추천 점수 높은 근장" list={topScoreList} loading={loading} showLegend={!isLoggedIn} filterKey={`${typeFilter}-${statusFilter}`} />

          <CardSection title="많이 찾아본 근장" list={popularList} loading={loading} filterKey={`${typeFilter}-${statusFilter}`} />
          <CardSection title="리뷰 많은 근장" list={mostReviewedList} loading={loading} filterKey={`${typeFilter}-${statusFilter}`} />
        </div>
      </div>
      )}

    </div>
  )
}

export default Home
