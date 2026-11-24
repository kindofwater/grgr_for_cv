import { useNavigate } from 'react-router-dom'
import Modal from './Modal'

// 비로그인 사용자가 잠긴 기능을 눌렀을 때 뜨는 로그인 유도 모달.
// 홈의 잠긴 카드에서 사용. (구 Home.jsx 인라인 모달 — 갤러리에 올리고 재사용하려고 승격)
export default function LoginPromptModal({ onClose }) {
  const navigate = useNavigate()

  return (
    <Modal
      open
      onOpenChange={(next) => { if (!next) onClose() }}
      size="sm"
      title="로그인이 필요한 기능이에요"
    >
      <div className="modal-icon">
        <svg viewBox="0 0 24 24" width="32" height="32" fill="none" stroke="currentColor"
             strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
          <rect x="5" y="11" width="14" height="9" rx="2"></rect>
          <path d="M8.5 11V8a3.5 3.5 0 0 1 7 0v3"></path>
        </svg>
      </div>
      <p className="modal-text">로그인이 필요한 기능이에요</p>
      <div className="modal-actions">
        <button className="modal-btn modal-btn-cancel" onClick={onClose}>닫기</button>
        {/* onClose 먼저 — LoginPromptProvider가 /login 라우트까지 감싸므로(App.jsx),
            안 닫으면 이 모달이 로그인 화면 위에 그대로 남는다(로그인페이지에서 '안 꺼짐' 버그). */}
        <button className="modal-btn is-primary" onClick={() => { onClose(); navigate('/login') }}>
          로그인하러 가기
        </button>
      </div>
    </Modal>
  )
}
