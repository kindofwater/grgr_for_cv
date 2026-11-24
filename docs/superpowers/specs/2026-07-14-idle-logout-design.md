# 유휴 로그아웃(Idle Logout) 설계

- 날짜: 2026-07-14 · 담당: 배경록
- 상태: 확정(적대적 검증 통과 후 개정본)
- 관련: [회원탈퇴 설계](2026-07-10-account-withdrawal-design.md) B-2(세션 보안) · `web/src/components/AuthContext.jsx`

---

## 1. 목표

로그인(**프로필 완료**) 사용자가 **30분 무활동**이면 자동 로그아웃하고 `/login`으로 보낸다.
경고 모달은 두지 않는다. 창을 껐다 열거나 **백그라운드에서 복귀해도** 경과가 30분을 넘었으면 로그아웃한다.

### 방어 범위 (정직하게 명시)
이 기능이 막는 것은 **"자리 비움(idle)"** 뿐이다.

- ❌ **"브라우저 닫고 즉시 다음 사람"은 커버하지 않는다.** `supabase.js`가 `persistSession: true`라 브라우저를 닫아도 세션이 localStorage에 남고, 30분이 지나지 않았으면 다음 사람이 그대로 로그인 상태로 들어온다.
- ❌ 토큰을 이미 탈취한 공격자도 막지 못한다(클라이언트 방어의 원리적 한계).

"브라우저 종료 = 로그아웃"(sessionStorage 탭 마커)이나 "공용 PC 체크박스" 옵트인은 **백로그**로 분리한다. 개인 PC에서 탭 닫을 때마다 재로그인해야 하는 UX 비용이 실재하므로 PM 결정 사항이다.

> 이전 논의에서 "공용 PC 보호"를 근거로 30분을 정당화했으나, 위와 같이 그 시나리오는 실제로 보호되지 않는다. **30분이라는 값은 유지하되 근거는 "자리 비움 보호"로 정정한다.**

---

## 2. 핵심 설계 원칙 — 벽시계 단일 진실원천 + 폴링 집행

**(1) 판정의 근거는 오직 `now - lastActive`(벽시계)다.** 타이머는 판정 근거가 아니라 "확인하러 깨워주는" 수단일 뿐이다.

이유: 인메모리 `setTimeout`/`setInterval`은 **노트북 절전·탭 freeze·bfcache·모바일 백그라운드에서 흐르지 않는다.** 타이머 경과를 판정 근거로 쓰면 이 모든 상황에서 유휴 로그아웃이 무력화되거나 오탐한다.

**(2) 집행은 주기적 폴링(업계 표준)으로 한다.**

```js
setInterval(() => { if (now - lastActive > TIMEOUT) logout() }, POLL_INTERVAL_MS)
```

- **자가교정**: 절전에서 깨어나든 백그라운드에서 돌아오든, **다음 틱이 알아서 잡는다.** "남은 시간 계산 후 정확 재무장" 같은 장치가 필요 없다.
- 정밀도는 폴링 간격(15초)까지만 보장되지만, **30분 정책에 15초 오차는 무의미**하다.
- 백그라운드에서 `setInterval`이 스로틀/정지돼도 무방하다 — 그동안은 아무도 보고 있지 않고, **복귀 즉시 재평가 지점(§5.3)이 잡는다.**

**(3) 의존성 0.** 위 구조에서 스케줄러 라이브러리가 할 일이 남지 않는다.

> **폐기된 대안 — `react-idle-timer`:** 초안은 "만료가 아니면 *남은 시간만큼만* 재무장"(정확 재무장)을 요구했고, 그러려면 알람을 `lastActive + 30분`에 맞춰야 한다. 그러나 `IIdleTimer`(v5.7.3) 타입 정의를 확인한 결과 **타임아웃을 동적으로 지정하는 API가 없다**(`start·reset·activate·pause·resume·…`뿐이며 `reset()`은 정의부터 *"restart timer"* = **설정된 풀 타임아웃으로 재시작**). 즉 알람이 항상 `지금 + 30분`으로 밀린다 → 절전/백그라운드에서 깨어날 때마다 마감이 뒤로 밀려 **로그아웃이 최대 30분 지연**(= 실질 정책이 최대 60분)된다.
> 애초에 이 라이브러리를 쓰려던 이유(모바일 이벤트·쓰로틀·탭 동기화)는 개정 설계에서 전부 우리 몫으로 넘어왔고(§5.2·§5.3·§5.6), 남은 역할은 폴링이 더 단순하게 대체한다. **의존성을 추가하지 않는다.**

