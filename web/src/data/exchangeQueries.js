import { supabase } from '../supabase'

// 최신 지갑 — RPC _wallet()이 auth.uid()로 직접 조회(인자 없음)
export async function fetchWallet() {
  const { data, error } = await supabase.rpc('_wallet')
  if (error) throw error
  return data
}

// 아래 지갑 변경 RPC는 모두 최신 _wallet() 결과를 반환한다.
export async function purchasePass(days) {
  const { data, error } = await supabase.rpc('purchase_pass', { p_days: days })
  if (error) throw error
  return data
}

export async function refundPass(days) {
  const { data, error } = await supabase.rpc('refund_pass', { p_days: days })
  if (error) throw error
  return data
}

export async function activatePass(days) {
  const { data, error } = await supabase.rpc('activate_pass', { p_days: days })
  if (error) throw error
  return data
}
