# 교환센터 (열람권 교환) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 포인트 ↔ 열람권 교환/사용/환불 + 광고 적립으로 근로고래의 핵심 가치 루프(리뷰→포인트→열람권→열람)를 완성한다.

**Architecture:** 포인트·열람권 변경은 Supabase RPC(SECURITY DEFINER, 원자 트랜잭션)로 처리하고, 프론트는 RPC가 돌려준 지갑으로 AuthContext를 갱신해 전역 상태(네비 포인트·상세 `hasPass`)를 일치시킨다. 화면은 mockup `screen-shop`/`screen-ad` 구조를 따른다.

**Tech Stack:** React + react-router-dom, Supabase JS, Vitest(순수 함수), Vite. 기존 패턴: `web/src/data/`(쿼리·RPC 래퍼), `web/src/lib/`(순수 함수+테스트), `web/src/pages/`(화면), `DB/`(SQL).

**Spec:** `docs/superpowers/specs/2026-06-08-exchange-center-design.md`

**Branch:** `feature/exchange-center` (이미 생성됨)

---

## File Structure

- Create: `web/src/lib/passes.js` — 가격·만료 순수 헬퍼
- Create: `web/src/lib/passes.test.js` — 위 테스트
- Create: `DB/2026-06-08_exchange.sql` — RPC 4종 (`purchase_pass`/`refund_pass`/`activate_pass`/`watch_ad_reward`) + `pass_price`
- Create: `web/src/data/exchangeQueries.js` — `fetchWallet` + RPC 래퍼 4종
- Create: `web/src/pages/ExchangeCenter.jsx` (+ `ExchangeCenter.css`) — 교환센터 화면
- Create: `web/src/pages/AdView.jsx` (+ `AdView.css`) — mock 광고 화면
- Modify: `web/src/App.jsx` — `/exchange`, `/ad` 라우트
- Modify: `web/src/pages/Home.jsx` — "교환센터" 링크 연결
- Modify: `web/src/pages/WorksiteDetail.jsx` — "교환센터" 링크 연결
- Modify: `docs/legacy/policy.md` — 환불 정책 한 줄 추가

테스트 인프라: 이 프로젝트는 `lib/`의 순수 함수만 vitest로 테스트한다(`scores.test.js`, `semesters.test.js`). 컴포넌트·데이터 계층·RPC는 기존 관례대로 단위테스트 없이 `npm run build` + 브라우저 + Supabase 수동 검증으로 확인한다.

---

## Task 1: 순수 헬퍼 `lib/passes.js` (TDD)

**Files:**
- Create: `web/src/lib/passes.js`
- Test: `web/src/lib/passes.test.js`

- [ ] **Step 1: 실패하는 테스트 작성**

`web/src/lib/passes.test.js`:
```js
import { describe, it, expect } from 'vitest'
import { passPrice, nextExpiry, PASS_DAYS } from './passes'

describe('passPrice', () => {
  it('7일=10P, 30일=20P', () => {
    expect(passPrice(7)).toBe(10)
    expect(passPrice(30)).toBe(20)
  })
  it('잘못된 일수는 INVALID_DAYS throw', () => {
    expect(() => passPrice(14)).toThrow('INVALID_DAYS')
  })
})

describe('PASS_DAYS', () => {
  it('지원 일수는 7, 30', () => {
    expect(PASS_DAYS).toEqual([7, 30])
  })
})

describe('nextExpiry (활성화 시 새 만료일 = max(now, 현재만료) + days)', () => {
  const NOW = new Date('2026-06-08T00:00:00')
  it('만료 없으면 now + days', () => {
    expect(nextExpiry(null, 7, NOW)).toEqual(new Date('2026-06-15T00:00:00'))
  })
  it('활성 중이면 현재만료 + days (연장)', () => {
    expect(nextExpiry(new Date('2026-06-20T00:00:00'), 30, NOW))
      .toEqual(new Date('2026-07-20T00:00:00'))
  })
  it('만료 지났으면 now 기준 + days', () => {
    expect(nextExpiry(new Date('2026-06-01T00:00:00'), 7, NOW))
      .toEqual(new Date('2026-06-15T00:00:00'))
  })
})
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd web && npx vitest run src/lib/passes.test.js`
Expected: FAIL — `Failed to resolve import "./passes"` (모듈 없음)