---

## 3. 구조

| 파일 | 역할 |
|---|---|
| `web/src/lib/idle.js` (신규) | **순수 판정만.** DOM·스토리지 금지 (`lib/README.md`의 "의존성 0 · ❌ React/DOM" 계약 준수) |
| `web/src/components/IdleLogout.jsx` (신규) | `return null` 마운트 전용. `useAuth()`의 **`user`·`logout()`만** 소비. 폴링 + 재평가 이벤트 배선 |
| `web/src/components/idleStorage.js` (신규) | `lastActive`의 localStorage I/O. `storage`를 **주입받아** node 환경에서 mock 테스트 가능 (`lib`은 DOM 금지 계약이라 여기에 둔다) |
| `web/src/App.jsx` (1줄) | `<IdleLogout />` 마운트 |

`AuthContext.jsx`(현수 영역)의 **내부 로직(경합 가드·hydrate·데드락 회피)은 수정하지 않는다.** 공개 API만 소비한다.

**단 하나의 예외 — `logout(opts)` 인자 전달 (현수 승인 2026-07-14):**

```js
// Before
const logout = () => { …; return supabase.auth.signOut() }        // 인자 없음 → auth-js 기본 scope:'global'
// After
const logout = (opts) => { …; return supabase.auth.signOut(opts) }  // 인자를 그대로 넘기기만 한다
```

**인자를 주지 않으면 기존과 100% 동일하게 동작한다**(하위 호환) — 그래서 `Signup.jsx`의 유령 세션 정리(`await logout()`)는 수정 없이 그대로 돈다. 내부 로직은 한 줄도 건드리지 않는다.

이 확장을 발판으로, **로그아웃 호출부를 아래와 같이 정리한다**:

| 호출부 | scope | 이유 |
|---|---|---|
| `IdleLogout` (신규) | **`'local'`** | 사용자가 의도한 적 없는 자동 로그아웃 |
| `AccountMenu.jsx:49` | **`'local'`** | 일반 앱의 "로그아웃" = 이 기기만 |
| `MyPage.jsx:369` | **`'local'`** | 위와 동일 |
| `Signup.jsx:180` (유령 세션) | 기본값 유지 | 이미 죽은 계정 토큰 — 영향 없음. **현수 파일이라 안 건드림** |
| `authQueries.js:120` (탈퇴) | 기본값 유지 | 계정 자체가 삭제되므로 scope 무의미 |

### 3.1 마운트 지점 (중요 — 틀리면 앱 전체 백지)

`App.jsx`에서 `<BrowserRouter>`는 `AppRoutes()` **안**에 있고, `if (isLoading) return null` 게이트가 그 **위**에 있다. 유일하게 안전한 자리:

```jsx
<BrowserRouter>
  <ScrollToTop />
  <IdleLogout />        {/* ← 여기 */}
  <ProfileGate>
    <Routes>…
```

- `App()` 안(= `AppRoutes` 형제)에 넣으면 → **Router 컨텍스트 밖** → `useNavigate()`가 throw → 에러 바운더리가 없어 **전 사용자 화이트스크린**.
- `<ProfileGate>` 안에 넣으면 → `needsProfile`일 때 `<Navigate/>`로 **언마운트·리마운트** 반복.
- 이 자리는 `isLoading === false` 이후에만 마운트되므로, `AuthContext`가 `session·user·isLoading`을 한 커밋으로 반영한 뒤의 **정확한 `user`를 첫 렌더부터** 본다.

---

## 4. `lastActive` 값 계약

