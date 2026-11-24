# 유휴 로그아웃(Idle Logout) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 로그인(프로필 완료) 사용자가 30분간 무활동이면 자동 로그아웃하고 `/login`으로 보낸다.

**Architecture:** 만료 판정의 진실원천은 **벽시계**(`now - lastActive`, localStorage)다. 타이머는 판정 근거가 아니라 "확인하러 깨워주는" 수단(15초 폴링)일 뿐이며, 백그라운드에서 타이머가 멈추는 문제는 **복귀 이벤트**(`visibilitychange`·`focus`·`pageshow`·`storage`)에서 즉시 재평가해 흡수한다. `AuthContext`(현수 영역)의 **내부 로직은 수정하지 않고** 공개 API(`user`·`logout()`)만 소비한다(단, `logout`이 `opts`를 통과시키도록 한 줄 확장 — 현수 승인).

**Tech Stack:** React 19.2.6 · react-router-dom 7.16.0 · Vitest 4.1.8 (node env) · **새 의존성 없음**

**설계 문서:** `docs/superpowers/specs/2026-07-14-idle-logout-design.md`

## Global Constraints

- **타임아웃 = 30분** (`IDLE_TIMEOUT_MS = 30 * 60 * 1000`), **폴링 = 15초** (`POLL_INTERVAL_MS = 15 * 1000`), **시계 오차 허용 = 60초** (`SKEW_MS`)
- **새 npm 의존성을 추가하지 않는다.** (`react-idle-timer`는 검토 후 폐기 — 설계 §2)
- **경고 모달을 만들지 않는다.** 만료 시 조용히 로그아웃한다.
- **`web/src/components/AuthContext.jsx`의 내부 로직(경합 가드 `loadSeq`·`hydrate`·데드락 회피)을 수정하지 않는다.** 공개 API(`user`, `logout`)만 쓴다.
  - **유일한 예외(현수 승인 2026-07-14):** `logout`이 `opts`를 받아 `signOut(opts)`로 넘기도록 **한 줄** 확장한다(Task 3).
- **로그아웃은 `{ scope: 'local' }`(이 기기만)로 부른다** — 유휴 로그아웃 + 수동 로그아웃(AccountMenu·MyPage) 전부. 인자를 안 주면 auth-js 기본값이 `'global'`이라 **사용자의 다른 기기 세션까지 끊긴다.**
  - 예외로 그대로 두는 것: `authQueries.js`(탈퇴 — 계정 자체가 삭제돼 scope 무의미), `Signup.jsx`(유령 세션 — 현수 파일·영향 없음)
- **`web/src/pages/Login.jsx` / `Signup.jsx`를 수정하지 않는다.** (현수 영역 — 조율 전까지 접촉 금지)
- **`web/src/lib/`는 의존성 0·DOM 금지 계약을 지킨다** (`web/src/lib/README.md`). localStorage 접근을 lib에 넣지 않는다.
- 활성 게이트는 `session`이 아니라 **`user`** 다 (가입 미완료 세션 제외).
- 로그아웃 시 **`lastActive` 키를 삭제하지 않는다.**
- 테스트는 **node 환경**에서 돈다(`vitest run`). jsdom을 도입하지 않는다 — 모든 자동 테스트는 순수 함수 + 주입된 mock storage로 짠다.

## File Structure

| 파일 | 책임 |
|---|---|
| `web/src/lib/idle.js` (신규) | **순수 판정만.** 상수 + `parseLastActive` + `isExpired`. DOM·스토리지·시간 접근 없음(`now`를 인자로 받음) |
| `web/src/lib/idle.test.js` (신규) | 위 순수 함수 단위테스트 |
| `web/src/components/idleStorage.js` (신규) | `lastActive`의 localStorage I/O. **`storage`를 인자로 주입**받아 node에서 mock 테스트 가능. React·DOM 전역 참조 없음 |
| `web/src/components/idleStorage.test.js` (신규) | 위 I/O 테스트(정상 · 부재 · throw) |
| `web/src/components/AuthContext.jsx` (수정, **1줄**) | `logout`이 `opts`를 받아 `signOut(opts)`로 전달. 내부 로직은 손대지 않음 (현수 승인) |
| `web/src/components/AccountMenu.jsx` (수정, 1줄) | 계정 메뉴 로그아웃 → `logout({ scope: 'local' })` |
| `web/src/pages/MyPage.jsx` (수정, 1줄) | 마이페이지 로그아웃 → `logout({ scope: 'local' })` |
| `web/src/components/IdleLogout.jsx` (신규) | `return null` 마운트 전용. `useAuth()`의 `user`·`logout({ scope: 'local' })` 소비 + 폴링/복귀 이벤트 배선 |
| `web/src/App.jsx` (수정) | `<IdleLogout />` 마운트 (58~60행 사이) |
| `web/src/lib/README.md` (수정) | (d) 현재 파일 표에 `idle.js` 추가 |
| `web/src/components/README.md` (수정) | (d) 현재 파일 표에 `IdleLogout.jsx`·`idleStorage.js` 추가 |
| `docs/superpowers/specs/2026-07-10-account-withdrawal-design.md` (수정) | B-2의 유휴 로그아웃 **45분 → 30분** |

---

### Task 1: `lib/idle.js` — 순수 판정 로직

**Files:**
- Create: `web/src/lib/idle.js`
- Test: `web/src/lib/idle.test.js`

**Interfaces:**
- Consumes: 없음 (의존성 0)
- Produces:
  - `IDLE_TIMEOUT_MS: number` (= 1800000)
  - `POLL_INTERVAL_MS: number` (= 15000)
  - `SKEW_MS: number` (= 60000)
  - `parseLastActive(raw: string | null) => { uid: string, ts: number } | null | 'invalid'`
  - `isExpired(entry, uid: string, now: number, timeout?: number) => boolean`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

Create `web/src/lib/idle.test.js`:

