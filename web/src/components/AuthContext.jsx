import { createContext, useContext, useEffect, useRef, useState } from 'react'
import { supabase } from '../supabase'
import { fetchMe } from '../data/profileQueries'

const AuthContext = createContext(null)

export function AuthProvider({ children }) {
  const [user, setUser] = useState(null)
  const [session, setSession] = useState(null)
  const [isLoading, setIsLoading] = useState(true)
  // 비동기 경합 가드(last-applied-wins). user/session을 세팅하는 경로가 둘 — 자동 hydrate(onAuthStateChange,
  // setTimeout 0 지연)와 수동 refreshProfile — 이고 둘 다 `await fetchMe()` 후 반영한다. 순서 보장이 없어:
  //  (a) OTP 가입 직후 자동 hydrate가 '프로필 생성 전' fetchMe→null 을 늦게 반영하면 createProfile 후의
  //      refreshProfile(프로필)을 덮어써 /home↔/login 튕김이 났다. → 각 로드는 seq를 claim, 자기 seq가
  //      최신일 때만 반영. refreshProfile은 fetch '완료 직후' claim해 stale hydrate를 무효화하면서 자기
  //      결과는 반영(로그인 직후 navigate가 user를 신뢰). hydrate는 시작 시점에 claim(최신 인증이벤트가 이김).
  //  (b) session·user·isLoading은 항상 '함께'(fetch 후, 최신 seq에서만) 커밋한다(React19 배칭 → 단일 렌더).
  //      안 그러면: 세션만 먼저 truthy → 로그인 시 가입폼 깜빡(needsProfile=session&&!user) / isLoading만
  //      먼저 풀림 → 새로고침 시 navbar가 로그아웃 상태로 깜빡(마운트 시 2번 도는 hydrate 중 먼저 끝난 쪽).
  const loadSeq = useRef(0)

  useEffect(() => {
    let active = true
    async function hydrate(s) {
      const seq = ++loadSeq.current
      if (!s) {
        // session·user·isLoading을 '함께'(최신 seq에서만) 푼다 — isLoading만 먼저 풀리면 마운트 시 2번 도는
        // hydrate 중 먼저 끝난 쪽이 isLoading은 풀고 user는 gated라, navbar가 로그아웃 상태로 깜빡인다.
        if (active && seq === loadSeq.current) { setSession(null); setUser(null); setIsLoading(false) }
        return
      }
      try {
        const me = await fetchMe()
        // session·user·isLoading 항상 '함께' 반영 → 부분상태(세션만/로딩만 풀림) 제거
        if (active && seq === loadSeq.current) {
          setSession(s); setUser(me ? { id: s.user.id, ...me } : null); setIsLoading(false)
        }
      } catch {
        if (active && seq === loadSeq.current) { setSession(s); setUser(null); setIsLoading(false) }
      }
    }
    supabase.auth.getSession().then(({ data }) => hydrate(data.session))
    // ⚠️ onAuthStateChange 콜백 '안에서' supabase 호출(fetchMe)을 하면 GoTrue 내부 lock과 데드락 → 영영 안 끝남.
    //    다음 틱(setTimeout 0)으로 미뤄 lock 밖에서 실행한다.
    const { data: sub } = supabase.auth.onAuthStateChange((_event, s) => {
      setTimeout(() => hydrate(s), 0)
    })
    return () => { active = false; sub.subscription.unsubscribe() }
  }, [])

  // Supabase를 건드리지 않는 로컬 머지(기존 login({...}) 대체)
  const mergeUser = (patch) => setUser((u) => (u ? { ...u, ...patch } : u))
  // 로그아웃: 즉시 상태를 비워(navigate('/login')가 user를 null로 보게 → /home 바운스 방지) navbar도 바로
  // 로그아웃 상태로. seq를 올려 진행 중 fetch가 user를 되살리는 것 막는다. 실제 signout은 onAuthStateChange로 재정리.
  // opts는 supabase.auth.signOut()에 그대로 전달한다(기본값 유지 — 인자 없으면 기존과 동일).
  // 유휴 로그아웃(IdleLogout)은 { scope: 'local' }로 불러 '이 브라우저만' 끊는다.
  // (인자를 안 주면 auth-js 기본이 scope:'global'이라 사용자의 모든 기기 세션이 폐기된다 —
  //  사용자가 직접 누른 로그아웃엔 합당하지만, 자동 유휴 로그아웃엔 부당하다)
  const logout = (opts) => {
    ++loadSeq.current
    setSession(null); setUser(null)
    return supabase.auth.signOut(opts)
  }
  // 프로필 행을 새로 만든 직후(create_profile)·로그인 직후 컨텍스트 갱신 → needsProfile 해제(리다이렉트 루프 방지).
  // fetch 완료 '직후' seq를 claim해 진행 중이던 stale hydrate를 무효화하고, session·user를 함께 반영한다.
  // (가입/로그인 외 동시 signout과 함께 호출되는 경로는 없음 — signout은 onAuthStateChange로 자체 처리.)
  const refreshProfile = async () => {
    const { data } = await supabase.auth.getSession()
    const s = data.session
    if (!s) { ++loadSeq.current; setSession(null); setUser(null); return null }
    try {
      const me = await fetchMe()
      const next = me ? { id: s.user.id, ...me } : null
      ++loadSeq.current   // 쓰기 직전 최신 claim → 늦게 도착할 stale hydrate가 이걸 덮지 못함
      setSession(s); setUser(next)   // session·user 함께 반영 → 로그인 직후 부분상태(가입폼) 깜빡임 방지
      return next
    } catch { return null }
  }
  // 인증은 됐지만 프로필 행이 아직 없음(미완료 가입) → 프로필 완성으로 유도
  const needsProfile = !isLoading && !!session && !user

  return (
    <AuthContext.Provider value={{ user, session, isLoading, needsProfile, mergeUser, refreshProfile, logout }}>
      {children}
    </AuthContext.Provider>
  )
}

// eslint-disable-next-line react-refresh/only-export-components
export function useAuth() { return useContext(AuthContext) }
