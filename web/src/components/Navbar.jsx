import { useNavigate, useLocation } from 'react-router-dom'
import { useAuth } from './AuthContext'
import './Navbar.css'
import AccountMenu from './AccountMenu'
import { useLoginPrompt } from './LoginPromptContext'

// 공용 상단 네비게이션. AppLayout이 한 번만 마운트해 페이지 이동 간 유지(깜빡임 방지).
// 내부에서 useAuth(닉네임·로그인 여부)·useNavigate를 쓰는 "연결형" 컴포넌트.
// 비로그인(게스트)이면 내비/검색 클릭은 /login으로 유도하고, 우측에 로그인/회원가입 버튼을 보인다.
export default function Navbar() {
  const navigate = useNavigate()
  const { pathname } = useLocation()
  const { user } = useAuth()
  const { promptLogin } = useLoginPrompt()

  // 게스트도 브라우징(근장찾기·공지)은 통과. 로그인 필요한 것(교환센터·마이페이지)은 로그인 모달로 유도.
  const GUEST_LOGIN_REQUIRED = new Set(['/exchange', '/mypage'])
  const go = (path) => () => {
    if (!user && GUEST_LOGIN_REQUIRED.has(path)) { promptLogin(); return }
    navigate(path)
  }
  const searchActive = pathname === '/search'

  return (
    <>
    <nav className="navbar">
      <div className="nav-inner">
        <div className="nav-logo" onClick={() => navigate('/home')} style={{ cursor: 'pointer' }}>근로고래</div>
        <div className="nav-links">
          <a className={searchActive ? 'nav-active' : ''} style={{ cursor: 'pointer' }} onClick={go('/search')}>근장찾기</a>
          <a className={pathname === '/exchange' ? 'nav-active' : ''} style={{ cursor: 'pointer' }} onClick={go('/exchange')}>교환센터</a>
          <a className={pathname.startsWith('/notice') ? 'nav-active' : ''} style={{ cursor: 'pointer' }} onClick={go('/notice')}>공지사항</a>
        </div>
        <div className="nav-right">
          {user ? (
            <AccountMenu />
          ) : (
            <button className="btn-signup-nav" onClick={() => navigate('/login')}>로그인 / 회원가입</button>
          )}
        </div>
      </div>
    </nav>

    {/* 하단 탭바 — 모바일(≤768px)에서만. 위 nav-links 숨김의 대체 메뉴 */}
    <nav className="bottom-nav">
      <a className={searchActive ? 'nav-active' : ''} onClick={go('/search')}>
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><circle cx="11" cy="11" r="7" /><line x1="21" y1="21" x2="15.65" y2="15.65" /></svg>
        근장찾기
      </a>
      <a className={pathname === '/exchange' ? 'nav-active' : ''} onClick={go('/exchange')}>
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><rect x="2" y="7" width="20" height="14" rx="2" /><path d="M16 7V5a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v2" /><line x1="12" y1="12" x2="12" y2="16" /><line x1="10" y1="14" x2="14" y2="14" /></svg>
        교환센터
      </a>
      <a className={pathname.startsWith('/notice') ? 'nav-active' : ''} onClick={go('/notice')}>
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9" /><path d="M13.73 21a2 2 0 0 1-3.46 0" /></svg>
        공지사항
      </a>
    </nav>
    </>
  )
}