```js
import { describe, it, expect } from 'vitest'
import { IDLE_TIMEOUT_MS, parseLastActive, isExpired } from './idle'

const UID = 'user-1'
const NOW = 1_800_000_000_000

describe('parseLastActive', () => {
  it('부재 → null', () => {
    expect(parseLastActive(null)).toBe(null)
    expect(parseLastActive('')).toBe(null)
  })

  it('JSON이 아니면 → invalid', () => {
    expect(parseLastActive('abc')).toBe('invalid')
  })

  it('필드 누락·형 불일치 → invalid', () => {
    expect(parseLastActive('{"uid":"user-1"}')).toBe('invalid')       // ts 없음
    expect(parseLastActive('{"ts":123}')).toBe('invalid')             // uid 없음
    expect(parseLastActive('{"uid":1,"ts":123}')).toBe('invalid')     // uid가 문자열 아님
    expect(parseLastActive('{"uid":"user-1","ts":"x"}')).toBe('invalid')
    expect(parseLastActive('null')).toBe('invalid')
  })

  it('정상 → { uid, ts }', () => {
    expect(parseLastActive('{"uid":"user-1","ts":123}')).toEqual({ uid: 'user-1', ts: 123 })
  })
})

describe('isExpired', () => {
  it('29분 59초 → false', () => {
    const entry = { uid: UID, ts: NOW - (IDLE_TIMEOUT_MS - 1000) }
    expect(isExpired(entry, UID, NOW)).toBe(false)
  })

  it('30분 정각 → false (초과해야 만료)', () => {
    const entry = { uid: UID, ts: NOW - IDLE_TIMEOUT_MS }
    expect(isExpired(entry, UID, NOW)).toBe(false)
  })

  it('30분 1초 → true', () => {
    const entry = { uid: UID, ts: NOW - (IDLE_TIMEOUT_MS + 1000) }
    expect(isExpired(entry, UID, NOW)).toBe(true)
  })

  it('부재(null) → false — 무장 시 시딩되므로 진짜 신규 세션뿐', () => {
    expect(isExpired(null, UID, NOW)).toBe(false)
  })

  it("가비지('invalid') → true (fail-closed)", () => {
    expect(isExpired('invalid', UID, NOW)).toBe(true)
  })

  it('미래 타임스탬프(skew 초과) → true — 시계 조작/오류 신뢰 불가', () => {
    const entry = { uid: UID, ts: NOW + 120_000 }
    expect(isExpired(entry, UID, NOW)).toBe(true)
  })

  it('미세한 미래(skew 이내) → false', () => {
    const entry = { uid: UID, ts: NOW + 10_000 }
    expect(isExpired(entry, UID, NOW)).toBe(false)
  })

  it('uid 불일치 → false (다른 계정 값은 무시 — 호출부가 재시딩)', () => {
    const entry = { uid: 'other-user', ts: NOW - 10 * 60 * 60 * 1000 }
    expect(isExpired(entry, UID, NOW)).toBe(false)
  })

  it('timeout 인자로 임계값을 주입할 수 있다', () => {
    const entry = { uid: UID, ts: NOW - 5000 }
    expect(isExpired(entry, UID, NOW, 3000)).toBe(true)
    expect(isExpired(entry, UID, NOW, 10_000)).toBe(false)
  })
})
```

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

Run:
```bash
cd web && npx vitest run src/lib/idle.test.js
```
Expected: FAIL — `Failed to resolve import "./idle"` (파일이 아직 없음)

- [ ] **Step 3: 최소 구현을 작성한다**

Create `web/src/lib/idle.js`:

```js
// 유휴 로그아웃 — 순수 판정 로직.
// lib 계약: 의존성 0 · ❌ DOM/스토리지 · 시간은 인자(now)로 주입받는다.
//
// 만료 판정의 유일한 진실원천은 '벽시계'(now - lastActive)다.
// 인메모리 타이머는 절전·탭 freeze·bfcache·모바일 백그라운드에서 흐르지 않으므로
// 판정 근거로 쓸 수 없다. 타이머는 '확인하러 깨워주는' 수단일 뿐.
// 설계: docs/superpowers/specs/2026-07-14-idle-logout-design.md

export const IDLE_TIMEOUT_MS = 30 * 60 * 1000   // 30분 무활동 → 로그아웃
export const POLL_INTERVAL_MS = 15 * 1000       // 15초마다 만료 확인(30분 정책에 15초 오차는 무의미)
export const SKEW_MS = 60 * 1000                // 시계 오차 허용치

// localStorage 원문 → { uid, ts } | null(부재) | 'invalid'(가비지)
export function parseLastActive(raw) {
  if (raw == null || raw === '') return null
  let obj
  try {
    obj = JSON.parse(raw)
  } catch {
    return 'invalid'
  }
  if (!obj || typeof obj !== 'object') return 'invalid'
  const { uid, ts } = obj
  if (typeof uid !== 'string' || uid === '') return 'invalid'
  if (typeof ts !== 'number' || !Number.isFinite(ts)) return 'invalid'
  return { uid, ts }
}

// 만료 여부. 판단이 불가능하면 만료로 본다(fail-closed).
export function isExpired(entry, uid, now, timeout = IDLE_TIMEOUT_MS) {
  if (entry === null) return false        // 부재 = 만료 아님 (시딩으로 처리되므로 신규 세션뿐)
  if (entry === 'invalid') return true    // 가비지 = 만료 (fail-closed)
  if (entry.uid !== uid) return false     // 다른 계정 값 = 무시 (호출부가 재시딩)
  const elapsed = now - entry.ts
  if (elapsed < -SKEW_MS) return true     // 미래 타임스탬프 = 신뢰 불가 → 만료
  return elapsed > timeout                // 정각(===)은 만료 아님. 초과해야 만료
}
```

- [ ] **Step 4: 테스트가 통과하는지 확인한다**

Run:
```bash
cd web && npx vitest run src/lib/idle.test.js
```
Expected: PASS — `Test Files 1 passed (1)`, `Tests 13 passed (13)`

- [ ] **Step 5: 커밋**

