import { supabase } from '../supabase'

// 회원가입 학교 선택용 — 대학교 목록 조회 (이름순).
// email_domain 포함: Signup이 이메일 도메인과 일치하는 학교(캠퍼스)만 드롭다운에 넣는다(universitiesForEmail).
export async function fetchUniversities() {
  const { data, error } = await supabase
    .from('universities')
    .select('id, name, campus, email_domain')
    .order('name')
  if (error) throw error
  return data ?? []
}

// 프로필 수정 — 거주지역·학적정보 + 단과대/학과/계열을 서버 RPC(update_profile)로 갱신.
// p_user_id 제거: 서버가 auth.uid() 사용. RPC라 point/is_admin/비번은 못 건드림.
// 단과대/학과는 이름→id 엄격 매칭(미일치 시 NO_COLLEGE/NO_DEPARTMENT — create_profile과 달리 폴백 없음).
export async function updateProfile({ region, admission_year, degree_program, academic_status, grade, college_name, department_name, track }) {
  const { data, error } = await supabase.rpc('update_profile', {
    p_region: region,
    p_admission_year: admission_year,
    p_degree_program: degree_program,
    p_academic_status: academic_status,
    p_grade: grade,
    p_college_name: college_name,
    p_department_name: department_name,
    p_track: track,
  })
  if (error) throw error
  const row = data?.[0]
  if (!row) return null
  // 컨텍스트 user는 college/department를 {name} 객체로 들고 있음(fetchMe 형태) → 같은 모양으로 머지되게 변환
  return { ...row, college: { name: row.college_name }, department: { name: row.department_name } }
}

// 20P를 사용해 닉네임을 즉시 변경한다.
// 포인트 차감·닉네임 변경·이력 기록은 change_nickname RPC 한 트랜잭션에서만 일어나며,
// 성공 시 새 닉네임과 최신 지갑을 함께 돌려받아 AuthContext와 화면을 한 번에 동기화한다.
export async function changeNickname(nickname) {
  const value = (nickname ?? '').trim()
  const { data, error } = await supabase.rpc('change_nickname', { p_nickname: value })
  if (error) throw error

  // 현재 RPC는 jsonb 객체를 반환한다. TABLE 반환으로 바뀌어도 호출부가 깨지지 않도록
  // 단일 행 배열만 가볍게 정규화한다.
  const result = Array.isArray(data) ? data[0] : data
  return { ...result, nickname: result?.nickname ?? value }
}

// Supabase Auth 로그인 (C4+)
export async function signIn(email, password) {
  const { data, error } = await supabase.auth.signInWithPassword({
    email: email.trim().toLowerCase(), password,
  })
  if (error) throw error
  return data
}

// 이메일 가입 여부 사전검사 — 로그인 이메일 단계에서 "있으면 로그인 / 없으면 가입" 분기용.
// email_registered RPC(security definer, auth.users 조회) → boolean. enumeration 트레이드오프 수용.
export async function emailRegistered(email) {
  const { data, error } = await supabase.rpc('email_registered', { p_email: email.trim().toLowerCase() })
  if (error) throw error
  return data === true
}

// 비밀번호 재설정 메일 발송. 존재하지 않는 이메일도 조용히 200(enumeration 방지, GoTrue 기본).
// recovery 링크 검증 = 이메일 소유 증명이라 미인증 계정도 이 경로로 인증·복구된다.
// ⚠️ redirectTo는 Supabase 대시보드 Auth > URL Configuration > Redirect URLs 에 등록돼 있어야 동작
//    (미등록이면 Site URL로 강제 이동). localhost 개발 URL + prod(grgr.kr) 둘 다 등록할 것.
export async function sendPasswordReset(email) {
  const { error } = await supabase.auth.resetPasswordForEmail(email.trim().toLowerCase(), {
    redirectTo: `${window.location.origin}/reset-password`,
  })
  if (error) throw error
}

// 프로필 수정 비밀번호 게이트용 — 페이지가 세션 이메일을 직접 다루지 않게 현재 계정으로 발송한다.
// 메일의 recovery 링크를 열어야 비밀번호를 바꿀 수 있으므로 게이트의 이메일 소유 확인 의미가 유지된다.
export async function sendPasswordResetToCurrentUser() {
  const { data, error } = await supabase.auth.getSession()
  if (error) throw error
  const email = data?.session?.user?.email
  if (!email) throw new Error('세션이 만료됐어요. 다시 로그인해주세요.')
  await sendPasswordReset(email)
}

