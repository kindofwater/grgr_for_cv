import Modal from './Modal'

export default function PrivacyConsentModal({ onClose }) {
  return (
    <Modal
      open
      onOpenChange={(next) => { if (!next) onClose() }}
      size="lg"
      title="개인정보 수집·이용 동의 (필수)"
      titleHidden={false}
      className="privacy-consent-modal"
    >
      <div className="privacy-consent-body">
        <p className="privacy-consent-lead">
          근로고래는 「개인정보 보호법」 제15조 제1항 제1호에 따라 회원 관리, 맞춤형 서비스 제공,
          서비스 개선 및 신규 서비스 개발을 위한 통계 활용을 위하여 아래와 같이 개인정보를
          수집·이용합니다.
        </p>

        <dl className="privacy-consent-list">
          <div>
            <dt>수집·이용 목적</dt>
            <dd>회원 관리, 맞춤형 서비스 제공, 서비스 개선 및 신규 서비스 개발을 위한 통계 활용</dd>
          </div>
          <div>
            <dt>수집 항목</dt>
            <dd>희망지역, 학교, 입학연도, 학위과정, 학년, 학적상태, 단과대학, 학과, 계열</dd>
          </div>
          <div>
            <dt>보유 및 이용기간</dt>
            <dd>회원 탈퇴 시까지</dd>
          </div>
          <div>
            <dt>동의 거부 권리 및 불이익</dt>
            <dd>
              이용자는 개인정보 수집·이용에 대한 동의를 거부할 권리가 있습니다. 다만, 위 개인정보는
              회원 관리 및 맞춤형 서비스 제공을 위한 필수 정보이므로 동의를 거부할 경우 회원가입 및
              서비스 이용이 제한됩니다.
            </dd>
          </div>
        </dl>
      </div>

      <div className="modal-actions">
        <button className="modal-btn is-primary" onClick={onClose}>확인</button>
      </div>
    </Modal>
  )
}