```bash
git add web/src/lib/idle.js web/src/lib/idle.test.js
git commit -m "feat(idle): lib/idle 순수 판정 — 벽시계 만료 판정(fail-closed)"
```

---

### Task 2: `components/idleStorage.js` — localStorage I/O

`lib`은 DOM 금지 계약이라 스토리지 접근은 여기(components 계층)에 둔다. `storage`를 **인자로 주입**받아 node 환경에서 mock으로 테스트한다(jsdom 불필요).

**Files:**
- Create: `web/src/components/idleStorage.js`
- Test: `web/src/components/idleStorage.test.js`

**Interfaces:**
- Consumes: 없음 (React·DOM 전역 참조 없음 — `storage`는 항상 인자로 받는다)
- Produces:
  - `LAST_ACTIVE_KEY: string` (= `'honeyjang.idle.lastActive'`)
  - `readLastActive(storage) => string | null`
  - `writeLastActive(storage, uid: string, ts: number) => boolean`

> **삭제 함수는 만들지 않는다.** 설계상 `lastActive`는 로그아웃 시에도 **지우지 않는다**(오프라인 `signOut()` 실패 시 fail-open 방지 — 설계 §4.1).

- [ ] **Step 1: 실패하는 테스트를 쓴다**

Create `web/src/components/idleStorage.test.js`:

```js
import { describe, it, expect } from 'vitest'
import { LAST_ACTIVE_KEY, readLastActive, writeLastActive } from './idleStorage'

function memStorage() {
  const m = new Map()
  return {
    getItem: (k) => (m.has(k) ? m.get(k) : null),
    setItem: (k, v) => m.set(k, String(v)),
  }
}

const throwingStorage = {
  getItem: () => { throw new Error('SecurityError') },
  setItem: () => { throw new Error('QuotaExceededError') },
}

describe('idleStorage', () => {
  it('쓴 값을 그대로 읽는다', () => {
    const s = memStorage()
    expect(writeLastActive(s, 'user-1', 123)).toBe(true)
    expect(readLastActive(s)).toBe('{"uid":"user-1","ts":123}')
  })

  it('키가 없으면 null', () => {
    expect(readLastActive(memStorage())).toBe(null)
  })

  it('약속된 키를 쓴다', () => {
    const s = memStorage()
    writeLastActive(s, 'user-1', 1)
    expect(s.getItem(LAST_ACTIVE_KEY)).toBe('{"uid":"user-1","ts":1}')
  })

  it('읽기가 throw해도 크래시하지 않고 null (프라이빗 모드 등)', () => {
    expect(readLastActive(throwingStorage)).toBe(null)
  })

  it('쓰기가 throw해도 크래시하지 않고 false', () => {
    expect(writeLastActive(throwingStorage, 'user-1', 1)).toBe(false)
  })
})
```

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

Run:
```bash
cd web && npx vitest run src/components/idleStorage.test.js
```
Expected: FAIL — `Failed to resolve import "./idleStorage"`

- [ ] **Step 3: 최소 구현을 작성한다**

Create `web/src/components/idleStorage.js`:

```js
// 유휴 로그아웃 — lastActive의 localStorage I/O.
// lib은 의존성 0·DOM 금지 계약이라(lib/README.md) 스토리지 접근은 여기에 둔다.
// storage를 '인자로 주입'받아 node 환경에서 mock 테스트가 가능하게 한다(jsdom 불필요).
//
// ⚠️ 삭제 함수는 두지 않는다. 설계상 lastActive는 로그아웃 시에도 지우지 않는다 —
//    signOut()이 네트워크 오류로 실패하면 auth-js가 세션을 안 지우는데, 키까지 지우면
//    다음 부팅에서 만료 판정 근거가 사라져 전임자 계정이 부활한다(fail-open).

export const LAST_ACTIVE_KEY = 'honeyjang.idle.lastActive'

// 실패해도 앱을 죽이지 않는다(사파리 프라이빗 등) — 지속성만 포기한다.
export function readLastActive(storage) {
  try {
    return storage.getItem(LAST_ACTIVE_KEY)
  } catch {
    return null
  }
}

export function writeLastActive(storage, uid, ts) {
  try {
    storage.setItem(LAST_ACTIVE_KEY, JSON.stringify({ uid, ts }))
    return true
  } catch {
    return false
  }
}
```

- [ ] **Step 4: 테스트가 통과하는지 확인한다**

Run:
```bash
cd web && npx vitest run src/components/idleStorage.test.js
```
Expected: PASS — `Tests 5 passed (5)`

- [ ] **Step 5: 커밋**

```bash
git add web/src/components/idleStorage.js web/src/components/idleStorage.test.js
git commit -m "feat(idle): idleStorage — lastActive localStorage I/O(주입형·throw 안전)"
```

---

### Task 3: 로그아웃 `scope` 정리 — `logout(opts)` + 수동 로그아웃도 `local`

`AuthContext.logout()`은 `supabase.auth.signOut()`을 **인자 없이** 호출한다 → auth-js 기본값 **`scope: 'global'`** → **그 사용자의 모든 기기 세션이 폐기된다.**

이 `'global'`은 **누가 고른 게 아니라 Supabase 기본값을 물려받은 것**이고, 두 곳에서 부당하다:

1. **유휴 로그아웃** — 사용자가 의도한 적이 없다. 실습실 PC에 켜둔 탭이 30분 유휴로 자동 로그아웃되면서 집에서 쓰던 폰까지 튕기면 그냥 버그다.
2. **수동 로그아웃 버튼** — 일반 앱(Gmail·페이스북 등)에서 "로그아웃"은 **이 기기만**이다. 학교 PC에서 로그아웃했다고 내 폰 세션까지 끊기면 사용자가 놀란다.

→ **`logout`이 `opts`를 통과시키게 하고, 유휴 로그아웃과 수동 로그아웃 모두 `{ scope: 'local' }`로 부른다.**