- [ ] **Step 3: 최소 구현**

`web/src/lib/passes.js`:
```js
// 열람권 가격·만료 계산 (순수 함수). 서버 RPC(DB/2026-06-08_exchange.sql)와 동일 규칙 유지.
export const PASS_DAYS = [7, 30]

export function passPrice(days) {
  if (days === 7) return 10
  if (days === 30) return 20
  throw new Error(`INVALID_DAYS: ${days}`)
}

// 활성화 시 새 만료일: max(now, 현재만료) + days일
export function nextExpiry(current, days, now = new Date()) {
  passPrice(days) // days 유효성 검증 (잘못되면 throw)
  const cur = current ? new Date(current) : null
  const base = cur && cur > now ? cur : now
  const result = new Date(base)
  result.setDate(result.getDate() + days)
  return result
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd web && npx vitest run src/lib/passes.test.js`
Expected: PASS (7 tests)

- [ ] **Step 5: 커밋**

```bash
git add web/src/lib/passes.js web/src/lib/passes.test.js
git commit -m "feat: 열람권 가격·만료 순수 헬퍼 lib/passes.js (TDD)"
```

---

## Task 2: 백엔드 RPC `DB/2026-06-08_exchange.sql`

**Files:**
- Create: `DB/2026-06-08_exchange.sql`

RPC는 자동 테스트 불가(DB 필요) → 파일 작성 후 Supabase에서 수동 실행·검증한다. 모든 함수는 갱신된 지갑을 **jsonb**로 반환한다(`{point_balance, pass_balances, pass_expires_at}`). 동시성·음수 방지를 위해 조건부 UPDATE(WHERE 잔액/재고 조건) 후 영향 행 0이면 예외.

- [ ] **Step 1: SQL 작성**

