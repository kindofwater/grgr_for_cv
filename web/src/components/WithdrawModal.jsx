import { useState } from 'react'
import Modal from './Modal'

const CONFIRM_PHRASE = '탈퇴합니다'

// 회원 탈퇴 확인 모달 — 되돌릴 수 없어(유예 없음) 문구 타이핑으로 이중 확인.
// 사라지는 것 안내 + "탈퇴합니다" 정확 입력 시에만 버튼 활성. onConfirm: 부모가 deleteAccount 실행.
export default function WithdrawModal({ onConfirm, onCancel }) {
  const [phrase, setPhrase] = useState('')
  const [loading, setLoading] = useState(false)
  const [err, setErr] = useState('')

  const canConfirm = phrase.trim() === CONFIRM_PHRASE && !loading

  async function handleConfirm() {
    if (!canConfirm) return
    setLoading(true); setErr('')
    try {
      await onConfirm()   // 성공 시 부모가 리다이렉트 → 이 모달은 언마운트됨
    } catch (e) {
      // deleteAccount 15초 타임아웃(TIMEOUT)이면 '멈춤' 안내로 구분 — 그 외는 일반 오류.
      setErr(e?.message === 'TIMEOUT'
        ? '요청이 지연되고 있어요. 연결을 확인하고 다시 시도해 주세요.'
        : '탈퇴 처리 중 오류가 났어요. 잠시 후 다시 시도해 주세요.')
      setLoading(false)
    }
  }

  return (
    <Modal
      open
      // 탈퇴 처리 중엔 Esc·배경클릭으로 못 닫는다 (RPC가 도는 중에 모달만 사라지면 사용자가 혼란)
      dismissible={!loading}
      onOpenChange={(next) => { if (!next && !loading) onCancel() }}
      size="md"
      title="정말 탈퇴하시겠어요?"
      titleHidden={false}
      className="modal-withdraw"
    >
      <ul className="mw-list">
        <li>작성한 리뷰는 <b>&quot;탈퇴한 사용자&quot;</b>로 익명 처리돼요(내용은 남아요).</li>
        <li>보유 <b>포인트·열람권은 모두 소멸</b>돼요.</li>
        <li>같은 이메일로는 <b>30일간 재가입할 수 없어요</b>.</li>
        <li><b>되돌릴 수 없어요.</b></li>
      </ul>

      <label className="mw-label" htmlFor="mw-phrase">
        확인을 위해 <b>{CONFIRM_PHRASE}</b> 를 입력해 주세요
      </label>
      <input
        id="mw-phrase"
        className="mw-input"
        value={phrase}
        onChange={(e) => setPhrase(e.target.value)}
        placeholder={CONFIRM_PHRASE}
        disabled={loading}
        autoFocus
      />
      {err && <p className="mw-err">{err}</p>}

      <div className="modal-actions">
        {/* 로딩 중엔 취소 비활성 — 삭제 요청은 되돌릴 수 없어(중간 취소 불가) 진행 중 이탈을 막는다.
            "취소=멈춤"이 아니라 요청은 계속 진행되므로, 취소를 열어두면 '취소했는데 계정 삭제됨' 오해가 생긴다.
            멈춤 대비는 deleteAccount의 15초 타임아웃이 담당(초과 시 에러로 풀려 취소 재활성). */}
        <button className="modal-btn modal-btn-cancel" onClick={onCancel} disabled={loading}>
          취소
        </button>
        <button className="modal-btn is-danger" onClick={handleConfirm} disabled={!canConfirm} aria-busy={loading}>탈퇴하기</button>
      </div>
    </Modal>
  )
}