localStorage에 `{ uid, ts }` 형태로 저장한다. `uid`를 함께 저장해 **공용 PC에서 A의 타임스탬프로 B가 튕기는 사고**를 막는다.

```js
// lib/idle.js — 순수 함수만
export const IDLE_TIMEOUT_MS = 30 * 60 * 1000   // 30분
export const POLL_INTERVAL_MS = 15 * 1000       // 폴링 주기
export const SKEW_MS = 60 * 1000                // 시계 오차 허용치

export function parseLastActive(raw)                       // → { uid, ts } | null | 'invalid'
export function isExpired(entry, uid, now, timeout)        // → boolean
```

> 폴링 채택으로 `msUntilExpiry`(남은 시간 계산)는 **불필요해져 제거**한다. 만료 여부만 물으면 된다.

**판정 규칙 (fail-closed):**

| 상태 | 판정 |
|---|---|
| 부재(`null`) | **만료 아님** (무장 시 즉시 시딩되므로 진짜 신규 세션에서만 발생) |
| 파싱 실패 · `NaN` | **만료** (fail-closed) |
| 미래 타임스탬프(> 60초 skew) | **만료** (신뢰 불가) |
| `uid` 불일치 | 무시 + 재시딩 |
| `now - ts > 30분` | **만료** |

### 4.1 생명주기 (원설계에서 뒤집힌 부분)

- ❌ ~~로그아웃 시 `lastActive` 키 제거~~ → **제거하지 않는다.**
- ✅ **`user`가 falsy→truthy로 전이할 때 `lastActive`를 시딩하되, 아래 두 경우를 반드시 구분한다** (2026-07-14 정정 — 원문은 "무조건 덮어쓴다"라고만 적혀 있었고, 이는 stale하고 위험한 문구였다. 아래 참고):

  | 전이 시점 | 의미 | 처리 |
  |---|---|---|
  | **마운트 시점에 이미 `user`가 truthy**(컴포넌트의 첫 effect 실행에서 감지) | **복원된 세션**(새로고침·재방문 — 로그인 자체는 그 이전에 이미 일어났다) | **먼저 저장된 `lastActive`로 판정한다.** 만료면 그 자리에서 로그아웃, 아니면 그제서야 `{ uid, ts: now }`로 시딩 |
  | **마운트 이후에 `user`가 null→값으로 바뀜** | **새 로그인 성공 / 가입 완료**(지금 이 순간 인증했다) | **무조건 `{ uid, ts: now }`로 덮어쓴다**(시딩) |

  ⚠️ **"무조건 시딩"을 두 경우 모두에 적용하면 안 된다.** 페이지 리로드로 복원된 세션도 `falsy→truthy` 전이이므로, 구분 없이 매번 시딩해버리면 **새로고침할 때마다 `lastActive`가 지금 시각으로 재시딩**된다. 그러면 §1의 헤드라인 요구("창을 껐다 열어도 30분 넘었으면 로그아웃")가 죽는다 — 30분 이상 방치 후 F5만 눌러도 시계가 리셋되어 로그아웃되지 않는 회귀가 생긴다.

  구현(`IdleLogout.jsx`)은 `firstRun` ref(첫 effect 실행 여부)로 두 경우를 가른다: `wasFirstRun`(마운트 시점에 이미 로그인)이면 "저장된 값으로 판정 먼저 → 유효하면 그제서야 시딩" 경로를 타고, 그 외(마운트 이후의 새 로그인)는 판정 없이 곧장 시딩한다.

  > **다음 유지보수자에게:** 위 표를 "복잡하니 그냥 falsy→truthy면 항상 무조건 시딩"으로 단순화하지 말 것 — 복원 세션의 만료 판정이 통째로 죽는 회귀가 그대로 부활한다.

**이 뒤집기 하나가 세 문제를 동시에 해결한다:**

