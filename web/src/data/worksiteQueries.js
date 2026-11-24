import { supabase } from '../supabase'
import { escapeLike, toCard } from '../lib/searchCards'

export async function fetchWorksite(id) {
  const { data, error } = await supabase
    .from('worksites')
    // university_id: 리뷰 작성 진입 가드(내 학교 근무지인지)용. 서버(write_review_with_points)도
    //   같은 검사를 하지만, 폼을 다 채운 뒤 실패시키지 않으려면 진입 시점에 알아야 한다.
    .select('id, university_id, organization_name, workplace_name, type, location_type, national_work_term, region, address, view_count')
    .eq('id', id).single()
  if (error) throw error
  return data
}

// 근무지 공고 목록: 활성 우선 → 최신, 최근 30개(SSC 이력 대비 캡). 대표/목록 선별은 lib/postings.selectPostings.
// ⚠️ is_placeholder는 셀렉트하지 않음 — postings는 컬럼 화이트리스트 grant(20260713144538)이고 이 컬럼은 grant 밖이라
//    직접 조회 시 permission denied. selectPostings는 필드가 없으면 非-placeholder로 취급(!undefined=true)해 그대로 동작.
//    placeholder 필터링이 필요한 비로그인 경로는 security definer RPC(get_worksite_public_detail)라 grant와 무관하게 반환.
export async function fetchPostings(worksiteId) {
  const cols = `id, source, title, source_url, job_category, preferred_track, preferred_college, preferred_dept,
    recruit_count, min_grade, eligible_degree, eligible_status, job_description, preference_notes,
    extra_notes, hourly_wage, work_period_text, work_duration_type, work_time_text, work_location,
    recruitment_period_text, contact_name, is_active, recruit_until, recruit_until_at,
    recruit_until_estimated, created_at`
  const { data, error } = await supabase
    .from('postings').select(cols).eq('worksite_id', worksiteId)
    .order('is_active', { ascending: false }).order('created_at', { ascending: false }).limit(30)
  if (error) throw error
  return data ?? []
}

// 리뷰 목록 — 마스킹 RPC. user_id 미반환(익명 신원 차단). 익명이면 author_nickname='익명'·work_semester=null.
// 반환 컬럼: id, work_year, work_semester, score_recommend, score_work, score_growth, score_vibe,
//   score_flex, work_content, opinion, is_anonymous, helpful_count, author_nickname, created_at.
export async function fetchReviews(worksiteId) {
  const { data, error } = await supabase
    .rpc('list_worksite_reviews', { p_worksite_id: worksiteId })
  if (error) throw error
  return data ?? []
}

// 비로그인 공개용 근무지 상세 — 화이트리스트 RPC(contact_name·리뷰 제외). InfoCard shape 반환.
export async function fetchWorksitePublicDetail(id) {
  const { data, error } = await supabase
    .rpc('get_worksite_public_detail', { p_worksite_id: Number(id) })
  if (error) throw error
  const row = data?.[0]
  if (!row) {
    const notFound = new Error('근무지를 찾을 수 없어요.')
    notFound.code = 'WORKSITE_NOT_FOUND'
    throw notFound
  }
  // 신 RPC는 postings(배열), 구 RPC는 posting(단수) — 둘 다 수용해 배포 순서와 무관하게 동작.
  // db push 전: posting 하나만 → 대표만 보이고 목록은 빈다(현행과 동일). push 후: 목록까지 켜짐.
  const postings = row.postings ?? (row.posting ? [row.posting] : [])
  return { worksite: row.worksite, postings }
}

// 비로그인 공개용 점수 집계 — 개수·추천율만 사용(리뷰 본문 경유 없음).
export async function fetchWorksiteScoreCard(id) {
  const { data, error } = await supabase
    .rpc('get_worksite_score_cards', { worksite_ids: [Number(id)] })
  if (error) throw error
  return data?.[0] ?? { review_count: 0, recommend_rate: 0 }
}

// 잠금(비로그인·무열람권)용 리뷰 티저 — 최신 리뷰 '첫 줄'만. 절단은 서버(RPC)에서 하므로 DOM에 전문이 안 실린다.
// 리뷰가 없거나 전부 블라인드면 null. 반환: { teaser, is_truncated }
export async function fetchReviewTeaser(id) {
  const { data, error } = await supabase
    .rpc('get_worksite_review_teaser', { p_worksite_id: Number(id) })
  if (error) throw error
  return data?.[0] ?? null
}

// 내 리뷰 id만 (worksite 한정) — RLS가 본인 행만 반환하므로 user_id 조건 불필요.
export async function fetchMyReviewIds(worksiteId) {
  const { data, error } = await supabase
    .from('reviews').select('id').eq('worksite_id', worksiteId)
  if (error) throw error
  return new Set((data ?? []).map((r) => r.id))
}

