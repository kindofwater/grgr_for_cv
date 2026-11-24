import { describe, it, expect } from 'vitest'
import { emailError, loginPwError, signupPwError, nicknameError, nicknameFromEmail, isEmailNotConfirmed, isInvalidCredentials, isRateLimited, isStaleSessionError, recoveryHashError } from './authValidation'

describe('emailError', () => {
  it('빈 값 → 입력 안내', () => {
    expect(emailError('')).toBe('이메일을 입력해주세요.')
    expect(emailError('   ')).toBe('이메일을 입력해주세요.')
  })
  it('형식 틀림 → 형식 안내', () => {
    expect(emailError('abc')).toBe('이메일 형식이 올바르지 않습니다.')
    expect(emailError('a@b')).toBe('이메일 형식이 올바르지 않습니다.')
    expect(emailError('a b@c.com')).toBe('이메일 형식이 올바르지 않습니다.')
  })
  it('올바른 이메일 → null', () => {
    expect(emailError('user@korea.ac.kr')).toBeNull()
    expect(emailError('  user@korea.ac.kr  ')).toBeNull()
  })
  it("'+' 태그 주소 → 거부 (별칭 무한 생성 = 가입 어뷰징 차단)", () => {
    expect(emailError('user+tag@korea.ac.kr')).toBe("'+' 기호는 사용할 수 없습니다.")
    expect(emailError('u+1+2@snu.ac.kr')).toBe("'+' 기호는 사용할 수 없습니다.")
  })
})

describe('loginPwError', () => {
  it('빈 값 → 입력 안내', () => {
    expect(loginPwError('')).toBe('비밀번호를 입력해주세요.')
    expect(loginPwError('   ')).toBe('비밀번호를 입력해주세요.')
  })
  it('값 있으면 null (길이 무관 — 서버가 검증)', () => {
    expect(loginPwError('a')).toBeNull()
    expect(loginPwError('whatever')).toBeNull()
  })
})

describe('signupPwError', () => {
  it('빈 값 → 입력 안내', () => {
    expect(signupPwError('')).toBe('비밀번호를 입력해주세요.')
    expect(signupPwError('   ')).toBe('비밀번호를 입력해주세요.')
  })
  const RULE = '비밀번호는 영문과 숫자를 포함해 8자 이상이어야 합니다.'
  it('8자 미만 → 규칙 안내', () => {
    expect(signupPwError('abc1234')).toBe(RULE)     // 7자(영문·숫자는 있음)
  })
  it('숫자만 / 영문만 → 규칙 안내 (길이가 충분해도 거부)', () => {
    expect(signupPwError('12345678')).toBe(RULE)
    expect(signupPwError('abcdefgh')).toBe(RULE)
  })
  it('영문+숫자 8자 이상 → null', () => {
    expect(signupPwError('abcd1234')).toBeNull()
    expect(signupPwError('Passw0rd!')).toBeNull()   // 특수문자·대문자는 있어도 되고 없어도 됨
  })
})

describe('isEmailNotConfirmed', () => {
  it('supabase 에러 code가 email_not_confirmed → true', () => {
    expect(isEmailNotConfirmed({ code: 'email_not_confirmed', message: 'Email not confirmed' })).toBe(true)
  })
  it('code 없는 구버전 에러 → message로 판별', () => {
    expect(isEmailNotConfirmed({ message: 'Email not confirmed' })).toBe(true)
  })
  it('비번 틀림(invalid_credentials) → false', () => {
    expect(isEmailNotConfirmed({ code: 'invalid_credentials', message: 'Invalid login credentials' })).toBe(false)
  })
  it('null/undefined/일반 에러 → false', () => {
    expect(isEmailNotConfirmed(null)).toBe(false)
    expect(isEmailNotConfirmed(undefined)).toBe(false)
    expect(isEmailNotConfirmed(new Error('network error'))).toBe(false)
  })
})

describe('isInvalidCredentials', () => {
  it('supabase 에러 code가 invalid_credentials → true', () => {
    expect(isInvalidCredentials({ code: 'invalid_credentials', message: 'Invalid login credentials' })).toBe(true)
  })
  it('code 없는 구버전 에러 → message로 판별(대소문자 무관)', () => {
    expect(isInvalidCredentials({ message: 'Invalid login credentials' })).toBe(true)
    expect(isInvalidCredentials({ message: 'invalid login credentials' })).toBe(true)
  })
  it('미인증(email_not_confirmed)·429 → false', () => {
    expect(isInvalidCredentials({ code: 'email_not_confirmed', message: 'Email not confirmed' })).toBe(false)
    expect(isInvalidCredentials({ status: 429, code: 'over_request_rate_limit', message: 'Too many requests' })).toBe(false)
  })
  it('null/undefined/일반 에러 → false', () => {
    expect(isInvalidCredentials(null)).toBe(false)
    expect(isInvalidCredentials(undefined)).toBe(false)
    expect(isInvalidCredentials(new Error('network error'))).toBe(false)
  })
})

describe('isStaleSessionError', () => {
  it('FK 위반(23503) — 삭제된 계정의 세션으로 insert → true', () => {
    expect(isStaleSessionError({
      code: '23503',
      message: 'insert or update on table "users" violates foreign key constraint "users_id_fkey"',
    })).toBe(true)
  })
  it('code 없는 에러 → message의 foreign key constraint로 판별', () => {
    expect(isStaleSessionError({ message: 'violates foreign key constraint "users_id_fkey"' })).toBe(true)
  })
  it('닉네임 중복(NICKNAME_TAKEN)·unique 위반 → false', () => {
    expect(isStaleSessionError({ message: 'NICKNAME_TAKEN' })).toBe(false)
    expect(isStaleSessionError({ code: '23505', message: 'duplicate key value violates unique constraint' })).toBe(false)
  })
  it('null/undefined/일반 에러 → false', () => {
    expect(isStaleSessionError(null)).toBe(false)
    expect(isStaleSessionError(undefined)).toBe(false)
    expect(isStaleSessionError(new Error('network error'))).toBe(false)
  })
})

