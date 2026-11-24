import { useEffect, useMemo, useState } from 'react'
import { Navigate, useParams, useNavigate } from 'react-router-dom'
import { computeScoreSummary } from '../lib/scores'
import { SEMESTER_ORDER } from '../lib/semesters'
import { canViewReviews } from '../lib/passes'
import {
  fetchWorksite, fetchPostings,
  fetchReviews, fetchMyReviewIds, incrementViewCount, deleteReview,
  fetchMyHelpfulIds, toggleHelpful, reportReview,
  fetchWorksitePublicDetail, fetchWorksiteScoreCard, fetchReviewTeaser,
} from '../data/worksiteQueries'
import { selectPostings, limitRecentPostings, hasJobDescription } from '../lib/postings'
import { worksiteTitle, worksiteDescription } from '../lib/seo'
import { PUBLIC_BROWSE, REVIEWS_OPEN_UNTIL } from '../config'
import { useAuth } from '../components/AuthContext'
import { useLoginPrompt } from '../components/LoginPromptContext'
import { useToast } from '../components/ToastContext'
import InfoCard from '../components/InfoCard'
import PageMeta from '../components/PageMeta'
import PostingList from '../components/PostingList'
import ScoreSummary from '../components/ScoreSummary'
import ReviewList from '../components/ReviewList'
import ConfirmModal from '../components/ConfirmModal'
import ReportModal from '../components/ReportModal'
import './WorksiteDetail.css'

