import { supabase } from '../supabase'

// 광고 시청 기록을 만들지 않고 오늘 보상 가능 여부를 조회한다.
export async function fetchAdRewardStatus() {
  const { data, error } = await supabase.rpc('get_ad_reward_status')
  if (error) throw error
  return data
}

// 활성 광고 + 1회용 토큰. 캡 도달 시 'CAP_REACHED', 광고 없으면 'NO_ADS' 에러.
export async function startAdView() {
  const { data, error } = await supabase.rpc('start_ad_view')
  if (error) throw error
  return data // { ad: { id, title, media_path, media_type, target_url, min_view_seconds }, token }
}

// 토큰으로 적립(서버가 min_view_seconds 월클럭 재검증). 'TOO_SOON'/'INVALID_TOKEN'/'CAP_REACHED' 가능.
export async function claimAdReward(token) {
  const { data, error } = await supabase.rpc('claim_ad_reward', { p_token: token })
  if (error) throw error
  return data // 지갑(point_balance, pass_balances, pass_expires_at)
}

// 클릭 로그(fire-and-forget).
export async function logAdClick(adId) {
  const { error } = await supabase.rpc('log_ad_click', { p_ad_id: adId })
  if (error) throw error
}

// 'ad-media' 버킷 공개 URL (Storage 접근도 data 레이어에서 — 페이지는 supabase 직접 import 금지)
export function adMediaUrl(path) {
  return supabase.storage.from('ad-media').getPublicUrl(path).data.publicUrl
}
