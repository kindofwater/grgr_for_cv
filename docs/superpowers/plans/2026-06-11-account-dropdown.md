# 계정 드롭다운 (AccountMenu) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 상단 닉네임 pill 클릭 시 `/mypage`로 바로 가는 대신, 포인트·열람권·마이페이지 탭 바로가기·로그아웃을 담은 **계정 드롭다운**을 연다.

**Architecture:** 새 `AccountMenu` 컴포넌트(연결형 예외 — Navbar처럼 `useAuth`/`useNavigate` + `data` 직접 사용)가 pill+드롭다운을 자체 보유. 드롭다운 열 때 `fetchWallet` lazy 조회. Navbar는 `<AccountMenu />`만 렌더. MyPage는 `?tab=` 쿼리로 초기 탭 선택. **DB 변경 0**(기존 `fetchWallet`/`activatePass` 재사용).

**Tech Stack:** React 19 + react-router-dom 7, Supabase JS(기존 쿼리), Vite.

**Spec:** `docs/superpowers/specs/2026-06-11-account-dropdown-design.md`
**Branch:** `feat/account-dropdown` (이미 생성됨)

> 모든 커밋 메시지 끝에 한 줄: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
> 폴더 만지기 전 그 폴더 `README.md` 읽고, 파일 추가 시 "현재 파일" 표 갱신(CLAUDE.md §5).
> 명령은 `web/`에서 실행. 작업 디렉터리는 `c:\새 폴더`. git hygiene: 무관한 `.gitignore`(working tree) 스테이징 금지 — 각 태스크의 `git add` 경로만.

---

## File Structure

- Create: `web/src/components/AccountMenu.jsx` — pill + 드롭다운(상태·지갑조회·액션) 자체 보유
- Create: `web/src/components/AccountMenu.css` — 드롭다운 스타일(토큰만)
- Modify: `web/src/components/Navbar.jsx` — 비게스트 분기의 `user-pill` 버튼 → `<AccountMenu />`
- Modify: `web/src/pages/MyPage.jsx` — `?tab=`로 초기 탭 선택
- Modify: `web/src/components/README.md`, `web/src/pages/README.md` — 표 갱신

재사용: `ConfirmModal`(`./ConfirmModal`), `fetchWallet`·`activatePass`(`../data/exchangeQueries`), `PASS_DAYS`(`../lib/passes`), `formatDate`(`../lib/dates`), `useAuth`(`../auth/AuthContext`).

> UI 컴포넌트라 단위테스트는 없음(기존 `Skeleton*`·`Navbar`와 동일). 검증은 lint + build + 수동 QA.

---

## Task 1: AccountMenu 컴포넌트 + CSS

**Files:**
- Create: `web/src/components/AccountMenu.jsx`
- Create: `web/src/components/AccountMenu.css`
- Modify: `web/src/components/README.md`

- [ ] **Step 1: 컴포넌트 작성** — `web/src/components/AccountMenu.jsx`

