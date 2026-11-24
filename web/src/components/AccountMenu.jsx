import { useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from './AuthContext'
import { isPassActive } from '../lib/passes'
import { formatDateTime } from '../lib/dates'
import ConfirmModal from './ConfirmModal'
import './AccountMenu.css'

// 닉네임 pill + 계정 드롭다운. Navbar에서 로그인 사용자에게 렌더.
// 포인트·열람가능기한은 컨텍스트(user)에서 바로 읽어 "즉시" 표시 — 별도 조회 없음(깜빡임 X).
// 지갑은 세션 하이드레이션 시 fetchMe로 로드되고, 이후 포인트를 바꾸는 액션이 끝날 때마다
// 그 호출부가 mergeUser/refreshProfile로 컨텍스트를 갱신한다(교환센터·광고·리뷰 작성/수정/삭제).
// 열람권 *사용*은 교환센터/마이페이지에서만(여긴 표시 안 함).
export default function AccountMenu() {
  const navigate = useNavigate()
  const { user, logout } = useAuth()
  const [open, setOpen] = useState(false)
  const [confirm, setConfirm] = useState(null) // { message, confirmText, action }
  const ref = useRef(null)

  // 바깥 클릭 / Esc 로 닫기 — open일 때만 document 리스너 부착
  useEffect(() => {
    if (!open) return
    const onDown = (e) => { if (ref.current && !ref.current.contains(e.target)) setOpen(false) }
    const onKey = (e) => { if (e.key === 'Escape') setOpen(false) }
    document.addEventListener('mousedown', onDown)
    document.addEventListener('keydown', onKey)
    return () => {
      document.removeEventListener('mousedown', onDown)
      document.removeEventListener('keydown', onKey)
    }
  }, [open])

  function toggle() {
    if (!user) { navigate('/login'); return }
    setOpen((o) => !o)
  }

  function goTab(tab) {
    setOpen(false)
    navigate(`/mypage?tab=${tab}`)
  }

  function askLogout() {
    setOpen(false)
    setConfirm({
      message: '로그아웃하시겠습니까?',
      confirmText: '확인',
      intent: 'neutral',          // 되돌릴 수 있는 행동 — 빨강 아님
      // scope:'local' — 이 브라우저만 로그아웃. 인자를 안 주면 auth-js 기본이 'global'이라
      // 학교 PC에서 로그아웃했을 뿐인데 집의 폰 세션까지 끊긴다.
      action: () => { logout({ scope: 'local' }); navigate('/login') },
    })
  }

  function runConfirm() {
    const action = confirm.action
    setConfirm(null)
    action()
  }

  const active = isPassActive(user?.pass_expires_at)

  return (
    <div className="acct" ref={ref}>
      <button className={`user-pill ${open ? 'acct-open' : ''}`} onClick={toggle}>
        <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
          <circle cx="12" cy="8" r="3.4"></circle>
          <path d="M5.5 19.5a6.6 6.6 0 0 1 13 0"></path>
        </svg>
        <span>{user?.nickname ?? '사용자'}님</span>
      </button>

      {open && (
        <div className="acct-menu">
          <div className="acct-wallet">
            <div className="acct-row" onClick={() => { setOpen(false); navigate('/exchange') }}>
              <span>포인트</span>
              <strong>{user?.point_balance ?? 0}P</strong>
            </div>
            {active && (
              <>
                <div className="acct-div acct-div-inset" />
                <div className="acct-pass">
                  <div className="acct-pass-on">
                    <div>열람가능기한</div>
                    <div className="acct-pass-date">{formatDateTime(user.pass_expires_at).slice(2)}</div>
                  </div>
                </div>
              </>
            )}
          </div>

          <div className="acct-div" />

          <button className="acct-item" onClick={() => goTab('points')}>포인트 내역</button>
          <button className="acct-item" onClick={() => goTab('reviews')}>내가 쓴 리뷰</button>
          <button className="acct-item" onClick={() => goTab('profile')}>프로필 수정</button>

          <div className="acct-div" />

          <button className="acct-item acct-logout" onClick={askLogout}>로그아웃</button>
        </div>
      )}

      {confirm && (
        <ConfirmModal
          message={confirm.message}
          confirmText={confirm.confirmText}
          intent={confirm.intent}
          onConfirm={runConfirm}
          onCancel={() => setConfirm(null)}
        />
      )}
    </div>
  )
}