1. **오프라인 `signOut()` 실패 자가치유.** `auth-js`의 `_signOut()`은 네트워크 오류(`AuthRetryableFetchError`·5xx) 시 `_removeSession()`에 도달하지 못하고 early-return한다 → **localStorage 세션 토큰이 살아남는다.** 원설계처럼 `lastActive`를 지우면 재판정 근거까지 사라져, 다음 사람이 **F5 한 번으로 전임자 계정을 복구**한다(fail-open). 키를 남겨두면 다음 재평가에서 stale 값을 보고 다시 로그아웃을 시도한다.
2. **`deleteAccount`가 `logout()`을 우회**(`authQueries.js`가 `supabase.auth.signOut()`을 직접 호출)해도, 키 정리를 호출부에 매달지 않으므로 애초에 문제가 없다.
3. **재로그인 즉시 튕김 방지.** 로그인 전이 시딩이 선행하므로 stale 값으로 새 세션이 만료 판정되는 일이 없다.

---

## 5. 동작

### 5.1 활성 조건
**`user`가 truthy일 때만** 동작한다(`session`이 아니다).

`session`으로 게이트하면 **가입 미완료 세션**(OTP 통과 후 프로필 입력 중, `needsProfile`)에서도 타이머가 돈다. 그 상태로 30분이 지나 로그아웃되면 `Login.jsx`의 `profileStep` 로컬 state가 남아 **`<Signup/>`이 세션 없이 좀비로 마운트된 채** 유지되고(경고 모달이 없어 사용자는 로그아웃을 모른다), 사용자가 3단계까지 채우고 제출하면 `auth.uid()`가 null이라 실패하며 **입력이 전소**된다.

`user` 게이트는 이를 원천 차단한다. 근거: 그 세션은 프로필·포인트·열람권이 없어 **보호할 자산이 0**인데, 대가로 가입 퍼널의 끝단만 깨뜨린다. 또한 `Login.jsx`(현수 영역)를 **한 줄도 건드리지 않는다.**

> 폐기된 대안: `Login.jsx`에 `useEffect(() => { if (!session) setProfileStep(false) })` 추가 — **정상 가입 플로우가 즉시 깨진다**(OTP 단계에서 `session`은 아직 null).

### 5.2 활동 감지
`['mousemove', 'keydown', 'input', 'scroll', 'click', 'touchstart']` → **1초 쓰로틀**로 `lastActive` 기록 + 타이머 리셋.

`input`이 필수다. `keydown`만으로는 모바일 **글라이드 입력·음성 입력·추천 단어·붙여넣기**가 "무활동"으로 잡힌다. `input`은 버블링되므로 document 바인딩으로 전부 포착된다.

### 5.3 재평가 지점
아래 **모두**에서 동일한 `checkExpiry()`를 호출한다 (초안의 "마운트 1회"로는 절전·bfcache 복귀에서 검사가 아예 안 돈다):

1. **마운트 즉시** 1회
2. **폴링** — `setInterval(checkExpiry, POLL_INTERVAL_MS)` (15초)
3. `document` `visibilitychange` → visible
4. `window` `focus`
5. `window` `pageshow` (bfcache 복원)
6. `window` `storage` (다른 탭 활동)

`checkExpiry()`는 **벽시계로 만료 여부만 판정**한다 — 만료면 로그아웃, 아니면 아무것도 하지 않는다(다음 틱이 다시 본다). **재무장·남은 시간 계산이 없다.**

3~6번이 필요한 이유: 백그라운드/절전에서 `setInterval`이 스로틀·정지되므로, **복귀 순간 즉시** 잡아야 한다(다음 틱을 기다리면 최대 15초 노출).

### 5.4 로그아웃 실행

```js
if (firing.current || !user) return
firing.current = true
const { error } = await logout({ scope: 'local' })   // ← 이 브라우저만 로그아웃
if (error) window.location.replace('/login')          // 하드 리로드로 메모리 상태 확실 제거
else navigate('/login', { replace: true, state: { reason: 'idle' } })
```

