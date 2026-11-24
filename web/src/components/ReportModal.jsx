import { useState } from 'react'
import Modal from './Modal'

const REASONS = ['허위/과장 후기', '욕설/비방', '광고/스팸', '개인정보 노출', '기타']

// 리뷰 신고 모달. 사유 하나 + 상세 내용(필수)을 적어 제출.
// (구버전은 인라인 style + 네이티브 라디오라 CSS를 고쳐도 혼자 안 따라왔다 → 전부 클래스로)
export default function ReportModal({ onSubmit, onCancel }) {
  const [reason, setReason] = useState(REASONS[0])
  const [opinion, setOpinion] = useState('')
  const [opinionErr, setOpinionErr] = useState(null)

  function submit() {
    if (!opinion.trim()) { setOpinionErr('내용을 입력해주세요'); return }
    onSubmit(reason, opinion.trim())
  }

  return (
    <Modal
      open
      onOpenChange={(next) => { if (!next) onCancel() }}
      size="md"
      title="신고 사유를 선택해주세요"
      titleHidden={false}
    >
      <div className="rp-list" role="radiogroup" aria-label="신고 사유">
        {REASONS.map((r) => (
          <label key={r} className={`rp-option${reason === r ? ' is-on' : ''}`}>
            <input
              type="radio"
              name="report-reason"
              className="rp-radio"
              checked={reason === r}
              onChange={() => setReason(r)}
            />
            <span>{r}</span>
          </label>
        ))}
      </div>

      <div className="rp-opinion">
        <label className="rp-opinion-label" htmlFor="report-opinion">
          내용(필수){opinionErr && <span className="rp-field-error">{opinionErr}</span>}
        </label>
        <textarea
          id="report-opinion"
          className="rp-textarea"
          maxLength="500"
          placeholder="신고 사유를 구체적으로 적어주세요."
          value={opinion}
          onChange={(e) => { setOpinion(e.target.value); if (opinionErr) setOpinionErr(null) }}
        />
      </div>

      <div className="modal-actions">
        <button className="modal-btn modal-btn-cancel" onClick={onCancel}>취소</button>
        <button className="modal-btn is-danger" onClick={submit}>신고</button>
      </div>
    </Modal>
  )
}
