import { useCallback, useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '../components/AuthContext'
import { useToast } from '../components/ToastContext'
import { PASS_DAYS, passPrice, passLabel, passDuration, isPassActive, nextExpiry } from '../lib/passes'
import { formatDateTime, parseServerDate } from '../lib/dates'
import { ANONYMOUS_REVIEW_POINTS, PUBLIC_REVIEW_POINTS } from '../lib/points'
import {
  fetchWallet,
  purchasePass,
  refundPass,
  activatePass,
} from '../data/exchangeQueries'
import ConfirmModal from '../components/ConfirmModal'
import AdModal from '../components/AdModal'
import NicknameChangeFlow from '../components/NicknameChangeFlow'
import { fetchAdRewardStatus } from '../data/adQueries'
import PageMeta from '../components/PageMeta'
import './ExchangeCenter.css'

const NICKNAME_CHANGE_PRICE = 20

// 열람권 카드 아이콘(클립보드+돋보기) · 적립행 진행 화살표 — 목업 SVG 그대로
const TICKET_ICON = (
  <svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
    <path d="M13 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h5" /><path d="M13 3l5 5" /><path d="M18 8v3" />
    <line x1="9" y1="8" x2="13.5" y2="8" /><line x1="9" y1="11.5" x2="11.5" y2="11.5" />
    <circle cx="16.5" cy="16.5" r="3" /><line x1="18.7" y1="18.7" x2="21" y2="21" />
  </svg>
)
const NICKNAME_CHANGE_ICON = (
  <svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
    <circle cx="9" cy="8" r="3" />
    <path d="M3.5 19c.5-3.6 2.4-5.4 5.5-5.4 1.4 0 2.6.4 3.5 1.1" />
    <path d="M14.3 17.9 19 13.2a1.4 1.4 0 0 1 2 2l-4.7 4.7-2.8.6.8-2.6Z" />
  </svg>
)
const GO_ARROW = (
  <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
    <path d="M9 6l6 6-6 6" />
  </svg>
)

function stockOf(passBalances, days) {
  return Number(passBalances?.[String(days)] ?? 0)
}

// 시/분 단위 권 도입으로 만료가 시각 단위 → 기한 표기는 항상 날짜+시각(HH:mm)
function expiryLabel(ts) {
  if (!ts) return '없음'
  if (!isPassActive(ts)) return '만료됨'
  return formatDateTime(ts)
}

// 구매 직후 모달용 만료 표기 — 일 단위 권은 'N월 N일', 시/분 단위 권은 'N월 N일 HH:mm'
function expiryMonthDayLabel(currentExpiry, days, minutes = 60) {
  const expiry = nextExpiry(parseServerDate(currentExpiry), days, new Date(), minutes)
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Seoul', month: 'numeric', day: 'numeric',
    hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
  }).formatToParts(expiry).reduce((result, part) => {
    result[part.type] = part.value
    return result
  }, {})
  const md = `${parts.month}월 ${parts.day}일`
  return days === 0 ? `${md} ${parts.hour}:${parts.minute}` : md
}

function errorText(e) {
  const message = e?.message ?? String(e)
  if (message.includes('INSUFFICIENT_POINTS')) return '포인트가 부족해요.'
  if (message.includes('NOT_AUTHENTICATED')) return '로그인 정보가 만료됐어요. 다시 로그인해주세요.'
  if (message.includes('NO_PROFILE')) return '프로필 정보를 찾지 못했어요.'
  if (message.includes('NO_PASS_STOCK')) return '보유한 열람권이 없어요.'
  return '처리 중 오류가 발생했어요: ' + message
}

// 스켈레톤 박스 — cold 로드 시 사이드바 값에만 사용(메인은 wallet 준비되면 표시)
const Sbox = ({ w = '100%', h = 16, mb = 0, br = 6 }) => (
  <div className="skeleton-box" style={{ width: w, height: h, marginBottom: mb, borderRadius: br }} />
)

