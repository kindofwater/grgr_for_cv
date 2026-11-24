import { supabase } from '../supabase'
import { noticeActivityAt, parseServerDate } from '../lib/dates'

function noticeOrder(a, b) {
  if (Boolean(a.is_pinned) !== Boolean(b.is_pinned)) return a.is_pinned ? -1 : 1
  const aTime = parseServerDate(noticeActivityAt(a.created_at, a.updated_at))?.getTime() ?? 0
  const bTime = parseServerDate(noticeActivityAt(b.created_at, b.updated_at))?.getTime() ?? 0
  return bTime - aTime
}

// 목록: 본문 제외(가벼움). 본문은 펼칠 때 fetchNoticeById로 지연 로드(공지 많아져도 가벼움).
// 고정(is_pinned) 우선 + 최신순.
export async function fetchNotices({ limit } = {}) {
  let q = supabase
    .from('notices')
    .select('id, title, is_pinned, created_at, updated_at')
    .order('is_pinned', { ascending: false })
    .order('created_at', { ascending: false })
  const { data, error } = await q
  if (error) throw error
  const notices = (data ?? []).sort(noticeOrder)
  return limit ? notices.slice(0, limit) : notices
}

// 여러 공지의 본문을 한 번에(목록 현재 페이지 prefetch용). id 배열 → [{id, content}]
export async function fetchNoticeContents(ids) {
  if (!ids?.length) return []
  const { data, error } = await supabase
    .from('notices')
    .select('id, content')
    .in('id', ids)
  if (error) throw error
  return data ?? []
}

// 상세: 본문 포함. 없는 id면 null 반환(throw 아님) → 페이지에서 "없음" 분기.
export async function fetchNoticeById(id) {
  const { data, error } = await supabase
    .from('notices')
    .select('id, title, content, is_pinned, created_at, updated_at')
    .eq('id', id)
    .maybeSingle()
  if (error) throw error
  return data
}