- **`scope: 'local'` 필수.** auth-js의 `signOut()` 기본값은 **`'global'`** 이라, 인자를 주지 않으면 **그 사용자의 모든 기기 세션이 폐기된다.** 유휴 로그아웃은 **사용자가 의도한 적이 없다** — 실습실 PC에 켜둔 탭이 30분 유휴로 자동 로그아웃되면서 **집에서 잘 쓰고 있던 폰까지 튕기면** 그냥 버그다. `'local'`은 이 브라우저만 끊는다. (수동 로그아웃도 같은 이유로 `'local'`로 바꾼다 — §3의 호출부 표)

- **`replace: true` 필수.** 기존 페이지 가드(`MyPage.jsx`, `Search.jsx`, `ExchangeCenter.jsx`, `WorksiteDetail.jsx`, `ReviewForm.jsx`)가 전부 `push`라, `push`로 이동하면 뒤로가기 시 **`/mypage` ↔ `/login` 핑퐁 트랩**에 갇힌다. 탈퇴 경로(`MyPage.jsx`)가 이미 `replace: true`라 관례도 일치한다.

### 5.5 로그아웃 중복 발화 가드 (`firing`)
`firing`은 **모듈 스코프 `let`이 아니라 컴포넌트 `ref`** 로 두고, **`user`가 falsy→truthy로 전이할 때 반드시 리셋**한다.

SPA라 로그아웃 → 재로그인 사이에 **페이지 리로드가 없다.** 가드를 리셋하지 않으면 `IdleLogout` 인스턴스와 플래그가 그대로 살아남아, **유휴 로그아웃이 페이지 로드당 딱 1회만 동작**한다(재로그인 후에는 영영 로그아웃되지 않음).

StrictMode 이중 마운트도 `ref`로 흡수한다(`Signup.jsx`의 `signUpStarted` 선례와 동일).

### 5.6 멀티탭
동기화의 근거는 **localStorage `lastActive` + `storage` 이벤트**다. 한 탭의 활동이 모든 탭의 벽시계를 갱신하므로, **유휴 탭이 활동 중인 탭을 죽이는 오판정**이 발생하지 않는다.

---

## 6. 엣지케이스

- **localStorage 접근 불가**(사파리 프라이빗 등) → `try/catch`. **읽기 경로에도 catch 필수.** 지속성만 포기하고 타이머는 계속 동작(앱은 죽지 않는다).
- 비로그인 / `needsProfile` → 완전 무동작.

---

## 7. 테스트

### 7.1 자동 (`web/src/lib/idle.test.js`, node env 유지)
- 경계값: 29:59 → false / **30:00 정각 → false**(초과해야 만료) / 30:01 → true
- 부재 → false
- `'abc'`·`NaN`·형 불일치 → **true** (fail-closed)
- **미래 타임스탬프**(skew 초과) → true / skew 이내 → false
- `uid` 불일치 → false(무시)

### 7.2 storage 래퍼
`getItem`/`setItem`이 throw하는 mock → **크래시 없이 지속성만 포기**하는지 (node env, 렌더 불필요).

### 7.3 수동 검증 체크리스트 (짧은 타임아웃 상수 주입) — 필수 5개
1. 로그아웃 → **재로그인 → 다시 유휴 → 또 로그아웃되는가** ← §5.5의 1회용 버그는 이걸로만 잡힌다
2. 탭을 백그라운드로 보내고 타임아웃 초과 → **복귀 즉시** 로그아웃되는가
3. 가입 프로필 단계(OTP 통과 후)에서 유휴 → **로그아웃되지 않는가**
4. 로그아웃 후 뒤로가기 → **핑퐁 없이** 이전 페이지로 가는가
5. 탭 2개: A 방치 + B에서 계속 활동 → **A가 B를 죽이지 않는가**

> jsdom + `@testing-library/react` 도입은 **Post-MVP 권고** (devDeps + vitest env 추가 필요).

---

## 8. 의존성

**없음 (의존성 0 추가).** §2 참조 — 폴링 구조에서 스케줄러 라이브러리가 할 일이 남지 않으며, `react-idle-timer`는 핵심 요구(알람을 `lastActive + 30분`에 맞추기)를 표현할 수 없어 폐기했다.

---

## 9. 이 PR 밖 — 조율 / 분리 항목

