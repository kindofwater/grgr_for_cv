import { useRef, useState } from 'react'
import { changeNickname, verifyCurrentPassword } from '../data/authQueries'
import { isInvalidCredentials, isRateLimited, nicknameError } from '../lib/authValidation'
import ConfirmModal from './ConfirmModal'
import Modal from './Modal'

function changeErrorText(error) {
  const message = error?.message ?? ''
  if (message.includes('NICKNAME_TAKEN')) return '이미 사용 중인 닉네임이에요.'
  if (message.includes('NICKNAME_UNCHANGED')) return '현재 닉네임과 같아요.'
  if (message.includes('NICKNAME_RESERVED')) return '쓸 수 없는 단어예요.'
  if (message.includes('NICKNAME_INVALID')) return '닉네임 규칙을 다시 확인해주세요.'
  if (message.includes('INSUFFICIENT_POINTS')) return '보유 포인트가 20P보다 적어요.'
  if (message.includes('NOT_AUTHENTICATED') || message.includes('NO_PROFILE')) {
    return '로그인 정보를 확인할 수 없어요. 다시 로그인해주세요.'
  }
  return '변경 중 오류가 발생했어요. 잠시 후 다시 시도해주세요.'
}

export default function NicknameChangeFlow({ currentNickname, onCancel, onChanged }) {
  const [step, setStep] = useState('confirm')
  const [password, setPassword] = useState('')
  const [passwordError, setPasswordError] = useState(null)
  const [nickname, setNickname] = useState(currentNickname ?? '')
  const [nicknameErrorText, setNicknameErrorText] = useState(null)
  const [busy, setBusy] = useState(false)
  const busyRef = useRef(false)

  function cancel() {
    if (!busyRef.current) onCancel()
  }

  async function verifyPassword(event) {
    event.preventDefault()
    if (busyRef.current) return
    if (!password) {
      setPasswordError('비밀번호를 입력해주세요.')
      return
    }

    busyRef.current = true
    setBusy(true)
    setPasswordError(null)
    try {
      await verifyCurrentPassword(password)
      setPassword('')
      setStep('nickname')
    } catch (error) {
      if (isInvalidCredentials(error)) setPasswordError('비밀번호가 올바르지 않습니다.')
      else if (isRateLimited(error)) setPasswordError('시도가 너무 많습니다. 잠시 후 다시 시도해주세요.')
      else setPasswordError('비밀번호 확인에 실패했어요. 다시 시도해주세요.')
    } finally {
      busyRef.current = false
      setBusy(false)
    }
  }

  async function submitNickname(event) {
    event.preventDefault()
    if (busyRef.current) return

    const value = nickname.trim()
    if (!value) {
      setNicknameErrorText('닉네임을 입력해주세요.')
      return
    }
    const validationError = nicknameError(value)
    if (validationError) {
      setNicknameErrorText(validationError)
      return
    }
    if (value === currentNickname) {
      setNicknameErrorText('현재 닉네임과 같아요.')
      return
    }

    busyRef.current = true
    setBusy(true)
    setNicknameErrorText(null)
    try {
      const updated = await changeNickname(value)
      onChanged(updated)
    } catch (error) {
      setNicknameErrorText(changeErrorText(error))
    } finally {
      busyRef.current = false
      setBusy(false)
    }
  }

  if (step === 'confirm') {
    return (
      <ConfirmModal
        message="20P를 사용해 닉네임을 변경하시겠습니까? 변경이 완료된 뒤에는 취소할 수 없습니다."
        confirmText="확인"
        intent="primary"
        onConfirm={() => setStep('password')}
        onCancel={cancel}
      />
    )
  }

  if (step === 'password') {
    return (
      <Modal
        open
        onOpenChange={(next) => { if (!next) cancel() }}
        dismissible={!busy}
        title="비밀번호 확인"
        titleHidden={false}
        size="sm"
        className="nickname-flow-password-modal"
      >
        <form className="nickname-flow-form" onSubmit={verifyPassword}>
          <p className="nickname-flow-description">본인 확인을 위해 현재 비밀번호를 입력해주세요.</p>
          <input
            className={`nickname-flow-input${passwordError ? ' has-error' : ''}`}
            type="password"
            value={password}
            onChange={(event) => { setPassword(event.target.value); setPasswordError(null) }}
            placeholder="비밀번호"
            autoComplete="current-password"
            autoFocus
            aria-label="현재 비밀번호"
            aria-invalid={!!passwordError}
            aria-describedby={passwordError ? 'nickname-password-error' : undefined}
            disabled={busy}
          />
          {passwordError && <div id="nickname-password-error" className="nickname-flow-error" role="alert">{passwordError}</div>}
          <div className="modal-actions">
            <button className="modal-btn modal-btn-cancel" type="button" onClick={cancel} disabled={busy}>취소</button>
            <button className="modal-btn is-primary" type="submit" disabled={busy} aria-busy={busy}>확인</button>
          </div>
        </form>
      </Modal>
    )
  }

  return (
    <Modal
      open
      onOpenChange={(next) => { if (!next) cancel() }}
      dismissible={!busy}
      title="닉네임 변경"
      titleHidden={false}
      size="md"
    >
      <form className="nickname-flow-form" onSubmit={submitNickname}>
        <p id="nickname-flow-hint" className="nickname-flow-description">
          한글, 영문, 숫자만 사용할 수 있어요.<br />
          2자 이상, 한글은 최대 8자, 영문과 숫자는 최대 16자예요.
        </p>
        <input
          className={`nickname-flow-input${nicknameErrorText ? ' has-error' : ''}`}
          value={nickname}
          onChange={(event) => { setNickname(event.target.value); setNicknameErrorText(null) }}
          onFocus={(event) => event.currentTarget.select()}
          placeholder="새 닉네임"
          autoComplete="nickname"
          autoFocus
          aria-label="새 닉네임"
          aria-invalid={!!nicknameErrorText}
          aria-describedby={`nickname-flow-hint${nicknameErrorText ? ' nickname-flow-error' : ''}`}
          disabled={busy}
        />
        {nicknameErrorText && <div id="nickname-flow-error" className="nickname-flow-error" role="alert">{nicknameErrorText}</div>}
        <div className="modal-actions">
          <button className="modal-btn modal-btn-cancel" type="button" onClick={cancel} disabled={busy}>취소</button>
          <button className="modal-btn is-primary" type="submit" disabled={busy} aria-busy={busy}>확인</button>
        </div>
      </form>
    </Modal>
  )
}