export default function WorksiteDetail() {
  const { id } = useParams()
  const navigate = useNavigate()
  const [state, setState] = useState({ error: null })   // worksite·posting·reviews 등을 도착하는 대로 채움
  const [confirm, setConfirm] = useState(null) // { reviewId } 또는 null
  const [report, setReport] = useState(null) // { reviewId } 또는 null
  const [helpfulIds, setHelpfulIds] = useState(new Set())
  const { user: authUser, refreshProfile } = useAuth()
  const { promptLogin } = useLoginPrompt()
  const toast = useToast()

  // 네이버식 점진 렌더링: 한 방(Promise.all)으로 묶지 않고 조각별로 따로 받아 '도착하는 대로' 렌더.
  // 정보(worksite)와 리뷰는 병렬 fetch하되, 점수·리뷰는 정보 준비 후 표시 → 정보→리뷰 순서 보장(추가 지연 없음).
  useEffect(() => {
    if (!authUser && !PUBLIC_BROWSE) { navigate('/login', { replace: true }); return }   // 비로그인 차단(플래그 off일 때만)
    let alive = true
    setState({ error: null })                        // id 바뀌면 초기화(점진 렌더 재시작)
    setHelpfulIds(new Set())

    const worksiteId = Number(id)
    if (!/^\d+$/.test(id ?? '') || !Number.isSafeInteger(worksiteId) || worksiteId <= 0) {
      setState({ error: null, notFound: true })
      return () => { alive = false }
    }

    // 근무지 정보 조회 실패 처리. 대학 스코프(worksites RLS)에 막히거나 없는 id면
    //   .single()이 0행 에러(PGRST116)를 던지는데, 그대로 두면 화면에 원시 DB 문구가 뜬다.
    //   서버가 '막힘'과 '없음'을 구분해 주지 않으므로 둘 다 근장찾기로 돌려보낸다.
    //   비로그인은 화이트리스트 RPC(security definer) 경로라 여기 안 걸린다.
    const onInfoError = (e) => {
      if (!alive) return
      if (e?.code === 'PGRST116' || e?.code === 'WORKSITE_NOT_FOUND') {
        setState({ error: null, notFound: true })
        return
      }
      setState((s) => ({ ...s, error: e.message }))
    }

    // 잠금 경로 = 비로그인(PUBLIC_BROWSE) + 무열람권 로그인. 둘 다 리뷰 목록 RPC를 아예 안 부른다.
    //   집계는 서버(get_worksite_score_cards), 본문은 티저 RPC가 첫 줄만 → 세부점수·리뷰 전문이 DOM에 없음.
    //   (예전엔 무열람권도 목록을 받아 CSS 블러만 씌웠음 = debt#3)
    //   단 한시 전면 공개 기간(REVIEWS_OPEN_UNTIL 전)엔 둘 다 열림 경로로 — 서버 RPC도 같은 시각까지 anon에게 전문을 준다.
    if (!canViewReviews(authUser?.pass_expires_at, REVIEWS_OPEN_UNTIL)) {
      // 그룹 A: 정보카드 — 비로그인은 화이트리스트 RPC, 로그인은 기존 경로(조회수 +1 포함)
      const infoP = !authUser
        ? fetchWorksitePublicDetail(worksiteId)
        : Promise.all([fetchWorksite(worksiteId), fetchPostings(worksiteId)])
            .then(([worksite, postings]) => { incrementViewCount(worksiteId); return { worksite, postings } })
      infoP
        .then((info) => { if (alive) setState((s) => ({ ...s, worksite: info.worksite, postings: info.postings })) })
        .catch(onInfoError)
      // 그룹 B: 집계 + 티저 (정보와 병렬 — 도착하는 대로 렌더)
      // 티저는 '있으면 좋은' 장식 → 실패해도 null로 삼키고 집계·CTA는 그대로 렌더한다.
      // (안 그러면 RPC 미배포 상태에서 Promise.all이 reject → 상세 페이지 전체가 에러 화면.
      //  프론트가 db push보다 먼저 나가도 안 깨지게 하는 안전장치)
      Promise.all([fetchWorksiteScoreCard(worksiteId), fetchReviewTeaser(worksiteId).catch(() => null)])
        .then(([card, teaser]) => {
          if (!alive) return
          setState((s) => ({
            ...s,
            publicSummary: { count: card.review_count, recommendRate: card.recommend_rate },
            teaser,
          }))
        })
        .catch((e) => { if (alive) setState((s) => ({ ...s, error: e.message })) })
      return () => { alive = false }
    }
    // 이하 열림 경로 = 열람권 보유자 + (한시 공개 기간의) 비로그인·무열람권
    // 그룹 A: 정보카드(가벼움) — 비로그인은 worksites RLS·조회수 RPC(auth.uid())를 못 타므로 화이트리스트 RPC로
    const infoP = !authUser
      ? fetchWorksitePublicDetail(worksiteId)
      : Promise.all([fetchWorksite(worksiteId), fetchPostings(worksiteId)])
          .then(([worksite, postings]) => { incrementViewCount(worksiteId); return { worksite, postings } })  // 조회수 +1은 fire-and-forget
    infoP
      .then((info) => { if (alive) setState((s) => ({ ...s, worksite: info.worksite, postings: info.postings })) })
      .catch(onInfoError)
    // 그룹 B: 점수·리뷰. 내 리뷰·내 도움됨은 본인범위 RLS(auth.uid()) 조회라 비로그인은 부르지 않고 빈 집합.
    Promise.all([
      fetchReviews(worksiteId),
      authUser ? fetchMyReviewIds(worksiteId) : new Set(),
      authUser ? fetchMyHelpfulIds(worksiteId) : new Set(),
    ])
      .then(([rawReviews, myReviewIds, helpful]) => {
        if (!alive) return
        // 마스킹 RPC(list_worksite_reviews)는 평문 author_nickname(익명이면 '익명', 탈퇴자면 null)·
        // user_id 없음을 반환. ReviewCard는 중첩 author.nickname을 읽으므로 여기서 정규화:
        //   nickname 있으면 { author: { nickname } }, 없으면(탈퇴자) author=null → '탈퇴한 사용자' 경로 유지.
        //   익명은 ReviewCard가 is_anonymous로 먼저 '익명' 처리하므로 author 값과 무관.
        const reviews = rawReviews.map((r) => ({
          ...r,
          author: r.author_nickname ? { nickname: r.author_nickname } : null,
        }))
        setHelpfulIds(helpful)
        setState((s) => ({ ...s, reviews, myReviewIds }))
      })
      .catch((e) => { if (alive) setState((s) => ({ ...s, error: e.message })) })
    return () => { alive = false }
    // navigate·toast는 각각 react-router·useCallback이 보장하는 안정 참조라 넣어도 재실행 안 됨
  }, [id, authUser, navigate, toast])

  // 정렬: ① 내 리뷰 먼저 → ② 최근 근무 학기 순 (work_year DESC → 학기 DESC)
  const sortedReviews = useMemo(() => {
    const mine = state.myReviewIds ?? new Set()
    return [...(state.reviews ?? [])].sort((a, b) => {
      const am = mine.has(a.id), bm = mine.has(b.id)
      if (am !== bm) return am ? -1 : 1                                 // ① 내 리뷰 먼저
      if (b.work_year !== a.work_year) return b.work_year - a.work_year // ② 최근 근무 순
      return SEMESTER_ORDER.indexOf(b.work_semester) - SEMESTER_ORDER.indexOf(a.work_semester)
    })
  }, [state.reviews, state.myReviewIds])

  // 블라인드 리뷰는 점수 요약에서 제외(서버 집계 RPC와 동일 기준). 목록엔 placeholder로 남지만 평균/추천율엔 미반영.
  const summary = useMemo(() => computeScoreSummary((state.reviews ?? []).filter((r) => !r.is_blinded)), [state.reviews])

  // 대표/목록 선별(단일 정본 — lib/postings). state.postings 없으면 대표 null·목록 빈 배열.
  // 목록은 직무 없는 공고를 숨긴 뒤 최신 5개만 표시 — 대표는 필터 밖(항상 표시).
  const { representative, others } = useMemo(() => {
    const sel = selectPostings(state.postings)
    return { representative: sel.representative, others: limitRecentPostings(sel.others.filter(hasJobDescription)) }
  }, [state.postings])

  function makeHandlers(r) {
    // 비로그인(한시 공개 기간)은 읽기만 — 도움됨·신고는 auth.uid() 기반 RPC라 로그인 유도 모달로
    if (!authUser) {
      return {
        onEdit: () => promptLogin(), onDelete: () => promptLogin(),
        onReport: () => promptLogin(), helpfulActive: false, onHelpful: () => promptLogin(),
      }
    }
    return {
      onEdit: () => navigate(`/worksite/${id}/review/${r.id}/edit`),
      onDelete: () => setConfirm({ reviewId: r.id }),
      onReport: () => setReport({ reviewId: r.id }),
      helpfulActive: helpfulIds.has(r.id),
      onHelpful: async () => {
        const active = helpfulIds.has(r.id)
        const newCount = await toggleHelpful(r.id)
        // DB가 반환한 정확한 count로 업데이트 (stale 클로저 문제 해결)
        setState((s) => ({
          ...s,
          reviews: s.reviews.map((rv) =>
            rv.id === r.id ? { ...rv, helpful_count: newCount } : rv
          ),
        }))
        setHelpfulIds((prev) => {
          const next = new Set(prev)
          if (active) next.delete(r.id); else next.add(r.id)
          return next
        })
      },
    }
  }

  async function doReport(reason, opinion) {
    try {
      await reportReview(report.reviewId, reason, opinion)
      setReport(null)
      toast('신고가 접수되었어요. 검토 후 조치됩니다.')
    } catch (e) {
      setReport(null)
      toast('신고 중 오류: ' + e.message, 'error')
    }
  }

  async function doDelete() {
    const targetId = confirm.reviewId
    try {
      await deleteReview(targetId)
      setConfirm(null)
      // 낙관적 제거 — 네트워크 재조회 없이 로컬에서 바로 제거 (C5)
      setState((s) => ({ ...s, reviews: s.reviews.filter((r) => r.id !== targetId) }))
      // 회수된 포인트를 컨텍스트에 반영 → AccountMenu(드롭다운) 잔액 즉시 갱신
      await refreshProfile()
    } catch (e) {
      setConfirm(null)
      toast(
        e.message?.includes('INSUFFICIENT_POINTS')
          ? '포인트가 부족해 삭제할 수 없어요. (광고 시청 등으로 충전 후 삭제 가능)'
          : '삭제 중 오류: ' + e.message,
        'error',
      )
    }
  }

  // 열람권 활성 여부 = 실제 만료시각(pass_expires_at) 기준. AuthContext 유저가 단일 진실 공급원.
  // 비로그인은 pass_expires_at이 undefined → locked. 즉 locked = 비로그인 ∪ 무열람권 (티저 경로).
  // 예외: 한시 전면 공개 기간(REVIEWS_OPEN_UNTIL 전)엔 누구나 unlocked — 서버 RPC와 같은 시각.
  const isAnon = !authUser                              // 비로그인 공개 경로(PUBLIC_BROWSE)
  const locked = !canViewReviews(authUser?.pass_expires_at, REVIEWS_OPEN_UNTIL)
  // 근무지 행만 있고 공고·리뷰가 전혀 없는 껍데기 데이터는 준비 중인 빈 화면을 노출하지 않는다.
  // 두 조회가 모두 끝난 뒤에만 판정하므로 로딩 중인 정상 상세를 404로 오인하지 않는다.
  const hasNoPublicContent = Boolean(
    state.worksite
    && Array.isArray(state.postings)
    && state.postings.length === 0
    && (locked
      ? state.publicSummary && Number(state.publicSummary.count) === 0
      : Array.isArray(state.reviews) && state.reviews.length === 0)
  )

  if (state.notFound || hasNoPublicContent) return <Navigate to="/search" replace />
  if (state.error) return <div className="home-wrap">에러: {state.error}</div>

  const infoReady = isAnon ? !!state.worksite : (state.worksite && state.postings)
  const reviewsReady = !locked && infoReady && state.reviews   // 정보 준비 후 점수·리뷰 표시(정보→리뷰)

  return (
    <div>
      {/* 데이터 도착 전엔 null title → 기본 타이틀, 도착하면 "기관명 근무지명 리뷰 — 근로고래" */}
      <PageMeta title={worksiteTitle(state.worksite)} description={worksiteDescription(state.worksite)} />
      <div className="detail-wrap">
        <div>
          {/* 정보카드 먼저 → 점수·리뷰는 정보 준비 후 도착하는 대로 */}
          {infoReady && representative && <InfoCard worksite={state.worksite} posting={representative} />}
          {/* 잠금이면 세부 별점을 DOM에 넣지 않음(publicOnly) — 예전 locked 분기는 CSS 마스킹뿐이었음(debt#3) */}
          {locked
            ? (state.publicSummary && <ScoreSummary summary={state.publicSummary} publicOnly />)
            : (reviewsReady && <ScoreSummary summary={summary} />)}
          {/* 다른 공고 목록은 점수 요약 아래(2026-07-21 결정) */}
          {infoReady && <PostingList postings={others} worksite={state.worksite} />}
        </div>
        {locked ? (
          state.publicSummary && (
            <ReviewList
              locked
              teaser={state.teaser}
              totalCount={state.publicSummary.count}
              isAnon={isAnon}
              // 리뷰 쓰기: 비로그인은 잠긴 기능 → 모달 / 로그인은 작성 폼 (로그인프롬프트 정책)
              onWrite={() => (isAnon ? promptLogin() : navigate(`/worksite/${id}/review`))}
              // 명시 CTA는 리다이렉트: 비로그인 → 로그인, 무열람권 → 교환센터
              onUnlock={() => (isAnon ? navigate('/login') : navigate('/exchange'))}
            />
          )
        ) : (
          reviewsReady && (
            <ReviewList
              reviews={sortedReviews}
              myReviewIds={state.myReviewIds}
              // 한시 공개 기간의 비로그인은 리뷰 쓰기가 잠긴 기능 → 로그인 유도 모달
              onWrite={() => (isAnon ? promptLogin() : navigate(`/worksite/${id}/review`))}
              handlers={makeHandlers}
            />
          )
        )}
      </div>
      {confirm && (
        <ConfirmModal
          message="이 리뷰를 삭제할까요? (적립한 포인트가 회수됩니다)"
          confirmText="확인"
          intent="danger"
          onConfirm={doDelete}
          onCancel={() => setConfirm(null)}
        />
      )}
      {report && <ReportModal onSubmit={doReport} onCancel={() => setReport(null)} />}
    </div>
  )
}
