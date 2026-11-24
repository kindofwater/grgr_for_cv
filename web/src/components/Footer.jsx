import { Link } from 'react-router-dom'
import './Footer.css'

// 전역 푸터 — AppLayout 하단에 1회 마운트(Navbar처럼 페이지 이동 간 유지).
// 왼쪽: 링크 3개(개인정보처리방침·이용약관·문의사항). 오른쪽: © 운영주체 표기.
// 1:1 문의 창구는 /contact 페이지로 옮김(문의사항 링크). margin-top:auto 로 짧은 페이지도 하단 고정.
export default function Footer() {
  return (
    <footer className="site-footer">
      <div className="gr-container site-footer-inner">
        <nav className="site-footer-links" aria-label="약관 및 정책">
          <Link to="/privacy">개인정보처리방침</Link>
          <span className="site-footer-sep" aria-hidden="true">·</span>
          <Link to="/terms">이용약관</Link>
          <span className="site-footer-sep" aria-hidden="true">·</span>
          <Link to="/contact">문의사항</Link>
        </nav>
        <p className="site-footer-copy">© 2026 근로고래</p>
      </div>
    </footer>
  )
}