`DB/2026-06-08_exchange.sql`:
```sql
-- ══════════════════════════════════════════════════════════════════
-- 교환센터 RPC — 포인트 ↔ 열람권 원자 트랜잭션
-- 실행: Supabase SQL 에디터에 붙여넣고 Run (팀원 누구나 — CLAUDE.md §3:
--       만지기 전 공유 → 이 파일 DB/에 누적 → 디스코드에 실행 기록)
-- 가격: 7일=10P, 30일=20P / 광고 시청=+5P (제한 없음)
-- 반환: jsonb { point_balance, pass_balances, pass_expires_at }
-- ══════════════════════════════════════════════════════════════════

create or replace function pass_price(p_days int)
returns int language sql immutable as $$
  select case p_days when 7 then 10 when 30 then 20 else null end
$$;

create or replace function _wallet(p_user_id int)
returns jsonb language sql as $$
  select jsonb_build_object(
    'point_balance',  u.point_balance,
    'pass_balances',  coalesce(u.pass_balances, '{}'::jsonb),
    'pass_expires_at', u.pass_expires_at
  ) from users u where u.id = p_user_id
$$;

-- 1) 구매: 포인트 → 재고
create or replace function purchase_pass(p_user_id int, p_days int)
returns jsonb language plpgsql security definer as $$
declare v_price int := pass_price(p_days); v_rows int;
begin
  if v_price is null then raise exception 'INVALID_DAYS'; end if;
  update users u
     set point_balance = u.point_balance - v_price,
         pass_balances = jsonb_set(
           coalesce(u.pass_balances, '{}'::jsonb), array[p_days::text],
           to_jsonb(coalesce((u.pass_balances ->> p_days::text)::int, 0) + 1), true)
   where u.id = p_user_id and u.point_balance >= v_price;
  get diagnostics v_rows = row_count;
  if v_rows = 0 then raise exception 'INSUFFICIENT_POINTS'; end if;
  insert into points (user_id, amount, reason) values (p_user_id, -v_price, 'pass_purchase');
  return _wallet(p_user_id);
end $$;

-- 2) 환불: 미사용 재고 → 포인트 (전액)
create or replace function refund_pass(p_user_id int, p_days int)
returns jsonb language plpgsql security definer as $$
declare v_price int := pass_price(p_days); v_rows int;
begin
  if v_price is null then raise exception 'INVALID_DAYS'; end if;
  update users u
     set pass_balances = jsonb_set(
           coalesce(u.pass_balances, '{}'::jsonb), array[p_days::text],
           to_jsonb((u.pass_balances ->> p_days::text)::int - 1), true),
         point_balance = u.point_balance + v_price
   where u.id = p_user_id and coalesce((u.pass_balances ->> p_days::text)::int, 0) >= 1;
  get diagnostics v_rows = row_count;
  if v_rows = 0 then raise exception 'NO_PASS_STOCK'; end if;
  insert into points (user_id, amount, reason) values (p_user_id, v_price, 'pass_refund');
  return _wallet(p_user_id);
end $$;

-- 3) 사용: 재고 → 활성(만료 연장)
create or replace function activate_pass(p_user_id int, p_days int)
returns jsonb language plpgsql security definer as $$
declare v_rows int;
begin
  if pass_price(p_days) is null then raise exception 'INVALID_DAYS'; end if;
  update users u
     set pass_balances = jsonb_set(
           coalesce(u.pass_balances, '{}'::jsonb), array[p_days::text],
           to_jsonb((u.pass_balances ->> p_days::text)::int - 1), true),
         pass_expires_at = greatest(now()::timestamp, coalesce(u.pass_expires_at, now()::timestamp))
                           + (p_days || ' days')::interval
   where u.id = p_user_id and coalesce((u.pass_balances ->> p_days::text)::int, 0) >= 1;
  get diagnostics v_rows = row_count;
  if v_rows = 0 then raise exception 'NO_PASS_STOCK'; end if;
  return _wallet(p_user_id);
end $$;

-- 4) 광고 시청 적립 (+5P, 제한 없음)
create or replace function watch_ad_reward(p_user_id int)
returns jsonb language plpgsql security definer as $$
declare v_ad_id int;
begin
  insert into ad_views (user_id) values (p_user_id) returning id into v_ad_id;
  update users set point_balance = point_balance + 5 where id = p_user_id;
  insert into points (user_id, amount, reason, ad_view_id) values (p_user_id, 5, 'ad_view', v_ad_id);
  return _wallet(p_user_id);
end $$;

grant execute on function pass_price(int)        to anon, authenticated;
grant execute on function _wallet(int)           to anon, authenticated;
grant execute on function purchase_pass(int,int) to anon, authenticated;
grant execute on function refund_pass(int,int)   to anon, authenticated;
grant execute on function activate_pass(int,int) to anon, authenticated;
grant execute on function watch_ad_reward(int)   to anon, authenticated;

-- ── 수동 검증 (Supabase SQL 에디터, user id는 실제 값으로) ──
-- select * from verify_login('seed1@korea.ac.kr','1q2w3e4r');  -- user id 확인
-- select purchase_pass(1, 7);    -- 10P 차감, {"7":1}
-- select activate_pass(1, 7);    -- {"7":0}, pass_expires_at +7일
-- select purchase_pass(1, 30);   -- 20P 차감, {"30":1}
-- select refund_pass(1, 30);     -- 20P 환불, {"30":0}
-- select watch_ad_reward(1);     -- +5P
-- select purchase_pass(1, 7) ;   -- 잔액 부족 시 INSUFFICIENT_POINTS
```

- [ ] **Step 2: Supabase에서 실행**

Supabase 대시보드 → SQL 에디터에 `DB/2026-06-08_exchange.sql` 전체 붙여넣고 Run.
Expected: "Success. No rows returned" (함수 생성/권한 부여 완료)

- [ ] **Step 3: 수동 검증**

SQL 에디터에서 파일 하단 검증 쿼리를 한 줄씩 실행(테스트 유저 id 사용).
Expected: 각 호출이 `{"point_balance":..,"pass_balances":..,"pass_expires_at":..}` 반환, 잔액 부족 시 `INSUFFICIENT_POINTS` 에러.

- [ ] **Step 4: 디스코드 정보 탭에 실행 기록** (CLAUDE.md §3)

