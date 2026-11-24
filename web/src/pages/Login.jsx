// 근로고래 로그인/회원가입 화면 — 이메일 먼저 입력 → 가입여부(email_registered)로 분기.
// 있으면 비밀번호 단계(로그인), 없으면 회원가입 모드(비번 설정 → 프로필 단계 <Signup/>).
// 로그인은 Supabase Auth signIn. 세션 반영은 AuthContext onAuthStateChange 가 처리(별도 login() 없음).
// 미인증 가입 이탈자(auth 행만 있고 메일 확인 전): signIn이 email_not_confirmed로 거부 →
// OTP 인증 단계(<Signup/>)로 보낸다. GoTrue가 비번 검증 후 미인증을 거부하므로 이 분기 = 비번 정확.
// 비번까지 잊은 미인증 유저는 비밀번호 재설정(#35)으로 구제(recovery 완료가 이메일 인증 겸함).

import { useEffect, useState } from 'react'
import { useNavigate, useLocation } from 'react-router-dom'
import { useAuth } from '../components/AuthContext'
import { useToast } from '../components/ToastContext'
import { emailRegistered, sendPasswordReset, signIn } from '../data/authQueries'
import { emailError, isSchoolEmail, isEmailNotConfirmed, isRateLimited, loginPwError, signupPwError } from '../lib/authValidation'
import ArrowButton from '../components/ArrowButton'
import Signup from './Signup'
import PageMeta from '../components/PageMeta'
import './Login.css'