**그대로 두는 것(의도적):**
- `web/src/data/authQueries.js:120` (탈퇴 후 `signOut()`) — 계정 자체가 삭제되므로 scope가 무의미
- `web/src/pages/Signup.jsx:180` (유령 세션 정리) — 이미 죽은 계정 토큰이라 영향이 없고, **현수 파일이라 건드리지 않는다**

**Files:**
- Modify: `web/src/components/AuthContext.jsx:55-59`
- Modify: `web/src/components/AccountMenu.jsx:49`
- Modify: `web/src/pages/MyPage.jsx:369`

**Interfaces:**
- Produces: `logout(opts?: { scope?: 'global' | 'local' | 'others' }) => Promise<{ error }>`
  - **인자를 주지 않으면 기존과 100% 동일하게 동작한다**(하위 호환). 그래서 `Signup.jsx`의 기존 호출은 수정 없이 그대로 돈다.

⚠️ **`AuthContext`의 내부 로직은 한 줄도 건드리지 않는다.** `++loadSeq.current`, `setSession(null)`, `setUser(null)`의 순서·내용을 그대로 둔다 — 경합 가드다.

- [ ] **Step 1: `logout`이 `opts`를 받아 넘기도록 고친다**

`web/src/components/AuthContext.jsx`의 `logout` (55~59행).

Before:
```jsx
  const logout = () => {
    ++loadSeq.current
    setSession(null); setUser(null)
    return supabase.auth.signOut()
  }
```

After:
```jsx
  // opts는 supabase.auth.signOut()에 그대로 전달한다(기본값 유지 — 인자 없으면 기존과 동일).
  // 유휴 로그아웃(IdleLogout)은 { scope: 'local' }로 불러 '이 브라우저만' 끊는다.
  // (인자를 안 주면 auth-js 기본이 scope:'global'이라 사용자의 모든 기기 세션이 폐기된다 —
  //  사용자가 직접 누른 로그아웃엔 합당하지만, 자동 유휴 로그아웃엔 부당하다)
  const logout = (opts) => {
    ++loadSeq.current
    setSession(null); setUser(null)
    return supabase.auth.signOut(opts)
  }
```

- [ ] **Step 2: 계정 메뉴의 로그아웃을 `local`로 바꾼다**

`web/src/components/AccountMenu.jsx` 49행.

Before:
```jsx
      action: () => { logout(); navigate('/login') },
```

After:
```jsx
      // scope:'local' — 이 브라우저만 로그아웃. 인자를 안 주면 auth-js 기본이 'global'이라
      // 학교 PC에서 로그아웃했을 뿐인데 집의 폰 세션까지 끊긴다.
      action: () => { logout({ scope: 'local' }); navigate('/login') },
```

- [ ] **Step 3: 마이페이지의 로그아웃을 `local`로 바꾼다**

`web/src/pages/MyPage.jsx` 369행.

Before:
```jsx
          <button className="my-logout" onClick={() => ask('로그아웃하시겠습니까?', '로그아웃', () => { logout(); navigate('/login') })}>로그아웃</button>
```

After:
```jsx
          {/* scope:'local' — 이 브라우저만. 기본값 'global'은 다른 기기 세션까지 끊는다 */}
          <button className="my-logout" onClick={() => ask('로그아웃하시겠습니까?', '로그아웃', () => { logout({ scope: 'local' }); navigate('/login') })}>로그아웃</button>
```

- [ ] **Step 4: 빌드·테스트·린트**

Run:
```bash
cd web && npm run build && npm run test && npx eslint src/components/AuthContext.jsx src/components/AccountMenu.jsx src/pages/MyPage.jsx
```
Expected: 빌드 성공 · 모든 테스트 PASS · eslint 출력 없음

- [ ] **Step 5: 수동 로그아웃이 여전히 동작하는지 확인한다**

Run:
```bash
cd web && npm run dev
```
1. 로그인 → 우측 상단 계정 메뉴 → **로그아웃** → `/login`으로 정상 이동
2. 다시 로그인 → **마이페이지 → 로그아웃** → 확인 모달 → `/login`으로 정상 이동

Expected: 두 경로 모두 기존과 똑같이 로그아웃된다. (바뀐 건 "다른 기기 세션을 안 끊는다"는 것뿐이라 이 브라우저에서 보이는 동작은 동일하다.)

- [ ] **Step 6: 커밋**

```bash
git add web/src/components/AuthContext.jsx web/src/components/AccountMenu.jsx web/src/pages/MyPage.jsx
git commit -m "feat(auth): logout(opts) 통과 + 수동 로그아웃 scope:'local' — 로그아웃이 다른 기기 세션을 끊지 않게"
```

---

### Task 4: `components/IdleLogout.jsx` — 폴링 + 복귀 이벤트 배선

이 파일이 설계의 심장이다. 아래는 전부 **적대적 검증에서 나온 실제 버그를 막는 장치**이므로 임의로 단순화하지 말 것(C-1/I-1/I-2/M-1은 리뷰에서 Critical/Important/Minor로 잡혀 실제 구현에 반영된 수정이다):

1. **`user` 게이트** (`session` 아님) — 가입 미완료 세션의 좀비 폼 방지
2. **`isLoading` 게이트(I-2)** — 세션 복원 중에는 판단하지 않는다(`firstRun` 유지). `if (isLoading) return`은 `firstRun.current = false` **위**에 두고, deps에 `isLoading`을 추가한다
3. **마운트 vs 로그인 구분** — 복원 세션은 *판정 먼저*, 새 로그인은 *무조건 시딩*
4. **`logout` 아이덴티티를 effect 의존성에서 제외** — `AuthContext.logout`은 메모이즈가 안 돼 매 렌더 새 함수다. 의존성에 넣으면 렌더마다 effect가 재실행되며 `lastActive`를 재시딩 → **유휴 시계가 영영 안 흐른다**
5. **`firing`/`seededFor` ref 가드 + uid 전이 시 리셋, early-return 포함(C-1, Critical)** — SPA라 로그아웃→재로그인에 리로드가 없어, `!uid || !store`로 빠지는 **early-return에서도** `seededFor.current = null; firing.current = false`를 리셋해야 한다. 안 하면 로그아웃이 **페이지 로드당 1회용**이 되고, stale `lastActive`로 재로그인 즉시 되튕긴다
6. **`onActivity`는 `writeLastActive` 전에 `check()`부터(I-1)** — 절전 복귀 시 `mousemove`가 만료 증거(`lastActive`)를 먼저 덮어써버리는 레이스 방지
7. **`doLogout`은 `try/catch`(M-1)** — `signOut()`이 throw해도 `firing` 가드가 고착되지 않도록 catch에서 `window.location.replace('/login')`로 강제 정리
8. **`navigate(..., { replace: true })`** — 기존 페이지 가드가 전부 `push`라 뒤로가기 핑퐁 트랩

