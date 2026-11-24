import { supabase } from '../supabase'

// 포인트 내역 — 오래된 순(잔액 누적 계산용). 리뷰 사유는 근장명까지 중첩조회.
// user_id 필터 불필요 — RLS(points 본인범위)가 auth.uid() 일치 행만 반환.
export async function fetchPointHistory() {
  const { data, error } = await supabase
    .from('points')
    .select('amount, reason, created_at, review:reviews ( worksite:worksites ( organization_name, workplace_name ) )')
    .order('created_at', { ascending: true })
  if (error) throw error
  return data ?? []
}

// 내가 쓴 리뷰 — 최신순, 근장명 포함.
// user_id 필터 불필요 — RLS(reviews 본인범위)가 auth.uid() 일치 행만 반환.
export async function fetchMyReviews() {
  const { data, error } = await supabase
    .from('reviews')
    .select('id, worksite_id, work_year, work_semester, opinion, work_content, is_blinded, created_at, worksite:worksites ( organization_name, workplace_name )')
    .is('deleted_at', null)
    .order('created_at', { ascending: false })
  if (error) throw error
  return data ?? []
}