```jsx
import { useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '../auth/AuthContext'
import { fetchWallet, activatePass } from '../data/exchangeQueries'
import { PASS_DAYS } from '../lib/passes'
import { formatDate } from '../lib/dates'
import ConfirmModal from './ConfirmModal'
import './AccountMenu.css'

// 닉네임 pill + 계정 드롭다운. Navbar에서 로그인 사용자에게 렌더.
// "연결형 예외"(Navbar처럼): useAuth/useNavigate + data 직접 사용.
export default function AccountMenu() {
  const navigate = useNavigate()
  const { user, login, logout } = useAuth()
  const [open, setOpen] = useState(false)
  const [wallet, setWallet] = useState(null)   // null = 미조회/로딩
  const [confirm, setConfirm] = useState(null) // { message, confirmText, action }
  const [busy, setBusy] = useState(false)
  const ref = useRef(null)

  // 바깥 클릭 / Esc 로 닫기 — open일 때만 document 리스너 부착(동기 setState 없음 → lint 안전)
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

  function loadWallet() {
    fetchWallet(user.id).then((w) => setWallet(w)).catch(() => { /* 실패 시 이전 값 유지 */ })
  }

  function toggle() {
    if (!user) { navigate('/login'); return }
    const next = !open
    setOpen(next)
    if (next) loadWallet()   // 열 때마다 최신 지갑(첫 열림엔 null→"…")
  }

  function goTab(tab) {
    setOpen(false)
    navigate(`/mypage?tab=${tab}`)
  }

  function useTicket(days) {
    setOpen(false)
    setConfirm({
      message: `${days}일 열람권을 지금 사용할까요? 사용하면 기존 만료에 ${days}일이 더해져요.`,
      confirmText: '사용',
      action: async () => {
        const w = await activatePass(user.id, days)
        setWallet(w)
        login({ ...user, ...w })
      },
    })
  }

  function askLogout() {
    setOpen(false)
    setConfirm({
      message: '로그아웃하시겠습니까?',
      confirmText: '로그아웃',
      action: async () => { logout(); navigate('/login') },
    })
  }

  async function runConfirm() {
    if (busy) return
    const action = confirm.action
    setConfirm(null)
    setBusy(true)
    try { await action() } catch (e) { alert(e.message) } finally { setBusy(false) }
  }

  const active = wallet?.pass_expires_at && new Date(wallet.pass_expires_at) > new Date()
  const stockDays = PASS_DAYS.filter((d) => Number(wallet?.pass_balances?.[String(d)] ?? 0) > 0)

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
            <div className="acct-row">
              <span>포인트</span>
              <strong>{wallet === null ? '…' : `${wallet.point_balance}P`}</strong>
            </div>
            {wallet !== null && (
              <div className="acct-pass">
                {active ? (
                  <span className="acct-pass-on">열람 가능 · {formatDate(wallet.pass_expires_at)}까지</span>
                ) : stockDays.length > 0 ? (
                  <div className="acct-pass-btns">
                    {stockDays.map((d) => (
                      <button key={d} className="acct-use" disabled={busy} onClick={() => useTicket(d)}>{d}일권 사용</button>
                    ))}
                  </div>
                ) : (
                  <button className="acct-cta" onClick={() => { setOpen(false); navigate('/exchange') }}>열람권한 없음 · 교환센터</button>
                )}
              </div>
            )}
          </div>

          <div className="acct-div" />

          <button className="acct-item" onClick={() => goTab('reviews')}>내가 쓴 리뷰</button>
          <button className="acct-item" onClick={() => goTab('points')}>포인트 내역</button>
          <button className="acct-item" onClick={() => goTab('profile')}>프로필 수정</button>

          <div className="acct-div" />

          <button className="acct-item acct-logout" onClick={askLogout}>로그아웃</button>
        </div>
      )}

      {confirm && (
        <ConfirmModal
          message={confirm.message}
          confirmText={confirm.confirmText}
          onConfirm={runConfirm}
          onCancel={() => setConfirm(null)}
        />
      )}
    </div>
  )
}
```

- [ ] **Step 2: 스타일 작성** — `web/src/components/AccountMenu.css` (토큰만, hex 금지, `:root` 재정의 금지)

```css
/* 계정 드롭다운. pill 기본 스타일은 Navbar.css의 .user-pill 재사용(Navbar 안에서 렌더되므로 로드됨). */
.acct { position: relative; display: inline-flex; }

.user-pill.acct-open { filter: brightness(0.95); }

.acct-menu {
  position: absolute;
  top: calc(100% + 8px);
  right: 0;
  min-width: 220px;
  background: var(--card);
  border: 1px solid var(--border);
  border-radius: 12px;
  box-shadow: var(--shadow-md);
  padding: 8px;
  z-index: 1100;
  font-family: var(--sans);
}

.acct-wallet { padding: 8px 10px; }
.acct-row { display: flex; justify-content: space-between; align-items: center; font-size: 13px; color: var(--text-sub); }
.acct-row strong { color: var(--text); font-size: 14px; }
.acct-pass { margin-top: 8px; }
.acct-pass-on { font-size: 12px; color: var(--text-sub); }
.acct-pass-btns { display: flex; gap: 6px; flex-wrap: wrap; }
.acct-use, .acct-cta {
  font-size: 12px; padding: 6px 10px; border-radius: 6px; cursor: pointer; font-family: inherit;
  border: 1px solid var(--primary); background: var(--primary); color: white;
}
.acct-use:disabled { opacity: 0.5; cursor: default; }
.acct-cta { width: 100%; background: transparent; color: var(--primary-dark); }

.acct-div { height: 1px; background: var(--border); margin: 6px 0; }

.acct-item {
  display: block; width: 100%; text-align: left;
  padding: 9px 10px; border: none; background: none; border-radius: 8px;
  font-size: 14px; color: var(--text); cursor: pointer; font-family: inherit;
}
.acct-item:hover { background: var(--surface); }
.acct-logout { color: var(--danger); }
```