**Files:**
- Create: `web/src/components/IdleLogout.jsx`

**Interfaces:**
- Consumes:
  - `useAuth()` from `./AuthContext` → `{ user, logout, isLoading }` (`user.id`가 uid, `logout(opts?)`는 `Promise<{ error }>` 반환 — Task 3에서 `opts` 인자가 추가됨, `isLoading`은 세션 복원 중 판단을 보류하기 위한 게이트)
  - `IDLE_TIMEOUT_MS`, `POLL_INTERVAL_MS`, `parseLastActive`, `isExpired` from `../lib/idle`
  - `readLastActive`, `writeLastActive` from `./idleStorage`
- Produces: default export `IdleLogout({ timeoutMs?, pollMs?, storage? }) => null`
  - props는 **테스트/수동검증용 주입구**다. 프로덕션에선 인자 없이 `<IdleLogout />`로 쓴다.

- [ ] **Step 1: 컴포넌트를 작성한다**

Create `web/src/components/IdleLogout.jsx`:

```jsx
import { useEffect, useRef } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from './AuthContext'
import { IDLE_TIMEOUT_MS, POLL_INTERVAL_MS, parseLastActive, isExpired } from '../lib/idle'
import { readLastActive, writeLastActive } from './idleStorage'

// 유휴 로그아웃 — 로그인(프로필 완료) 사용자가 timeoutMs 동안 무활동이면 자동 로그아웃.
// 설계: docs/superpowers/specs/2026-07-14-idle-logout-design.md
//
// 원칙: 만료 판정의 진실원천은 '벽시계'(now - lastActive)다. 타이머(폴링)는 '확인하러 깨워주는'
//   수단일 뿐 — 만료 여부는 매번 localStorage의 lastActive를 다시 읽어 판정한다.
//   (인메모리 타이머는 절전·탭 freeze·bfcache·모바일 백그라운드에서 흐르지 않는다)
//
// ⚠️ 마운트 위치: 반드시 <BrowserRouter> 안(useNavigate 사용) · <ProfileGate> 밖(언마운트 방지).
//    App() 안에 두면 Router 컨텍스트 밖이라 useNavigate()가 throw → 앱 전체 백지.

// 'input' 필수 — keydown만으론 모바일 글라이드·음성입력·추천단어·붙여넣기가 '무활동'으로 잡힌다.
// (input은 버블링되므로 document 바인딩으로 전부 포착)
const ACTIVITY_EVENTS = ['mousemove', 'keydown', 'input', 'scroll', 'click', 'touchstart']
// 백그라운드에선 setInterval이 스로틀/정지되므로 복귀 '순간' 즉시 재평가해야 한다.
const RESUME_WINDOW_EVENTS = ['focus', 'pageshow', 'storage']
const ACTIVITY_THROTTLE_MS = 1000   // localStorage 쓰기 폭주 방지

export default function IdleLogout({
  timeoutMs = IDLE_TIMEOUT_MS,
  pollMs = POLL_INTERVAL_MS,
  storage,
}) {
  const { user, logout, isLoading } = useAuth()
  const navigate = useNavigate()
  const uid = user?.id ?? null
  const store = storage ?? (typeof window !== 'undefined' ? window.localStorage : null)

  // ⚠️ AuthContext의 logout·navigate를 effect 의존성에 넣으면 안 된다.
  //    logout은 AuthProvider에서 매 렌더 새로 만들어지는 함수(메모이즈 없음)라,
  //    의존성에 넣으면 렌더마다 effect가 재실행되며 lastActive를 재시딩 →
  //    유휴 시계가 영영 안 흐르고 로그아웃이 절대 발생하지 않는다.
  //    최신 참조는 ref로만 들고 다닌다.
  const logoutRef = useRef(logout)
  const navigateRef = useRef(navigate)
  useEffect(() => {
    logoutRef.current = logout
    navigateRef.current = navigate
  })

  // 로그아웃 중복 발화 가드. 모듈 스코프 let이 아니라 ref —
  // SPA라 로그아웃→재로그인 사이에 페이지 리로드가 없어, uid 전이 때 리셋하지 않으면
  // 유휴 로그아웃이 '페이지 로드당 1회용'이 된다(재로그인 후 영영 로그아웃 안 됨).
  const firing = useRef(false)
  // 이미 시딩을 마친 uid. StrictMode 이중 마운트에서 재시딩·가드 초기화를 막는다.
  const seededFor = useRef(null)
  // 첫 effect 실행인지. '마운트 시점에 이미 로그인' = 복원된 세션을 구분하는 유일한 신호.
  const firstRun = useRef(true)

  useEffect(() => {
    if (isLoading) return          // 세션 복원 중 — 아직 판단하지 않는다(firstRun 유지)
    const wasFirstRun = firstRun.current
    firstRun.current = false

    // 비로그인 / 가입 미완료(needsProfile: 인증O·프로필X) → 완전 무동작.
    // user 게이트인 이유: session으로 게이트하면 OTP 통과 후 프로필 입력 중에도 타이머가 돌아,
    // 로그아웃 시 Login의 profileStep이 남아 <Signup/>이 좀비로 살아있고 입력이 전소된다.
    if (!uid || !store) {
      // 로그아웃 → 다음 로그인은 같은 계정이라도 '새 로그인'으로 취급해야 한다.
      // 안 비우면: firing이 true로 고착돼 유휴 로그아웃이 '페이지 로드당 1회용'이 되고(a),
      //           stale lastActive로 재로그인 즉시 되튕긴다(b). SPA라 리로드가 없어 ref가 살아남는다.
      seededFor.current = null
      firing.current = false
      return
    }

    const doLogout = async () => {
      if (firing.current) return
      firing.current = true
      try {
        // lastActive는 '지우지 않는다'(idleStorage에 삭제 함수가 없는 이유).
        // scope:'local' 필수 — 인자를 안 주면 auth-js 기본이 'global'이라 사용자의 모든 기기
        // 세션이 끊긴다. 유휴 로그아웃은 사용자가 의도한 적이 없으므로 이 브라우저만 끊는다.
        const { error } = (await logoutRef.current({ scope: 'local' })) ?? {}
        // signOut()이 네트워크 오류로 실패하면 auth-js가 localStorage 세션을 안 지운다
        // → 하드 리로드로 메모리 상태까지 확실히 날린다.
        if (error) window.location.replace('/login')
        // replace 필수: 기존 페이지 가드(MyPage·Search·ExchangeCenter·WorksiteDetail·ReviewForm)가
        // 전부 push라, push로 가면 뒤로가기 시 /mypage ↔ /login 핑퐁 트랩에 갇힌다.
        else navigateRef.current('/login', { replace: true, state: { reason: 'idle' } })
      } catch {
        // signOut이 throw해도 firing이 true로 고착되면 안 된다 — 하드 리로드로 확실히 정리.
        window.location.replace('/login')
      }
    }

    const check = () => {
      if (firing.current) return
      const entry = parseLastActive(readLastActive(store))
      if (isExpired(entry, uid, Date.now(), timeoutMs)) doLogout()
    }

    if (seededFor.current !== uid) {
      // 이 uid로는 아직 시딩하지 않았다 = '복원된 세션의 첫 마운트' 또는 '새 로그인'.
      if (wasFirstRun) {
        // 마운트 시점에 이미 로그인 = 복원된 세션 → 저장된 lastActive로 '먼저 판정'한다.
        // ("창을 껐다가 40분 뒤 다시 열었다"를 여기서 잡는다. 무조건 시딩해버리면 이 요구가 죽는다.)
        const entry = parseLastActive(readLastActive(store))
        if (isExpired(entry, uid, Date.now(), timeoutMs)) {
          seededFor.current = uid
          doLogout()
          return
        }
      }
      // 새 로그인(uid가 마운트 이후 null→값) 또는 아직 유효한 복원 세션 → 시딩.
      // (재로그인 시 stale 값으로 즉시 튕기는 것을 막는다)
      firing.current = false
      seededFor.current = uid
      writeLastActive(store, uid, Date.now())
    }

    let lastWrite = 0
    const onActivity = () => {
      const now = Date.now()
      if (now - lastWrite < ACTIVITY_THROTTLE_MS) return
      check()                 // 만료 증거를 덮어쓰기 전에 먼저 판정 (절전 복귀 레이스 방지)
      if (firing.current) return
      lastWrite = now
      writeLastActive(store, uid, now)
    }

    ACTIVITY_EVENTS.forEach((e) => document.addEventListener(e, onActivity, { passive: true }))
    document.addEventListener('visibilitychange', check)
    RESUME_WINDOW_EVENTS.forEach((e) => window.addEventListener(e, check))
    const pollId = setInterval(check, pollMs)

    check()   // 마운트 즉시 1회

    return () => {
      clearInterval(pollId)
      ACTIVITY_EVENTS.forEach((e) => document.removeEventListener(e, onActivity))
      document.removeEventListener('visibilitychange', check)
      RESUME_WINDOW_EVENTS.forEach((e) => window.removeEventListener(e, check))
    }
    // logout·navigate는 의도적으로 제외(위 주석 참고). storage/timeoutMs/pollMs는 안정적.
  }, [uid, store, timeoutMs, pollMs, isLoading])

  return null
}
```