| 항목 | 이유 | 조치 |
|---|---|---|
| ~~`logout({ scope: 'local' })`~~ | **✅ 해소됨 — 현수 승인(2026-07-14).** `AuthContext.logout`이 `opts`를 받아 `signOut(opts)`로 넘기도록 한 줄 확장하고, 유휴 로그아웃은 `{ scope: 'local' }`로 호출한다(§3·§5.4). **이 계획에 포함**되며 더 이상 PR 밖 항목이 아니다 | — |
| **유휴 사유 토스트** (`Login.jsx` ~4줄) | 사용자가 이유도 모른 채 로그아웃된다. **경고 모달이 아니라 사후 1줄 안내**라 "모달 없음" 합의와 충돌하지 않음. `Login.jsx`에 `toast` state·`<Toast>`가 이미 있어 `useLocation().state?.reason === 'idle'`로 표시 가능 | 현수(인증 영역) **조율 후 별도 커밋.** 토스트 없어도 나머지 설계는 완결 |
| **ReviewForm 초안 저장** | 유휴 로그아웃 시 장문 리뷰가 전소. 단 유휴 로그아웃과 **독립적 가치**(탭 discard·네트워크 오류로도 소실) | **별도 PR 권장**, 유휴 로그아웃과 동시 출하 |
| **"브라우저 종료 = 로그아웃"** | §1의 미커버 범위. UX 비용 실재 | **백로그 / PM 결정** |
| **기존 spec 문구 정정** | `2026-07-10-account-withdrawal-design.md` B-2가 **45분**으로 적혀 있음 | **30분으로 갱신** |

---

## 10. 부록 — 적대적 검증 이력

이 설계는 초안에 대해 6개 관점(인증 경합 · 보안 실효성 · 탭/지속성 · 모바일 현실 · 플로우 회귀 · 테스트 공백)의 적대적 검증을 거쳤다. 제기된 33건이 3중 심판(반증 · "억까" 판정 · 수정안 비례성)을 통과했고, 그 결과 초안에서 다음이 **뒤집혔다**:

1. 마운트 지점 — `App()` 안 → **`<BrowserRouter>` 직속** (그대로 뒀으면 전 사용자 화이트스크린)
2. 만료 판정 — 인메모리 타이머 → **벽시계 `lastActive` 단일 진실원천**
3. `lastActive` 생명주기 — 로그아웃 시 삭제 → **삭제하지 않고 로그인 시 시딩** (fail-open 제거)
4. 활성 게이트 — `session` → **`user`**
5. 이동 — `push` → **`replace`**
6. 중복 가드 — 모듈 스코프 → **ref + 세션 전이 시 리셋**
7. 활동 이벤트 — **`input` 추가**
8. `lib/idle.js` — localStorage 포함 → **순수 판정만** (lib 계약 준수)
9. 목표 문구 — "공용 PC 보호" → **"자리 비움 보호"** (과장 정정)

### 10-2. 계획 수립 중 추가 개정 (2026-07-14)

10. **집행 방식 — "정확 재무장" → "주기적 폴링"(업계 표준), `react-idle-timer` 폐기 → 의존성 0**

계획을 쓰다 `react-idle-timer@5.7.3`의 `IIdleTimer` 타입 정의를 확인한 결과, **타임아웃을 동적으로 지정하는 API가 없어** 개정 설계의 "남은 시간만큼 재무장"을 표현할 수 없음이 드러났다(§2의 폐기 사유 참조).

그러나 근본적으로는, "정확 재무장"이라는 요구 자체가 **불필요한 정교화**였다. 표준 패턴인 **주기적 폴링**(15초마다 `now - lastActive > 30분?`)은 자가교정이라 절전·백그라운드 복귀를 자동으로 흡수하며, 30분 정책에 15초 오차는 무의미하다. 폴링을 택하면 재무장 로직·`msUntilExpiry`·스케줄러 라이브러리가 **전부 사라진다.**

**벽시계 단일 진실원천이라는 핵심은 그대로다.** 1~9의 다른 개정 사항도 전부 유지된다 — 바뀐 것은 "집행 방식"뿐이다.
