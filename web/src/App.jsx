/// main component, 각 페이지를 라우트로 등록하는 중심 파일.
/// 새 페이지를 추가하려면: 1) import 추가  2) <Route /> 한 줄 추가

import { useEffect } from 'react'
import { BrowserRouter, Routes, Route, Navigate, useLocation } from 'react-router-dom'
import { AuthProvider, useAuth } from './components/AuthContext'
import { ToastProvider } from './components/ToastContext'
import { LoginPromptProvider } from './components/LoginPromptContext'
import AppLayout from './components/AppLayout'
import IdleLogout from './components/IdleLogout'
import Login from './pages/Login'
import ResetPassword from './pages/ResetPassword'
import Home from './pages/Home'
import Search from './pages/Search'
import WorksiteDetail from './pages/WorksiteDetail'
import ReviewForm from './pages/ReviewForm'
import ExchangeCenter from './pages/ExchangeCenter'
import MyPage from './pages/MyPage'
import Notice from './pages/Notice'
import Privacy from './pages/Privacy'
import Terms from './pages/Terms'
import Contact from './pages/Contact'
import NotFound from './pages/NotFound'
import './App.css'

// 세션복원 레이스 가드: AuthContext.isLoading이 true인 동안 라우트를 렌더하지 않는다.
// (새로고침 시 getSession()이 비동기라 잠깐 user=null → 각 페이지의 if(!user) navigate('/login')가 오발동하는 문제 방지)
// useAuth()는 AuthProvider 자식 안에서만 호출 가능하므로 별도 컴포넌트로 분리.
// 미완료 가입(인증O·프로필X)이면 프로필 완성(Login이 렌더)으로 보냄. /login 에선 Login이 직접 처리.
// /reset-password 예외 필수: 프로필 없는 계정이 recovery 링크로 들어와도 비밀번호부터 바꿀 수 있어야 함
// (여기서 쫓아내면 그 계정은 비번을 영영 못 바꿈. 변경 후 홈 이동 시점에 이 게이트가 프로필 단계로 보냄).
function ProfileGate({ children }) {
  const { needsProfile } = useAuth()
  const location = useLocation()
  if (needsProfile && location.pathname !== '/login' && location.pathname !== '/reset-password') {
    return <Navigate to="/login" replace />
  }
  return children
}

// 라우트 이동(pathname) + 쿼리 변경(search, 예: 마이페이지 ?tab=) 시 스크롤 최상단으로.
// React Router 기본은 스크롤 유지(SPA)라 상세→리뷰폼, 탭 전환 등에서 이전 스크롤이 남았음.
// 안전: 공지 아코디언은 로컬 state·검색 필터도 로컬이라 URL 안 바뀜 → 무관. 공지 진입 시
// ?open 1회 제거(replace)는 이미 최상단이라 무해.
function ScrollToTop() {
  const { pathname, search } = useLocation()
  useEffect(() => { window.scrollTo(0, 0) }, [pathname, search])
  return null
}

function GoogleAnalyticsPageViews() {
  const { pathname, search } = useLocation()

  useEffect(() => {
    if (typeof window.gtag !== 'function') return

    window.gtag('event', 'page_view', {
      page_location: window.location.href,
      page_path: `${pathname}${search}`,
      page_title: document.title,
    })
  }, [pathname, search])

  return null
}

function AppRoutes() {
  const { isLoading } = useAuth()

  // 구 localStorage 세션 블롭 잔재 1회 정리 (이전 인증 방식 잔재)
  useEffect(() => {
    localStorage.removeItem('honeyjang.user')
  }, [])

  // 세션 복원 중엔 라우트 렌더만 막고(깜빡임 가드) 화면엔 아무것도 안 띄운다('로딩 중' 문구 X).
  if (isLoading) return null

  return (
    <BrowserRouter>
      <GoogleAnalyticsPageViews />
      <ScrollToTop />
      {/* 유휴 로그아웃(30분). 반드시 BrowserRouter 안(useNavigate) · ProfileGate 밖(언마운트 방지).
          App() 안에 두면 Router 컨텍스트 밖이라 useNavigate()가 throw → 앱 전체 백지. */}
      <IdleLogout />
      <LoginPromptProvider>
      <ProfileGate>
      <Routes>
        <Route path="/" element={<Navigate to="/home" replace />} />
        {/* 자체 상단바/전체화면이라 공용 레이아웃(Navbar) 밖에 둔다 */}
        <Route path="/login" element={<Login />} />
        {/* 비밀번호 재설정 착지(메일 recovery 링크의 redirectTo). Login과 같은 자체 화면 */}
        <Route path="/reset-password" element={<ResetPassword />} />
        {/* 구 /ad 라우트 → 교환센터 모달(AdModal)로 이전. 북마크 호환용 리다이렉트 */}
        <Route path="/ad" element={<Navigate to="/exchange" replace />} />
        {/* 공용 레이아웃: Navbar를 한 번만 마운트해 페이지 이동 간 유지(깜빡임 방지) */}
        <Route element={<AppLayout />}>
          <Route path="/home" element={<Home />} />
          <Route path="/search" element={<Search />} />
          <Route path="/worksite/:id" element={<WorksiteDetail />} />
          <Route path="/worksite/:id/review" element={<ReviewForm />} />
          <Route
            path="/worksite/:id/review/:reviewId/edit"
            element={<ReviewForm />}
          />
          <Route path="/exchange" element={<ExchangeCenter />} />
          <Route path="/mypage" element={<MyPage />} />
          <Route path="/notice" element={<Notice />} />
          {/* 법적 고지 — 푸터에서 링크. 비로그인도 열람 가능(리다이렉트 없음) */}
          <Route path="/privacy" element={<Privacy />} />
          <Route path="/terms" element={<Terms />} />
          <Route path="/contact" element={<Contact />} />
          <Route path="*" element={<NotFound />} />
        </Route>
      </Routes>
      </ProfileGate>
      </LoginPromptProvider>
    </BrowserRouter>
  )
}

function App() {
  return (
    <AuthProvider>
      <ToastProvider>
        <AppRoutes />
      </ToastProvider>
    </AuthProvider>
  )
}

export default App;