- [ ] **Step 2: 빌드와 린트가 통과하는지 확인한다**

컴포넌트는 아직 어디에도 마운트되지 않았으므로, 이 단계에서는 **컴파일·린트만** 확인한다.

Run:
```bash
cd web && npm run build && npx eslint src/components/IdleLogout.jsx
```
Expected: `✓ built in ...` 그리고 eslint 출력 없음(경고·에러 0).

> `react-hooks/exhaustive-deps` 경고가 뜨면, 위 주석에 적힌 이유(의도적 제외)를 근거로 해당 줄에만
> `// eslint-disable-next-line react-hooks/exhaustive-deps` 를 붙인다. **의존성 배열에 `logout`을 넣지 말 것** — 넣으면 유휴 로그아웃이 절대 발동하지 않는다.

- [ ] **Step 3: 기존 테스트가 깨지지 않았는지 확인한다**

Run:
```bash
cd web && npm run test
```
Expected: 전부 PASS (신규 `idle.test.js`·`idleStorage.test.js` 포함)

- [ ] **Step 4: 커밋**

```bash
git add web/src/components/IdleLogout.jsx
git commit -m "feat(idle): IdleLogout — 벽시계 폴링 + 복귀 이벤트 재평가(AuthContext 공개 API만 소비)"
```

---

### Task 5: `App.jsx`에 마운트

**Files:**
- Modify: `web/src/App.jsx` (import 추가 + 58~60행 사이에 1줄)

**Interfaces:**
- Consumes: `IdleLogout` (Task 4의 default export)
- Produces: 없음

⚠️ **마운트 위치가 이 태스크의 전부다.** 틀리면 앱 전체가 백지가 된다.
- `App()`(92~98행) 안에 넣으면 → `<BrowserRouter>`(58행)가 `AppRoutes` **안**에 있으므로 **Router 컨텍스트 밖** → `useNavigate()` throw → 에러 바운더리가 없어 **전 사용자 화이트스크린**
- `<ProfileGate>`(60행) **안**에 넣으면 → `needsProfile`일 때 `<Navigate/>`가 children을 대체해 **언마운트·리마운트** 반복
- 정답: `<BrowserRouter>` 직속, `<ScrollToTop />`(59행) **바로 다음**, `<ProfileGate>` **앞**

