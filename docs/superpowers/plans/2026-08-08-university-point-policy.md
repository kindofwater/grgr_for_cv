# 대학별 포인트 정책 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 서울대에 한해 열람권 최소 상품을 1시간 → 5분으로, 광고 적립을 5P → 2P로 한시 조정한다.

**Architecture:** 대학별 값을 `university_point_policy` 표 한 곳에 두고, 값 계산은 헬퍼 함수 2개로 모아 RPC 4개가 공유한다. 되돌리기가 행 하나 삭제로 끝나야 해서 RPC 하드코딩 분기를 택하지 않았다. 프론트는 `lib/passes.js`가 분(minutes)을 **기본값 60**의 선택 인자로 받게 해서, 값을 안 넘기는 기존 호출부가 그대로 동작하게 한다.

**Tech Stack:** Supabase(Postgres) 마이그레이션 SQL, React + Vite, Vitest

## Global Constraints

- 서울대 값: `hour_pass_minutes = 5`, `ad_reward_points = 2`. 열람권 **가격은 5P 그대로** — `pass_price`는 건드리지 않는다.
- 마이그레이션 파일명은 손으로 짓지 말고 `cd web && npx supabase migration new university_point_policy`로 생성한다 (이 저장소는 수동 타임스탬프 작명으로 버전 충돌을 2회 겪었다).
- 마이그레이션 헤더 2줄 필수: `-- 목적: <한 줄>` / `-- 날짜: 2026-08-08 · 담당: 배경록`
- RPC 4개(`activate_pass`·`claim_ad_reward`·`get_ad_reward_status`·`_wallet`)는 **시그니처 불변** → `create or replace`, `DROP FUNCTION` 금지.
- ⚠️ **`search_path` 함정**: `activate_pass`·`get_ad_reward_status`·`_wallet`은 `set search_path = pg_catalog, pg_temp`다. 새 헬퍼를 반드시 `public.hour_pass_minutes_for(...)` / `public.ad_reward_points_for(...)`로 **완전 수식**해야 한다. 빠뜨리면 런타임에 함수를 못 찾는다. (`claim_ad_reward`만 `search_path = public`이지만 일관성을 위해 여기서도 수식한다.)
- ⚠️ **헬퍼는 security definer가 아니다.** 호출자 4개가 전부 `security definer`인 것에 의존한다. `university_point_policy`는 RLS 활성·정책 0건이라, 일반 사용자 컨텍스트에서 부르면 막히는 게 아니라 **0행을 보고 조용히 기본값으로 폴백해 틀린 값이 나온다.**
- 대학은 id를 박지 말고 `universities.name = '서울대학교'`로 찾는다.
- 마이그레이션 전체를 `begin;` / `commit;` 하나로 감싼다.
- 작업 브랜치는 이미 만들어진 **`feat/university-point-policy`**. 새로 파지 않는다.
- 커밋만 하고 **push 하지 않는다**. `supabase db push`도 실행하지 않는다.
- ⚠️ **배포 순서가 포인트 정책 v2와 반대다** — 프론트 먼저, DB 나중. 그래서 프론트 태스크(1·2)가 마이그레이션 태스크(3)보다 앞에 온다.

---

### Task 1: `lib/passes.js` — 분(minutes) 인자 도입

**Files:**
- Modify: `web/src/lib/passes.js`
- Test: `web/src/lib/passes.test.js`

**Interfaces:**
- Consumes: 없음 (첫 작업)
- Produces:
  - `passLabel(days, minutes = 60): string`
  - `passDuration(days, minutes = 60): string`
  - `nextExpiry(current, days, now = new Date(), minutes = 60): Date`
  - `passPrice(days)`·`PASS_DAYS`·`isPassActive`는 **변경 없음**

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`web/src/lib/passes.test.js` 맨 아래에 아래 블록을 덧붙인다. 기존 `describe`들은 건드리지 않는다 — 기본값 60이 기존 동작을 보존하는지가 회귀 방어선이다.