"YYYY-MM-DD `DB/2026-06-08_exchange.sql` 실행 — 교환센터 RPC 4종 추가" 기록.

- [ ] **Step 5: 커밋**

```bash
git add DB/2026-06-08_exchange.sql
git commit -m "feat(db): 교환센터 RPC (purchase/refund/activate/watch_ad)"
```

---

## Task 3: 데이터 계층 `data/exchangeQueries.js`

**Files:**
- Create: `web/src/data/exchangeQueries.js`

- [ ] **Step 1: 구현**

`web/src/data/exchangeQueries.js`:
```js
import { supabase } from '../supabase'

// 최신 지갑 — verify_login은 pass_balances를 안 주므로 별도 조회
export async function fetchWallet(userId) {
  const { data, error } = await supabase
    .from('users')
    .select('point_balance, pass_balances, pass_expires_at')
    .eq('id', userId).single()
  if (error) throw error
  return data
}

// 아래 4개는 갱신된 지갑 { point_balance, pass_balances, pass_expires_at } 반환
export async function purchasePass(userId, days) {
  const { data, error } = await supabase.rpc('purchase_pass', { p_user_id: userId, p_days: days })
  if (error) throw error
  return data
}

export async function refundPass(userId, days) {
  const { data, error } = await supabase.rpc('refund_pass', { p_user_id: userId, p_days: days })
  if (error) throw error
  return data
}

export async function activatePass(userId, days) {
  const { data, error } = await supabase.rpc('activate_pass', { p_user_id: userId, p_days: days })
  if (error) throw error
  return data
}

export async function watchAdReward(userId) {
  const { data, error } = await supabase.rpc('watch_ad_reward', { p_user_id: userId })
  if (error) throw error
  return data
}
```

- [ ] **Step 2: 빌드 확인**

Run: `cd web && npm run build`
Expected: 빌드 성공 (import 해소 확인)

- [ ] **Step 3: 커밋**

```bash
git add web/src/data/exchangeQueries.js
git commit -m "feat: 교환센터 데이터 계층 exchangeQueries.js"
```

---

## Task 4: 광고 화면 `pages/AdView.jsx` + `/ad` 라우트

**Files:**
- Create: `web/src/pages/AdView.jsx`, `web/src/pages/AdView.css`
- Modify: `web/src/App.jsx`

- [ ] **Step 1: AdView.css 작성**

`web/src/pages/AdView.css`:
```css
.ad-wrap { max-width: 600px; margin: 0 auto; padding: 40px 24px; text-align: center; }
.ad-lead { font-size: 14px; color: var(--text); margin-bottom: 20px; }
.ad-lead strong { color: var(--accent); }
.ad-box {
  background: var(--social-bg); border: 2px dashed var(--border);
  border-radius: 16px; padding: 60px 24px; margin-bottom: 28px;
}
.ad-box-label { font-size: 11px; font-weight: 700; letter-spacing: 1px; color: var(--text); margin-bottom: 16px; }
.ad-progress { margin-top: 20px; background: var(--border); border-radius: 4px; height: 6px; overflow: hidden; }
.ad-progress > div { height: 100%; background: var(--accent); border-radius: 4px; transition: width .1s linear; }
.ad-cta {
  width: 100%; background: var(--accent); color: #fff; border: none; border-radius: 12px;
  padding: 15px; font-size: 16px; font-weight: 700; cursor: pointer; font-family: inherit;
}
.ad-cta:disabled { opacity: .5; cursor: default; }
.ad-skip { margin-top: 12px; background: none; border: none; font-size: 13px; color: var(--text); cursor: pointer; font-family: inherit; }
```

- [ ] **Step 2: AdView.jsx 작성**