- [ ] **Step 1: import를 추가한다**

`web/src/App.jsx`의 import 블록(7행 `AppLayout` 다음)에 한 줄 추가:

```jsx
import AppLayout from './components/AppLayout'
import IdleLogout from './components/IdleLogout'
```

- [ ] **Step 2: `<BrowserRouter>` 직속에 마운트한다**

`web/src/App.jsx` 57~61행을 다음과 같이 바꾼다.

Before:
```jsx
  return (
    <BrowserRouter>
      <ScrollToTop />
      <ProfileGate>
      <Routes>
```

After:
```jsx
  return (
    <BrowserRouter>
      <ScrollToTop />
      {/* 유휴 로그아웃(30분). 반드시 BrowserRouter 안(useNavigate) · ProfileGate 밖(언마운트 방지).
          App() 안에 두면 Router 컨텍스트 밖이라 useNavigate()가 throw → 앱 전체 백지. */}
      <IdleLogout />
      <ProfileGate>
      <Routes>
```

- [ ] **Step 3: 빌드 + 전체 테스트**

Run:
```bash
cd web && npm run build && npm run test
```
Expected: `✓ built in ...` · 모든 테스트 PASS

- [ ] **Step 4: 앱이 실제로 뜨는지 확인한다 (화이트스크린 회귀 방지)**

Run:
```bash
cd web && npm run dev
```
브라우저에서 `http://localhost:5173/login` 을 연다.
Expected: **로그인 화면이 정상 렌더된다.** 콘솔에 `useNavigate() may be used only in the context of a <Router>` 에러가 **없어야** 한다.
(이 에러가 보이면 마운트 위치가 틀린 것 — Step 2로 돌아간다.)

- [ ] **Step 5: 커밋**

```bash
git add web/src/App.jsx
git commit -m "feat(idle): App에 IdleLogout 마운트(BrowserRouter 직속·ProfileGate 밖)"
```

---

### Task 6: 수동 검증 — 짧은 타임아웃으로 5개 시나리오

30분을 실시간으로 기다릴 수 없으므로, `<IdleLogout />`의 주입구(props)로 **짧은 값**을 넣어 검증한다.
아래 5개는 **자동 테스트로 못 잡는 것들**이며, 특히 1번은 "페이지 로드당 1회용" 버그를 잡는 **유일한** 수단이다.

**Files:**
- Modify (임시): `web/src/App.jsx` — 검증 후 반드시 되돌린다

- [ ] **Step 1: 임시로 타임아웃을 줄인다**

`web/src/App.jsx`의 마운트를 **임시로** 바꾼다:

```jsx
<IdleLogout timeoutMs={20000} pollMs={2000} />
```
(20초 무활동 → 로그아웃, 2초마다 확인)

- [ ] **Step 2: 5개 시나리오를 순서대로 확인한다**

`npm run dev` 후 로그인한 상태에서:

1. **재로그인 후 다시 로그아웃되는가** ← 가장 중요
   로그인 → 20초 가만히 둠 → `/login`으로 튕김 확인 → **그 자리에서 다시 로그인** → 다시 20초 가만히 둠 → **또 로그아웃되어야 한다.**
   (여기서 로그아웃이 안 되면 `firing` 가드가 리셋되지 않은 것 — Task 4 Step 1의 `seededFor`/`firing` 로직을 다시 본다.)

2. **백그라운드 복귀 시 즉시 로그아웃되는가**
   로그인 → 다른 탭으로 전환 → 30초 이상 대기 → 근로고래 탭으로 복귀 → **복귀 즉시** `/login`으로 가야 한다(2초 폴링을 기다리지 않고).

3. **가입 프로필 단계에서는 로그아웃되지 않는가**
   새 계정 가입 → OTP 인증 통과 → **프로필 입력 단계에서** 20초 이상 가만히 둠 → **로그아웃되면 안 된다**(입력 폼이 그대로 유지).

4. **뒤로가기가 핑퐁하지 않는가**
   로그인 → `/home` → `/mypage` 이동 → 20초 대기 → `/login`으로 튕김 → **뒤로가기** → `/mypage`↔`/login`을 오가지 않고 이전 페이지로 정상 복귀해야 한다.

5. **탭 2개에서 활동 중인 탭을 죽이지 않는가**
   탭 A와 탭 B 모두 로그인 상태로 연다 → 탭 A는 방치하고 **탭 B에서 계속 마우스를 움직인다** → 30초 후 **탭 A도 로그아웃되면 안 된다**(B의 활동이 lastActive를 갱신하므로).

- [ ] **Step 3: 창 껐다 켜기도 확인한다 (설계의 핵심 요구)**

로그인 → 브라우저 탭/창을 **완전히 닫는다** → 30초 이상 기다린다 → 다시 `http://localhost:5173/home` 을 연다
Expected: **로그인 화면으로 튕겨야 한다** (복원된 세션 + stale lastActive → 마운트 시 판정).

- [ ] **Step 4: 임시 변경을 되돌린다**

`web/src/App.jsx`를 원래대로 되돌린다:

```jsx
<IdleLogout />
```

Run:
```bash
cd web && git diff src/App.jsx
```
Expected: **`timeoutMs`·`pollMs` prop이 남아있지 않아야 한다.** (`git diff`에 아무 출력이 없거나, Task 5에서 커밋한 내용과 동일해야 한다)

- [ ] **Step 5: 되돌린 상태로 빌드 확인**

Run:
```bash
cd web && npm run build
```
Expected: `✓ built in ...`

> 이 태스크는 코드 산출물이 없다(임시 변경을 되돌리므로 커밋할 것이 없다). 5개 시나리오 + 창 껐다 켜기가 **모두 통과해야** 다음 태스크로 넘어간다. 실패한 항목이 있으면 Task 4로 돌아간다.