```js
describe('minutes 인자 (2026-08-08 대학별 정책)', () => {
  it('기본값 60이면 기존 표기 그대로 (회귀)', () => {
    expect(passLabel(0)).toBe('1시간 열람권')
    expect(passDuration(0)).toBe('1시간')
    expect(passLabel(7)).toBe('7일 열람권')
  })

  it('minutes=5면 5분 표기', () => {
    expect(passLabel(0, 5)).toBe('5분 열람권')
    expect(passDuration(0, 5)).toBe('5분')
  })

  it('60의 배수면 시간 단위로 표기', () => {
    expect(passLabel(0, 120)).toBe('2시간 열람권')
    expect(passDuration(0, 60)).toBe('1시간')
  })

  it('60의 배수가 아니면 분 단위로 표기', () => {
    expect(passLabel(0, 90)).toBe('90분 열람권')
  })

  it('일 단위 권은 minutes를 무시한다', () => {
    expect(passLabel(7, 5)).toBe('7일 열람권')
    expect(passDuration(30, 5)).toBe('30일')
  })

  it('nextExpiry는 minutes만큼 더한다', () => {
    const now = new Date('2026-08-08T00:00:00Z')
    expect(nextExpiry(null, 0, now, 5).toISOString()).toBe('2026-08-08T00:05:00.000Z')
    expect(nextExpiry(null, 0, now).toISOString()).toBe('2026-08-08T01:00:00.000Z')
  })

  it('nextExpiry는 활성 중이면 현재만료 기준으로 minutes를 더한다', () => {
    const now = new Date('2026-08-08T00:00:00Z')
    const cur = new Date('2026-08-08T02:00:00Z')
    expect(nextExpiry(cur, 0, now, 5).toISOString()).toBe('2026-08-08T02:05:00.000Z')
  })

  it('일 단위 권의 만료 계산은 minutes에 영향받지 않는다', () => {
    const now = new Date('2026-08-08T00:00:00Z')
    expect(nextExpiry(null, 7, now, 5).toISOString()).toBe(nextExpiry(null, 7, now).toISOString())
  })
})
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `cd web && npx vitest run src/lib/passes.test.js`
Expected: FAIL — `passLabel(0, 5)`가 `'1시간 열람권'`을 반환해 `'5분 열람권'`과 불일치

- [ ] **Step 3: 최소 구현**

`web/src/lib/passes.js`의 `passLabel`·`passDuration`·`nextExpiry` 세 함수를 아래로 교체한다. 파일 상단 주석(`// 0 = 1시간권 센티널 …`)도 함께 갱신한다.

기존:

```js
// 0 = 1시간권 센티널 — 서버 pass_price(p_days)와 동일 규칙(키·시그니처는 계속 '일' 단위)
```

변경:

```js
// 0 = 최소 상품 센티널 — 서버 pass_price(p_days)와 동일 규칙(키·시그니처는 계속 '일' 단위).
// 이 상품의 실제 지속시간은 대학마다 다르다(university_point_policy.hour_pass_minutes) —
// 서버 _wallet()이 hour_pass_minutes로 내려주고, 화면이 그 값을 아래 함수들에 넘긴다.
// 값을 안 넘기면 기본 60분이라 옛 호출부는 그대로 동작한다.
```

그리고 세 함수:

```js
// 최소 상품(days=0)의 기간 문구: 60의 배수면 시간, 아니면 분
function minuteText(minutes) {
  return minutes % 60 === 0 ? `${minutes / 60}시간` : `${minutes}분`
}

// 화면 공용 라벨: '1시간 열람권' / '5분 열람권' / 'N일 열람권'
export function passLabel(days, minutes = 60) {
  passPrice(days) // days 유효성 검증
  return days === 0 ? `${minuteText(minutes)} 열람권` : `${days}일 열람권`
}

// 문장 속 기간 표기: '1시간' / '5분' / 'N일'
export function passDuration(days, minutes = 60) {
  passPrice(days)
  return days === 0 ? minuteText(minutes) : `${days}일`
}

// 활성화 시 새 만료일: max(now, 현재만료) + 기간(최소 상품은 minutes분)
export function nextExpiry(current, days, now = new Date(), minutes = 60) {
  passPrice(days) // days 유효성 검증 (잘못되면 throw)
  const cur = current ? new Date(current) : null
  const base = cur && cur > now ? cur : now
  const result = new Date(base)
  if (days === 0) result.setTime(result.getTime() + minutes * 60 * 1000)
  else result.setDate(result.getDate() + days)
  return result
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd web && npx vitest run src/lib/passes.test.js`
Expected: PASS — 기존 테스트 전부 포함해 통과

- [ ] **Step 5: 커밋**