// 본인 확인(재인증) — 현재 세션의 이메일 + 입력 비밀번호로 signIn을 다시 수행 (프로필 수정 진입 게이트).
// GoTrue에 별도 verify 엔드포인트가 없어 재로그인이 표준 방법. 성공 시 세션이 새로 발급되지만
// 같은 유저라 부작용 없음(onAuthStateChange가 흡수). 틀리면 invalid_credentials로 거부.
export async function verifyCurrentPassword(password) {
  const { data, error } = await supabase.auth.getSession()
  if (error) throw error
  const email = data?.session?.user?.email
  if (!email) throw new Error('세션이 만료됐어요. 다시 로그인해주세요.')
  await signIn(email, password)
}

// 새 비밀번호 확정 — recovery 링크로 만들어진 세션(또는 일반 세션)에서 호출.
// 같은 비밀번호 재사용 시 GoTrue가 code 'same_password' 로 거부.
export async function updatePassword(password) {
  const { error } = await supabase.auth.updateUser({ password })
  if (error) throw error
}

// users 테이블에 해당 닉네임이 이미 존재하는지 검사한다. 있으면 true, 없으면 false.
// (공백 트림 후 정확 일치 비교. 빈 값이면 검사하지 않고 false.)
// ⚠️ RLS 주의: users SELECT 정책은 authenticated·본인행(id = auth.uid())만 허용한다.
//    따라서 가입(anon) 시점엔 항상 0행 → false 반환(사전검사가 사실상 무력). 에러는 아님.
//    실제 닉네임 중복 차단은 가입 트리거 handle_new_user 의 NICKNAME_TAKEN 이 담당한다.
//    (이 함수는 로그인 사용자가 자기 닉네임을 바꿀 때 등의 보조 검사로만 신뢰 가능)
export async function checkNicknameExists(nickname) {
  const v = (nickname ?? '').trim()
  if (!v) return false
  const { data, error } = await supabase
    .from('users')
    .select('nickname')
    .eq('nickname', v)
    .limit(1)
  if (error) throw error
  return data.length > 0
}

// 회원가입 1: 계정 생성 + OTP 코드 메일 발송 (프로필 metadata 없음). 세션은 verify 후 생김.
export async function signUpAuth(email, password) {
  const { data, error } = await supabase.auth.signUp({
    email: email.trim().toLowerCase(), password,
  })
  if (error) throw error
  return data
}

// 회원가입 2: 메일로 받은 6자리 코드 검증 → 성공 시 세션 생성.
export async function verifyEmailOtp(email, token) {
  const { data, error } = await supabase.auth.verifyOtp({
    email: email.trim().toLowerCase(), token, type: 'signup',
  })
  if (error) throw error
  return data
}

// 코드 재전송.
export async function resendOtp(email) {
  const { error } = await supabase.auth.resend({ type: 'signup', email: email.trim().toLowerCase() })
  if (error) throw error
}

// 회원가입 3(마지막): 프로필 행 저장. auth.uid() 기준. 닉네임 중복 시 NICKNAME_TAKEN.
export async function createProfile(p) {
  const { error } = await supabase.rpc('create_profile', {
    p_nickname: p.nickname, p_university_id: p.university_id,
    p_college_name: p.college_name, p_department_name: p.department_name, p_track: p.track,
    p_admission_year: p.admission_year, p_degree_program: p.degree_program,
    p_academic_status: p.academic_status, p_grade: p.grade, p_region: p.region,
  })
  if (error) throw error
}

// promise가 ms 안에 안 끝나면 Error('TIMEOUT')로 거절. 원 promise는 중단 못 하지만(fetch abort 없음)
// 최소한 호출부가 무한정 대기하지 않게 한다. WithdrawModal이 'TIMEOUT'을 지연 안내로 변환한다.
function withTimeout(promise, ms) {
  let timer
  const timeout = new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('TIMEOUT')), ms) })
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer))
}

// 회원 탈퇴 — delete_account RPC(방식 B: security-definer가 auth.users 삭제 → cascade/SET NULL) 호출 후 로컬 세션 정리.
// ⚠️ 나중에 A(Edge Function)로 교체 시 이 함수 "본문만" supabase.functions.invoke('delete-account')로 바꾸면 됨(호출부 불변).
// 삭제 RPC는 되돌릴 수 없어 중간 취소가 없다(모달이 로딩 중 취소를 막음). 대신 15초 타임아웃으로
// 서버/네트워크가 멈춰도 모달이 영구히 갇히지 않게 한다(초과 시 throw → 모달이 에러 표시·취소 재활성).
export async function deleteAccount() {
  const { error } = await withTimeout(supabase.rpc('delete_account'), 15000)
  if (error) throw error
  // 삭제 후 로컬 세션 제거(잔존 access token 무력화). 이미 삭제는 끝났으므로 signOut이 늦어도/실패해도
  // best-effort로 넘어간다(여기서 멈춰 모달이 갇히지 않게 5초 상한 + 실패 무시).
  await withTimeout(supabase.auth.signOut(), 5000).catch(() => {})
}
