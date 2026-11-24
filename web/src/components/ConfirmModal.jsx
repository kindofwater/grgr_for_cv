import Modal from './Modal'

// 확인/취소 모달 — 리뷰 삭제·로그아웃·열람권 교환/사용/환불·익명 제출에 재사용.
//
// intent = 확인 버튼의 성격. 취소 버튼은 언제나 아웃라인이라 색으로 안 싸운다.
//   primary(파랑)  되돌릴 수 있거나 권장되는 진행 — 교환·사용·익명 제출
//   neutral(회색)  권장하지도 위험하지도 않은 것 — 로그아웃·환불
//   danger(빨강)   되돌릴 수 없는 상실 — 리뷰 삭제·회원 탈퇴
//
// ⚠️ className prop을 다시 만들지 말 것. 페이지별 스타일 주입 통로가 되는 순간 모달이 다시 갈라진다.
//    변형이 필요하면 intent처럼 '정해진 값'으로만 늘린다.

// 주 질문("…?")과 뒤따르는 설명을 분리 → 설명은 옅은 note로. 모든 확인 모달을
// '질문(600) + 설명(500 옅음)' 같은 계층 구조로 통일한다.
//   "이 리뷰를 삭제할까요? (적립한 포인트가 회수됩니다)" → 질문 + note(괄호)
//   "30일 열람권을 지금 사용할까요? 사용하면 …"        → 질문 + note(설명)
//   "로그아웃하시겠습니까?"                            → 질문만(뒤 설명 없음)
// JSX 메시지(ReviewForm 익명확인 = 질문 + <span class=modal-note>)는 이미 이 구조라 그대로 통과.
function renderMessage(message) {
  if (typeof message !== 'string') return message
  const m = message.match(/^(.*?\?)\s*([\s\S]+)$/)
  if (m) return <>{m[1]}<span className="modal-note">{m[2]}</span></>
  return message
}

// 폭을 메시지 길이로 자동 선택: 짧은 단문 질문은 좁게(xs 240), 설명이 붙어 길면 넓게(sm 280).
//   - 문자열: 끝 괄호(작은 별도 줄)를 빼고 본문 길이로 판정 → 삭제("이 리뷰를 삭제할까요?")는 짧게.
//   - JSX 메시지도 텍스트만 뽑아 같은 기준으로 판정 → 익명 '수정'(짧음)=240 / '제출'(설명 김)=280.
const WIDE_AT = 24  // 본문 글자수(공백 포함) 이 값 초과면 sm(280), 이하면 xs(240)
function textLen(node) {
  if (node == null || typeof node === 'boolean') return 0
  if (typeof node === 'string' || typeof node === 'number') return [...String(node)].length
  if (Array.isArray(node)) return node.reduce((n, c) => n + textLen(c), 0)
  return node.props ? textLen(node.props.children) : 0
}
function pickSize(message) {
  const len = typeof message === 'string'
    ? [...message.replace(/\s*\([^)]*\)\s*$/, '')].length
    : textLen(message)
  return len > WIDE_AT ? 'sm' : 'xs'
}

export default function ConfirmModal({
  message,
  confirmText = '확인',
  cancelText = '취소',
  intent = 'primary',
  onConfirm,
  onCancel,
}) {
  return (
    <Modal
      open
      onOpenChange={(next) => { if (!next) onCancel() }}
      size={pickSize(message)}
      title={confirmText}
    >
      <p className="modal-text">{renderMessage(message)}</p>
      <div className="modal-actions">
        <button className="modal-btn modal-btn-cancel" onClick={onCancel}>{cancelText}</button>
        <button className={`modal-btn is-${intent}`} onClick={onConfirm}>{confirmText}</button>
      </div>
    </Modal>
  )
}