```bash
git add web/src/lib/passes.js web/src/lib/passes.test.js
git commit -F - <<'EOF'
feat: 열람권 최소 상품의 지속시간을 인자로 받게 변경

대학별로 다른 값(university_point_policy.hour_pass_minutes)을 화면이
넘길 수 있게 minutes를 선택 인자로 추가한다. 기본값 60이라 값을 안
넘기는 기존 호출부는 그대로 동작한다.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 2: 화면 배선 — 교환센터·마이페이지

**Files:**
- Modify: `web/src/pages/ExchangeCenter.jsx` (56·191·214·219·230·243행 부근)
- Modify: `web/src/pages/MyPage.jsx:507`

**Interfaces:**
- Consumes: Task 1의 `passLabel(days, minutes)`·`passDuration(days, minutes)`·`nextExpiry(current, days, now, minutes)`
- Produces: 없음 (화면 문구만)

두 화면 모두 `fetchWallet()`(= 서버 `_wallet()`)로 지갑을 받는다. Task 3이 거기에 `hour_pass_minutes`를 실어 보낸다. **이 태스크 시점에는 서버가 아직 그 필드를 안 주므로 `undefined`가 되고, 기본값 60이 적용돼 화면은 지금과 똑같이 동작한다.** 이게 정상이다 — 프론트를 먼저 배포해도 안전한 이유다.

- [ ] **Step 1: `ExchangeCenter.jsx`에 지속시간 변수를 만든다**

`wallet` 상태를 읽는 곳 근처(컴포넌트 본문 상단, `wallet`이 정의된 뒤)에 아래를 추가한다:

```jsx
  // 최소 상품(0)의 지속시간 — 서버 _wallet()이 대학별 값을 준다. 없으면 60분(기본 정책).
  const hourPassMinutes = wallet?.hour_pass_minutes ?? 60
