import { Outlet } from 'react-router-dom'
import Navbar from './Navbar'
import Footer from './Footer'

// 공용 레이아웃 — Navbar/Footer를 한 번만 마운트해 페이지 이동 간 유지(깜빡임 방지).
// App.jsx의 레이아웃 라우트(<Route element={<AppLayout/>}>)로 감싼 페이지들이 <Outlet/>에 렌더된다.
// Login은 자체 화면(고유 상단바/전체화면)이라 이 레이아웃 밖의 별도 라우트. (구 /ad는 교환센터 AdModal로 이전)
//
// Footer는 #root(flex column) 마지막 자식이라 margin-top:auto로 짧은 페이지에서도 하단에 붙는다.
// 지갑 prefetch effect는 C4 AuthContext의 fetchMe가 세션 하이드레이션 시 이미 로드하므로 제거됨.
export default function AppLayout() {
  return (
    <>
      <Navbar />
      <Outlet />
      <Footer />
    </>
  )
}