describe('isRateLimited', () => {
  it('GoTrue 이메일 발송 rate limit(code) → true', () => {
    expect(isRateLimited({ code: 'over_email_send_rate_limit', message: '...' })).toBe(true)
  })
  it('HTTP 429 status → true', () => {
    expect(isRateLimited({ status: 429, message: 'Too many requests' })).toBe(true)
  })
  it('네트워크/기타 에러 → false', () => {
    expect(isRateLimited({ status: 500, message: 'Internal error' })).toBe(false)
    expect(isRateLimited(new Error('Failed to fetch'))).toBe(false)
  })
  it('null/undefined → false', () => {
    expect(isRateLimited(null)).toBe(false)
    expect(isRateLimited(undefined)).toBe(false)
  })
})

describe('recoveryHashError', () => {
  it('만료된 recovery 링크의 해시 → error_code 반환', () => {
    expect(recoveryHashError('#error=access_denied&error_code=otp_expired&error_description=Email+link+is+invalid'))
      .toBe('otp_expired')
  })
  it('error만 있고 error_code 없음 → link_error', () => {
    expect(recoveryHashError('#error=server_error')).toBe('link_error')
  })
  it('정상 토큰 해시 → null', () => {
    expect(recoveryHashError('#access_token=abc&refresh_token=def&type=recovery')).toBeNull()
  })
  it('빈 해시/null → null', () => {
    expect(recoveryHashError('')).toBeNull()
    expect(recoveryHashError(null)).toBeNull()
    expect(recoveryHashError('#')).toBeNull()
  })
})

describe('nicknameError', () => {
  it('빈 값 → null (이메일 @앞부분으로 자동 대체되므로 허용)', () => {
    expect(nicknameError('')).toBeNull()
    expect(nicknameError('   ')).toBeNull()
  })
  it('허용 외 문자(공백·특수문자·자모·이모지) → 문자 안내', () => {
    const msg = '한글·영문·숫자만'
    expect(nicknameError('고 래')).toBe(msg)
    expect(nicknameError('go-rae')).toBe(msg)
    expect(nicknameError('고래!')).toBe(msg)
    expect(nicknameError('ㄱㄴ')).toBe(msg)      // 완성형 아닌 자모
    expect(nicknameError('고래🐳')).toBe(msg)
  })
  it('2자 미만 → 짧음 안내', () => {
    expect(nicknameError('a')).toBe('너무 짧아요')
    expect(nicknameError('곰')).toBe('너무 짧아요')      // 한글 1자도 글자수 2 미만
  })
  it('가중 16 초과(한글 2·영숫자 1) → 김 안내', () => {
    const msg = '너무 길어요'
    expect(nicknameError('가'.repeat(9))).toBe(msg)    // 한글 9자 = 18 > 16
    expect(nicknameError('a'.repeat(17))).toBe(msg)    // 영문 17자 = 17 > 16
    expect(nicknameError('가'.repeat(7) + 'abc')).toBe(msg)  // 혼용 14+3 = 17 > 16
  })
  it('경계값: 한글 8자·영문 16자·혼용 16 → null', () => {
    expect(nicknameError('고래')).toBeNull()
    expect(nicknameError('가'.repeat(8))).toBeNull()   // 16
    expect(nicknameError('a'.repeat(16))).toBeNull()   // 16
    expect(nicknameError('가'.repeat(7) + 'ab')).toBeNull()  // 14+2 = 16
    expect(nicknameError('고래123')).toBeNull()
  })
  it('예약어 부분 일치(대소문자 무시) → 사용 불가 안내', () => {
    const msg = '쓸 수 없는 단어예요'
    expect(nicknameError('익명')).toBe(msg)
    expect(nicknameError('익명123')).toBe(msg)
    expect(nicknameError('진짜운영자')).toBe(msg)
    expect(nicknameError('관리자님')).toBe(msg)
    expect(nicknameError('근로고래')).toBe(msg)
    expect(nicknameError('Admin1')).toBe(msg)
    expect(nicknameError('GRGR')).toBe(msg)
  })
})

describe('nicknameFromEmail', () => {
  it('허용 외 문자 제거 후 유효하면 그 값', () => {
    expect(nicknameFromEmail('brightdear999@korea.ac.kr')).toBe('brightdear999')
    expect(nicknameFromEmail('bright.dear@korea.ac.kr')).toBe('brightdear')
    expect(nicknameFromEmail('a-1@korea.ac.kr')).toBe('a1')
  })
  it('가중 16 초과분은 잘라서 반환', () => {
    expect(nicknameFromEmail('a'.repeat(20) + '@korea.ac.kr')).toBe('a'.repeat(16))
  })
  it('정제 후 2자 미만이거나 예약어면 null (직접 입력 요구)', () => {
    expect(nicknameFromEmail('a@korea.ac.kr')).toBeNull()
    expect(nicknameFromEmail('a..@korea.ac.kr')).toBeNull()
    expect(nicknameFromEmail('ad.min@korea.ac.kr')).toBeNull()   // 정제 결과 'admin' = 예약어
    expect(nicknameFromEmail('')).toBeNull()
    expect(nicknameFromEmail(null)).toBeNull()
  })
})