`web/src/pages/AdView.jsx`:
```jsx
import { useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '../auth/AuthContext'
import { watchAdReward } from '../data/exchangeQueries'
import './AdView.css'

const AD_SECONDS = 3 // mock 광고 길이

export default function AdView() {
  const navigate = useNavigate()
  const { user, login } = useAuth()
  const [progress, setProgress] = useState(0)
  const [done, setDone] = useState(false)
  const [claiming, setClaiming] = useState(false)
  const timer = useRef(null)

  useEffect(() => {
    if (!user) { navigate('/login'); return }
    const start = Date.now()
    timer.current = setInterval(() => {
      const ratio = Math.min(1, (Date.now() - start) / (AD_SECONDS * 1000))
      setProgress(ratio)
      if (ratio >= 1) { clearInterval(timer.current); setDone(true) }
    }, 100)
    return () => clearInterval(timer.current)
  }, [user, navigate])

  async function claim() {
    if (!done || claiming) return
    setClaiming(true)
    try {
      const wallet = await watchAdReward(user.id)
      login({ ...user, ...wallet }) // 전역 포인트 갱신
      navigate('/exchange')
    } catch (e) {
      setClaiming(false)
      alert('포인트 적립 중 오류가 발생했어요: ' + e.message)
    }
  }

  return (
    <div className="ad-wrap">
      <div className="ad-lead">광고를 끝까지 시청하면 <strong>+5P</strong>가 지급됩니다.</div>
      <div className="ad-box">
        <div className="ad-box-label">ADVERTISEMENT</div>
        <div>{done ? '시청 완료!' : '광고 재생 중...'}</div>
        <div className="ad-progress"><div style={{ width: `${Math.round(progress * 100)}%` }} /></div>
      </div>
      <button className="ad-cta" disabled={!done || claiming} onClick={claim}>
        {done ? (claiming ? '적립 중...' : '시청 완료 — +5P 받기') : '광고 재생 중...'}
      </button>
      <button className="ad-skip" onClick={() => navigate('/exchange')}>건너뛰기 (포인트 미지급)</button>
    </div>
  )
}
```

- [ ] **Step 3: App.jsx에 `/ad` 라우트 추가**

`web/src/App.jsx` — import 추가 (ReviewForm import 아래):
```jsx
import ReviewForm from './pages/ReviewForm'
import AdView from './pages/AdView'
```
라우트 추가 (`/worksite/:id/review` 줄 아래):
```jsx
          <Route path="/worksite/:id/review" element={<ReviewForm />} />
          <Route path="/ad" element={<AdView />} />
```

- [ ] **Step 4: 빌드 확인**

Run: `cd web && npm run build`
Expected: 빌드 성공

- [ ] **Step 5: 커밋**

```bash
git add web/src/pages/AdView.jsx web/src/pages/AdView.css web/src/App.jsx
git commit -m "feat: mock 광고 화면 AdView + /ad 라우트 (+5P 적립)"
```

---

## Task 5: 교환센터 `pages/ExchangeCenter.jsx` + `/exchange` 라우트

**Files:**
- Create: `web/src/pages/ExchangeCenter.jsx`, `web/src/pages/ExchangeCenter.css`
- Modify: `web/src/App.jsx`

`.navbar`/`.nav-*`/`.user-pill` 클래스는 Home.css에 정의돼 전역 번들에 포함되므로 재사용한다. 교환센터 전용 클래스만 ExchangeCenter.css에 작성한다.

- [ ] **Step 1: ExchangeCenter.css 작성**

