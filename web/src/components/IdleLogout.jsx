import { useEffect, useRef } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from './AuthContext'
import { IDLE_TIMEOUT_MS, POLL_INTERVAL_MS, parseLastActive, isExpired } from '../lib/idle'
import { readLastActive, writeLastActive } from './idleStorage'

// 유휴 로그아웃 — 로그인(프로필 완료) 사용자가 timeoutMs 동안 무활동이면 자동 로그아웃.
// 설계: docs/superpowers/specs/2026-07-14-idle-logout-design.md
//
// 원칙: 만료 판정의 진실원천은 '벽시계'(now - lastActive)다. 타이머(폴링)는 '확인하러 깨워주는'
//   수단일 뿐 — 만료 여부는 매번 localStorage의 lastActive를 다시 읽어 판정한다.
//   (인메모리 타이머는 절전·탭 freeze·bfcache·모바일 백그라운드에서 흐르지 않는다)
//
// ⚠️ 마운트 위치: 반드시 <BrowserRouter> 안(useNavigate 사용) · <ProfileGate> 밖(언마운트 방지).
//    App() 안에 두면 Router 컨텍스트 밖이라 useNavigate()가 throw → 앱 전체 백지.

// 'input' 필수 — keydown만으론 모바일 글라이드·음성입력·추천단어·붙여넣기가 '무활동'으로 잡힌다.
// (input은 버블링되므로 document 바인딩으로 전부 포착)
const ACTIVITY_EVENTS = ['mousemove', 'keydown', 'input', 'scroll', 'click', 'touchstart']
// 백그라운드에선 setInterval이 스로틀/정지되므로 복귀 '순간' 즉시 재평가해야 한다.
const RESUME_WINDOW_EVENTS = ['focus', 'pageshow', 'storage']
const ACTIVITY_THROTTLE_MS = 1000   // localStorage 쓰기 폭주 방지

// signOut 실패 시 하드 리로드는 '탭당 1회'로 제한한다. GoTrue가 죽어 signOut이 계속 실패하면
// 리로드→세션복원→만료→리로드가 무한 반복돼 탭이 벽돌이 된다(로그인 화면조차 못 씀).
const HARD_RELOAD_ONCE_KEY = 'honeyjang.idle.hardReloaded'

