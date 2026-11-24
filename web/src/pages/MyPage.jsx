import { useCallback, useEffect, useRef, useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { useAuth } from '../components/AuthContext'
import { useToast } from '../components/ToastContext'
import { PASS_DAYS, isPassActive, passLabel } from '../lib/passes'
import { computeRunningBalance } from '../lib/points'
import { formatDateTime as fmtDateTime } from '../lib/dates'
import { fetchWallet } from '../data/exchangeQueries'
import { deleteReview } from '../data/worksiteQueries'
import { fetchPointHistory, fetchMyReviews } from '../data/mypageQueries'
import { updateProfile, deleteAccount, sendPasswordResetToCurrentUser, verifyCurrentPassword } from '../data/authQueries'
import { isInvalidCredentials, isRateLimited } from '../lib/authValidation'
import { REGIONS, DEGREE_PROGRAMS, ACADEMIC_STATUSES, GRADES, admissionYears, colleges, departments, PREFFEREDTRACK, univIndexFromEmail } from '../lib/profileOptions'
import ConfirmModal from '../components/ConfirmModal'
import Pagination from '../components/Pagination'
import Dropdown from '../components/Dropdown'
import WithdrawModal from '../components/WithdrawModal'
import PageMeta from '../components/PageMeta'
import './MyPage.css'

// 리뷰 항목 액션 아이콘 (수정=연필 / 삭제=휴지통). 색은 CSS(currentColor)로.
const EDIT_ICON = (
  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
    <path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7" />
    <path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z" />
  </svg>
)
const TRASH_ICON = (
  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
    <polyline points="3 6 5 6 21 6" /><path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6" />
    <path d="M10 11v6" /><path d="M14 11v6" /><path d="M9 6V4a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2" />
  </svg>
)

const REASON_LABELS = {
  review_write: '리뷰 작성',
  review_delete: '리뷰 삭제(롤백)',
  review_anon_switch: '리뷰 익명 여부 변경',
  review_policy_grant: '포인트 정책 개편 추가 지급',
  false_review_penalty: '거짓/허위 리뷰 작성',
  ad_view: '광고 시청',
  signup_bonus: '가입 축하금',
  pass_purchase: '열람권 교환',
  pass_refund: '열람권 환불',
  nickname_change_ticket_purchase: '닉네임 변경권 교환',
  nickname_change_ticket_refund: '닉네임 변경권 환불',
  nickname_change: '닉네임 변경',
}

function worksiteName(ws) {
  if (!ws) return ''
  return [ws.organization_name, ws.workplace_name].filter(Boolean).join(' - ')
}

function reasonText(row) {
  const label = REASON_LABELS[row.reason] ?? row.reason
  const name = worksiteName(row.review?.worksite)
  return name ? `${label} — ${name}` : label
}

// 시/분 단위 권 도입으로 만료가 시각 단위 → 날짜+시각(HH:mm)으로 표기
function fmtExpiry(ts) {
  if (!ts) return '없음'
  if (!isPassActive(ts)) return '만료됨'
  return fmtDateTime(ts).slice(2)
}

function stockOf(passBalances, days) {
  return Number(passBalances?.[String(days)] ?? 0)
}

function preview(text, n = 60) {
  const t = (text ?? '').trim()
  return t.length > n ? t.slice(0, n) + '...' : t
}

function errorText(e) {
  if (e.message?.includes('INSUFFICIENT_POINTS')) return '포인트가 부족해요. (광고 시청 등으로 충전 후 다시 시도)'
  if (e.message?.includes('NO_PASS_STOCK')) return '보유한 열람권이 없어요.'
  return '처리 중 오류가 발생했어요: ' + e.message
}

// ── 탭: 포인트 내역 ── (rows는 최신순, 각 행에 balance 포함) — 10개씩 페이지네이션
function PointHistoryTab({ rows }) {
  const [page, setPage] = useState(1)
  if (rows.length === 0) return <div className="my-empty">아직 포인트 내역이 없어요.</div>
  const PER_PAGE = 10
  const totalPages = Math.max(1, Math.ceil(rows.length / PER_PAGE))
  const safePage = Math.min(page, totalPages)
  const pageRows = rows.slice((safePage - 1) * PER_PAGE, safePage * PER_PAGE)
  return (
    <div className="my-sec">
      <h3>포인트 내역</h3>
      {pageRows.map((row, i) => {
        const description = reasonText(row)
        return (
          <div className="ph-item" key={`${safePage}-${i}`}>
            <div>
              <div className="ph-desc" title={description}>{description}</div>
              <div className="ph-date">{fmtDateTime(row.created_at)}</div>
            </div>
            <div className={`ph-amt ${row.amount >= 0 ? 'plus' : 'minus'}`}>
              {row.amount >= 0 ? `+${row.amount}P` : `${row.amount}P`}
            </div>
            <div className="ph-balance">{row.balance}P</div>
          </div>
        )
      })}
      {totalPages > 1 && <Pagination page={safePage} totalPages={totalPages} onPage={setPage} />}
    </div>
  )
}

// ── 탭: 프로필 수정 (거주지역·학적정보) + 회원 탈퇴 ──
// 초기값은 컨텍스트 user에서 바로 채움(verify_login이 region·소속학교까지 반환). 저장은 update_profile RPC.
// 소속학교는 읽기전용(수정은 college/department FK 정합성 때문에 추후 묶어서).
function ProfileTab({ user, onSaved }) {
  // 단과대/학과 목록의 대학 index — Signup과 동일하게 세션 이메일 @ 뒤 라벨(korea=0, snu=1)로 결정
  const { session } = useAuth()
  const uniIdx = univIndexFromEmail(session?.user?.email)
  const [form, setForm] = useState(() => ({
    region: user.region ?? REGIONS[0],
    admission_year: String(user.admission_year ?? new Date().getFullYear()),
    degree_program: user.degree_program ?? 'undergrad',
    academic_status: user.academic_status ?? 'enrolled',
    grade: String(user.grade ?? 1),
    college: user.college?.name ?? '',
    department: user.department?.name ?? '',
    // 계열 어휘 교체(2026-07-20) 이전에 가입한 값('인문사회계열' 등)은 현재 선택지에 없다.
    //   그대로 두면 드롭다운은 빈칸으로 보이는데 값은 truthy라 검증을 통과해 '빈칸인 채 저장'된다.
    //   → 모르는 값은 미선택으로 낮춰 다시 고르게 한다.
    track: PREFFEREDTRACK.includes(user.track) ? user.track : '',
  }))
  const [saving, setSaving] = useState(false)
  const toast = useToast()
  const navigate = useNavigate()
  const [withdrawOpen, setWithdrawOpen] = useState(false)
  // 진입 게이트 — 탭에 들어올 때마다(컴포넌트 마운트) 다시 잠긴다
  const [unlocked, setUnlocked] = useState(false)
  const [gatePw, setGatePw] = useState('')
  const [gateErr, setGateErr] = useState(null)
  const [gateBusy, setGateBusy] = useState(false)
  const [gateResetBusy, setGateResetBusy] = useState(false)
  const [gateResetErr, setGateResetErr] = useState(null)
  const [gateResetSent, setGateResetSent] = useState(false)
  const [gateResetCooldown, setGateResetCooldown] = useState(0)

  useEffect(() => {
    if (gateResetCooldown <= 0) return
    const timer = window.setTimeout(
      () => setGateResetCooldown((seconds) => Math.max(0, seconds - 1)),
      1000,
    )
    return () => window.clearTimeout(timer)
  }, [gateResetCooldown])

  // 본인 확인 — 세션 이메일 + 입력 비밀번호로 재인증(verifyCurrentPassword) 후 폼 공개
  async function handleUnlock(e) {
    e.preventDefault()
    if (gateBusy) return
    if (!gatePw) { setGateErr('비밀번호를 입력해주세요.'); return }
    setGateBusy(true); setGateErr(null)
    try {
      await verifyCurrentPassword(gatePw)
      setUnlocked(true)
      setGatePw('')
    } catch (err) {
      if (isInvalidCredentials(err)) setGateErr('비밀번호가 올바르지 않습니다.')
      else if (isRateLimited(err)) setGateErr('시도가 너무 많습니다. 잠시 후 다시 시도해주세요.')
      else setGateErr('확인 실패: ' + err.message)
    } finally {
      setGateBusy(false)
    }
  }

  async function handleGatePasswordReset() {
    if (gateBusy || gateResetBusy || gateResetCooldown > 0) return
    setGateResetBusy(true)
    setGateResetErr(null)
    try {
      await sendPasswordResetToCurrentUser()
      setGateResetSent(true)
      setGateResetCooldown(60)
      toast('비밀번호 재설정 이메일을 보냈어요.', 'info', 5000)
    } catch (err) {
      if (isRateLimited(err)) setGateResetCooldown(60)
      setGateResetErr(
        isRateLimited(err)
          ? '요청이 너무 잦아요. 잠시 후 다시 시도해주세요.'
          : '재설정 메일 발송에 실패했어요. 잠시 후 다시 시도해주세요.',
      )
    } finally {
      setGateResetBusy(false)
    }
  }

  async function handleWithdraw() {
    await deleteAccount()                    // 실패 시 throw → 모달이 에러 표시(모달 유지)
    navigate('/login', { replace: true })    // 성공: signOut 됨 → 로그인으로
  }

  function set(key, val) { setForm((f) => ({ ...f, [key]: val })) }

  async function save() {
    if (saving) return
    // 계단식 드롭다운 특성상 단과대 변경 직후 학과가 빈 값일 수 있음 — 서버 호출 전 차단
    if (!form.college || !form.department || !form.track) {
      toast('단과대학·학과·계열을 모두 선택해주세요.', 'error')
      return
    }
    setSaving(true)
    try {
      const updated = await updateProfile({
        region: form.region,
        admission_year: Number(form.admission_year),
        degree_program: form.degree_program,
        academic_status: form.academic_status,
        grade: Number(form.grade),
        college_name: form.college,
        department_name: form.department,
        track: form.track,
      })
      onSaved?.(updated)
      toast('저장됐어요.')
    } catch (e) {
      const m = e.message ?? ''
      toast(
        m.includes('NO_COLLEGE') || m.includes('NO_DEPARTMENT')
          ? '선택한 단과대학/학과가 서버 목록과 달라요. 새로고침 후 다시 시도해주세요.'
          : '저장 실패: ' + m,
        'error',
      )
    } finally {
      setSaving(false)
    }
  }

  const schoolText = user.university_name
    ? user.university_name + (user.university_campus ? ` (${user.university_campus})` : '')
    : '—'

  // 잠금 상태: 폼 대신 흰 박스 가운데 비밀번호 확인만 노출(회원 탈퇴 버튼 포함 전부 숨김)
  if (!unlocked) {
    return (
      <>
        <div className="my-sec pf-lock">
          <form className="pf-lock-inner" onSubmit={handleUnlock}>
            <h3 className="pf-lock-title">비밀번호 확인</h3>
            <p className="pf-lock-desc">개인정보 보호를 위해 비밀번호를 다시 입력해주세요.</p>
            <input
              className="pf-lock-input" type="password" placeholder="비밀번호"
              value={gatePw} onChange={(e) => { setGatePw(e.target.value); setGateErr(null) }}
              autoComplete="current-password" autoFocus aria-label="비밀번호 확인"
            />
            {gateErr && <div className="pf-lock-err">{gateErr}</div>}
            <button className="pf-lock-btn" type="submit" disabled={gateBusy || gateResetBusy} aria-busy={gateBusy}>확인</button>
            <button
              className="pf-pw-btn"
              type="button"
              onClick={handleGatePasswordReset}
              disabled={gateBusy || gateResetBusy || gateResetCooldown > 0}
              aria-busy={gateResetBusy}
            >
              {gateResetCooldown > 0
                ? `재설정 메일 다시 보내기 (${gateResetCooldown}초)`
                : gateResetSent
                  ? '재설정 메일 다시 보내기'
                  : '비밀번호 변경'}
            </button>
            {gateResetErr && <div className="pf-lock-err pf-reset-error">{gateResetErr}</div>}
            {gateResetSent && (
              <p className="pf-lock-reset-note" role="status">
                가입한 학교 이메일에서 재설정 링크를 확인해주세요.
              </p>
            )}
          </form>
        </div>
      </>
    )
  }

  return (
    <>
      <div className="my-sec">
        <h3>프로필 수정</h3>
        <div className="profile-form">
          {/* 소속학교(읽기전용) — 라벨+값 한 줄, 아래 구분선으로 편집영역과 분리 */}
          <div className="pf-readonly">
            <span className="pf-ro-label">소속 학교</span>
            <span className="pf-ro-val">{schoolText}</span>
          </div>
          {/* 편집 필드 — 2열 그리드, 각 셀 라벨 위 + 입력 아래 */}
          <div className="pf-grid">
            <div className="pf-field">
              <div className="pf-label">단과대학</div>
              {/* Signup과 동일한 계단식 — 단과대 변경 시 학과 초기화 */}
              <Dropdown size="sm" value={form.college} ariaLabel="단과대학"
                onChange={(v) => setForm((f) => ({ ...f, college: v, department: '' }))}
                options={[{ value: '', label: '선택' }, ...colleges[uniIdx].map((c) => ({ value: c, label: c }))]} />
            </div>
            <div className="pf-field">
              <div className="pf-label">학과</div>
              <Dropdown size="sm" value={form.department} ariaLabel="학과"
                onChange={(v) => set('department', v)}
                options={form.college
                  ? [{ value: '', label: '선택' }, ...(departments[uniIdx][colleges[uniIdx].indexOf(form.college)] ?? []).map((d) => ({ value: d, label: d }))]
                  : [{ value: '', label: '단과대학을 먼저 선택해주세요' }]}
                disabled={!form.college} />
            </div>
            <div className="pf-field">
              <div className="pf-label">계열</div>
              <Dropdown size="sm" value={form.track} ariaLabel="계열"
                onChange={(v) => set('track', v)}
                options={[{ value: '', label: '선택' }, ...PREFFEREDTRACK.map((t) => ({ value: t, label: t }))]} />
            </div>
            <div className="pf-field">
              <div className="pf-label">거주 지역</div>
              <Dropdown size="sm" value={form.region} ariaLabel="거주 지역"
                onChange={(v) => set('region', v)} options={REGIONS} />
            </div>
            <div className="pf-field">
              <div className="pf-label">입학연도</div>
              <Dropdown size="sm" value={String(form.admission_year)} ariaLabel="입학연도"
                onChange={(v) => set('admission_year', v)} options={admissionYears().map((y) => String(y))} />
            </div>
            <div className="pf-field">
              <div className="pf-label">학위과정</div>
              <Dropdown size="sm" value={form.degree_program} ariaLabel="학위과정"
                onChange={(v) => set('degree_program', v)} options={DEGREE_PROGRAMS.map(([v, l]) => ({ value: v, label: l }))} />
            </div>
            <div className="pf-field">
              <div className="pf-label">학년</div>
              <Dropdown size="sm" value={String(form.grade)} ariaLabel="학년"
                onChange={(v) => set('grade', v)} options={GRADES.map((g) => ({ value: String(g), label: `${g}학년` }))} />
            </div>
            <div className="pf-field">
              <div className="pf-label">학적상태</div>
              <Dropdown size="sm" value={form.academic_status} ariaLabel="학적상태"
                onChange={(v) => set('academic_status', v)} options={ACADEMIC_STATUSES.map(([v, l]) => ({ value: v, label: l }))} />
            </div>
          </div>
          <button className={`pf-save${saving ? ' is-saving' : ''}`} onClick={save} disabled={saving} aria-busy={saving}>저장</button>
        </div>
      </div>
      <button className="my-withdraw" onClick={() => setWithdrawOpen(true)}>회원 탈퇴</button>
      {withdrawOpen && (
        <WithdrawModal onCancel={() => setWithdrawOpen(false)} onConfirm={handleWithdraw} />
      )}
    </>
  )
}

// ── 탭: 내가 쓴 리뷰 ──
function MyReviewsTab({ reviews, busy, onDelete, onEdit, onFind }) {
  if (reviews.length === 0) {
    return (
      <div className="my-sec">
        <h3>내가 쓴 리뷰</h3>
        <div className="my-empty">
          아직 작성한 리뷰가 없어요.
          <div><button className="tk-btn tk-btn-buy" style={{ maxWidth: 160, margin: '14px auto 0' }} onClick={onFind}>근장 찾기</button></div>
        </div>
      </div>
    )
  }
  return (
    <div className="my-sec">
      <h3>내가 쓴 리뷰</h3>
      {reviews.map((r) => (
        <div className="rev-item" key={r.id}>
          <div>
            <div className="rev-place">
              {worksiteName(r.worksite)}
              {r.is_blinded && (
                <span style={{ display: 'inline-block', marginLeft: 6, fontSize: 11, fontWeight: 700, color: 'var(--text-muted)', background: 'var(--surface)', borderRadius: 6, padding: '1px 7px', verticalAlign: 'middle' }}>블라인드됨</span>
              )}
            </div>
            <div className="rev-meta">{r.work_year}년 {r.work_semester} · {fmtDateTime(r.created_at)} 작성</div>
            <div className="rev-preview">{preview(r.opinion || r.work_content)}</div>
          </div>
          <div className="rev-item-actions">
            <button className="rev-act rev-act-edit" title="수정" onClick={() => onEdit(r)}>{EDIT_ICON}</button>
            <button className="rev-act rev-act-del" title="삭제" disabled={busy} onClick={() => onDelete(r.id)}>{TRASH_ICON}</button>
          </div>
        </div>
      ))}
    </div>
  )
}

// 스켈레톤 박스(인라인) — 사이드바 지갑 값 로딩에만 사용(본문은 가변이라 스켈레톤 없이 로드 후 표시)
const Sbox = ({ w = '100%', h = 16, mb = 0, br = 6 }) => (
  <div className="skeleton-box" style={{ width: w, height: h, marginBottom: mb, borderRadius: br }} />
)

export default function MyPage() {
  const navigate = useNavigate()
  const { user, mergeUser, logout } = useAuth()
  const toast = useToast()
  // AuthContext(fetchMe)가 세션 시 로드한 지갑을 초기값으로 씀 → 사이드바는 즉시 렌더. 본문(내역/리뷰)만 따로 로딩.
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
  const [pointRows, setPointRows] = useState([]) // 최신순 + balance
  const [reviews, setReviews] = useState([])
  const [contentLoaded, setContentLoaded] = useState(false) // 본문(포인트내역·리뷰) 로드 완료 여부
  const [searchParams, setSearchParams] = useSearchParams()
  const tabParam = searchParams.get('tab')
  const tab = ['points', 'reviews', 'profile'].includes(tabParam) ? tabParam : 'points' // 'points' | 'reviews' | 'profile' — URL ?tab=에서 파생
  const [error, setError] = useState(null)
  const [busy, setBusy] = useState(false)
  const [confirm, setConfirm] = useState(null) // { message, confirmText, action }
  // 초기 병렬 조회가 리뷰 삭제 같은 더 최신 지갑 쓰기를 뒤늦게 덮지 못하게 한다.
  const walletLoadSeq = useRef(0)

  const loadAll = useCallback(() => {
    if (!user) return
    const seq = ++walletLoadSeq.current
    Promise.all([fetchWallet(), fetchPointHistory(), fetchMyReviews()])
      .then(([w, ph, rv]) => {
        if (seq !== walletLoadSeq.current) return
        setWallet(w)
        setPointRows(computeRunningBalance(ph).reverse()) // 누적계산(오래된순) 후 최신순 표시
        setReviews(rv)
        setContentLoaded(true)
        setError(null)
      })
      .catch((e) => {
        if (seq === walletLoadSeq.current) setError(e.message)
      })
  }, [user])

  useEffect(() => {
    if (!user) {
      ++walletLoadSeq.current
      navigate('/login', { replace: true })
      return
    }   // 인증 바운스는 replace — push면 뒤로가기가 가드로 되돌아와 핑퐁 트랩
    loadAll()
  }, [user, navigate, loadAll])

  function ask(message, confirmText, intent, action) {
    setConfirm({ message, confirmText, intent, action })
  }

  async function runAction(action) {
    if (busy) return
    setBusy(true)
    try {
      await action()
    } catch (e) {
      toast(errorText(e), 'error')
    } finally {
      setBusy(false)
    }
  }

  function removeReview(reviewId) {
    ask('이 리뷰를 삭제할까요? (적립한 포인트가 회수됩니다)', '확인', 'danger', async () => {
      await deleteReview(reviewId)
      setReviews((rs) => rs.filter((r) => r.id !== reviewId))
      // 삭제 성공 후 지갑·포인트내역 재동기화. 재조회가 실패하면 전체 재조회로 부분 정합 방지.
      try {
        const [w, ph] = await Promise.all([fetchWallet(), fetchPointHistory()])
        ++walletLoadSeq.current
        setWallet(w)
        setPointRows(computeRunningBalance(ph).reverse())
        mergeUser(w)
      } catch {
        loadAll()
      }
    })
  }

  if (error) return (
    <div className="home-wrap" style={{ textAlign: 'center', padding: '60px 20px' }}>
      <div style={{ marginBottom: 16, color: 'var(--text)' }}>불러오지 못했어요: {error}</div>
      <button className="tk-btn tk-btn-buy" style={{ display: 'block', maxWidth: 160, margin: '0 auto' }} onClick={() => { setError(null); loadAll() }}>다시 시도</button>
    </div>
  )
  return (
    <div>
      <PageMeta title="마이페이지" />
      <div className="my-wrap">
        <aside className="my-sidebar">
          <div className="my-profile">
            <div className="my-avatar">
              <svg viewBox="0 0 24 24" width="26" height="26" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
                <circle cx="12" cy="8" r="3.4"></circle><path d="M5.5 19.5a6.6 6.6 0 0 1 13 0"></path>
              </svg>
            </div>
            <div className="my-name">{user?.nickname ?? '사용자'}</div>
          </div>

          <div className="my-wallet">
            <div className="my-wallet-row my-expiry-row"><span>열람가능기한</span>{wallet ? <strong>{fmtExpiry(wallet.pass_expires_at)}</strong> : <Sbox w={72} h={15} />}</div>
            <div className="my-wallet-div" />
            <div className="my-wallet-row"><span>보유 포인트</span>{wallet ? <strong className="mw-pt">{wallet.point_balance}P</strong> : <Sbox w={44} h={15} />}</div>
            <div className="my-wallet-group-div" />
            {PASS_DAYS.map((d) => {
              const stock = wallet ? stockOf(wallet.pass_balances, d) : 0
              return (
                <div className="my-wallet-pass" key={d}>
                  <span className="mw-pass-name">{passLabel(d, wallet?.hour_pass_minutes ?? 60)}</span>
                  {wallet
                    ? <strong className="mw-pass-stock">{stock}장</strong>
                    : <Sbox w={28} h={15} />}
                </div>
              )
            })}
            <div className="my-wallet-div" />
          </div>

          <div className="my-menu">
            <a className={tab === 'points' ? 'on' : ''} onClick={() => setSearchParams({ tab: 'points' })}>포인트 내역</a>
            <a className={tab === 'reviews' ? 'on' : ''} onClick={() => setSearchParams({ tab: 'reviews' })}>내가 쓴 리뷰</a>
            <a className={tab === 'profile' ? 'on' : ''} onClick={() => setSearchParams({ tab: 'profile' })}>프로필 수정</a>
          </div>

          {/* scope:'local' — 이 브라우저만. 기본값 'global'은 다른 기기 세션까지 끊는다 */}
          <button className="my-logout" onClick={() => ask('로그아웃하시겠습니까?', '확인', 'neutral', () => { logout({ scope: 'local' }); navigate('/login') })}>로그아웃</button>
        </aside>

        <main>
          {tab === 'profile' ? (
            <ProfileTab
              user={user}
              onSaved={(updated) => mergeUser(updated)}
            />
          ) : !contentLoaded ? (
            null
          ) : tab === 'points' ? (
            <PointHistoryTab rows={pointRows} />
          ) : (
            <MyReviewsTab reviews={reviews} busy={busy} onDelete={removeReview} onEdit={(r) => navigate(`/worksite/${r.worksite_id}/review/${r.id}/edit`)} onFind={() => navigate('/search')} />
          )}
        </main>
      </div>

      {confirm && (
        <ConfirmModal
          message={confirm.message}
          confirmText={confirm.confirmText}
          intent={confirm.intent}
          onConfirm={() => { const a = confirm.action; setConfirm(null); runAction(a) }}
          onCancel={() => setConfirm(null)}
        />
      )}
    </div>
  )
}