`web/src/pages/ExchangeCenter.css`:
```css
.ex-wrap { max-width: 980px; margin: 0 auto; padding: 28px 24px; display: grid; grid-template-columns: 240px 1fr; gap: 24px; }
@media (max-width: 768px) { .ex-wrap { grid-template-columns: 1fr; } }

.ex-side { border: 1px solid var(--border); border-radius: 14px; padding: 18px; height: fit-content; }
.ex-stat-label { font-size: 12px; color: var(--text); }
.ex-points { font-size: 34px; font-weight: 800; color: var(--accent); line-height: 1; margin-top: 4px; }
.ex-points small { font-size: 20px; }
.ex-div { border-top: 1px solid var(--border); margin: 14px 0; }
.ex-stock-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }
.ex-stock-cell { text-align: center; }
.ex-stock-name { font-size: 12px; color: var(--text); }
.ex-stock-qty { font-size: 18px; font-weight: 700; color: var(--text-h); margin-top: 2px; }
.ex-expiry { font-size: 15px; font-weight: 600; color: var(--text-h); margin-top: 5px; }

.ex-section-title { font-size: 17px; font-weight: 700; color: var(--text-h); margin: 0 0 14px; }
.tk-list { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; margin-bottom: 28px; }
@media (max-width: 560px) { .tk-list { grid-template-columns: 1fr; } }
.tk-card { border: 1px solid var(--border); border-radius: 14px; padding: 16px; }
.tk-name { font-size: 15px; font-weight: 700; color: var(--text-h); }
.tk-price { font-size: 20px; font-weight: 800; color: var(--accent); margin-top: 2px; }
.tk-foot { display: flex; gap: 8px; margin-top: 14px; }
.tk-btn { flex: 1; border-radius: 9px; padding: 9px; font-size: 14px; font-weight: 600; cursor: pointer; font-family: inherit; border: 1px solid var(--border); background: var(--bg); color: var(--text-h); }
.tk-btn-buy { background: var(--accent); color: #fff; border-color: var(--accent); }
.tk-btn:disabled { opacity: .45; cursor: default; }
.tk-refund { margin-top: 8px; font-size: 12px; color: var(--text); background: none; border: none; cursor: pointer; font-family: inherit; text-decoration: underline; }
.tk-refund:disabled { opacity: .4; cursor: default; text-decoration: none; }

.ex-earn { border: 1px solid var(--border); border-radius: 14px; overflow: hidden; }
.ex-row { display: flex; align-items: center; gap: 12px; padding: 16px; cursor: pointer; }
.ex-row + .ex-row { border-top: 1px solid var(--border); }
.ex-row:hover { background: var(--social-bg); }
.ex-row-body { flex: 1; }
.ex-row-title { font-size: 15px; font-weight: 600; color: var(--text-h); }
.ex-row-sub { font-size: 12px; color: var(--text); margin-top: 2px; }
.ex-reward { font-size: 15px; font-weight: 800; color: var(--good); }
```

- [ ] **Step 2: ExchangeCenter.jsx 작성**

