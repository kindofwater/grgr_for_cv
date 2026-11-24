// 근로고래 회원가입 화면.
// Login 에서 회원가입 분기 후 마운트. step 0 = 이메일 OTP 인증(미인증 fresh), step 1~3 = 프로필.
// 인증: signUpAuth(코드 메일 발송) → verifyEmailOtp. 프로필은 맨 마지막 createProfile 로 저장.
// 이어쓰기: 이미 세션 있으면(인증 완료) step 1부터 시작. 스타일은 Login.css 공유.

import { useState, useEffect, useRef } from 'react'
import { useNavigate } from 'react-router-dom'
import { fetchUniversities, signUpAuth, verifyEmailOtp, resendOtp, createProfile } from '../data/authQueries'
import { useAuth } from '../components/AuthContext'
import { useToast } from '../components/ToastContext'
import { nicknameError, nicknameFromEmail, isStaleSessionError } from '../lib/authValidation'
import { REGIONS, DEGREE_PROGRAMS, ACADEMIC_STATUSES, GRADES, admissionYears, colleges, departments, PREFFEREDTRACK, univIndexFromEmail, univIndexFromDomain, universitiesForEmail } from '../lib/profileOptions'
import ArrowButton from '../components/ArrowButton'
import Dropdown from '../components/Dropdown'
import PrivacyConsentModal from '../components/PrivacyConsentModal'
import TermsConsentModal from '../components/TermsConsentModal'
import './Login.css'

// 드롭다운 옵션은 공용(lib/profileOptions)을 쓴다. 입학연도 목록만 여기서 한 번 계산해 재사용.
const ADMISSION_YEARS = admissionYears()

// 단과대학·학과·계열 옵션은 공용(lib/profileOptions)의 colleges/departments(index 병렬)·PREFFEREDTRACK 사용.
// 학과는 단과대 선택에 종속(계단식) — 미선택 시 비활성 + 안내 문구만.