function Login() {
  const { needsProfile, user, refreshProfile, logout } = useAuth()   // 인증O·프로필X → Signup; user 있으면 홈으로
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [passwordConfirm, setPasswordConfirm] = useState('')   // 회원가입 비밀번호 재입력
  const [emailErr, setEmailErr] = useState(null)   // 이메일 필드 인라인 에러(라벨에 표시)
  const [pwErr, setPwErr] = useState(null)         // 비밀번호 필드 인라인 에러
  const [pwConfirmErr, setPwConfirmErr] = useState(null)  // 비밀번호 재입력 인라인 에러
  const [loading, setLoading] = useState(false)
  const [registered, setRegistered] = useState(false)   // 이메일 확인 완료 → 비밀번호 단계
  const [leaving, setLeaving] = useState(false)          // SSO 버튼 퇴장 애니메이션 중
  const [isSignUpMode, setIsSignUpMode] = useState(false)  // 이메일 미가입 → 회원가입 모드
  const [leavingToProfile, setLeavingToProfile] = useState(false) // 비번 단계 → 프로필 단계 전환 애니메이션 중
  const [profileStep, setProfileStep] = useState(false)           // 회원가입 2단계(프로필 입력) 표시 → <Signup/> 마운트
  const [resumeNotice, setResumeNotice] = useState(null)          // 미인증 재로그인 → OTP 단계 진입 사유 안내
  const [resetSent, setResetSent] = useState(false)          // 비번 재설정 메일 발송 → 안내 패널 표시
  const [leavingToReset, setLeavingToReset] = useState(false) // 비번 단계 → 재설정 안내 전환 애니메이션 중
  const [leavingFromReset, setLeavingFromReset] = useState(false) // 재설정 안내 → 비번 단계 복귀 애니메이션 중
  const navigate = useNavigate()
  const toast = useToast()
  const location = useLocation()

  // 이미 완전히 로그인된 유저(프로필 보유)가 로그인 화면에 오면 홈으로 (튕김 자동복구 포함)
  useEffect(() => { if (user) navigate('/home', { replace: true }) }, [user, navigate])

  // 30분 유휴 자동 로그아웃(IdleLogout)이 state.reason='idle'로 보낸다 → 왜 튕겼는지 알려준다.
  // ⚠️ 유휴 '경고 모달'은 일부러 안 만든다(의도된 부재). 안내는 이 토스트 하나로 끝.
  // 뒤로가기·새로고침으로 같은 토스트가 다시 뜨지 않게 state를 1회 소비하고 지운다.
  useEffect(() => {
    if (location.state?.reason !== 'idle') return
    toast('30분 동안 활동이 없어 자동으로 로그아웃했어요.', 'info', 5000)
    navigate(location.pathname, { replace: true, state: null })
  }, [location.state, location.pathname, navigate, toast])

  // 확인 버튼: 이메일 형식·학교이메일 검증 후 가입여부(email_registered)를 조회 → 비밀번호 단계로 진입.
  // 가입돼 있으면 로그인 모드, 아니면 회원가입 모드(끝나면 registered=true).
  async function check() {
    if (loading) return   // Enter 연타 등 요청 중 재진입 방지
    const err = emailError(email)
    if (err) { setEmailErr(err); return }
    setEmailErr(null)
    if (!isSchoolEmail(email)) { setEmailErr('학교 이메일이 아닙니다'); return }
    setLoading(true)
    try {
      const exists = await emailRegistered(email)
      setIsSignUpMode(!exists)
      setLeaving(true)               // 가입 여부 상관없이 비밀번호 단계 진입 애니메이션 시작 (끝나면 registered=true)
    } catch (err) {
      console.error('이메일 확인 실패:', err)
      toast('확인 중 오류가 발생했어요. 잠시 후 다시 시도해주세요.', 'error')
    } finally {
      setLoading(false)
    }
  }

  // 비밀번호 입력 후 로그인 시도 — Supabase Auth signIn.
  // 미인증 거부(email_not_confirmed)는 가입 이탈 복귀 케이스 → <Signup/> OTP 단계로 라우팅.
  // ⚠️ Enter 키는 버튼 disabled를 우회하므로 요청 중·전환 중 재진입을 여기서 직접 막는다.
  async function handleLogin() {
    if (loading || leavingToReset || backLeaving) return
    const err = loginPwError(password)
    if (err) { setPwErr(err); return }
    setPwErr(null)
    setLoading(true)
    try {
      await signIn(email, password)
      await refreshProfile()   // 프로필을 먼저 컨텍스트에 반영 → /home 진입 시 needsProfile 오판 방지
      navigate('/home')      // 성공 → 홈
    } catch (err) {
      if (isEmailNotConfirmed(err)) {
        // 미인증 가입 이탈자(비번은 정확): <Signup/> 마운트 → signUpAuth가 기존 미인증 계정에 인증코드 재발송 → OTP 단계
        setResumeNotice('가입 인증이 완료되지 않았어요. 메일로 받은 코드를 입력해주세요.')
        setProfileStep(true)
      } else {
        console.error('로그인 실패:', err)
        setPwErr('비밀번호가 올바르지 않습니다.')   // 비번 틀림/없는 계정 — 비번 필드에 인라인
      }
    } finally {
      setLoading(false)
    }
  }

  // '비밀번호를 잊은 경우' — 재설정 메일 발송 성공 시 안내 패널로 전환(비번 단계 진입과 동일한 애니메이션)
  // 요청 중(loading)엔 goBack/ESC가 막혀 있어(아래 가드) await 후에도 비번 단계임이 보장된다.
  async function handleForgotPassword() {
    if (loading || leavingToReset || backLeaving) return
    setLoading(true)
    try {
      await sendPasswordReset(email)
      setPwErr(null)
      setLeavingToReset(true)   // 필드 퇴장 애니메이션 → onAnimationEnd 에서 resetSent=true
    } catch (err) {
      console.error('재설정 메일 발송 실패:', err)
      setPwErr(isRateLimited(err)
        ? '요청이 너무 잦아요. 잠시 후 다시 시도해주세요.'
        : '재설정 메일 발송에 실패했어요. 잠시 후 다시 시도해주세요.')
    } finally {
      setLoading(false)
    }
  }

  // 안내 패널의 '여기' — 재설정 메일 재전송. rate limit(429)만 "너무 잦아요", 그 외는 일반 실패로 구분
  async function handleResendReset() {
    if (loading || leavingFromReset) return
    setLoading(true)
    try { await sendPasswordReset(email); toast('재설정 메일을 다시 보냈어요.', 'info', 5000) }
    catch (err) {
      console.error('재설정 메일 재전송 실패:', err)
      toast(isRateLimited(err)
        ? '재전송이 너무 잦아요. 잠시 후 다시 시도해주세요.'
        : '재설정 메일 재전송에 실패했어요. 연결을 확인하고 다시 시도해주세요.', 'error', 5000)
    }
    finally { setLoading(false) }
  }

  // 회원가입 1단계(비밀번호) 완료 → 2단계(프로필) 전환 애니메이션 시작
  function handleSignUp() {
    const err = signupPwError(password)
    if (err) { setPwErr(err); return }
    if (password !== passwordConfirm) { setPwConfirmErr('비밀번호가 일치하지 않습니다.'); return }
    setPwErr(null)
    setPwConfirmErr(null)
    setLeavingToProfile(true)   // credentials 블록 왼쪽으로 슬라이드 아웃 → onAnimationEnd 에서 profileStep
  }

  const [backLeaving, setBackLeaving] = useState(false)  // 뒤로가기: 비번 필드 퇴장 애니메이션 중
  const [returning, setReturning] = useState(false)      // 뒤로가기 후 SSO 버튼 재등장 애니메이션 중

  // 비밀번호 단계 → 이메일 단계로 되돌아가기. 비번 필드 퇴장 애니메이션 시작 → onAnimationEnd에서 마무리
  // 재설정 안내 패널에서는 비번 단계로 한 단계만 복귀(전환/요청 중에는 무시).
  // ⚠️ loading 가드 필수: 재설정 메일 발송 대기 중 뒤로 가면 leavingToReset이 이메일 단계에 좌초해 화면이 죽는다.
  function goBack() {
    if (loading || backLeaving || leavingToReset || leavingFromReset) return
    if (resetSent) { setPwErr(null); setLeavingFromReset(true); return }   // 패널 퇴장 애니메이션 → onAnimationEnd
    setPwErr(null)
    setBackLeaving(true)
  }

  // 뒤로가기 애니메이션 종료 후 이메일 단계 상태로 초기화 (로그인·회원가입 블록 공용)
  function finishBack() {
    setRegistered(false)
    setIsSignUpMode(false)
    setPassword('')
    setPasswordConfirm('')
    setPwErr(null)
    setPwConfirmErr(null)
    setLeaving(false)
    setBackLeaving(false)
    setLeavingToReset(false)   // 방어: 좌초된 재설정 전환 플래그가 이메일 단계를 field-leaving으로 가리는 것 방지
    setResetSent(false)
    setLeavingFromReset(false)
    setReturning(true)
  }

  // 비밀번호 단계에서 ESC → 한 단계 뒤로(어디에 포커스가 있든). goBack과 동일한 가드/분기.
  // <Signup/> 표시 중엔 리스너 해제 — credentials 블록이 언마운트라 backLeaving을 지울 animationend가 없어 좌초함.
  useEffect(() => {
    if (!registered || profileStep || needsProfile) return
    function onKey(e) {
      if (e.key !== 'Escape') return
      if (loading || backLeaving || leavingToReset || leavingFromReset) return
      if (resetSent) { setPwErr(null); setLeavingFromReset(true); return }
      setPwErr(null)
      setBackLeaving(true)
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [registered, resetSent, backLeaving, leavingToReset, leavingFromReset, loading, profileStep, needsProfile])

  return (
    <div id="screen-login">
      <PageMeta title="로그인" />
      <nav className="navbar">
        <div className="nav-inner">
          {/* 로고 = 홈. 미완성 가입(인증O·프로필X)은 세션을 정리하고 '게스트 홈'으로 —
              안 그러면 ProfileGate가 도로 여기로 돌려보내 탈출구가 없다. 가입은 다음 로그인 때 프로필 단계로 재개. */}
          <div
            className="nav-logo"
            onClick={async () => {
              // scope:'local' — 로고 클릭은 명시적 로그아웃이 아니라 이 브라우저의 미완성 세션 정리(IdleLogout 컨벤션)
              if (needsProfile) { try { await logout({ scope: 'local' }) } catch { /* 실패해도 컨텍스트는 비워짐 — 진행 */ } }
              navigate('/home')
            }}
            style={{ cursor: 'pointer' }}
          >근로고래</div>
          {/* 로그인 화면 자체가 로그인/회원가입 플로우라 상단 우측 버튼(장식·무동작) 제거 */}
        </div>
      </nav>

      <div className="auth-wrap">
        <div className={`auth-card${(profileStep || needsProfile) ? ' is-profile' : ''}`}>
          {!profileStep && !needsProfile && (
            <div
              className={`auth-credentials${leavingToProfile ? ' leaving-left' : ''}`}
              onAnimationEnd={(e) => {
                // 래퍼 자신의 슬라이드아웃만 처리 (자식 애니메이션 버블링은 무시)
                if (leavingToProfile && e.target === e.currentTarget) {
                  setProfileStep(true)
                  setLeavingToProfile(false)
                }
              }}
            >
              <div className="auth-2col">
                <div className="a2-side">
                  <div className="a2-logo">근로<br />고래</div>
                  {!registered && (
                    <div className={`a2-heading${leaving ? ' heading-out-right' : ''}`}>이메일 입력으로 시작하기</div>
                  )}
                  {registered && !isSignUpMode && !resetSent && (
                    // 재설정 전환 시엔 비번 헤딩이 오른쪽으로 퇴장(이메일→비번 전환과 동일한 스왑)
                    <div className={leavingToReset ? 'a2-heading heading-out-right' : 'a2-heading heading-in-left'}>로그인 비밀번호 입력하기</div>
                  )}
                  {registered && !isSignUpMode && resetSent && (
                    <div className={leavingFromReset ? 'a2-heading heading-out-right' : 'a2-heading heading-in-left'}>비밀번호 재설정하기</div>
                  )}
                  {registered && isSignUpMode && (
                    <div className="a2-heading heading-in-left">회원가입 비밀번호 입력하기</div>
                  )}
                </div>
                <div className="a2-divider" />
                <div className="a2-main">
              {/* 자리는 항상 예약(높이 연속성) — 비번 단계에서만 보이게 */}
              <button
                type="button"
                className={`btn-back${registered ? '' : ' is-hidden'}`}
                onClick={goBack}
                aria-label="이메일 다시 입력"
                tabIndex={registered ? 0 : -1}
              >
                <svg viewBox="0 0 24 24" width="28" height="28" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                  <line x1="19" y1="12" x2="5" y2="12" />
                  <polyline points="12 19 5 12 12 5" />
                </svg>
              </button>
              {/* 재설정 패널에서도 마운트 유지(is-ghost로 숨김) — 언마운트하면 높이가 한 프레임에 무너져 레이아웃이 튐 */}
              <div className={`email-field${emailErr ? ' has-error' : ''}${leavingToReset ? ' field-leaving' : ''}${resetSent ? ' is-ghost' : ''}`}>
                <div className="email-control">
                  <input
                    type="email"
                    id="login-email"
                    className="email-input"
                    placeholder=" "
                    value={email}
                    disabled={registered}
                    onChange={(e) => { setEmail(e.target.value); if (emailErr) setEmailErr(null) }}
                    onKeyDown={(e) => {
                      if (e.key === 'Enter') check()
                    }}
                  />
                  <label htmlFor="login-email" className="email-label">
                    {/* 라벨 문구는 폭별 CSS 토글(≤480px = 짧은 버전) — 미디어쿼리로 텍스트를 못 바꾸므로 두 span */}
                    {emailErr ?? (
                      <>
                        <span className="lbl-desktop">이메일(Ex. example@univ.ac.kr)</span>
                        <span className="lbl-mobile">(Ex. example@univ.ac.kr)</span>
                      </>
                    )}
                  </label>
                </div>
                {!leaving && !registered && (
                  <ArrowButton label="확인" onClick={check} disabled={loading} />
                )}
              </div>

              <div className="auth-switch">
                {registered && !isSignUpMode && !resetSent && (
                  // 로그인: 단일 비밀번호 필드 + 인라인 화살표 버튼 + 아래 '잊은 경우' 링크
                  <>
                  <div
                    className={`email-field field-enter${pwErr ? ' has-error' : ''}${(backLeaving || leavingToReset) ? ' field-leaving' : ''}`}
                    onAnimationEnd={(e) => {
                      if (e.target !== e.currentTarget) return
                      if (backLeaving) finishBack()
                      else if (leavingToReset) { setLeavingToReset(false); setResetSent(true) }
                    }}
                  >
                    <div className="email-control">
                      <input
                        type="password"
                        id="login-password"
                        className="email-input"
                        placeholder=" "
                        value={password}
                        onChange={(e) => { setPassword(e.target.value); if (pwErr) setPwErr(null) }}
                        onKeyDown={(e) => { if (e.key === 'Enter') handleLogin() }}
                        autoFocus
                      />
                      <label htmlFor="login-password" className="email-label">
                        {pwErr ?? '비밀번호'}
                      </label>
                    </div>
                    <ArrowButton label="로그인" onClick={handleLogin} disabled={loading} />
                  </div>
                  <div className={`pw-forgot field-enter${(backLeaving || leavingToReset) ? ' field-leaving' : ''}`}>
                    <button type="button" className="btn-text-link" onClick={handleForgotPassword} disabled={loading}>
                      비밀번호를 잊은 경우
                    </button>
                  </div>
                  </>
                )}
                {registered && !isSignUpMode && resetSent && (
                  // 재설정 메일 발송 안내 — 필드 영역 대체. '여기' = 재전송. 복귀 시 진입과 대칭으로 퇴장 애니메이션
                  <div
                    className={`reset-sent field-enter${leavingFromReset ? ' field-leaving' : ''}`}
                    onAnimationEnd={(e) => {
                      if (leavingFromReset && e.target === e.currentTarget) { setResetSent(false); setLeavingFromReset(false) }
                    }}
                  >
                    비밀번호 재설정 이메일을 보냈습니다.<br />
                    만약 이메일이 수신되지 않았다면,{' '}
                    <button type="button" className="btn-text-link" onClick={handleResendReset} disabled={loading}>여기</button>
                    를 눌러 재설정 메일을 다시 받으세요.
                  </div>
                )}
                {registered && isSignUpMode && (
                  // 회원가입: 비밀번호 + 재입력 두 필드(인라인 버튼 없음) + 맨밑 제출 버튼
                  <div
                    className={`signup-pw field-enter${backLeaving ? ' field-leaving' : ''}`}
                    onAnimationEnd={(e) => { if (backLeaving && e.target === e.currentTarget) finishBack() }}
                  >
                    <div className={`email-field${pwErr ? ' has-error' : ''}`}>
                      <div className="email-control">
                        <input
                          type="password"
                          id="signup-password"
                          className="email-input"
                          placeholder=" "
                          value={password}
                          onChange={(e) => { setPassword(e.target.value); if (pwErr) setPwErr(null) }}
                          onKeyDown={(e) => { if (e.key === 'Enter') handleSignUp() }}
                          autoFocus
                        />
                        <label htmlFor="signup-password" className="email-label">
                          {pwErr ?? '회원가입 비밀번호 (영문+숫자 8자 이상)'}
                        </label>
                      </div>
                    </div>
                    <div className={`email-field${pwConfirmErr ? ' has-error' : ''}`}>
                      <div className="email-control">
                        <input
                          type="password"
                          id="signup-password-confirm"
                          className="email-input"
                          placeholder=" "
                          value={passwordConfirm}
                          onChange={(e) => { setPasswordConfirm(e.target.value); if (pwConfirmErr) setPwConfirmErr(null) }}
                          onKeyDown={(e) => { if (e.key === 'Enter') handleSignUp() }}
                        />
                        <label htmlFor="signup-password-confirm" className="email-label">
                          {pwConfirmErr ?? '비밀번호 재입력'}
                        </label>
                      </div>
                    </div>
                    <ArrowButton label="회원가입" onClick={handleSignUp} disabled={loading} />
                  </div>
                )}
                {!registered && (
                  <button
                    className={`btn-sso${leaving ? ' btn-leaving' : ''}${returning ? ' btn-returning' : ''}`}
                    onClick={() => toast('아직 불가능! 조금만 기다려!')}
                    onAnimationEnd={() => {
                      if (leaving) {
                        setRegistered(true)
                        setLeaving(false)
                      } else if (returning) {
                        setReturning(false)
                      }
                    }}
                  >
                    <svg
                      viewBox="0 0 24 24"
                      width="16"
                      height="16"
                      fill="none"
                      stroke="currentColor"
                      strokeWidth="1.7"
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      style={{ flex: '0 0 auto' }}
                    >
                      <path d="M4 21V9.5l8-4.5 8 4.5V21"></path>
                      <path d="M3 21h18"></path>
                      <rect x="10" y="14" width="4" height="7"></rect>
                    </svg>
                    학교 포털 아이디로 로그인
                  </button>
                )}
              </div>
              </div>
              </div>
            </div>
          )}

          {(profileStep || needsProfile) && <Signup email={email} password={password} notice={resumeNotice} onBack={() => { setProfileStep(false); setResumeNotice(null); setLeavingToReset(false); setBackLeaving(false) }} />}

        </div>
      </div>
    </div>
  )
}


export default Login