`web/src/pages/ExchangeCenter.jsx`:
```jsx
import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '../auth/AuthContext'
import { PASS_DAYS, passPrice } from '../lib/passes'
import { fetchWallet, purchasePass, refundPass, activatePass } from '../data/exchangeQueries'
import './ExchangeCenter.css'

function stockOf(passBalances, days) {
  return Number(passBalances?.[String(days)] ?? 0)
}

function formatDate(ts) {
  if (!ts) return '없음'
  const d = new Date(ts)
  if (d <= new Date()) return '만료됨'
  return `${d.getFullYear()}.${String(d.getMonth() + 1).padStart(2, '0')}.${String(d.getDate()).padStart(2, '0')} 까지`
}

function errorText(e) {
  if (e.message?.includes('INSUFFICIENT_POINTS')) return '포인트가 부족해요.'
  if (e.message?.includes('NO_PASS_STOCK')) return '보유한 열람권이 없어요.'
  return '처리 중 오류가 발생했어요: ' + e.message
}

export default function ExchangeCenter() {
  const navigate = useNavigate()
  const { user, login } = useAuth()
  const [wallet, setWallet] = useState(null)
  const [error, setError] = useState(null)
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    if (!user) { navigate('/login'); return }
    let alive = true
    fetchWallet(user.id)
      .then((w) => { if (alive) setWallet(w) })
      .catch((e) => { if (alive) setError(e.message) })
    return () => { alive = false }
  }, [user, navigate])

  // RPC 실행 → 지갑 갱신 + 전역(AuthContext) 동기화
  async function run(action) {
    if (busy) return
    setBusy(true)
    try {
      const w = await action()
      setWallet(w)
      login({ ...user, ...w })
    } catch (e) {
      alert(errorText(e))
    } finally {
      setBusy(false)
    }
  }

  if (error) return <div className="home-wrap">에러: {error}</div>
  if (!wallet) return <div className="home-wrap">불러오는 중...</div>

  return (
    <div>
      <nav className="navbar">
        <div className="nav-logo" onClick={() => navigate('/home')} style={{ cursor: 'pointer' }}>근로고래</div>
        <div className="nav-links">
          <a style={{ cursor: 'pointer' }} onClick={() => navigate('/home')}>근장찾기</a>
          <a style={{ cursor: 'pointer' }} onClick={() => navigate('/exchange')}>교환센터</a>
          <a style={{ cursor: 'pointer' }}>공지사항</a>
        </div>
        <div className="nav-right">
          <span style={{ fontSize: 13, marginRight: 10, color: 'var(--text)' }}>내 포인트 <b style={{ color: 'var(--accent)' }}>{wallet.point_balance}P</b></span>
          <button className="user-pill">
            <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
              <circle cx="12" cy="8" r="3.4"></circle><path d="M5.5 19.5a6.6 6.6 0 0 1 13 0"></path>
            </svg>
            <span>{user?.nickname ?? '사용자'}님</span>
          </button>
        </div>
      </nav>

      <div className="ex-wrap">
        {/* 사이드바: 포인트 · 재고 · 만료 */}
        <aside className="ex-side">
          <div className="ex-stat-label">내 포인트</div>
          <div className="ex-points">{wallet.point_balance}<small>P</small></div>
          <div className="ex-div" />
          <div className="ex-stock-grid">
            {PASS_DAYS.map((d) => (
              <div className="ex-stock-cell" key={d}>
                <div className="ex-stock-name">{d}일 열람권</div>
                <div className="ex-stock-qty">{stockOf(wallet.pass_balances, d)}장</div>
              </div>
            ))}
          </div>
          <div className="ex-div" />
          <div className="ex-stat-label">열람 가능 기한</div>
          <div className="ex-expiry">{formatDate(wallet.pass_expires_at)}</div>
        </aside>

        {/* 메인: 열람권 카드 + 적립 */}
        <main>
          <div className="ex-section-title">열람권</div>
          <div className="tk-list">
            {PASS_DAYS.map((d) => {
              const stock = stockOf(wallet.pass_balances, d)
              return (
                <div className="tk-card" key={d}>
                  <div className="tk-name">{d}일 열람권</div>
                  <div className="tk-price">{passPrice(d)}P</div>
                  <div className="tk-foot">
                    <button className="tk-btn" disabled={busy || stock < 1} onClick={() => run(() => activatePass(user.id, d))}>사용하기</button>
                    <button className="tk-btn tk-btn-buy" disabled={busy} onClick={() => run(() => purchasePass(user.id, d))}>교환하기</button>
                  </div>
                  <button className="tk-refund" disabled={busy || stock < 1} onClick={() => run(() => refundPass(user.id, d))}>
                    미사용 열람권 환불 (+{passPrice(d)}P)
                  </button>
                </div>
              )
            })}
          </div>

          <div className="ex-section-title">포인트 적립하기</div>
          <div className="ex-earn">
            <div className="ex-row" onClick={() => navigate('/home')}>
              <div className="ex-row-body">
                <div className="ex-row-title">근장 리뷰 작성하기</div>
                <div className="ex-row-sub">내가 일했던 근로장학 후기를 남기면 포인트가 쌓여요</div>
              </div>
              <span className="ex-reward">+15P</span>
            </div>
            <div className="ex-row" onClick={() => navigate('/ad')}>
              <div className="ex-row-body">
                <div className="ex-row-title">광고 시청하기</div>
                <div className="ex-row-sub">짧은 광고 1편을 끝까지 보면 포인트가 쌓여요</div>
              </div>
              <span className="ex-reward">+5P</span>
            </div>
          </div>
        </main>
      </div>
    </div>
  )
}
```

- [ ] **Step 3: App.jsx에 `/exchange` 라우트 추가**

`web/src/App.jsx` — import 추가 (AdView import 아래):
```jsx
import AdView from './pages/AdView'
import ExchangeCenter from './pages/ExchangeCenter'
```
라우트 추가 (`/ad` 줄 아래):
```jsx
          <Route path="/ad" element={<AdView />} />
          <Route path="/exchange" element={<ExchangeCenter />} />
```

- [ ] **Step 4: 빌드 + 린트 확인**

Run: `cd web && npm run build && npm run lint`
Expected: 빌드 성공, 린트 에러 0 (기존 경고 2개만)