// 조회수 +1 (실패해도 무시) — auth.uid() 기반 RPC(security definer)로 worksites update.
export async function incrementViewCount(worksiteId) {
  try {
    await supabase.rpc('increment_worksite_view', { p_worksite_id: worksiteId })
  } catch { /* fire-and-forget: 조회수 실패는 무시 */ }
}

export async function fetchMyReviewById(reviewId, worksiteId) {
  // RLS 본인범위: 본인 리뷰만 반환되므로 user_id 조건 불필요.
  const { data, error } = await supabase
    .from('reviews')
    .select(`id, work_year, work_semester, score_work, score_growth,
      score_vibe, score_flex, score_recommend, work_content, opinion, is_anonymous`)
    .eq('id', reviewId)
    .eq('worksite_id', worksiteId)
    .is('deleted_at', null)
    .maybeSingle()
  if (error) throw error
  return data
}

// 한 학기당 1리뷰(근무지 불문) — worksite 무관하게 그 학기 리뷰를 찾는다.
// RLS 본인범위: 본인 리뷰만 반환되므로 user_id 조건 불필요.
export async function fetchMyReviewForPeriod(workYear, workSemester) {
  const { data, error } = await supabase
    .from('reviews')
    .select('id, worksite_id')
    .eq('work_year', workYear)
    .eq('work_semester', workSemester)
    .is('deleted_at', null)
    .order('id', { ascending: false })
    .limit(1)
    .maybeSingle()
  if (error) throw error
  return data
}

export async function createReview(payload) {
  // payload 키: p_worksite_id, p_work_year, p_work_semester,
  //   p_work, p_growth, p_vibe, p_flex, p_recommend, p_work_content, p_opinion, p_is_anonymous
  //   (작성자 신원은 auth.uid() — 클라가 p_user_id를 넘기지 않음)
  const { data, error } = await supabase.rpc('write_review_with_points', payload)
  if (error) throw error
  return data
}

export async function updateReview(reviewId, fields) {
  // 본인 검증은 RPC 안에서 auth.uid()로 — 클라가 p_user_id를 넘기지 않음
  const { error } = await supabase.rpc('update_review_with_points', {
    p_review_id: reviewId,
    p_work_year: fields.work_year,
    p_work_semester: fields.work_semester,
    p_work: fields.score_work,
    p_growth: fields.score_growth,
    p_vibe: fields.score_vibe,
    p_flex: fields.score_flex,
    p_recommend: fields.score_recommend,
    p_work_content: fields.work_content,
    p_opinion: fields.opinion,
    p_is_anonymous: fields.is_anonymous,
  })
  if (error) throw error
}

export async function deleteReview(reviewId) {
  // error.message 에 'INSUFFICIENT_POINTS' 포함 가능 → 호출부에서 분기
  // 본인 검증은 RPC 안에서 auth.uid()로 — 클라가 p_user_id를 넘기지 않음
  const { error } = await supabase.rpc('delete_review_with_rollback', { p_review_id: reviewId })
  if (error) throw error
}

// worksiteId 기준 조회 → reviews 결과에 의존하지 않아 Promise.all에 포함 가능
// RLS 본인범위: 내 review_helpful 행만 반환되므로 user_id 조건 불필요.
export async function fetchMyHelpfulIds(worksiteId) {
  const { data, error } = await supabase
    .from('review_helpful')
    .select('review_id, review:reviews!inner(worksite_id)')
    .eq('review.worksite_id', worksiteId)
  if (error) throw error
  return new Set((data ?? []).map((r) => r.review_id))
}

// toggle_helpful RPC: 단일 트랜잭션으로 review_helpful 토글 + helpful_count 증감
// C3(비원자), C4(stale 클로저) 동시 해결 — DB가 현재 count를 알아서 계산
// 사용자 신원은 auth.uid() — 클라가 p_user_id를 넘기지 않음
export async function toggleHelpful(reviewId) {
  const { data, error } = await supabase
    .rpc('toggle_helpful', { p_review_id: reviewId })
  if (error) throw error
  return data  // 변경 후 helpful_count
}

// get_review_stats RPC: 여러 근무지의 평균 점수·리뷰 수를 한 번에 집계
// (reviews 날것 전송 없이 서버에서 avg/count만 반환). 반환: [{ worksite_id, avg_score, review_count }]
export async function getReviewStats(worksiteIds) {
  const { data, error } = await supabase
    .rpc('get_review_stats', { worksite_ids: worksiteIds })
  if (error) throw error
  return data ?? []
}

// ── 홈 화면(근무지 목록) 전용 ──