---

### Task 7: 문서 갱신

**Files:**
- Modify: `web/src/lib/README.md` — (d) 현재 파일 표
- Modify: `web/src/components/README.md` — (d) 현재 파일 표
- Modify: `docs/superpowers/specs/2026-07-10-account-withdrawal-design.md` — B-2의 45분 → 30분

- [ ] **Step 1: `lib/README.md`의 파일 표에 추가한다**

`web/src/lib/README.md`의 `## (d) 현재 파일` 표에 두 줄 추가:

```markdown
| `idle.js` | 유휴 로그아웃 판정 (`IDLE_TIMEOUT_MS`, `POLL_INTERVAL_MS`, `parseLastActive`, `isExpired`). 벽시계 기준·fail-closed. 시간은 `now` 인자로 주입 |
| `idle.test.js` | `idle.js` 단위테스트 |
```

- [ ] **Step 2: `components/README.md`의 파일 표에 추가한다**

`web/src/components/README.md`의 `## (d) 현재 파일` 표에 두 줄 추가:

```markdown
| `IdleLogout.jsx` | 유휴 로그아웃(30분). `return null` 마운트 전용 — `App.jsx`의 `<BrowserRouter>` 직속·`<ProfileGate>` 밖에 마운트(다른 위치에 두면 `useNavigate()` throw로 앱 백지). `useAuth()`의 `user`·`logout()`만 소비하고 `AuthContext` 내부는 안 건드림. 판정은 `lib/idle`(벽시계), I/O는 `idleStorage` |
| `idleStorage.js` / `.test.js` | `IdleLogout`의 `lastActive` localStorage I/O. `storage`를 주입받아 node 환경 테스트 가능. **삭제 함수 없음**(로그아웃 시에도 지우지 않는 게 설계) |
```

- [ ] **Step 3: 탈퇴 spec B-2를 확정값으로 맞춘다 (45분 → 30분 · 저장 전략 정정)**

`docs/superpowers/specs/2026-07-10-account-withdrawal-design.md`의 B-2에는 **확정값과 다른 값(45분)** 과, **우리 설계와 충돌하는 저장 전략**이 남아 있다. 둘 다 고친다.

**(a) 40행** — Before:
```markdown
- **값**: 유휴 **45분**(넉넉히 — 일상 앱전환은 안 튕기고 장시간 방치만 잡음). 비금융 학생앱이라 짧게 안 함.
```
After:
```markdown
- **값**: 유휴 **30분**. (확정: 2026-07-14) 구현 설계는 `2026-07-14-idle-logout-design.md` 참조 — 벽시계 단일 진실원천 · 15초 폴링 · 의존성 0.
```

**(b) 45행** — Before:
```markdown
- **"창 넘어가면 즉시 로그아웃 아님"** — 넘어간 것만으론 안 함. 돌아왔을 때 누적 idle이 45분 넘었을 때만.
```
After:
```markdown
- **"창 넘어가면 즉시 로그아웃 아님"** — 넘어간 것만으론 안 함. 돌아왔을 때 누적 idle이 30분 넘었을 때만.
```

**(c) 46행 (성능)** — 이 항목은 **폐기한다.** `lastActivity`를 메모리 변수로 두고 백그라운드 전환 시에만 저장하면 **탭 간 동기화가 불가능**하다(탭 A가 활동 중인데 탭 B가 그것을 볼 수 없어, 방치된 탭이 활동 중인 탭을 로그아웃시킨다).

Before:
```markdown
- **성능**: 핫패스(매 이벤트)는 변수 대입뿐. `localStorage`는 **백그라운드 전환 시(`visibilitychange`/`pagehide`)에만** 1회 저장 — 매 이벤트 저장 아님. `mousemove`는 throttle/제외, `click·keydown·scroll·touchstart`(+`passive`)만.
```
After:
```markdown
- **성능**: 활동 이벤트는 **1초 쓰로틀**로 `localStorage`에 `lastActive` 기록(+`passive` 리스너). ~~백그라운드 전환 시에만 저장~~ 은 폐기 — `lastActive`가 탭 간 동기화의 유일한 근거라 메모리 변수로는 성립하지 않는다(방치된 탭이 활동 중인 탭을 죽인다). 초당 1회 localStorage 쓰기는 무시 가능한 비용.
```

- [ ] **Step 4: 커밋**

```bash
git add web/src/lib/README.md web/src/components/README.md docs/superpowers/specs/2026-07-10-account-withdrawal-design.md
git commit -m "docs(idle): lib·components README 파일표 갱신 + 탈퇴 spec 유휴 로그아웃 45분→30분"
```

---

## 이 계획에 포함되지 않은 것 (설계 §9)

아래는 **의도적으로 제외**했다. 임의로 구현하지 말 것.

| 항목 | 왜 제외했나 |
|---|---|
| **`logout({ scope: 'local' })`** | `AuthContext.logout()`이 `supabase.auth.signOut()`을 인자 없이 호출 → auth-js 기본 `scope: 'global'` → **유휴 로그아웃이 사용자의 모든 기기 세션을 끊는다.** 고치려면 `AuthContext` 공개 API를 확장해야 하는데, 이는 "AuthContext 내부 미수정" 제약과 충돌 → **현수와 협의 필요.** 협의 전까지는 현행(전 기기 로그아웃)이 유지된다 |
| **유휴 사유 토스트** (`Login.jsx`) | `Login.jsx`는 현수 영역 — 조율 후 별도 커밋. 토스트가 없어도 이 계획의 나머지는 완결된다 |
| **ReviewForm 초안 저장** | 유휴 로그아웃과 독립적 가치(탭 discard·네트워크 오류로도 소실). 별도 PR |
| **"브라우저 종료 = 로그아웃"** | 설계 §1의 미커버 범위. UX 비용이 실재해 PM 결정 사항(백로그) |
| **jsdom + @testing-library** | Post-MVP 권고. 이 계획의 자동 테스트는 전부 node env에서 순수 함수 + mock storage로 돈다 |
