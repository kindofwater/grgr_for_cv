import { supabase } from '../supabase'

// 로그인 사용자의 프로필 + 지갑. 세션 있을 때만 호출. 없으면 null.
export async function fetchMe() {
  const { data, error } = await supabase
    .from('users')
    .select('id, nickname, region, admission_year, degree_program, academic_status, grade, track, university_id, universities(name, campus), colleges(name), departments(name)')
    .limit(1)
    .maybeSingle()
  if (error) throw error
  if (!data) return null
  const { data: wallet, error: wErr } = await supabase.rpc('_wallet')
  if (wErr) throw wErr
  const { universities, colleges, departments, ...profile } = data
  return {
    ...profile,
    university_name: universities?.name ?? null,
    university_campus: universities?.campus ?? null,
    college: colleges ?? null,       // { name } | null — Home reads authUser.college?.name
    department: departments ?? null, // { name } | null — Home reads authUser.department?.name
    ...wallet, // point_balance, pass_balances, pass_expires_at
  }
}