export default function ExchangeCenter() {
  const navigate = useNavigate()
  const { user, mergeUser } = useAuth()
  const toast = useToast()
  // 지갑은 AuthContext(fetchMe)가 세션 하이드레이션 시 로드해둠 → 있으면 즉시 렌더(스켈레톤 생략), 없으면 null→스켈레톤
  const [wallet, setWallet] = useState(() => (
    user?.pass_balances != null
      ? {
          point_balance: user.point_balance,
          pass_balances: user.pass_balances,
          pass_expires_at: user.pass_expires_at,
          hour_pass_minutes: user.hour_pass_minutes,
        }
      : null
  ))
  // 최소 상품(0)의 지속시간 — 서버 _wallet()이 대학별 값을 준다. 없으면 60분(기본 정책).
  const hourPassMinutes = wallet?.hour_pass_minutes ?? 60
  const [error, setError] = useState(null)
  const [busy, setBusy] = useState(false)
  const [confirm, setConfirm] = useState(null) // { message, confirmText, cancelText, action, afterSuccess? }
  const [showAd, setShowAd] = useState(false)
  const [adRewardStatus, setAdRewardStatus] = useState(null)
  const [showNicknameChange, setShowNicknameChange] = useState(false)
  // React state가 반영되기 전 같은 틱에 확인 버튼을 두 번 눌러도 RPC는 한 번만 실행한다.
  const busyRef = useRef(false)
  // 초기 지갑 조회가 교환/환불 결과보다 늦게 도착해 최신 로컬 지갑을 덮지 못하게 한다.
  const walletLoadSeq = useRef(0)
  const adStatusLoadSeq = useRef(0)

  const loadWallet = useCallback(() => {
    if (!user) return
    const seq = ++walletLoadSeq.current
    fetchWallet()
      .then((w) => {
        if (seq !== walletLoadSeq.current) return
        setWallet(w)
        setError(null)
      })
      .catch((e) => {
        if (seq === walletLoadSeq.current) setError(e.message)
      })
  }, [user])

  const loadAdRewardStatus = useCallback(() => {
    if (!user) return
    const seq = ++adStatusLoadSeq.current
    fetchAdRewardStatus()
      .then((status) => {
        if (seq === adStatusLoadSeq.current) setAdRewardStatus(status)
      })
      .catch(() => {
        // 상태 조회 장애가 광고 기능 전체를 막지는 않게 하고, 시작 RPC의 서버 검증에 맡긴다.
        if (seq === adStatusLoadSeq.current) setAdRewardStatus({ available: true })
      })
  }, [user])

  useEffect(() => {
    if (!user) {
      ++walletLoadSeq.current
      ++adStatusLoadSeq.current
      navigate('/login', { replace: true })
      return
    }   // 인증 바운스는 replace — push면 뒤로가기가 가드로 되돌아와 핑퐁 트랩
    loadWallet()
    loadAdRewardStatus()
  }, [user, navigate, loadWallet, loadAdRewardStatus])

  // RPC 실행 → 지갑 갱신 + 전역(AuthContext) 동기화
  async function run(action, afterSuccess) {
    if (busyRef.current) return
    busyRef.current = true
    setBusy(true)
    try {
      const w = await action()
      // 이동처럼 지갑을 바꾸지 않는 작업은 undefined를 반환한다.
      if (w != null) {
        ++walletLoadSeq.current
        setWallet(w)
        mergeUser(w)
      }
      afterSuccess?.(w)
    } catch (e) {
      toast(errorText(e), 'error')
    } finally {
      busyRef.current = false
      setBusy(false)
    }
  }

  // 확인 모달을 띄우고, 확인 시 run(action) 실행
  function ask(message, confirmText, intent, action, { afterSuccess = null, cancelText = '취소' } = {}) {
    setConfirm({ message, confirmText, cancelText, intent, action, afterSuccess })
  }

  if (error) return (
    <div className="home-wrap" style={{ textAlign: 'center', padding: '60px 20px' }}>
      <div style={{ marginBottom: 16, color: 'var(--text)' }}>불러오지 못했어요: {error}</div>
      <button className="tk-btn tk-btn-buy" style={{ display: 'block', maxWidth: 160, margin: '0 auto' }} onClick={() => { setError(null); loadWallet() }}>다시 시도</button>
    </div>
  )
  return (
    <div>
      <PageMeta title="교환센터" />
      <div className="ex-wrap">
        {/* 사이드바: 포인트 · 재고 · 만료 */}
        <aside className="ex-side" aria-label="내 지갑">
          <div className="ex-stat-label">내 포인트</div>
          {wallet ? <div className="ex-points">{wallet.point_balance}<small>P</small></div> : <Sbox w={90} h={30} mb={2} />}
          <div className="ex-div" />
          <div className="ex-stock-grid">
            {PASS_DAYS.map((d) => (
              <div className="ex-stock-cell" key={d}>
                {/* 사이드바는 3열이라 짧은 라벨(최소상품권·7일권·30일권) — 카드 목록은 passLabel 유지 */}
                <div className="ex-stock-name">{passDuration(d, hourPassMinutes)}권</div>
                {wallet ? <div className="ex-stock-qty">{stockOf(wallet.pass_balances, d)}장</div> : <Sbox w={36} h={16} />}
              </div>
            ))}
          </div>
          <div className="ex-div" />
          <div className="ex-stat-label">열람 가능 기한</div>
          {wallet ? <div className="ex-expiry">{expiryLabel(wallet.pass_expires_at)}</div> : <Sbox w={72} h={16} />}
        </aside>

        {/* 메인: 열람권 교환 · 닉네임 변경 · 포인트 적립 — wallet 준비 후 표시 */}
        {wallet && (
        <main>
          <section className="ex-section" aria-labelledby="exchange-pass-title">
            <h2 id="exchange-pass-title" className="ex-section-title">열람권 교환</h2>
            <div className="tk-list">
              {PASS_DAYS.map((d) => {
                const stock = stockOf(wallet.pass_balances, d)
                return (
                  <div className="tk-card" key={d}>
                    <div className="tk-top">
                      <span className="tk-ic" aria-hidden="true">{TICKET_ICON}</span>
                      <div className="tk-info">
                        <div className="tk-name">{passLabel(d, hourPassMinutes)}</div>
                        <div className="tk-price">{passPrice(d)}P</div>
                      </div>
                    </div>
                    <div className="tk-foot">
                      <button className="tk-btn" disabled={busy || stock < 1} onClick={() => ask(`${passLabel(d, hourPassMinutes)}을 지금 사용할까요? 사용하면 지금부터 ${passDuration(d, hourPassMinutes)} 동안 열람할 수 있어요.`, '확인', 'primary', () => activatePass(d))}>사용하기</button>
                      <button
                        className="tk-btn tk-btn-buy"
                        disabled={busy || Number(wallet.point_balance ?? 0) < passPrice(d)}
                        onClick={() => ask(
                          `${passLabel(d, hourPassMinutes)}을 ${passPrice(d)}P로 교환할까요?`,
                          '확인',
                          'primary',
                          () => purchasePass(d),
                          {
                            afterSuccess: (purchasedWallet) => ask(
                              `방금 교환한 ${passLabel(d, hourPassMinutes)}을 바로 적용하시겠습니까? ${expiryMonthDayLabel(purchasedWallet.pass_expires_at, d, hourPassMinutes)}까지 리뷰를 열람할 수 있어요.`,
                              '확인',
                              'primary',
                              () => activatePass(d),
                              { cancelText: '나중에' },
                            ),
                          },
                        )}
                      >
                        교환하기
                      </button>
                    </div>
                    {stock >= 1 && (
                      <button className="tk-refund" disabled={busy} onClick={() => ask(`미사용 ${passLabel(d, hourPassMinutes)} 1장을 환불할까요? ${passPrice(d)}P가 환급돼요.`, '확인', 'primary', () => refundPass(d))}>
                        미사용 열람권 환불 (+{passPrice(d)}P)
                      </button>
                    )}
                  </div>
                )
              })}
            </div>
          </section>

          <section className="ex-section" aria-labelledby="exchange-nickname-title">
            <h2 id="exchange-nickname-title" className="ex-section-title">닉네임 변경</h2>
            <div className="tk-list">
              <div className="tk-card">
              <div className="tk-top">
                <span className="tk-ic tk-ic-nickname" aria-hidden="true">{NICKNAME_CHANGE_ICON}</span>
                <div className="tk-info">
                  <div className="tk-name">닉네임 변경</div>
                  <div className="tk-price">{NICKNAME_CHANGE_PRICE}P</div>
                </div>
              </div>
              <div className="tk-foot">
                <button
                  className="tk-btn tk-btn-buy"
                  disabled={busy || Number(wallet.point_balance ?? 0) < NICKNAME_CHANGE_PRICE}
                  aria-label="20포인트로 닉네임 변경하기"
                  onClick={() => setShowNicknameChange(true)}
                >
                  교환하기
                </button>
              </div>
              </div>
            </div>
          </section>

          <section className="ex-section" aria-labelledby="exchange-earn-title">
            <h2 id="exchange-earn-title" className="ex-section-title">포인트 적립하기</h2>
            <div className="ex-earn">
              <div className="ex-row" onClick={() => navigate('/search')}>
                <div className="ex-row-body">
                  <div className="ex-row-title">근장 리뷰 작성하기</div>
                  <div className="ex-row-sub">닉네임 기재 {PUBLIC_REVIEW_POINTS}P · 익명 {ANONYMOUS_REVIEW_POINTS}P — 내가 일했던 근로장학 후기를 남겨요</div>
                </div>
                <span className="ex-reward">+{PUBLIC_REVIEW_POINTS}P</span>
                <span className="ex-go" aria-hidden="true">{GO_ARROW}</span>
              </div>
              <div
                className="ex-row"
                role="button"
                tabIndex={0}
                onClick={() => {
                  if (adRewardStatus?.available) setShowAd(true)
                  else toast('오늘 볼 수 있는 광고가 없어요.', 'info')
                }}
                onKeyDown={(event) => {
                  if (event.key !== 'Enter' && event.key !== ' ') return
                  event.preventDefault()
                  if (adRewardStatus?.available) setShowAd(true)
                  else toast('오늘 볼 수 있는 광고가 없어요.', 'info')
                }}
              >
                <div className="ex-row-body">
                  <div className="ex-row-title">광고 시청하기</div>
                  <div className="ex-row-sub">광고 1편당 {adRewardStatus?.reward_points != null ? `${adRewardStatus.reward_points}P` : '—'} · 하루 최대 {adRewardStatus?.daily_cap ?? 1}회</div>
                </div>
                <span className="ex-reward">{adRewardStatus?.reward_points != null ? `+${adRewardStatus.reward_points}P` : '—'}</span>
                <span className="ex-go" aria-hidden="true">{GO_ARROW}</span>
              </div>
            </div>
          </section>
        </main>
        )}
      </div>

      {confirm && (
        <ConfirmModal
          message={confirm.message}
          confirmText={confirm.confirmText}
          cancelText={confirm.cancelText}
          intent={confirm.intent}
          onConfirm={() => { const { action, afterSuccess } = confirm; setConfirm(null); run(action, afterSuccess) }}
          onCancel={() => setConfirm(null)}
        />
      )}

      {showAd && (
        <AdModal
          onClose={() => setShowAd(false)}
          onUnavailable={(reason) => {
            setAdRewardStatus({ available: false, unavailable_reason: reason })
            toast('오늘 볼 수 있는 광고가 없어요.', 'info')
          }}
          onClaimed={(w) => {
            ++walletLoadSeq.current
            setWallet(w)
            mergeUser(w)
            loadAdRewardStatus()
          }}
        />
      )}

      {showNicknameChange && (
        <NicknameChangeFlow
          currentNickname={user?.nickname}
          onCancel={() => setShowNicknameChange(false)}
          onChanged={(updated) => {
            ++walletLoadSeq.current
            setWallet(updated)
            mergeUser(updated)
            setShowNicknameChange(false)
            toast('닉네임을 변경했어요.')
          }}
        />
      )}
    </div>
  )
}
