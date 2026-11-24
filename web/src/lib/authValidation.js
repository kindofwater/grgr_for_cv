// 로그인/회원가입 입력 검증 (순수 함수). 각 함수는 에러 메시지(string) 또는 null 반환.
// 메시지는 입력 필드 라벨에 인라인으로 표시된다(Login/Signup). 서버·네트워크 에러는 여기서 안 다룬다.

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

export function emailError(value) {
  const v = (value ?? '').trim()
  if (!v) return '이메일을 입력해주세요.'
  if (!EMAIL_RE.test(v)) return '이메일 형식이 올바르지 않습니다.'
  // '+' 태그 주소 차단 — 같은 계정으로 별칭 무한 생성(가입/포인트 어뷰징) 방지
  if (v.includes('+')) return "'+' 기호는 사용할 수 없습니다."
  return null
}

// 학교 이메일(@[학교].ac.kr) 여부 — 순수 검사. 도메인이 .ac.kr 로 끝나야 true.
export function isSchoolEmail(value) {
  const v = (value ?? '').trim().toLowerCase()
  return /@[^\s@]+\.ac\.kr$/.test(v)
}

// 로그인 비밀번호 — 존재만 검사(정확성은 서버 verify_login).
export function loginPwError(value) {
  if (!(value ?? '').trim()) return '비밀번호를 입력해주세요.'
  return null
}

// 회원가입 비밀번호 — 존재 + 최소 8자 + 영문·숫자 각각 1자 이상.
//   길이만 보던 시절엔 '12345678'·'aaaaaaaa' 같은 게 통과했다(2026-07-20 강화).
//   ⚠️ 로그인(loginPwError)에는 이 규칙을 걸지 않는다 — 규칙 강화 이전에 가입한 계정이
//   기존 비밀번호로 못 들어오게 되기 때문. 로그인은 존재만 보고 정확성은 서버가 판정한다.
//   길이·종류를 따로 안내하지 않고 한 문구로 합친 건, 어느 조건이 틀렸는지 알려주면
//   공격자에게 힌트가 되고 사용자에겐 오히려 여러 번 되돌아오게 만들기 때문.
export function signupPwError(value) {
  const v = value ?? ''
  if (!v.trim()) return '비밀번호를 입력해주세요.'
  const ok = v.length >= 8 && /[A-Za-z]/.test(v) && /[0-9]/.test(v)
  if (!ok) return '비밀번호는 영문과 숫자를 포함해 8자 이상이어야 합니다.'
  return null
}

// Supabase 로그인 에러가 "이메일 미인증" 거부인지 판별.
// GoTrue는 비밀번호를 먼저 검증한 뒤 미인증을 거부하므로, 이 에러 = 비번은 맞음 + OTP 인증만 남음.
// supabase-js 2.39+ 는 error.code('email_not_confirmed') 제공 — 구버전 대비 message 매칭 폴백.
export function isEmailNotConfirmed(err) {
  if (!err) return false
  if (err.code === 'email_not_confirmed') return true
  return typeof err.message === 'string' && err.message.toLowerCase().includes('email not confirmed')
}

// 로그인/재인증 거부가 "비밀번호 틀림"인지 판별 (MyPage 프로필 수정 진입 게이트 등).
// GoTrue는 없는 계정도 같은 에러를 주지만, 세션 이메일로 재인증하는 경로에선 곧 비번 틀림이다.
export function isInvalidCredentials(err) {
  if (!err) return false
  if (err.code === 'invalid_credentials') return true
  return typeof err.message === 'string' && err.message.toLowerCase().includes('invalid login credentials')
}

// GoTrue 이메일 발송 rate limit 여부 판별 — 진짜 429만 "너무 잦아요"로 안내하고
// 그 외(오프라인·5xx)는 일반 발송 실패로 구분하기 위함.
export function isRateLimited(err) {
  if (!err) return false
  return err.status === 429 || err.code === 'over_email_send_rate_limit'
}