- [ ] **Step 3: components README 갱신** — `web/src/components/README.md` "현재 파일" 표에 1줄 추가(`Navbar.jsx` 행 위/아래 적당한 곳)

```markdown
| `AccountMenu.jsx` (+`.css`) | 닉네임 pill + 계정 드롭다운(포인트·열람권·마이페이지 탭·로그아웃). **연결형(예외)**: `useAuth`·`useNavigate` + `data`(`fetchWallet`/`activatePass`) 직접 사용. Navbar가 로그인 시 렌더 |
```

- [ ] **Step 4: lint** — Run: `cd web && npm run lint`
Expected: build 관련 에러 0. `AccountMenu.jsx`에서 `react-hooks/set-state-in-effect` 같은 새 에러가 나오면 STOP하고 보고(eslint-disable 추가 금지). 기존 2개 경고(Home/WorksiteDetail)만 허용.

- [ ] **Step 5: 커밋**

```bash
git add web/src/components/AccountMenu.jsx web/src/components/AccountMenu.css web/src/components/README.md
git commit -m "feat(account): AccountMenu 드롭다운 컴포넌트 추가 (아직 미연결)"
```

---

## Task 2: Navbar 연결

**Files:**
- Modify: `web/src/components/Navbar.jsx`

- [ ] **Step 1: import 추가** — `web/src/components/Navbar.jsx`

`import './Navbar.css'` 위 또는 아래(import 블록)에 추가:
```jsx
import AccountMenu from './AccountMenu'
```

- [ ] **Step 2: pill → AccountMenu 교체** — 같은 파일, `nav-right`의 비게스트(`:`) 분기

찾기:
```jsx
        ) : (
          <button className="user-pill" onClick={() => navigate('/mypage')}>
            <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
              <circle cx="12" cy="8" r="3.4"></circle>
              <path d="M5.5 19.5a6.6 6.6 0 0 1 13 0"></path>
            </svg>
            <span>{user?.nickname ?? '사용자'}님</span>
          </button>
        )}
```
바꾸기:
```jsx
        ) : (
          <AccountMenu />
        )}
```

> `user`는 위 `guest` 계산에 여전히 쓰이므로 import/구조분해 그대로 둔다(미사용 아님).

- [ ] **Step 3: lint + build** — Run: `cd web && npm run lint && npm run build`
Expected: 빌드 성공. 기존 2개 경고 외 새 에러/경고 없음(특히 `user`/`navigate` no-unused 경고가 새로 생기지 않는지 확인).

- [ ] **Step 4: 수동 확인** — `cd web && npm run dev` → 로그인 상태에서 우상단 닉네임 pill 클릭 → 드롭다운 열림(포인트·열람상태·메뉴·로그아웃), 바깥 클릭/Esc로 닫힘.

- [ ] **Step 5: 커밋**

```bash
git add web/src/components/Navbar.jsx
git commit -m "feat(account): Navbar 닉네임 pill을 AccountMenu로 교체"
```

---

## Task 3: MyPage `?tab=` 초기 탭

**Files:**
- Modify: `web/src/pages/MyPage.jsx`
- Modify: `web/src/pages/README.md`

- [ ] **Step 1: useSearchParams import** — `web/src/pages/MyPage.jsx`

