// 비밀번호 재설정 착지 화면 (/reset-password) — 메일의 recovery 링크가 여기로 리다이렉트된다.
// 링크가 유효하면 supabase-js(detectSessionInUrl)가 착지 시점에 이미 세션을 만들어 둔 상태 →
// 새 비밀번호 두 번 입력받아 updatePassword(auth.updateUser)로 확정한다.
// 링크가 만료/무효면 해시에 error_code가 실려 오고 세션이 없다 → 안내 + 로그인 화면으로 유도.
// 프로필 없는 계정(미인증 이탈자 → recovery로 인증 겸 복구)은 변경 완료 후 기존 needsProfile
// 라우팅(ProfileGate → /login → Signup 프로필 단계)이 그대로 받아준다. 스타일은 Login.css 공유.

import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '../components/AuthContext'
import { updatePassword } from '../data/authQueries'
import { recoveryHashError, signupPwError } from '../lib/authValidation'
import ArrowButton from '../components/ArrowButton'
import PageMeta from '../components/PageMeta'
import './Login.css'

function ResetPassword() {
  const { session } = useAuth()
  // 해시는 첫 렌더에서 한 번만 캡처(라이브러리가 소비 후 지울 수 있음)
  const [linkError] = useState(() => recoveryHashError(window.location.hash))
  const [password, setPassword] = useState('')
  const [passwordConfirm, setPasswordConfirm] = useState('')
  const [pwErr, setPwErr] = useState(null)
  const [pwConfirmErr, setPwConfirmErr] = useState(null)
  const [loading, setLoading] = useState(false)
  const [done, setDone] = useState(false)   // 변경 완료 → 안내 후 홈으로
  const navigate = useNavigate()

  // 세션 없거나 링크 자체가 실패(만료/재사용)면 폼 대신 안내.
  // ⚠️ 링크 에러 시 auth-js는 기존 세션을 유지한다 — 그때 폼을 보여주면 공용 PC에서
  //    '로그인돼 있던 다른 계정'의 비밀번호를 바꿔버릴 수 있어 linkError면 무조건 안내로.
  const invalid = !done && (!session || !!linkError)

  // 변경 완료 안내를 잠깐 보여주고 홈으로. (프로필 없는 계정은 ProfileGate가 프로필 단계로 보냄)
  useEffect(() => {
    if (!done) return
    const t = setTimeout(() => navigate('/home', { replace: true }), 1600)
    return () => clearTimeout(t)
  }, [done, navigate])

  async function handleSubmit() {
    if (loading || done) return
    const err = signupPwError(password)
    if (err) { setPwErr(err); return }
    if (password !== passwordConfirm) { setPwConfirmErr('비밀번호가 일치하지 않습니다.'); return }
    setPwErr(null)
    setPwConfirmErr(null)
    setLoading(true)
    try {
      await updatePassword(password)
      setDone(true)
    } catch (err) {
      console.error('비밀번호 변경 실패:', err)
      if (err?.code === 'same_password') {
        setPwErr('이전과 다른 비밀번호를 입력해주세요.')
      } else {
        setPwErr('비밀번호 변경에 실패했어요. 잠시 후 다시 시도해주세요.')
      }
    } finally {
      setLoading(false)
    }
  }

  return (
    <div id="screen-login">
      <PageMeta title="비밀번호 재설정" />
      <nav className="navbar">
        <div className="nav-inner">
          <div className="nav-logo" onClick={() => navigate('/home')} style={{ cursor: 'pointer' }}>근로고래</div>
          <div className="nav-links"></div>
          <div className="nav-right"></div>
        </div>
      </nav>

      <div className="auth-wrap">
        <div className="auth-card">
          <div className="auth-credentials">
            <div className="auth-2col">
              <div className="a2-side">
                <div className="a2-logo">근로<br />고래</div>
                <div className="a2-heading">
                  {done ? '비밀번호 변경 완료' : (invalid ? '비밀번호 재설정' : '새 비밀번호 설정하기')}
                </div>
              </div>
              <div className="a2-divider" />
              <div className="a2-main">
                {invalid && (
                  // 만료/무효 링크 또는 세션 없는 직접 진입
                  <div className="reset-sent field-enter">
                    {linkError ? '재설정 링크가 만료됐거나 이미 사용됐어요.' : '재설정 링크가 유효하지 않아요.'}<br />
                    로그인 화면의 "비밀번호를 잊은 경우"에서{' '}
                    <button type="button" className="btn-text-link" onClick={() => navigate('/login')}>다시 요청</button>
                    해주세요.
                  </div>
                )}

                {!invalid && done && (
                  <div className="reset-sent field-enter">
                    비밀번호가 변경됐어요. 잠시 후 이동합니다.<br />
                    <button type="button" className="btn-text-link" onClick={() => navigate('/home', { replace: true })}>바로 이동하기</button>
                  </div>
                )}

                {!invalid && !done && (
                  // 가입 비번 단계와 동일 구성: 비밀번호 + 재입력 + 완료 버튼 (signup-pw 스타일 재사용)
                  <div className="signup-pw field-enter">
                    {/* 어느 계정을 바꾸는지 명시(세션/기대 계정 불일치를 사용자가 눈치챌 수 있게) */}
                    <div className="reset-account">{session?.user?.email} 계정의 비밀번호를 변경합니다</div>
                    {/* 비번 매니저가 계정을 올바르게 연결하도록 시각적으로 숨긴 username 필드 */}
                    <input
                      type="email" autoComplete="username" value={session?.user?.email ?? ''} readOnly
                      aria-hidden="true" tabIndex={-1}
                      style={{ position: 'absolute', width: 1, height: 1, opacity: 0, pointerEvents: 'none' }}
                    />
                    <div className={`email-field${pwErr ? ' has-error' : ''}`}>
                      <div className="email-control">
                        <input
                          type="password"
                          id="reset-password"
                          className="email-input"
                          placeholder=" "
                          value={password}
                          onChange={(e) => { setPassword(e.target.value); if (pwErr) setPwErr(null) }}
                          onKeyDown={(e) => { if (e.key === 'Enter') handleSubmit() }}
                          autoComplete="new-password"
                          autoFocus
                        />
                        <label htmlFor="reset-password" className="email-label">
                          {pwErr ?? '새 비밀번호 (영문+숫자 8자 이상)'}
                        </label>
                      </div>
                    </div>
                    <div className={`email-field${pwConfirmErr ? ' has-error' : ''}`}>
                      <div className="email-control">
                        <input
                          type="password"
                          id="reset-password-confirm"
                          className="email-input"
                          placeholder=" "
                          value={passwordConfirm}
                          onChange={(e) => { setPasswordConfirm(e.target.value); if (pwConfirmErr) setPwConfirmErr(null) }}
                          onKeyDown={(e) => { if (e.key === 'Enter') handleSubmit() }}
                          autoComplete="new-password"
                        />
                        <label htmlFor="reset-password-confirm" className="email-label">
                          {pwConfirmErr ?? '비밀번호 재입력'}
                        </label>
                      </div>
                    </div>
                    <ArrowButton label="완료" onClick={handleSubmit} disabled={loading} />
                  </div>
                )}
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

export default ResetPassword