// 프로필 저장 실패가 '유령 세션'(auth 계정 삭제 후 남은 토큰) 신호인지 판별.
// users.id → auth.users FK 위반(23503)은 create_profile의 unique 변환(NICKNAME_TAKEN)을 안 거치고
// 날것으로 온다 — 이 세션으로는 영영 저장 불가하므로 로그아웃 후 재로그인 유도가 정답.
export function isStaleSessionError(err) {
  if (!err) return false
  if (err.code === '23503') return true
  return typeof err.message === 'string' && err.message.includes('foreign key constraint')
}

// 비밀번호 재설정 착지(/reset-password) 시 URL 해시의 GoTrue 에러 파싱 — 만료/사용된 링크 감지.
// '#error=...&error_code=otp_expired...' → 'otp_expired' · error만 있으면 'link_error' · 정상(토큰/빈 해시) → null
export function recoveryHashError(hash) {
  const params = new URLSearchParams((hash ?? '').replace(/^#/, ''))
  const code = params.get('error_code')
  if (code) return code
  return params.get('error') ? 'link_error' : null
}

// ── 닉네임 규칙 — 서버 validate_nickname(20260721071224_nickname_policy.sql)과 반드시 동일하게 유지 ──
//   · 허용 문자: 완성형 한글(가-힣)·영문·숫자만
//   · 길이: 2자 이상 + 가중치(한글 2·영숫자 1) 합 16 이하 → 한글 8자 / 영문 16자 / 혼용 비례
//   · 예약어: 부분 일치(소문자화) 차단 — 운영진·서비스 사칭 및 '익명'(익명 리뷰 표시 문자열) 위장 방지
const NICKNAME_CHAR_RE = /^[가-힣A-Za-z0-9]+$/
const RESERVED_NICKNAMES = [
  '익명', '운영자', '관리자', '근로고래', '고래지기',
  'admin', 'administrator', 'manager', 'operator', 'staff',
  'system', 'anonymous', 'official', 'grgr', 'geunrogorae',
]

// 가중 길이 — 한글 2 · 영숫자 1
function nicknameWeight(v) {
  let w = 0
  for (const ch of v) w += /[가-힣]/.test(ch) ? 2 : 1
  return w
}

// 닉네임 — 빈 값은 허용(이메일 @앞부분으로 자동 대체 — nicknameFromEmail). 에러 메시지 또는 null.
// ⚠️ 문구는 8자 이하로 유지 — 라벨(27px "닉네임") 옆 인라인 표시라, 360px 폰에서 그보다 길면
//    줄바꿈되며 라벨 아래로 지저분하게 접힌다(측정 확인). 길이 규칙은 짧음/김을 나눠 각각 안내.
export function nicknameError(value) {
  const v = (value ?? '').trim()
  if (!v) return null
  if (!NICKNAME_CHAR_RE.test(v)) return '한글·영문·숫자만'
  if (v.length < 2) return '너무 짧아요'
  if (nicknameWeight(v) > 16) return '너무 길어요'
  const lower = v.toLowerCase()
  if (RESERVED_NICKNAMES.some((r) => lower.includes(r))) return '쓸 수 없는 단어예요'
  return null
}

// 닉네임 미입력 시 폴백 — 이메일 @앞부분을 규칙에 맞게 정제(허용 외 문자 제거 + 가중 16 절단).
// 정제 결과가 규칙(길이·예약어)을 통과하지 못하면 null → 호출부는 직접 입력을 요구해야 한다.
// (예: 'bright.dear'→'brightdear' OK, 'ad.min'→'admin' 예약어라 null, 'a-1'→'a1' 2자 OK)
export function nicknameFromEmail(email) {
  const raw = ((email ?? '').split('@')[0] ?? '').replace(/[^가-힣A-Za-z0-9]/g, '')
  let out = ''
  let w = 0
  for (const ch of raw) {
    const cw = /[가-힣]/.test(ch) ? 2 : 1
    if (w + cw > 16) break
    out += ch
    w += cw
  }
  return out.length >= 2 && nicknameError(out) === null ? out : null
}