export default function IdleLogout({
  timeoutMs = IDLE_TIMEOUT_MS,
  pollMs = POLL_INTERVAL_MS,
  storage,
}) {
  const { user, logout, isLoading } = useAuth()
  const navigate = useNavigate()
  const uid = user?.id ?? null
  const store = storage ?? (typeof window !== 'undefined' ? window.localStorage : null)

  // ⚠️ AuthContext의 logout·navigate를 effect 의존성에 넣으면 안 된다.
  //    logout은 AuthProvider에서 매 렌더 새로 만들어지는 함수(메모이즈 없음)라,
  //    의존성에 넣으면 렌더마다 effect가 재실행되며 lastActive를 재시딩 →
  //    유휴 시계가 영영 안 흐르고 로그아웃이 절대 발생하지 않는다.
  //    최신 참조는 ref로만 들고 다닌다.
  const logoutRef = useRef(logout)
  const navigateRef = useRef(navigate)
  useEffect(() => {
    logoutRef.current = logout
    navigateRef.current = navigate
  })

  // 로그아웃 중복 발화 가드. 모듈 스코프 let이 아니라 ref —
  // SPA라 로그아웃→재로그인 사이에 페이지 리로드가 없어, uid 전이 때 리셋하지 않으면
  // 유휴 로그아웃이 '페이지 로드당 1회용'이 된다(재로그인 후 영영 로그아웃 안 됨).
  const firing = useRef(false)
  // 이미 시딩을 마친 uid. StrictMode 이중 마운트에서 재시딩·가드 초기화를 막는다.
  const seededFor = useRef(null)
  // 첫 effect 실행인지. '마운트 시점에 이미 로그인' = 복원된 세션을 구분하는 유일한 신호.
  const firstRun = useRef(true)

  useEffect(() => {
    if (isLoading) return          // 세션 복원 중 — 아직 판단하지 않는다(firstRun 유지)
    const wasFirstRun = firstRun.current
    firstRun.current = false

    // 비로그인 / 가입 미완료(needsProfile: 인증O·프로필X) → 완전 무동작.
    // user 게이트인 이유: session으로 게이트하면 OTP 통과 후 프로필 입력 중에도 타이머가 돌아,
    // 로그아웃 시 Login의 profileStep이 남아 <Signup/>이 좀비로 살아있고 입력이 전소된다.
    if (!uid || !store) {
      // 로그아웃 → 다음 로그인은 같은 계정이라도 '새 로그인'으로 취급해야 한다.
      // 안 비우면: firing이 true로 고착돼 유휴 로그아웃이 '페이지 로드당 1회용'이 되고(a),
      //           stale lastActive로 재로그인 즉시 되튕긴다(b). SPA라 리로드가 없어 ref가 살아남는다.
      seededFor.current = null
      firing.current = false
      return
    }

    const doLogout = async () => {
      if (firing.current) return
      firing.current = true

      // signOut() 실패(네트워크 오류 등) 시 auth-js가 localStorage 세션을 안 지운다
      // → 하드 리로드로 메모리 상태까지 확실히 날린다. 단, GoTrue가 죽어 signOut이 계속
      // 실패하면 '리로드→세션복원→lastActive 여전히 만료→doLogout→또 실패→리로드'가
      // 무한 반복돼 탭이 벽돌이 된다(로그인 화면조차 못 씀) — 그래서 하드 리로드는 탭당 1회만
      // 허용하고, 이미 한 번 했으면 소프트 이동(replace)으로 끝낸다.
      const bailOut = () => {
        let already
        try { already = sessionStorage.getItem(HARD_RELOAD_ONCE_KEY) === '1' } catch { already = true } // 접근 불가 → 소프트 이동
        if (already) {
          // 이미 한 번 하드 리로드했다 → 또 하면 무한 루프. 소프트 이동으로 끝낸다.
          navigateRef.current('/login', { replace: true, state: { reason: 'idle' } })
          return
        }
        try {
          sessionStorage.setItem(HARD_RELOAD_ONCE_KEY, '1')
          // 되확인: 못 남겼는데 하드 리로드하면, 부팅 때마다 플래그가 없어 무한 리로드가 된다.
          if (sessionStorage.getItem(HARD_RELOAD_ONCE_KEY) !== '1') throw new Error('not persisted')
        } catch {
          // 플래그를 못 남긴다 → 하드 리로드 금지(무한 루프 방지). 소프트 이동으로 끝낸다.
          navigateRef.current('/login', { replace: true, state: { reason: 'idle' } })
          return
        }
        window.location.replace('/login')
      }

      try {
        // lastActive는 '지우지 않는다'(idleStorage에 삭제 함수가 없는 이유).
        // scope:'local' 필수 — 인자를 안 주면 auth-js 기본이 'global'이라 사용자의 모든 기기
        // 세션이 끊긴다. 유휴 로그아웃은 사용자가 의도한 적이 없으므로 이 브라우저만 끊는다.
        const { error } = (await logoutRef.current({ scope: 'local' })) ?? {}
        if (error) { bailOut(); return }
        // 성공했으면 다음 유휴 로그아웃에서 다시 하드 리로드를 쓸 수 있도록 플래그를 정리한다.
        try { sessionStorage.removeItem(HARD_RELOAD_ONCE_KEY) } catch { /* 무시 */ }
        // replace 필수: 페이지 가드(MyPage·Search·ExchangeCenter·WorksiteDetail·ReviewForm)도
        // replace라, push로 가면 뒤로가기 시 /mypage ↔ /login 핑퐁 트랩에 갇힌다.
        navigateRef.current('/login', { replace: true, state: { reason: 'idle' } })
      } catch {
        // signOut이 throw해도 firing이 true로 고착되면 안 된다 — bailOut으로 확실히 정리.
        bailOut()
      }
    }

    const check = () => {
      if (firing.current) return
      const entry = parseLastActive(readLastActive(store))
      if (isExpired(entry, uid, Date.now(), timeoutMs)) doLogout()
    }

    if (seededFor.current !== uid) {
      // 이 uid로는 아직 시딩하지 않았다 = '복원된 세션의 첫 마운트' 또는 '새 로그인'.
      if (wasFirstRun) {
        // 마운트 시점에 이미 로그인 = 복원된 세션 → 저장된 lastActive로 '먼저 판정'한다.
        // ("창을 껐다가 40분 뒤 다시 열었다"를 여기서 잡는다. 무조건 시딩해버리면 이 요구가 죽는다.)
        const entry = parseLastActive(readLastActive(store))
        if (isExpired(entry, uid, Date.now(), timeoutMs)) {
          seededFor.current = uid
          doLogout()
          return
        }
      }
      // 새 로그인(uid가 마운트 이후 null→값) 또는 아직 유효한 복원 세션 → 시딩.
      // (재로그인 시 stale 값으로 즉시 튕기는 것을 막는다)
      firing.current = false
      seededFor.current = uid
      writeLastActive(store, uid, Date.now())
    }

    let lastWrite = 0
    const onActivity = () => {
      const now = Date.now()
      if (now - lastWrite < ACTIVITY_THROTTLE_MS) return
      check()                 // 만료 증거를 덮어쓰기 전에 먼저 판정 (절전 복귀 레이스 방지)
      if (firing.current) return
      lastWrite = now
      writeLastActive(store, uid, now)
    }

    ACTIVITY_EVENTS.forEach((e) => document.addEventListener(e, onActivity, { passive: true }))
    document.addEventListener('visibilitychange', check)
    RESUME_WINDOW_EVENTS.forEach((e) => window.addEventListener(e, check))
    const pollId = setInterval(check, pollMs)

    check()   // 마운트 즉시 1회

    return () => {
      clearInterval(pollId)
      ACTIVITY_EVENTS.forEach((e) => document.removeEventListener(e, onActivity))
      document.removeEventListener('visibilitychange', check)
      RESUME_WINDOW_EVENTS.forEach((e) => window.removeEventListener(e, check))
    }
    // logout·navigate는 의도적으로 제외(위 주석 참고). storage/timeoutMs/pollMs는 안정적.
  }, [uid, store, timeoutMs, pollMs, isLoading])

  return null
}
