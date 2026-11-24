import { useEffect, useRef, useState } from 'react'
import { useAuth } from './AuthContext'
import { useToast } from './ToastContext'
import { startAdView, claimAdReward, logAdClick, adMediaUrl } from '../data/adQueries'
import Modal from './Modal'
import './AdModal.css'

const RING_R = 19
const RING = 2 * Math.PI * RING_R // 카운트다운 링 둘레 (닫기 X를 둘러쌈)

// 리워드 광고 모달. 교환센터 '광고 시청하기'에서 띄움.
// 닫기는 X · '포인트 받기' 2가지로만 (배경 클릭/Esc로는 안 닫힘).
// 이미지(가게 보러가기)는 시작부터 클릭 가능 — 새 탭만 열고 모달은 유지(카운트다운 계속).
// props: onClose(), onClaimed(지갑) — 부모(ExchangeCenter)가 지갑·전역 머지.
export default function AdModal({ onClose, onClaimed, onUnavailable }) {
  const { user } = useAuth()
  const toast = useToast()
  const [status, setStatus] = useState('loading') // loading | ready | noads | error
  const [ad, setAd] = useState(null)
  const [token, setToken] = useState(null)
  const [deadline, setDeadline] = useState(null) // 미디어가 실제로 뜬 시점에 설정
  const [remaining, setRemaining] = useState(0)
  const [progress, setProgress] = useState(0) // 0..1 (카운트다운 링)
  const [claiming, setClaiming] = useState(false)
  const [errMsg, setErrMsg] = useState('')
  const claimed = useRef(false)
  const closed = useRef(false)
  const clickLogged = useRef(false)   // 클릭 로그는 시청(뷰)당 1회 — 반복 클릭으로 ad_clicks 부풀리기 방지
  const [warnOpen, setWarnOpen] = useState(false)   // #18: 5초 전 X → 리워드 상실 경고
  const pausedRemainingRef = useRef(0)              // 경고 중 카운트다운 일시정지용(남은 ms)

  // onClose를 ref로 들고 다닌다 — 아래 로드 effect가 '마운트당 1회'로 고정돼야 하는데
  // 부모가 넘기는 onClose는 매 렌더 새 함수라 deps에 넣으면 effect가 다시 돈다(아래 주석 참고).
  const onCloseRef = useRef(onClose)
  useEffect(() => { onCloseRef.current = onClose })
  const onUnavailableRef = useRef(onUnavailable)
  useEffect(() => { onUnavailableRef.current = onUnavailable })

  // 광고 로드 — 마운트당 정확히 1회.
  // ⚠️ deps에 user·onClose를 넣으면 안 된다(예전 버그): onClose는 부모 렌더마다 새 함수이고,
  //    user는 인증 하이드레이트마다 새 객체다. autoRefreshToken 때문에 탭이 포커스를 되찾으면
  //    (= 광고 링크가 연 새 탭에서 돌아오면) onAuthStateChange가 새 user를 만들고 → effect 재실행 →
  //    start_ad_view가 또 불려 ① order by random()이 '다른 광고'로 갈아치우고 ② 새 토큰의 서버
  //    created_at은 now()인데 화면의 deadline은 이미 만료라 '포인트 받기'가 TOO_SOON으로 터졌다.
  useEffect(() => {
    if (!user) { onCloseRef.current(); return }
    let active = true
    ;(async () => {
      try {
        const res = await startAdView()
        if (!active) return
        setAd(res.ad)
        setToken(res.token)
        setRemaining(res.ad.min_view_seconds)
        // 새 시청 = 새 카운트다운. (재실행 경로가 생기더라도 옛 deadline이 남아 '이미 만료' 상태로
        //  보이는 일이 없게 — 아래 setDeadline은 d ?? 로 멱등이라 여기서 비워줘야 다시 잡힌다)
        setDeadline(null)
        setProgress(0)
        // 미디어까지 미리 받아두고 준비되면 'ready' → '로딩 중' 화면 없이 광고가 바로 뜸
        if (res.ad.media_type === 'video') {
          setStatus('ready') // 비디오는 자체 버퍼링(onLoadedData가 카운트 시작)
        } else {
          const pre = new Image()
          // 사진은 디코드 완료 = 화면에 바로 보임 → 이 시점에 5초 카운트도 시작
          // (img onLoad의 startCountdown과 d ?? 로 멱등. effect에서 setState하면 lint 위반이라 콜백에서)
          const ready = () => {
            if (!active) return
            setStatus('ready')
            setDeadline((d) => d ?? (Date.now() + res.ad.min_view_seconds * 1000))
          }
          pre.onload = ready
          pre.onerror = ready // 깨져도 일단 띄우고 그 자리서 처리
          pre.src = adMediaUrl(res.ad.media_path)
        }
      } catch (e) {
        if (!active) return
        const m = e.message || ''
        if (m.includes('CAP_REACHED')) {
          onUnavailableRef.current?.('CAP_REACHED')
          onCloseRef.current()
        }
        else if (m.includes('NO_ADS')) setStatus('noads')
        else { setErrMsg(m); setStatus('error') }
      }
    })()
    return () => { active = false }
    // user는 '마운트 시점 1회'만 본다(모달은 로그인 상태에서만 열림) — 의도된 빈 deps
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  // 카운트다운 (deadline은 미디어 onLoad 시점에 설정 → 광고가 실제로 보인 뒤부터 5초)
  // 경고(warnOpen) 중엔 멈춤 — 남은 시간은 pausedRemainingRef에 저장, '계속 시청'이 deadline을 다시 밀어 재개
  useEffect(() => {
    if (!deadline || !ad || warnOpen) return
    const total = ad.min_view_seconds * 1000
    const id = setInterval(() => {
      const left = Math.max(0, deadline - Date.now())
      setRemaining(Math.ceil(left / 1000))
      setProgress(Math.min(1, (total - left) / total))
      if (left <= 0) clearInterval(id)
    }, 100)
    return () => clearInterval(id)
  }, [deadline, ad, warnOpen])

  const unlocked = status === 'ready' && deadline != null && remaining <= 0

  // 미디어가 화면에 뜬 뒤부터 5초 카운트 시작 (1회만 설정)
  function startCountdown() {
    setDeadline((d) => d ?? (Date.now() + ad.min_view_seconds * 1000))
  }

  function finish() {
    closed.current = true
    onClose()
  }

  // 시청 보상 적립 후 닫기. TOO_SOON(서버 5초 경계)이면 잠깐 뒤 1회 재시도.
  // ⚠️ 닫기를 '적립 성공'에 종속시키지 않는다. 적립이 계속 실패하는 상황(캡이 도중에 내려감,
  //    다른 탭이 캡을 먼저 소진, 세션 만료, 네트워크 단절)에서 X가 claim만 부르고 끝나면
  //    사용자가 모달에 갇힌다 — 실제로 그렇게 갇힌 사고가 있었다.
  // force=true(X로 부른 경우)면 적립 결과와 무관하게 닫는다.
  async function claim(force = false) {
    if (!unlocked || claiming || claimed.current) return
    setClaiming(true)
    try {
      let wallet
      try {
        wallet = await claimAdReward(token)
      } catch (e1) {
        if (!(e1.message || '').includes('TOO_SOON')) throw e1
        await new Promise((r) => setTimeout(r, 700))
        wallet = await claimAdReward(token)
      }
      claimed.current = true
      onClaimed?.(wallet)
      finish()
    } catch (e) {
      const m = e.message || ''
      // 더 시도해봤자 소용없는 상태 — 붙잡아두지 말고 닫는다.
      // INVALID_TOKEN: 이미 적립됐거나 토큰이 죽음 / CAP_REACHED: 오늘 몫 소진(적립 자체가 불가)
      if (m.includes('INVALID_TOKEN')) { claimed.current = true; finish(); return }
      if (m.includes('CAP_REACHED')) {
        claimed.current = true
        if (!closed.current) toast('오늘 광고 보상은 다 받으셨어요.', 'info')
        finish()
        return
      }
      setClaiming(false)
      if (!closed.current) toast('포인트 적립 중 오류가 발생했어요: ' + m, 'error')
      if (force) finish()   // X로 눌렀으면 적립 실패라도 나갈 수 있어야 한다
    }
  }

  // X: 5초 후엔 받고 나가기, 5초 전엔 리워드 상실 경고(+카운트다운 일시정지)
  function onX() {
    if (unlocked) {
      if (!claimed.current && !claiming) claim(true)   // 적립 실패해도 닫힘
      else finish()
      return
    }
    // 아직 5초 전 — 그냥 닫으면 포인트를 못 받으므로 경고를 띄우고 카운트다운을 멈춘다
    pausedRemainingRef.current = deadline ? Math.max(0, deadline - Date.now()) : (ad ? ad.min_view_seconds * 1000 : 0)
    setWarnOpen(true)
  }

  // 경고 '계속 시청' — 멈췄던 지점부터 재개(남은 ms만큼 deadline 다시 설정)
  function resumeWatching() {
    if (pausedRemainingRef.current > 0) setDeadline(Date.now() + pausedRemainingRef.current)
    setWarnOpen(false)
  }

  // 경고 '그냥 나가기' — 미지급 퇴장
  function leaveNow() {
    setWarnOpen(false)
    finish()
  }

  // 이미지(가게 보러가기): 새 탭으로만 열고 모달은 유지 — 적립은 '포인트 받기'/X가 담당.
  // 시작부터 클릭 가능(unlocked 불요). 카운트다운은 계속 흐르므로 다녀와서 받으면 됨.
  function onShop() {
    if (!ad?.target_url) return
    window.open(ad.target_url, '_blank', 'noopener,noreferrer')
    if (!clickLogged.current) {
      clickLogged.current = true
      logAdClick(ad.id).catch(() => {})
    }
  }

  // 광고·사진 준비 전(loading)에는 아무것도 띄우지 않음 → '로딩 중' 화면 없이 준비되면 바로 광고
  if (status === 'loading') return null

  let inner
  if (status !== 'ready') {
    const s = {
      noads:   { emoji: '🗂️', msg: '지금은 볼 수 있는 광고가 없어요.', back: true },
      error:   { emoji: '⚠️', msg: `광고를 불러오지 못했어요${errMsg ? ': ' + errMsg : ''}`, back: true },
    }[status]
    inner = (
      <div className="ad-state" role="status" aria-live="polite">
        <div className="ad-emoji">{s.emoji}</div>
        <div className="ad-msg">{s.msg}</div>
        {s.back && <button className="ad-back" onClick={finish}>닫기</button>}
      </div>
    )
  } else {
    const mediaUrl = adMediaUrl(ad.media_path)
    const canShop = !!ad.target_url   // 시작부터 노출 — unlocked 조건 제거(클릭해도 모달 유지라 어뷰징 여지 없음)
    inner = (
      <>
        <div
          className={`ad-player${canShop ? ' is-clickable' : ''}`}
          onClick={canShop ? onShop : undefined}
          onKeyDown={canShop ? (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); onShop() } } : undefined}
          role={canShop ? 'link' : 'img'}
          tabIndex={canShop ? 0 : undefined}
          aria-label={canShop ? `${ad.title} 보러가기` : ad.title}
        >
          {ad.media_type === 'video'
            ? <video className="ad-media" src={mediaUrl} autoPlay muted loop playsInline onLoadedData={startCountdown} aria-label={ad.title} />
            : <img className="ad-media is-photo" src={mediaUrl} alt={ad.title} onLoad={startCountdown} onError={startCountdown} />}

          {/* 우상단 닫기 X + (카운트다운 중) 둘레 링 */}
          <div className="ad-corner">
            {!unlocked && (
              <svg className="ad-ring" width="44" height="44" viewBox="0 0 44 44" aria-hidden="true">
                <circle className="ad-ring-track" cx="22" cy="22" r={RING_R} fill="none" strokeWidth="3" />
                <circle className="ad-ring-bar" cx="22" cy="22" r={RING_R} fill="none" strokeWidth="3"
                  strokeLinecap="round" strokeDasharray={RING} strokeDashoffset={RING * (1 - progress)} />
              </svg>
            )}
            <button
              className="ad-x"
              onClick={(e) => { e.stopPropagation(); onX() }}
              aria-label={unlocked ? '포인트 받고 닫기' : '닫기 (포인트 미지급)'}
            >✕</button>
          </div>

          {canShop && <span className="ad-shophint">{ad.title} 보러가기 ↗</span>}
        </div>

        <div className="ad-foot">
          <button
            className={`ad-claim${unlocked && !claiming ? ' is-ready' : ''}`}
            disabled={!unlocked || claiming}
            onClick={claim}
            aria-label={unlocked ? '포인트 받기' : `${remaining}초 시청 후 포인트 받기`}
            aria-busy={claiming}
          >
            {unlocked ? '포인트 받기 →' : '포인트 받기'}
          </button>
        </div>
      </>
    )
  }

  return (
    <>
      <Modal
        open
        // 닫기는 X · '포인트 받기' 2가지로만 (이미지 클릭은 새 탭만 열고 유지).
        // Esc·배경클릭으로 안 닫히는 건 리워드 어뷰징 방지 사양 — 버그가 아니다.
        dismissible={false}
        onOpenChange={() => {}}
        size="lg"
        title="리워드 광고"
        className="ad-modal"
      >
        {inner}
      </Modal>

      {/* 5초 전 X → 리워드 상실 경고. 광고 모달 위에 뜨는 중첩 Dialog.
          Portal 덕에 DOM 순서로 자연스럽게 위에 쌓이고, 같은 스크림이 두 겹 겹쳐 광고가 어두워진다.
          (구버전은 z-index 999 vs 1000 때문에 .ad-leavewarn 오버레이를 따로 만들어야 했다) */}
      {warnOpen && (
        <Modal
          open
          onOpenChange={(next) => { if (!next) resumeWatching() }}
          size="sm"
          title="나가기 확인"
        >
          <p className="modal-text">잠깐! 지금 나가면 포인트를 못 받아요</p>
          <div className="modal-actions">
            <button className="modal-btn modal-btn-cancel" onClick={leaveNow}>그냥 나가기</button>
            <button className="modal-btn is-primary" onClick={resumeWatching}>계속 시청</button>
          </div>
        </Modal>
      )}
    </>
  )
}