// 홈 피드 = 히어로 추천 1곳 + 선반 3종을 서버가 조립해 한 번에 반환(get_home_feed rpc).
//   예전엔 후보 공고를 브라우저로 전부 받아 프런트에서 dedup·정렬했는데, 국가근장이 6,700여 곳이라
//   쿼리별 상한을 둘 수밖에 없었고 그 상한이 모수보다 작아 후보가 잘렸다(학교 408중 300·교내 81중 30).
//   그래서 "추천 점수 높은 근장 10곳"이 실은 '우연히 받아온 것 중 top 10'이었다.
//   서버가 전수 기준으로 뽑으면서 페이로드도 220KB+ → 10KB대로 줄었다.
//   개인화(자격·매칭)는 프로필을 넘기지 않고 서버가 auth.uid()로 직접 읽는다.

// flat 카드 행 → 화면(PlaceCard·FeaturedRec)이 쓰는 {worksite, ...} 모양으로 변환.
//   검색(searchWorksiteCards)과 같은 방식 — RPC는 flat, 모양 맞추기는 data 계층 담당.
function toHomeCard(row) {
  if (!row) return null
  return {
    worksite: {
      id: row.worksite_id,
      organization_name: row.organization_name,
      workplace_name: row.workplace_name,
      region: row.region,
      type: row.type,
      location_type: row.location_type,
      view_count: row.view_count,
    },
    is_active: row.is_active,
    preferred_track: row.preferred_track,
    preferred_college: row.preferred_college,
    preferred_dept: row.preferred_dept,        // 히어로 '내 학과 맞춤' 배지 판단용
    work_duration_type: row.work_duration_type,
    eligible_degree: row.eligible_degree,
    eligible_status: row.eligible_status,
    avg_score: row.avg_score,
    review_count: row.review_count,
  }
}

// type: 'all'|'national'|'school' · status: 'all'|'open'|'closed' (홈 필터바 값 그대로)
export async function fetchHomeFeed({ type = 'all', status = 'all' } = {}) {
  const { data, error } = await supabase.rpc('get_home_feed', {
    p_types: type === 'all' ? null : [type],
    p_actives: status === 'open' ? [true] : status === 'closed' ? [false] : null,
  })
  if (error) throw error
  return {
    hero: toHomeCard(data?.hero ?? null),
    topScore: (data?.top_score ?? []).map(toHomeCard),
    popular: (data?.popular ?? []).map(toHomeCard),
    mostReviewed: (data?.most_reviewed ?? []).map(toHomeCard),
  }
}

// ── 근장찾기(검색 목록) 전용 ──

// 카드 결과 + 총개수. 서버가 dedup·필터·정렬·페이징을 모두 수행(프론트 재정렬 없음).
// flat RPC 행을 ResultCard가 쓰는 {worksite,posting,stats,is_active} 모양으로 변환해 반환.
export async function searchWorksiteCards({ query, sort, page, perPage, filters }) {
  const f = filters ?? {}
  const { data, error } = await supabase.rpc('search_worksite_cards', {
    p_query: escapeLike(query ?? ''),
    p_sort: sort,                         // 'recommend' | 'reviews'
    p_limit: perPage,
    p_offset: (page - 1) * perPage,
    p_actives: f.p_actives ?? null,
    p_types: f.p_types ?? null,
    p_locations: f.p_locations ?? null,
    p_regions: f.p_regions ?? null,
    p_durations: f.p_durations ?? null,
    p_tracks: f.p_tracks ?? null,
    p_degrees: f.p_degrees ?? null,
    p_statuses: f.p_statuses ?? null,
  })
  if (error) throw error
  const rows = data ?? []
  const total = rows.length ? Number(rows[0].total_count) : 0
  return { cards: rows.map((r) => toCard(r)), total }
}

// 검색창 입력 중 드롭다운 제안(이름 부분일치, 경량). 점수·집계 없음.
export async function searchWorksiteSuggestions(query, limit = 8) {
  const { data, error } = await supabase.rpc('search_worksite_suggestions', {
    p_query: escapeLike(query),
    p_limit: limit,
  })
  if (error) throw error
  return data ?? []
}

// 근장찾기 카드 점수 집계 RPC 래퍼. 반환: [{ worksite_id, review_count, avg_recommend,
//   avg_work, avg_growth, avg_vibe, avg_flex, recommend_rate }]. (서버 집계 — 날 리뷰 미전송)
export async function getWorksiteScoreCards(worksiteIds) {
  const { data, error } = await supabase
    .rpc('get_worksite_score_cards', { worksite_ids: worksiteIds })
  if (error) throw error
  return data ?? []
}

// report_review RPC: reporter_id=auth.uid(), reported_user_id는 서버가 리뷰에서 채움.
// 클라가 reporter_id를 넘기지 않음. opinion은 필수(서버도 빈값 거부).
export async function reportReview(reviewId, reason, opinion) {
  const { error } = await supabase.rpc('report_review', {
    p_review_id: reviewId, p_reason: reason, p_opinion: opinion,
  })
  if (error) throw error
}