```

- [ ] **Step 2: `ExchangeCenter.jsx`의 호출부 6곳에 값을 넘긴다**

`passLabel(d)` → `passLabel(d, hourPassMinutes)`, `passDuration(d)` → `passDuration(d, hourPassMinutes)`로 바꾼다. 대상은 191·214·219(2곳: `passLabel`과 `passDuration`)·224·230·243행의 호출이다.

- [ ] **Step 2-b: `expiryMonthDayLabel`에 `minutes`를 받게 한다**

⚠️ `expiryMonthDayLabel`은 컴포넌트 **바깥**(54-55행)에 정의된 함수라 `hourPassMinutes`를 클로저로 볼 수 없다. 시그니처에 인자를 추가한다.

54-56행:

```jsx
// 구매 직후 모달용 만료 표기 — 일 단위 권은 'N월 N일', 1시간권은 'N월 N일 HH:mm'
function expiryMonthDayLabel(currentExpiry, days) {
  const expiry = nextExpiry(parseServerDate(currentExpiry), days)
```

→

```jsx
// 구매 직후 모달용 만료 표기 — 일 단위 권은 'N월 N일', 시/분 단위 권은 'N월 N일 HH:mm'
function expiryMonthDayLabel(currentExpiry, days, minutes = 60) {
  const expiry = nextExpiry(parseServerDate(currentExpiry), days, new Date(), minutes)
```

함수의 나머지 본문(57행 이하 `Intl.DateTimeFormat` 부분)은 **건드리지 않는다.**

그리고 230행의 호출부:

```jsx
${expiryMonthDayLabel(purchasedWallet.pass_expires_at, d)}
```

→

```jsx
${expiryMonthDayLabel(purchasedWallet.pass_expires_at, d, hourPassMinutes)}
```

47행 주석의 `1시간권 도입으로` 도 `시/분 단위 권 도입으로`로 고친다.

190행의 주석(`사이드바는 3열이라 짧은 라벨(1시간권·7일권·30일권)`)도 값이 고정이 아니게 됐으니 `짧은 라벨(최소상품권·7일권·30일권)`으로 고친다.

- [ ] **Step 3: `MyPage.jsx:507`에도 같은 값을 넘긴다**

507행:

```jsx
                  <span className="mw-pass-name">{passLabel(d)}</span>
```

→

```jsx
                  <span className="mw-pass-name">{passLabel(d, wallet?.hour_pass_minutes ?? 60)}</span>
```

> `MyPage`의 `wallet` 초기값은 `AuthContext`의 `user`에서 오고 거기엔 `hour_pass_minutes`가 없다. 따라서 첫 렌더는 60분 기준으로 그렸다가 `fetchWallet()` 응답 후 정확한 값으로 바뀐다. 서울대 유저에게 "1시간 열람권"이 잠깐 스쳤다가 "5분 열람권"이 되는데, 지갑 카드가 로딩 후 갱신되는 기존 동작과 같은 성격이라 그대로 둔다.

- [ ] **Step 4: 남은 호출부가 없는지 확인**

Run: `cd web && grep -rn "passLabel(\|passDuration(\|nextExpiry(" src/ | grep -v "lib/passes"`
Expected: 모든 호출이 두 번째(또는 네 번째) 인자를 넘기고 있다. 안 넘기는 게 남아 있으면 그 화면은 항상 60분으로 표시된다 — 의도한 것인지 확인하고, 아니면 넘긴다.

- [ ] **Step 5: 테스트·빌드·린트 확인**

Run: `cd web && npm run test`
Expected: 전부 PASS

Run: `cd web && npm run build`
Expected: 빌드 성공

Run: `cd web && npx eslint src/pages/ExchangeCenter.jsx src/pages/MyPage.jsx`
Expected: 새 에러 0 (기존 에러가 있으면 `git stash` 비교로 사전 존재 여부를 확인하고 보고)

- [ ] **Step 6: 커밋**

```bash
git add web/src/pages/ExchangeCenter.jsx web/src/pages/MyPage.jsx
git commit -F - <<'EOF'
feat: 열람권 표기에 대학별 지속시간 반영

교환센터·마이페이지가 지갑의 hour_pass_minutes를 passes 함수에 넘긴다.
서버가 아직 그 필드를 안 주는 동안에는 기본값 60분이 적용돼 화면 동작이
지금과 같다 — 프론트를 먼저 배포해도 안전하다.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 3: 마이그레이션 — 표·헬퍼·RPC 4개·재고 방어·공지

**Files:**
- Create: `web/supabase/migrations/<CLI가 생성한 타임스탬프>_university_point_policy.sql`

**Interfaces:**
- Consumes: 없음 (서버 단독)
- Produces: `_wallet()` 응답에 `hour_pass_minutes` 키 — Task 2의 화면이 이걸 읽는다

- [ ] **Step 1: 마이그레이션 파일을 CLI로 생성한다**

```bash
cd web && npx supabase migration new university_point_policy
```

Expected: `web/supabase/migrations/2026XXXXXXXXXX_university_point_policy.sql` 생성. **파일명을 손으로 바꾸지 않는다.**

- [ ] **Step 2: 헤더 + 표 + 헬퍼 2개를 쓴다**

```sql
-- 목적: 대학별 포인트 정책 도입 — 서울대 한시 조정(최소 열람권 60분→5분, 광고 적립 5P→2P).
-- 날짜: 2026-08-08 · 담당: 배경록
--
-- 왜 표인가: 리뷰가 쌓이면 되돌릴 한시 조치다. RPC에 대학 id를 박으면 되돌릴 때 본문을 또
--   replace해야 하는데, 이 저장소는 본문 복사로 로직이 조용히 사라지는 사고를 두 번 겪었다
--   (대학 스코프 검사 유실 → 20260808120745로 복구). 표로 두면 원복이 행 삭제 한 줄이다.
--
-- 되돌리기: delete from public.university_point_policy where university_id = <서울대 id>;
--   헬퍼가 없는 행을 60분·전역 5P로 폴백하므로 RPC는 손댈 필요가 없다. 공지도 함께 정리할 것.

begin;

-- ── 1) 대학별 정책 표 ──
-- ad_reward_points가 null이면 전역 ad_reward_config를 쓴다(전역 기본이 바뀌면 자동 추종).
-- ad_reward_config의 check (id = 1)은 건드리지 않는다 — 전역 기본값 자리로 유지.
create table if not exists public.university_point_policy (
  university_id     int primary key references public.universities(id) on delete cascade,
  hour_pass_minutes int not null default 60 check (hour_pass_minutes between 1 and 1440),
  ad_reward_points  int check (ad_reward_points >= 0),
  note              text,
  updated_at        timestamptz not null default now()
);

-- 클라이언트 직접 접근 차단 — 읽기는 아래 헬퍼(내부 전용)로만.
alter table public.university_point_policy enable row level security;
revoke all on public.university_point_policy from anon, authenticated;

-- ── 2) 공유 헬퍼 — 값 계산을 한 곳으로 모은다 ──
-- ⚠️ security definer 아님. 호출자 4개가 전부 security definer인 것에 의존한다.
--    security invoker 경로에서 부르면 RLS(정책 0건) 때문에 0행을 보고 조용히 기본값으로
--    폴백한다 — 막히는 게 아니라 틀린 값이 나온다. 새 호출부를 만들 때 반드시 확인할 것.
create or replace function public.hour_pass_minutes_for(p_uid uuid)
returns int
language sql
stable
set search_path = public
as $$
  select coalesce(
    (select p.hour_pass_minutes
       from public.university_point_policy p
       join public.users u on u.university_id = p.university_id
      where u.id = p_uid),
    60)
$$;

create or replace function public.ad_reward_points_for(p_uid uuid)
returns int
language sql
stable
set search_path = public
as $$
  select coalesce(
    (select p.ad_reward_points
       from public.university_point_policy p
       join public.users u on u.university_id = p.university_id
      where u.id = p_uid),
    (select c.reward_points from public.ad_reward_config c where c.id = 1))
$$;

revoke execute on function public.hour_pass_minutes_for(uuid) from public, anon, authenticated;
revoke execute on function public.ad_reward_points_for(uuid)  from public, anon, authenticated;

-- ── 3) 서울대 시드 ──
-- 대학 id를 박지 않고 이름으로 찾는다. 재실행 시 값을 수렴시킨다.
insert into public.university_point_policy (university_id, hour_pass_minutes, ad_reward_points, note)
select u.id, 5, 2, '서울대 리뷰 부족 — 리뷰 선순환을 위한 한시 조정. 되돌릴 때 이 행을 삭제'
from public.universities u
where u.name = '서울대학교'
on conflict (university_id) do update
  set hour_pass_minutes = excluded.hour_pass_minutes,
      ad_reward_points  = excluded.ad_reward_points,
      note              = excluded.note,
      updated_at        = now();
```

- [ ] **Step 3: `_wallet`과 `activate_pass`를 교체한다**

두 함수 모두 `search_path = pg_catalog, pg_temp`다 — 헬퍼를 `public.`으로 완전 수식한 것을 확인하며 쓴다. 본문은 각 최신본(`_wallet`: 20260801074833 / `activate_pass`: 20260801071450) 그대로에 표시한 부분만 바꾼다.

```sql
-- ── 4) _wallet — 응답에 hour_pass_minutes 추가 ──
-- 반환이 jsonb라 시그니처 불변. 구 프론트는 모르는 키를 무시하므로 배포 순서에 안전하다.
create or replace function public._wallet()
returns jsonb
language sql
security definer
set search_path = pg_catalog, pg_temp
as $$
  select jsonb_build_object(
    'point_balance',     u.point_balance,
    'pass_balances',     coalesce(u.pass_balances, '{}'::jsonb),
    'pass_expires_at',   u.pass_expires_at,
    'hour_pass_minutes', public.hour_pass_minutes_for(u.id)
  )
  from public.users u
  where u.id = auth.uid()
$$;

revoke execute on function public._wallet() from public, anon;
grant execute on function public._wallet() to authenticated;

-- ── 5) activate_pass — 최소 상품(p_days=0)의 지속시간을 대학별로 ──
-- 본문은 20260801071450 그대로, interval '1 hour' 자리만 헬퍼로 교체. 시그니처 불변.
create or replace function public.activate_pass(p_days int)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_rows int;
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  if public.pass_price(p_days) is null then
    raise exception 'INVALID_DAYS';
  end if;

  update public.users u
  set pass_balances = case
        when coalesce((u.pass_balances ->> p_days::text)::int, 0) = 1
          then coalesce(u.pass_balances, '{}'::jsonb) - p_days::text
        else jsonb_set(
          coalesce(u.pass_balances, '{}'::jsonb),
          array[p_days::text],
          to_jsonb(coalesce((u.pass_balances ->> p_days::text)::int, 0) - 1),
          true
        )
      end,
      pass_expires_at = greatest(now(), coalesce(u.pass_expires_at, now()))
        + case
            when p_days = 0
              then public.hour_pass_minutes_for(v_uid) * interval '1 minute'
            else (p_days || ' days')::interval
          end
  where u.id = v_uid
    and coalesce((u.pass_balances ->> p_days::text)::int, 0) >= 1;

  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    raise exception 'NO_PASS_STOCK';
  end if;

  return public._wallet();
end;
$$;
```

- [ ] **Step 4: 광고 RPC 2개를 교체한다**

⚠️ **`claim_ad_reward`는 `v_cfg.reward_points`를 두 곳(원장 insert + 잔액 update)에서 쓴다. 둘 다 바꿔야 한다** — 한쪽만 고치면 원장과 잔액이 어긋난다.

```sql
-- ── 6) claim_ad_reward — 적립액을 대학별로 ──
-- 본문은 20260713164934 그대로, 적립액 산출만 헬퍼로 교체(원장·잔액 두 곳 모두).
-- daily_cap·cooldown은 전역 유지 — 이번 조정 대상이 아니다.
create or replace function public.claim_ad_reward(p_token uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_view ad_views;
  v_min int;
  v_cfg ad_reward_config;
  v_today int;
  v_rows int;
  v_amount int;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;

  -- H3: 사용자 행 잠금 — 같은 유저의 동시 claim을 직렬화. 뒤따르는 트랜잭션은
  -- 앞선 커밋 이후의 claimed 집계를 보게 되어 cap 검사(count-then-act)가 유효해진다.
  perform 1 from users where id = v_uid for update;

  -- H2: 대상 시청 행도 잠금 — 같은 토큰 동시 호출이 여기서 줄을 선다.
  select * into v_view from ad_views
    where token = p_token and user_id = v_uid and claimed_at is null
    for update;
  if v_view.id is null then raise exception 'INVALID_TOKEN'; end if;

  select coalesce(min_view_seconds, 5) into v_min from ads where id = v_view.ad_id;
  if now() < v_view.created_at + (coalesce(v_min,5) * interval '1 second') then
    raise exception 'TOO_SOON';
  end if;

  select * into v_cfg from ad_reward_config where id = 1;
  if v_cfg.id is null then raise exception 'NO_CONFIG'; end if;

  select count(*) into v_today from ad_views
    where user_id = v_uid and claimed_at is not null and claimed_at::date = current_date;
  if v_today >= v_cfg.daily_cap then raise exception 'CAP_REACHED'; end if;

  -- 대학별 적립액 — get_ad_reward_status가 화면에 보여주는 값과 같은 헬퍼를 쓴다.
  v_amount := public.ad_reward_points_for(v_uid);

  -- 조건부 UPDATE + row_count 확인: 락을 못 잡는 경로가 생겨도 이중 적립 불가
  update ad_views set claimed_at = now() where id = v_view.id and claimed_at is null;
  get diagnostics v_rows = row_count;
  if v_rows = 0 then raise exception 'INVALID_TOKEN'; end if;

  insert into points (user_id, amount, reason, ad_view_id) values (v_uid, v_amount, 'ad_view', v_view.id);
  update users set point_balance = point_balance + v_amount where id = v_uid;
  return _wallet();
end $$;

-- ── 7) get_ad_reward_status — 화면에 보여줄 적립액도 같은 헬퍼로 ──
-- 본문은 20260802002643 그대로, reward_points 산출만 교체. daily_cap·cooldown은 전역 유지.
create or replace function public.get_ad_reward_status()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_daily_cap integer;
  v_reward_points integer;
  v_cooldown_minutes integer;
  v_claimed_today integer;
  v_last_claimed_at timestamptz;
  v_cooldown_until timestamptz;
  v_available boolean;
  v_reason text;
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select c.daily_cap, c.cooldown_minutes
    into v_daily_cap, v_cooldown_minutes
  from public.ad_reward_config c
  where c.id = 1;

  if not found then
    raise exception 'NO_CONFIG';
  end if;

  v_reward_points := public.ad_reward_points_for(v_uid);

  select count(*)::integer, max(v.claimed_at)
    into v_claimed_today, v_last_claimed_at
  from public.ad_views v
  where v.user_id = v_uid
    and v.claimed_at is not null
    and v.claimed_at::date = current_date;

  v_cooldown_until := case
    when v_cooldown_minutes > 0 and v_last_claimed_at is not null
      then v_last_claimed_at + (v_cooldown_minutes * interval '1 minute')
    else null
  end;

  if v_claimed_today >= v_daily_cap then
    v_available := false;
    v_reason := 'CAP_REACHED';
  elsif v_cooldown_until is not null and now() < v_cooldown_until then
    v_available := false;
    v_reason := 'COOLDOWN';
  else
    v_available := true;
    v_reason := null;
  end if;

  return jsonb_build_object(
    'available', v_available,
    'unavailable_reason', v_reason,
    'daily_cap', v_daily_cap,
    'claimed_today', v_claimed_today,
    'remaining_today', greatest(v_daily_cap - v_claimed_today, 0),
    'reward_points', v_reward_points,
    'cooldown_until', v_cooldown_until
  );
end;
$$;
```

- [ ] **Step 5: 재고 방어 블록을 쓴다**

```sql
-- ── 8) 기존 1시간권 재고 방어 환불 ──
-- 2026-08-08 조회 기준 서울대 유저의 미사용 최소상품 재고는 0건이었다. 조회와 적용 사이에
-- 누가 살 수 있으므로, 남아 있으면 산 값(pass_price(0)=5P)만큼 환급하고 키를 제거한다.
-- 예상 결과는 0행이며, 생기면 5P 주고 산 상품이 말없이 1/12로 깎이는 것을 막는다.
-- 0 재고 키를 남기지 않는 규약은 20260801071450과 같다.
with target as (
  select u.id as user_id,
         coalesce((u.pass_balances ->> '0')::int, 0) as stock
  from public.users u
  join public.universities un on un.id = u.university_id
  join public.university_point_policy p on p.university_id = u.university_id
  where un.name = '서울대학교'
    and p.hour_pass_minutes < 60
    and coalesce((u.pass_balances ->> '0')::int, 0) > 0
), refunded as (
  insert into public.points (user_id, amount, reason)
  select t.user_id, t.stock * public.pass_price(0), 'pass_refund'
  from target t
  returning user_id, amount
)
update public.users u
set pass_balances = coalesce(u.pass_balances, '{}'::jsonb) - '0',
    point_balance = u.point_balance + r.amount
from refunded r
where u.id = r.user_id;
```

- [ ] **Step 6: 공지 + `commit;`을 쓴다**

`20260727103000_insert_review_event_notices.sql`이 대학 전용 공지의 선례다. 제목 기준 upsert로 멱등하게 만든다.

```sql
-- ── 9) 서울대 전용 공지 ──
-- university_id를 서울대로 한정해 다른 학교엔 안 보인다. is_pinned=false(고정은 필독 공지만).
-- 제목 기준 upsert라 재실행·db reset에 안전하다.
do $$
declare
  v_uni_id integer;
  v_notice_id integer;
  v_content text := $notice$안녕하세요, 근로고래입니다. 🐳

서울대학교 이용자분들께 열람권과 포인트 적립 관련 한시 조정을 안내드립니다.

1. 무엇이 바뀌나요

• 최소 열람권: 1시간 → 5분 (가격은 5P 그대로입니다)
• 광고 시청 적립: 1편당 5P → 2P

7일 열람권(20P)과 30일 열람권(35P)의 기간과 가격은 그대로입니다.

2. 왜 조정하나요

서울대학교는 아직 서비스 초기 단계입니다. 리뷰가 충분히 모여야 열람권의 가치도 살아나기 때문에, 리뷰가 쌓이는 선순환이 자리잡을 때까지 한시적으로 조정했습니다.

3. 언제 되돌리나요

리뷰가 충분히 모이면 다른 학교와 동일한 기준으로 되돌립니다. 되돌릴 때 공지로 다시 안내드리겠습니다.

이용에 불편을 드려 죄송합니다. 더 나은 정보를 더 빨리 드릴 수 있도록 하겠습니다.

감사합니다.
근로고래 드림$notice$;
begin
  select id into v_uni_id from public.universities where name = '서울대학교';
  if v_uni_id is null then
    raise exception '서울대학교 대학 행을 찾지 못해 공지 등록을 중단합니다';
  end if;

  select id into v_notice_id
  from public.notices
  where university_id = v_uni_id
    and title = '[안내] 서울대 열람권·적립 한시 조정'
  order by id
  limit 1;

  if v_notice_id is null then
    insert into public.notices (title, content, is_pinned, university_id)
    values ('[안내] 서울대 열람권·적립 한시 조정', v_content, false, v_uni_id);
  else
    update public.notices
    set content = v_content, updated_at = now()
    where id = v_notice_id;
  end if;
end
$$;

commit;
```

- [ ] **Step 7: 파일이 온전한지 확인한다**

```bash
MIG=$(ls web/supabase/migrations/*_university_point_policy.sql)
grep -c "^begin;" "$MIG"                                   # 1
grep -c "^commit;" "$MIG"                                  # 1
grep -c "create or replace function" "$MIG"                # 6 (헬퍼2 + RPC4)
grep -c "DROP FUNCTION\|drop function" "$MIG"              # 0
grep -c "interval '1 hour'" "$MIG"                         # 0  ← 남아 있으면 교체 누락
grep -c "v_cfg.reward_points" "$MIG"                       # 0  ← 남아 있으면 적립액 교체 누락
grep -c "public.hour_pass_minutes_for\|public.ad_reward_points_for" "$MIG"   # 5 이상
```

Expected: 주석의 숫자와 일치. 특히 `interval '1 hour'`와 `v_cfg.reward_points`가 **0건**이어야 한다.

- [ ] **Step 8: 커밋**

```bash
git add web/supabase/migrations/
git commit -F - <<'EOF'
feat(db): 대학별 포인트 정책 — 서울대 5분 열람권 + 광고 2P

university_point_policy 표와 헬퍼 2개를 두고, RPC 4개가 그 헬퍼를
공유하게 한다. 값을 각자 계산하면 화면엔 5P·지급은 2P로 갈리므로
계산을 한 곳으로 모았다.

되돌리기는 행 하나 삭제로 끝난다 — 헬퍼가 60분·전역 5P로 폴백한다.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 4: 문서 갱신

**Files:**
- Modify: `web/supabase/README.md` (migrations 목록)
- Modify: `web/src/lib/README.md` (`passes.js` 설명)

**Interfaces:**
- Consumes: Task 3의 마이그레이션 파일명(타임스탬프)

- [ ] **Step 1: `web/supabase/README.md`에 항목을 추가한다**

`20260808120745_restore_review_university_scope.sql` 항목 **아래**에 넣는다 (타임스탬프는 Task 3에서 CLI가 만든 실제 값으로 채운다):

```markdown
  - `<타임스탬프>_university_point_policy.sql` = **push 대기** — **대학별 포인트 정책 도입 + 서울대 한시 조정**: ①`university_point_policy` 표 신설(`university_id` PK · `hour_pass_minutes` not null default 60 · `ad_reward_points` nullable(null이면 전역 `ad_reward_config` 추종) · `note`). RLS 활성·정책 0건으로 클라 직접 접근 차단 ②**공유 헬퍼 2개** `hour_pass_minutes_for(uuid)`·`ad_reward_points_for(uuid)` — 값 계산을 한 곳으로 모아 RPC 간 드리프트를 구조적으로 차단(각자 계산하면 화면엔 5P·지급은 2P로 갈린다) ③RPC 4개 replace(시그니처 전부 불변): `activate_pass`(최소상품 지속시간), `claim_ad_reward`(적립액 — **원장·잔액 두 곳 모두**), `get_ad_reward_status`(표시 적립액), `_wallet`(`hour_pass_minutes` 키 추가) ④서울대 시드 `hour_pass_minutes=5, ad_reward_points=2` ⑤서울대 미사용 최소상품 재고 방어 환불(적용 시점 0행 예상) ⑥서울대 전용 공지. ⚠️ **헬퍼는 security definer가 아니다** — 호출자 4개가 전부 definer인 것에 의존한다. security invoker 경로에서 부르면 RLS 때문에 0행을 보고 **조용히 기본값으로 폴백해 틀린 값이 나온다**(막히지 않는다). ⚠️ `activate_pass`·`get_ad_reward_status`·`_wallet`은 `search_path = pg_catalog, pg_temp`라 헬퍼를 `public.`으로 완전 수식해야 한다. ⚠️ **배포 순서가 포인트 정책 v2와 반대** — 프론트 먼저, DB 나중(프론트만 먼저 나가면 기본값 60분으로 무해, DB만 먼저 나가면 "1시간"이라 적힌 상품이 5분을 준다). **되돌리기**: `delete from public.university_point_policy where university_id = <서울대 id>;` 한 줄 — RPC 무수정, 프론트도 자동 복귀. 공지도 함께 정리할 것. 담당 배경록. spec `docs/superpowers/specs/2026-08-08-university-point-policy-design.md` · plan `docs/superpowers/plans/2026-08-08-university-point-policy.md`.
```

- [ ] **Step 2: `web/src/lib/README.md`의 `passes.js` 설명을 갱신한다**

25행의 항목:

```markdown
| `passes.js` | 열람권 가격·만료 계산 (`passPrice`, `nextExpiry`, `PASS_DAYS`) |
```

를 이렇게 바꾼다:

```markdown
| `passes.js` | 열람권 가격·표기·만료 계산 (`passPrice`, `passLabel`, `passDuration`, `nextExpiry`, `PASS_DAYS`). 최소 상품(0)의 지속시간은 대학마다 다르므로 `minutes` 인자로 받는다(기본 60) |
```

- [ ] **Step 3: 커밋**

```bash
git add web/supabase/README.md web/src/lib/README.md
git commit -F - <<'EOF'
docs: 대학별 포인트 정책 마이그레이션 기록

web/supabase/README.md에 항목을 추가하고, lib/README.md의 passes.js
설명에 minutes 인자를 반영한다.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

## 배포 (사용자가 직접 — 에이전트가 실행하지 않는다)

⚠️ **포인트 정책 v2와 순서가 반대다. 프론트 먼저, DB 나중.**

1. 디스코드에 한 마디 (CLAUDE.md §3-1)
2. prod 프론트 배포: `main` 머지 → `prod` 머지 → `git push origin prod`
   - 이 시점엔 서버가 `hour_pass_minutes`를 안 주므로 기본값 60분 — 화면·동작 모두 지금과 같다
3. `cd web && npx supabase migration list` — **대기 목록부터 확인**(남의 미적용분이 함께 나간다)
4. `cd web && npx supabase db push`
5. push 직후 서울대 계정으로 교환센터를 열어 "5분 열람권"·"광고 1편당 2P"가 보이는지 확인

## 검증 한계

로컬 `supabase db reset`은 이 환경에 Docker가 없어 돌릴 수 없다. 서버 SQL은 읽기 검토 + push 후 실측(5단계)으로 갈음한다.