// notice: 진입 사유 안내(예: 미인증 재로그인 → OTP 단계로 온 이유). OTP 필드 라벨 자리에 1회 표시.
function Signup({ email: emailProp, password, notice, onBack }) {
  const { session, refreshProfile, logout } = useAuth()
  const toast = useToast()
  const verified = !!session                       // 이미 인증됨(resume 또는 OTP 통과 후)
  const email = emailProp || session?.user?.email || ''
  const [loading, setLoading] = useState(false)
  const [otp, setOtp] = useState('')
  const [otpErr, setOtpErr] = useState(null)                 // 빨강 — 검증 실패·발송 실패
  const [otpNotice, setOtpNotice] = useState(notice ?? null) // 파랑 — 정보성 안내(재전송 완료 등). 에러와 동시엔 에러 우선
  const [otpSending, setOtpSending] = useState(false)
  const [termsConsentOpen, setTermsConsentOpen] = useState(false)
  const [privacyConsentOpen, setPrivacyConsentOpen] = useState(false)
  // 필수 동의 3종(#34) — 셋 다 체크해야 OTP 인증 진행. 이어쓰기(세션 보유)는 step 0을 안 거치므로 해당 없음.
  const [consents, setConsents] = useState({ terms: false, privacy: false, age: false })
  const [nickname, setNickname] = useState('')
  const [region, setRegion] = useState('서울')   // 거주지역 기본값
  const [school, setSchool] = useState('')        // universities 조회 후 이메일 도메인과 일치하는 학교로 자동 설정
  const [universities, setUniversities] = useState([])   // 이메일 도메인과 일치하는 학교(캠퍼스)만. 미등록 도메인은 고려대 폴백
  // 단과대/학과 목록의 대학 index — "저장될 학교"(드롭다운 선택값, 폴백 포함)를 따라가
  // create_profile에 넘어가는 university_id와 항상 일치시킨다. 학교 미확정(조회 전)엔 이메일 기준.
  const selectedUni = universities.find((u) => String(u.id) === school)
  const uniIdx = selectedUni ? univIndexFromDomain(selectedUni.email_domain) : univIndexFromEmail(email)
  const [nicknameErr, setNicknameErr] = useState(null)   // 닉네임 필드 인라인 에러(라벨에 표시)
  const [schoolErr, setSchoolErr] = useState(null)       // 학교 필드 인라인 에러
  // 프로필 2단계 입력값
  const [admissionYear, setAdmissionYear] = useState(String(ADMISSION_YEARS[0]))
  const [degreeProgram, setDegreeProgram] = useState('undergrad')
  const [grade, setGrade] = useState('1')
  const [academicStatus, setAcademicStatus] = useState('enrolled')
  // 프로필 3단계 입력값
  const [college, setCollege] = useState('')
  const [department, setDepartment] = useState('')
  const [track, setTrack] = useState('')
  const [collegeErr, setCollegeErr] = useState(null)       // 단과대학 필드 인라인 에러
  const [departmentErr, setDepartmentErr] = useState(null) // 학과 필드 인라인 에러
  const [trackErr, setTrackErr] = useState(null)           // 계열 필드 인라인 에러
  const [profileSubStep, setProfileSubStep] = useState(verified ? 1 : 0)   // 0=OTP(미인증), 1~3=프로필
  const [progressFilled, setProgressFilled] = useState(false)  // 진척도 바 차오름 트리거
  const navigate = useNavigate()

  // 마운트 시 학교 드롭다운 채우기 — 이메일 도메인과 일치하는 학교(캠퍼스)만.
  // 이 드롭다운은 학교 "선택"이 아니라 같은 도메인의 분리 캠퍼스(서울/세종) 선택 용도:
  // 학교는 이메일이 결정하므로 다른 학교는 선택지에 없다(등록 학교끼리 불일치 원천 차단).
  // 미등록 도메인은 고려대 폴백(universitiesForEmail) — 기존 '기본값 고려대' 동작 유지(2026-07-17 결정).
  // 그래도 비면(고려대 행 부재 = 조회 실패급) 1단계 검증이 안내 문구로 차단.
  useEffect(() => {
    let alive = true
    ;(async () => {
      try {
        const data = await fetchUniversities()
        if (alive && data.length) {
          const matched = universitiesForEmail(data, email)
          setUniversities(matched)
          if (matched.length) setSchool(String(matched[0].id))   // 단일 캠퍼스면 사실상 자동 확정
        }
      } catch { /* 드롭다운 비어도 진행 가능 */ }
    })()
    return () => { alive = false }
  }, [email])

  // 마운트 직후 진척도 바를 0 → 현재 단계로 차오르게. (단계 변경 시에도 width transition 으로 애니메이션)
  useEffect(() => {
    const t = setTimeout(() => setProgressFilled(true), 60)   // 0%→목표% 로 전환되며 차오름
    return () => clearTimeout(t)
  }, [])

  // 미인증 fresh 가입이면 마운트 시 계정 생성 + 코드 메일 발송 (1회).
  // ⚠️ StrictMode(개발)는 effect를 2번 실행 → signUp 중복 호출 시 중복키 에러.
  //    ref 가드로 딱 한 번만 호출되게 막는다.
  const signUpStarted = useRef(false)
  useEffect(() => {
    if (verified || signUpStarted.current) return
    signUpStarted.current = true
    ;(async () => {
      try {
        await signUpAuth(email, password)
      } catch (e) {
        const m = e?.message || ''
        // 이미 가입(미인증)된 이메일이면 새 코드만 재전송 → 계속 진행 가능
        if (m.includes('already registered') || m.includes('User already registered')) {
          try { await resendOtp(email) } catch { /* 재전송 실패는 무시 */ }
        } else {
          console.error('인증 메일 발송 실패:', e)
          setOtpNotice(null)
          setOtpErr('인증 메일 발송에 실패했어요. 잠시 후 다시 시도해주세요.')
        }
      }
    })()
  }, [])  // eslint-disable-line react-hooks/exhaustive-deps

  // OTP 코드 검증 → 성공 시 프로필 단계로. 필수 동의 3종이 선행 조건.
  async function handleVerifyOtp() {
    if (!(consents.terms && consents.privacy && consents.age)) {
      setOtpNotice(null)
      setOtpErr('필수 항목에 모두 동의해주세요.')
      return
    }
    if (!otp.trim()) { setOtpErr('코드를 입력해주세요.'); return }
    setOtpSending(true)
    try {
      await verifyEmailOtp(email, otp.trim())
      setOtpErr(null)
      setProfileSubStep(1)
    } catch {
      setOtpErr('코드가 올바르지 않거나 만료됐어요.')
    } finally {
      setOtpSending(false)
    }
  }

  // 코드 재전송. 성공은 정보(파랑), 실패는 에러(빨강)로 구분 표시.
  async function handleResendOtp() {
    setOtpSending(true)
    try { await resendOtp(email); setOtpErr(null); setOtpNotice('코드를 다시 보냈어요.') }
    catch { setOtpNotice(null); setOtpErr('재전송이 너무 잦아요. 잠시 후 다시 시도해주세요.') }
    finally { setOtpSending(false) }
  }

  // 프로필 입력 진행 — 마지막(3단계) 전까지는 다음 단계로. 마지막에서 createProfile.
  async function handleProfileSubmit() {
    if (profileSubStep < 3) {
      // 1단계: 닉네임(규칙은 authValidation nicknameError, 미입력은 이메일 @앞부분 대체) + 학교 선택 검증
      if (profileSubStep === 1) {
        const nErr = nicknameError(nickname)
        if (nErr) { setNicknameErr(nErr); return }
        // 미입력 폴백(이메일 @앞부분 정제)이 규칙을 통과 못 하면 직접 입력을 요구한다
        // (점·하이픈 제거 후 2자 미만이거나 예약어가 되는 이메일 — 서버 NICKNAME_INVALID로 가입이 터지는 것 방지)
        if (!nickname.trim() && !nicknameFromEmail(email)) {
          setNicknameErr('직접 입력해주세요')   // 문구는 8자 이하 유지(모바일 인라인 — authValidation nicknameError 주석 참고)
          return
        }
        // 도메인 미등록(빈 목록)과 단순 미선택을 구분해 안내
        if (!school) {
          setSchoolErr(universities.length === 0 ? '아직 지원하지 않는 학교 이메일이에요.' : '학교를 선택해주세요.')
          return
        }
        // 닉네임 중복은 마지막 create_profile 의 NICKNAME_TAKEN 이 담당(서버 권위).
      }
      setProfileSubStep(profileSubStep + 1)
      return
    }
    // 3단계: 단과대학·학과·계열 필수 선택 검증 (미선택은 인라인 에러 + 빨간 테두리)
    let bad = false
    if (!college) { setCollegeErr('단과대학을 선택해주세요.'); bad = true }
    if (!department) { setDepartmentErr('학과를 선택해주세요.'); bad = true }
    if (!track) { setTrackErr('계열을 선택해주세요.'); bad = true }
    if (bad) return
    setLoading(true)
    try {
      await createProfile({
        nickname: nickname.trim() || nicknameFromEmail(email),   // 미입력 시 이메일 @앞부분(규칙 정제 — 1단계에서 null 아님 보장)
        university_id: Number(school),
        college_name: college,        // 단과대학 드롭다운 선택값
        department_name: department,  // 학과 드롭다운 선택값
        track,                        // 계열 드롭다운 선택값
        admission_year: Number(admissionYear),
        degree_program: degreeProgram,
        academic_status: academicStatus,
        grade: Number(grade),
        region,
      })
      await refreshProfile()   // 새 프로필을 컨텍스트에 반영 → needsProfile 해제(리다이렉트 루프 방지)
      navigate('/home')        // 이미 인증(세션) 완료 → 홈으로
    } catch (err) {
      console.error('프로필 저장 실패:', err)
      const m = err?.message || ''
      if (m.includes('NICKNAME_TAKEN')) {
        setNicknameErr('이미 있는 닉네임')   // 문구는 8자 이하 유지(모바일 인라인)
        setProfileSubStep(1)   // 닉네임 필드 보이도록 1단계로 복귀해 인라인 표시
      } else if (m.includes('NICKNAME_RESERVED')) {
        // 서버 validate_nickname — 프론트 검증을 우회했거나 목록이 어긋난 경우의 안전망
        setNicknameErr('쓸 수 없는 단어예요')
        setProfileSubStep(1)
      } else if (m.includes('NICKNAME_INVALID')) {
        setNicknameErr('다시 확인해주세요')   // 서버는 문자/길이를 구분 안 하므로 통합 안내
        setProfileSubStep(1)
      } else if (m.includes('NO_COLLEGE') || m.includes('NO_DEPARTMENT')) {
        toast('학과 정보를 다시 확인해 주세요.', 'error')
      } else if (isStaleSessionError(err)) {
        // 유령 세션(계정 삭제 후 남은 토큰): 이 세션으론 영영 저장 불가 → 비우고 처음부터
        toast(`탭 종료 후 다시 시도해 보세요. (오류 ${err?.code ?? '23503'})`, 'error', 5000)
        // scope:'local' — 이 브라우저만. 기본값 'global'은 다른 기기 세션까지 끊는다
        await logout({ scope: 'local' })
        onBack?.()   // Login의 profileStep 잔재 정리(needsProfile 경로면 no-op)
      } else {
        toast('회원가입 중 오류가 발생했어요. 잠시 후 다시 시도해주세요.', 'error')
      }
    } finally {
      setLoading(false)
    }
  }

  // 뒤로가기 — 2·3단계는 이전 단계로, 1단계는 Login 비밀번호 단계로 복귀(onBack)
  function handleBack() {
    setNicknameErr(null)
    setSchoolErr(null)
    if (profileSubStep > (verified ? 1 : 0)) setProfileSubStep(profileSubStep - 1)
    else onBack?.()
  }

  // 제출(화살표) 버튼 — OTP 단계는 로고 옆(sp-right), 프로필 1~3단계는 카드 오른쪽 아래(sp-left 끝)
  const submitBtn = (
    <div className="sp-submit">
      <ArrowButton
        label={profileSubStep === 0 ? '인증' : (profileSubStep < 3 ? '다음' : '완료')}
        onClick={profileSubStep === 0 ? handleVerifyOtp : handleProfileSubmit}
        disabled={loading || otpSending}
      />
      {(loading || otpSending) && (
        <div className="sp-loading-dots" role="status" aria-label="처리 중">
          <span /><span /><span />
        </div>
      )}
    </div>
  )

  return (
    <>
      {/* 회원가입 2단계: 좌측 입력 묶음 + 구분선 + 우측 로고/화살표 (mockup 이미지).
          입력 필드는 sp-left 안에 sp-group 추가. 프로필 div는 총 3단계 → 아래 진척도 바(3등분). */}
      {/* 뒤로가기는 signup-profile(slide-in transform) 밖에 둬야 함 — transform이 컨테이닝 블록이
          되어 로딩 중 버튼이 밀리는 현상 방지. auth-card 직속 자식이라 카드 모서리에 고정됨 */}
      {profileSubStep !== 1 && (
        <button type="button" className="btn-back signup-back" onClick={handleBack} aria-label="이전 단계">
          <svg viewBox="0 0 24 24" width="28" height="28" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <line x1="19" y1="12" x2="5" y2="12" />
            <polyline points="12 19 5 12 12 5" />
          </svg>
        </button>
      )}
      <div className={`signup-profile${profileSubStep > 0 ? ' sp-roomy' : ''}`} key={profileSubStep}>
        <div className="sp-left">
          {profileSubStep === 0 && (
            <div className="sp-group">
              {/* 에러/안내는 큰 라벨을 바꾸지 않고 오른쪽에 작은 글씨로(에러 빨강 · 안내 파랑, 에러 우선) */}
              <div className="sp-field-label">
                인증 코드
                {otpErr && <span className="sp-field-error">{otpErr}</span>}
                {!otpErr && otpNotice && <span className="sp-field-notice">{otpNotice}</span>}
              </div>
              <div className={`email-field${otpErr ? ' has-error' : ''}`}>
                <div className="email-control">
                  <input
                    type="text" inputMode="numeric" id="signup-otp"
                    className="email-input" placeholder=" " value={otp}
                    onChange={(e) => { setOtp(e.target.value); if (otpErr) setOtpErr(null) }}
                    onKeyDown={(e) => { if (e.key === 'Enter') handleVerifyOtp() }}
                    autoFocus
                  />
                  <label htmlFor="signup-otp" className="email-label otp-hint">{`${email} 로 보낸 6자리 코드`}</label>
                </div>
              </div>
              <button type="button" className="btn-text-link" onClick={handleResendOtp} disabled={otpSending} style={{ marginTop: '8px', textDecoration: 'underline' }}>
                코드 재전송
              </button>
              {/* 필수 동의 체크박스(#34) — 개인정보 수집·이용은 회원가입용 상세 모달로 확인 */}
              <div className="sp-consent-checks">
                <label className="consent-check">
                  <input type="checkbox" checked={consents.terms} onChange={(e) => { setConsents((c) => ({ ...c, terms: e.target.checked })); if (otpErr) setOtpErr(null) }} />
                  <span>
                    <em className="consent-tag">[필수]</em>{' '}
                    <button
                      type="button"
                      className="consent-link"
                      onClick={(e) => {
                        e.preventDefault()
                        e.stopPropagation()
                        setTermsConsentOpen(true)
                      }}
                    >
                      이용약관
                    </button>{' '}
                    동의
                  </span>
                </label>
                <label className="consent-check">
                  <input type="checkbox" checked={consents.privacy} onChange={(e) => { setConsents((c) => ({ ...c, privacy: e.target.checked })); if (otpErr) setOtpErr(null) }} />
                  <span>
                    <em className="consent-tag">[필수]</em>{' '}
                    <button
                      type="button"
                      className="consent-link"
                      onClick={(e) => {
                        e.preventDefault()
                        e.stopPropagation()
                        setPrivacyConsentOpen(true)
                      }}
                    >
                      개인정보 수집 및 이용
                    </button>{' '}
                    동의
                  </span>
                </label>
                <label className="consent-check">
                  <input type="checkbox" checked={consents.age} onChange={(e) => { setConsents((c) => ({ ...c, age: e.target.checked })); if (otpErr) setOtpErr(null) }} />
                  <span><em className="consent-tag">[필수]</em> 만 14세 이상</span>
                </label>
              </div>
            </div>
          )}
          {profileSubStep === 1 && (
            <>
              <div className="sp-group">
                {/* 추천 닉네임 = 이메일 @앞부분을 규칙에 맞게 정제한 값(미입력 시 실제 저장될 폴백과 동일). 에러 시엔 에러가 자리 차지 */}
                <div className="sp-field-label">
                  닉네임
                  {nicknameErr
                    ? <span className="sp-field-error">{nicknameErr}</span>
                    : nicknameFromEmail(email) && (
                      <span className="sp-field-notice sp-nick-reco">
                        추천 :{' '}
                        <button type="button" className="sp-nick-suggest" onClick={() => setNickname(nicknameFromEmail(email))}>
                          {nicknameFromEmail(email)}
                        </button>
                      </span>
                    )}
                </div>
                <div className={`email-field${nicknameErr ? ' has-error' : ''}`}>
                  <div className="email-control">
                    <input
                      type="text"
                      id="signup-nickname"
                      aria-label="닉네임"
                      className="email-input nickname-input"
                      placeholder="닉네임을 입력하세요"
                      value={nickname}
                      onChange={(e) => { setNickname(e.target.value); if (nicknameErr) setNicknameErr(null) }}
                    />
                  </div>
                </div>
              </div>
              <div className="sp-group">
                <div className="sp-field-label">거주 지역</div>
                <Dropdown value={region} onChange={setRegion} options={REGIONS} ariaLabel="거주 지역" />
              </div>
              <div className="sp-group">
                <div className={`sp-field-label${schoolErr ? ' is-error' : ''}`}>{schoolErr ?? '학교'}</div>
                {/* 이메일 도메인과 일치하는 학교만 — 복수면 캠퍼스 선택, 미등록 도메인이면 안내 placeholder */}
                <Dropdown
                  value={school}
                  onChange={(v) => { setSchool(v); if (schoolErr) setSchoolErr(null) }}
                  options={universities.length
                    ? universities.map((u) => ({ value: String(u.id), label: `${u.name}${u.campus ? ` (${u.campus})` : ''}` }))
                    : [{ value: '', label: '아직 지원하지 않는 학교 이메일이에요' }]}
                  disabled={universities.length === 0}
                  ariaLabel="학교"
                  hasError={!!schoolErr}
                />
              </div>
            </>
          )}

          {profileSubStep === 2 && (
            <>
              <div className="sp-group">
                <div className="sp-field-label">입학연도</div>
                <Dropdown value={admissionYear} onChange={setAdmissionYear} options={ADMISSION_YEARS.map((y) => String(y))} ariaLabel="입학연도" />
              </div>
              <div className="sp-group">
                <div className="sp-field-label">학위과정</div>
                <Dropdown value={degreeProgram} onChange={setDegreeProgram} options={DEGREE_PROGRAMS.map(([v, l]) => ({ value: v, label: l }))} ariaLabel="학위과정" />
              </div>
              <div className="sp-group">
                <div className="sp-field-label">학년</div>
                <Dropdown value={grade} onChange={setGrade} options={GRADES.map((g) => ({ value: String(g), label: `${g}학년` }))} ariaLabel="학년" />
              </div>
              <div className="sp-group">
                <div className="sp-field-label">학적상태</div>
                <Dropdown value={academicStatus} onChange={setAcademicStatus} options={ACADEMIC_STATUSES.map(([v, l]) => ({ value: v, label: l }))} ariaLabel="학적상태" />
              </div>
            </>
          )}

          {profileSubStep === 3 && (
            <>
              <div className="sp-group">
                <div className="sp-field-label">단과대학{collegeErr && <span className="sp-field-error">{collegeErr}</span>}</div>
                {/* 단과대 변경 시 학과 선택은 무효 — 항상 초기화 */}
                <Dropdown value={college} onChange={(v) => { setCollege(v); setDepartment(''); if (collegeErr) setCollegeErr(null) }} options={[{ value: '', label: '선택' }, ...colleges[uniIdx].map((c) => ({ value: c, label: c }))]} ariaLabel="단과대학" hasError={!!collegeErr} />
              </div>
              <div className="sp-group">
                <div className="sp-field-label">학과{departmentErr && <span className="sp-field-error">{departmentErr}</span>}</div>
                {/* 계단식: 단과대 미선택이면 비활성 + 안내만, 선택하면 해당 단과대 학과만(colleges와 index 병렬) */}
                <Dropdown value={department} onChange={(v) => { setDepartment(v); if (departmentErr) setDepartmentErr(null) }}
                  options={college
                    ? [{ value: '', label: '선택' }, ...(departments[uniIdx][colleges[uniIdx].indexOf(college)] ?? []).map((d) => ({ value: d, label: d }))]
                    : [{ value: '', label: '단과대학을 먼저 선택해주세요' }]}
                  disabled={!college} ariaLabel="학과" hasError={!!departmentErr} />
              </div>
              <div className="sp-group">
                <div className="sp-field-label">계열{trackErr && <span className="sp-field-error">{trackErr}</span>}</div>
                <Dropdown value={track} onChange={(v) => { setTrack(v); if (trackErr) setTrackErr(null) }} options={[{ value: '', label: '선택' }, ...PREFFEREDTRACK.map((t) => ({ value: t, label: t }))]} ariaLabel="계열" hasError={!!trackErr} />
              </div>
            </>
          )}
          {profileSubStep > 0 && submitBtn}
        </div>

        <div className="sp-divider" />

        <div className="sp-right">
          <div className="sp-logo">근로고래</div>
          {profileSubStep === 0 && submitBtn}
        </div>
      </div>

      <div className="signup-progress">
        <div
          className="sp-progress-fill"
          style={{ width: progressFilled ? `${((profileSubStep + 1) / 4) * 100}%` : '0%' }}
        />
      </div>

      {privacyConsentOpen && (
        <PrivacyConsentModal onClose={() => setPrivacyConsentOpen(false)} />
      )}

      {termsConsentOpen && (
        <TermsConsentModal onClose={() => setTermsConsentOpen(false)} />
      )}
    </>
  )
}

export default Signup