찾기:
```jsx
import { useNavigate } from 'react-router-dom'
```
바꾸기:
```jsx
import { useNavigate, useSearchParams } from 'react-router-dom'
```

- [ ] **Step 2: 초기 탭을 쿼리에서** — 같은 파일

찾기:
```jsx
  const [tab, setTab] = useState('points') // 'points' | 'reviews'
```
바꾸기:
```jsx
  const [searchParams] = useSearchParams()
  const tabParam = searchParams.get('tab')
  const [tab, setTab] = useState(['points', 'reviews', 'profile'].includes(tabParam) ? tabParam : 'points') // 'points' | 'reviews' | 'profile'
```

> URL은 탭 클릭 시 안 바꿔도 됨(드롭다운 진입 시 초기 선택만이 목적). 기존 탭 클릭 동작은 그대로.

- [ ] **Step 3: pages README 갱신** — `web/src/pages/README.md`의 `MyPage.jsx` 행 비고 끝에 추가:
`· 계정 드롭다운에서 \`?tab=points|reviews|profile\`로 진입 시 해당 탭 선택`

- [ ] **Step 4: lint + build** — Run: `cd web && npm run lint && npm run build`
Expected: 빌드 성공, 새 에러 없음.

- [ ] **Step 5: 수동 확인** — 드롭다운에서 "내가 쓴 리뷰"/"포인트 내역"/"프로필 수정" 클릭 → `/mypage`로 가며 해당 탭이 열려 있는지 확인.

- [ ] **Step 6: 커밋**

```bash
git add web/src/pages/MyPage.jsx web/src/pages/README.md
git commit -m "feat(account): MyPage ?tab= 쿼리로 초기 탭 선택"
```

---

## Task 4: 전체 검증 (lint·빌드·테스트·수동 QA)

**Files:** 없음(검증만)

- [ ] **Step 1: 테스트·lint·빌드** — Run: `cd web && npm run test && npm run lint && npm run build`
Expected: 테스트 26 그린(변동 없음), lint 0 errors(기존 2 경고만), 빌드 성공.

- [ ] **Step 2: 수동 QA** — `cd web && npm run dev`:
  - pill 클릭 → 드롭다운. 포인트 표시, 열람상태가 (활성=기한 / 비활성+재고=종류별 사용버튼 / 재고0=교환센터 CTA) 중 맞게.
  - "내가 쓴 리뷰/포인트 내역/프로필 수정" → `/mypage` 해당 탭.
  - "교환센터" CTA → `/exchange`. (열람권 있는 계정/없는 계정 각각 확인 가능하면)
  - "{d}일권 사용" → ConfirmModal → 사용 후 포인트/열람상태 갱신.
  - "로그아웃" → ConfirmModal → 로그인 화면.
  - 바깥 클릭/Esc로 닫힘. 모바일 폭(≤768px)에서도 pill 보이고 드롭다운 동작.

- [ ] **Step 3: (해당 시) 마무리 커밋** — QA 중 고친 게 있으면 커밋, 없으면 생략.

---

## Self-Review (작성자 점검)

- **Spec 커버리지:** §3 컴포넌트→T1, §4 Navbar연결→T2, §5 드롭다운/열람로직→T1, §6 MyPage `?tab=`→T3, §8 스타일→T1(css), §7 보안/접근성(Esc·바깥클릭·busy)→T1. 누락 없음. DB 변경/시드 없음(의도).
- **Placeholder:** 없음(전 코드 기재).
- **이름 일관성:** `fetchWallet`/`activatePass`/`PASS_DAYS`/`formatDate`/`ConfirmModal`(props `message`/`confirmText`/`onConfirm`/`onCancel`) — 실제 시그니처와 일치. 탭 키 `points`/`reviews`/`profile` = MyPage 탭과 일치. CSS 클래스 `acct*` = JSX와 일치.
- **lint 주의:** 바깥클릭 effect는 리스너 부착만(동기 setState 없음) → `set-state-in-effect` 미발생. `wallet`/`active`/`stockDays` 파생값은 렌더 중 계산(상태 아님).