- [ ] **Step 5: 커밋**

```bash
git add web/src/pages/ExchangeCenter.jsx web/src/pages/ExchangeCenter.css web/src/App.jsx
git commit -m "feat: 교환센터 ExchangeCenter + /exchange 라우트 (교환/사용/환불)"
```

---

## Task 6: 네비 "교환센터" 링크 연결

**Files:**
- Modify: `web/src/pages/Home.jsx`
- Modify: `web/src/pages/WorksiteDetail.jsx`

- [ ] **Step 1: Home.jsx 교환센터 링크 연결**

`web/src/pages/Home.jsx` — 기존:
```jsx
          <a onClick={!isLoggedIn ? onLockedClick : undefined}>교환센터</a>
```
변경:
```jsx
          <a style={{ cursor: 'pointer' }} onClick={!isLoggedIn ? onLockedClick : () => navigate('/exchange')}>교환센터</a>
```

- [ ] **Step 2: WorksiteDetail.jsx 교환센터 링크 연결**

`web/src/pages/WorksiteDetail.jsx` — 기존:
```jsx
          <a style={{ cursor: 'pointer' }}>교환센터</a>
```
변경:
```jsx
          <a style={{ cursor: 'pointer' }} onClick={() => navigate('/exchange')}>교환센터</a>
```

- [ ] **Step 3: 빌드 확인**

Run: `cd web && npm run build`
Expected: 빌드 성공

- [ ] **Step 4: 커밋**

```bash
git add web/src/pages/Home.jsx web/src/pages/WorksiteDetail.jsx
git commit -m "feat: 네비 '교환센터' 링크 → /exchange 연결"
```

---

## Task 7: 환불 정책 문서화 + 최종 검증

**Files:**
- Modify: `docs/legacy/policy.md`

- [ ] **Step 1: policy.md 교환 섹션에 환불 정책 추가**

`docs/legacy/policy.md` — 기존 `### 교환 (열람권)` 표 바로 아래:
```markdown
| 교환 항목 | 필요 포인트 |
|------|--------|
| 7일 열람권 | 10포인트 |
| 30일 열람권 | 20포인트 |
```
표 다음 줄에 추가:
```markdown

### 환불 (열람권)
- **미사용 재고 열람권만** 환불 가능 → 교환에 쓴 포인트 전액 반환 (7일 10P / 30일 20P)
- 이미 사용(활성화)한 열람권은 환불 불가
```

- [ ] **Step 2: 전체 검증 (lint + build + test)**

Run: `cd web && npm run lint && npm run build && npm run test`
Expected: lint 에러 0(경고 2), build 성공, test 통과 (기존 14 + passes 7 = 21)

- [ ] **Step 3: 브라우저 수동 검증 (dev 서버)**

dev 서버에서 로그인 후:
1. 네비 "교환센터" 클릭 → `/exchange` 진입, 포인트·재고·만료 표시
2. "교환하기"(7일) → 포인트 −10, 7일 재고 +1, 네비 포인트 갱신
3. "사용하기"(7일) → 재고 −1, 열람 가능 기한 +7일
4. 근장 상세 진입 → 잠금 해제(`hasPass` 활성) 확인
5. "미사용 열람권 환불" → 포인트 복구, 재고 −1
6. "광고 시청하기" → `/ad` → 시청 완료 → +5P, `/exchange` 복귀
7. 포인트 부족 상태로 교환 → "포인트가 부족해요" alert

- [ ] **Step 4: 커밋**

```bash
git add docs/legacy/policy.md
git commit -m "docs: policy.md 열람권 환불 정책 명시"
```

---

## 완료 기준

- `npm run lint` 에러 0, `npm run build` 성공, `npm run test` 통과(21)
- 교환/사용/환불/광고 4동작이 브라우저에서 포인트·재고·만료·잠금에 정확히 반영
- 네비 "교환센터" 링크 동작, `hasPass`가 활성 열람권과 전역 일치
- `DB/2026-06-08_exchange.sql`이 Supabase에 실행되고 디스코드에 기록됨

검증 완료 후 `feature/exchange-center` → `main` 머지는 별도 확인 후 진행.
