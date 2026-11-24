# 포인트 정책 v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 가입 축하금 5P 지급을 종료하고, 리뷰 적립을 실명 30P·익명 20P로 올리며, 리뷰를 2개 이상 쓴 유저에게 `(살아있는 리뷰 수 − 1) × 5P`를 소급 지급한다.

**Architecture:** DB 변경은 마이그레이션 **1개 파일**에 전부 담는다 — 적립가 변경과 소급 지급이 같은 트랜잭션에서 끝나야 그 사이 들어온 리뷰가 어중간한 금액으로 적립되지 않는다. RPC는 셋 다 시그니처가 그대로라 `create or replace`면 되고 `DROP FUNCTION`은 필요 없다. 프론트는 리뷰 적립가 상수를 `web/src/lib/points.js`로 끌어올려 단위 테스트를 붙이고, `ReviewForm`·`ExchangeCenter`가 그 상수를 참조하게 한다.

**Tech Stack:** Supabase(Postgres) 마이그레이션 SQL, React + Vite, Vitest

## Global Constraints

- 마이그레이션 파일 맨 위 헤더 2줄 필수: `-- 목적: <한 줄>` / `-- 날짜: 2026-08-08 · 담당: 배경록`
- 마이그레이션 파일명은 **손으로 짓지 말고** `cd web && npx supabase migration new point_policy_v2_and_drop_signup_bonus` 로 생성한다 (과거 수동 타임스탬프 작명으로 버전 충돌 2회 발생).
- 리뷰 적립가: 닉네임 공개 **30P**, 익명 **20P**.
- 소급 지급 금액: 유저별 대상 리뷰 중 가장 오래된 1건(최소 `id`)을 제외한 각 리뷰에 **+5P**, `reason='review_policy_grant'`, `review_id` 지정.
- 소급 대상 리뷰 집합: `user_id is not null` + `deleted_at is null` + `points` 원장에 `reason='review_write'` 행이 있는 리뷰.
- `MyPage.jsx` 의 `signup_bonus: '가입 축하금'` 라벨은 **삭제하지 않는다** (기존 유저 내역에 원장 행이 남아 있음).
- 이미 지급된 가입 축하금은 회수하지 않는다.
- 과거 날짜 업데이트 공지(`[업데이트] 8월 1일` 안의 "15P → 25P" 이력)는 **수정하지 않는다** — 그 시점의 사실 기록이다.
- 작업 브랜치는 이미 만들어진 **`feat/point-policy-v2`**. 새 브랜치를 파지 않는다.
- 커밋만 하고 **push 하지 않는다**.

---

### Task 1: 리뷰 적립가 상수를 lib으로 끌어올리기

지금 적립가는 `ReviewForm.jsx` 안의 지역 상수와 `ExchangeCenter.jsx` 안의 문자열 리터럴로 **이중 소스**다. 값을 바꾸는 작업이니 이번에 `lib`으로 모아 테스트를 붙인다. `web/src/lib/README.md` 규칙대로 lib은 순수 함수 + 테스트다.

**Files:**
- Modify: `web/src/lib/points.js`
- Test: `web/src/lib/points.test.js`

**Interfaces:**
- Consumes: 없음 (첫 작업)
- Produces:
  - `export const PUBLIC_REVIEW_POINTS = 30`
  - `export const ANONYMOUS_REVIEW_POINTS = 20`
  - `export function reviewPoints(isAnonymous: boolean): number` — `isAnonymous` 가 truthy면 20, 아니면 30

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`web/src/lib/points.test.js` 파일 **맨 위**의 import 줄에 `reviewPoints`, `PUBLIC_REVIEW_POINTS`, `ANONYMOUS_REVIEW_POINTS` 를 추가한다. 기존 import 줄이 이런 모양이면:

```js
import { computeRunningBalance } from './points'
```

이렇게 바꾼다:

```js
import {
  computeRunningBalance,
  reviewPoints,
  PUBLIC_REVIEW_POINTS,
  ANONYMOUS_REVIEW_POINTS,
} from './points'
```

(파일이 `vitest` 에서 `describe`/`it`/`expect` 를 import 하고 있으면 그 줄은 그대로 둔다.)

그리고 파일 **맨 아래**에 아래 블록을 덧붙인다:

```js
describe('reviewPoints', () => {
  it('닉네임 공개 리뷰는 30P', () => {
    expect(reviewPoints(false)).toBe(30)
    expect(PUBLIC_REVIEW_POINTS).toBe(30)
  })

  it('익명 리뷰는 20P', () => {
    expect(reviewPoints(true)).toBe(20)
    expect(ANONYMOUS_REVIEW_POINTS).toBe(20)
  })

  it('isAnonymous가 undefined/null이면 닉네임 공개로 본다', () => {
    expect(reviewPoints(undefined)).toBe(30)
    expect(reviewPoints(null)).toBe(30)
  })

  it('실명과 익명의 차이는 10P', () => {
    expect(PUBLIC_REVIEW_POINTS - ANONYMOUS_REVIEW_POINTS).toBe(10)
  })
})
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `cd web && npx vitest run src/lib/points.test.js`
Expected: FAIL — `reviewPoints is not a function` (또는 `No test found`가 아니라 import 관련 에러)

- [ ] **Step 3: 최소 구현**

`web/src/lib/points.js` **맨 위**(기존 `computeRunningBalance` 주석 위)에 아래를 추가한다:

```js
// 리뷰 적립 포인트 (2026-08-08 정책 v2). 서버 RPC write_review_with_points·
// update_review_with_points의 상수와 동일해야 한다 — 바꿀 땐 마이그레이션과 함께.
export const PUBLIC_REVIEW_POINTS = 30
export const ANONYMOUS_REVIEW_POINTS = 20

export function reviewPoints(isAnonymous) {
  return isAnonymous ? ANONYMOUS_REVIEW_POINTS : PUBLIC_REVIEW_POINTS
}

```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd web && npx vitest run src/lib/points.test.js`
Expected: PASS (기존 `computeRunningBalance` 테스트 포함 전부 통과)

- [ ] **Step 5: 커밋**

```bash
git add web/src/lib/points.js web/src/lib/points.test.js
git commit -F - <<'EOF'
feat: 리뷰 적립가 상수를 lib/points로 이동 (실명 30P·익명 20P)

ReviewForm의 지역 상수와 ExchangeCenter의 문자열 리터럴로 이중 소스였다.
값을 바꾸는 김에 lib으로 모아 테스트를 붙인다.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 2: 프론트 — 리뷰 작성 화면·교환센터 적립가 반영

**Files:**
- Modify: `web/src/pages/ReviewForm.jsx` (21-22행 상수, 122행 주석, import 블록)
- Modify: `web/src/pages/ExchangeCenter.jsx:283`, `web/src/pages/ExchangeCenter.jsx:285`

**Interfaces:**
- Consumes: Task 1의 `reviewPoints`, `PUBLIC_REVIEW_POINTS`, `ANONYMOUS_REVIEW_POINTS` (`web/src/lib/points.js`)
- Produces: 없음 (화면 문구만)

- [ ] **Step 1: `ReviewForm.jsx` 의 지역 상수를 lib import로 교체**

21-22행의 이 두 줄을 **삭제**한다:

```js
const PUBLIC_REVIEW_POINTS = 25;
const ANONYMOUS_REVIEW_POINTS = 15;
```

그리고 파일 상단 import 블록 — `import { useAuth } from "../components/AuthContext";` 바로 **아래**에 추가한다:

```js
import { reviewPoints } from "../lib/points";
```

> `pages → lib` 방향이라 CLAUDE.md의 의존성 규칙(역방향 import 금지)에 맞는다.
> 상수 두 개가 아니라 `reviewPoints` 하나만 가져오는 이유는 아래 Step 2에서 계산식을 그 함수로 바꾸기 때문이다.

- [ ] **Step 2: `ReviewForm.jsx` 의 `pointDelta` 계산을 `reviewPoints`로 바꾼다**

122-128행 전체(주석 포함)를 아래로 교체한다:

기존:

```js
  // 제출 시 발생할 포인트 증감(버튼 표시용): 작성=익명 +15/닉네임 공개 +25, 수정=익명 토글 차액(±10/0)
  const pointDelta = isEdit
    ? (isAnonymous ? ANONYMOUS_REVIEW_POINTS : PUBLIC_REVIEW_POINTS)
      - (originalIsAnonymous ? ANONYMOUS_REVIEW_POINTS : PUBLIC_REVIEW_POINTS)
    : isAnonymous
      ? ANONYMOUS_REVIEW_POINTS
      : PUBLIC_REVIEW_POINTS;
```

변경:

```js
  // 제출 시 발생할 포인트 증감(버튼 표시용): 작성=익명 +20/닉네임 공개 +30, 수정=익명 토글 차액(±10/0)
  const pointDelta = isEdit
    ? reviewPoints(isAnonymous) - reviewPoints(originalIsAnonymous)
    : reviewPoints(isAnonymous);
```

> 동작은 동일하다 — 삼항 두 겹이 함수 호출로 바뀌었을 뿐이다.

- [ ] **Step 3: `ExchangeCenter.jsx` 문구·배지를 상수 기반으로 바꾼다**

283행:

```jsx
                  <div className="ex-row-sub">닉네임 기재 25P · 익명 15P — 내가 일했던 근로장학 후기를 남겨요</div>
```

를 이렇게 바꾼다:

```jsx
                  <div className="ex-row-sub">닉네임 기재 {PUBLIC_REVIEW_POINTS}P · 익명 {ANONYMOUS_REVIEW_POINTS}P — 내가 일했던 근로장학 후기를 남겨요</div>
```

285행:

```jsx
                <span className="ex-reward">+25P</span>
```

를 이렇게 바꾼다:

```jsx
                <span className="ex-reward">+{PUBLIC_REVIEW_POINTS}P</span>
```

그리고 `ExchangeCenter.jsx` 의 import 블록에 아래를 추가한다 (이미 `../lib/passes` 등을 import하고 있으면 그 근처에 둔다):

```js
import { ANONYMOUS_REVIEW_POINTS, PUBLIC_REVIEW_POINTS } from '../lib/points'
```

> ⚠️ `ExchangeCenter.jsx` 가 이미 `../lib/points` 에서 뭔가를 import하고 있다면 새 줄을 만들지 말고 **기존 import 문에 이름만 추가**한다. 확인: `grep -n "lib/points" web/src/pages/ExchangeCenter.jsx`
> ⚠️ 이 파일은 따옴표 스타일이 작은따옴표다 (`ReviewForm.jsx` 는 큰따옴표). **각 파일의 기존 스타일을 따른다.**

- [ ] **Step 4: 전체 테스트 + 빌드 확인**

Run: `cd web && npm run test`
Expected: 전부 PASS

Run: `cd web && npm run build`
Expected: 빌드 성공 (에러 0)

- [ ] **Step 5: 커밋**

```bash
git add web/src/pages/ReviewForm.jsx web/src/pages/ExchangeCenter.jsx
git commit -F - <<'EOF'
feat: 리뷰 적립 표기를 30P/20P로 상향

ReviewForm의 지역 상수를 lib/points import로 교체하고,
교환센터의 하드코딩된 문구·배지도 같은 상수를 참조하게 한다.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 3: 프론트 — 가입 축하금 토스트 제거

**Files:**
- Modify: `web/src/pages/Signup.jsx:188-189`

**Interfaces:**
- Consumes: 없음
- Produces: 없음

- [ ] **Step 1: 토스트와 주석을 삭제한다**

188-189행의 이 두 줄을 **삭제**한다:

```js
      // 가입 축하 5p는 create_profile이 서버에서 지급(원장 reason='signup_bonus') — 여기선 안내만.
      toast('가입 축하 5p를 지급했어요!')
```

삭제 후 그 자리는 이렇게 남는다:

```js
      await refreshProfile()   // 새 프로필을 컨텍스트에 반영 → needsProfile 해제(리다이렉트 루프 방지)
      navigate('/home')        // 이미 인증(세션) 완료 → 홈으로
```

- [ ] **Step 2: `toast` 가 이 파일에서 계속 쓰이는지 확인한다**

Run: `grep -n "toast" web/src/pages/Signup.jsx`
Expected: 다른 곳에서도 `toast(...)` 를 쓰고 있으면 import를 **그대로 둔다**. 이 호출이 유일했다면 미사용 import가 되므로 `toast` import 줄도 함께 지운다.

- [ ] **Step 3: `MyPage.jsx` 의 `signup_bonus` 라벨이 그대로인지 확인한다**

Run: `grep -n "signup_bonus" web/src/pages/MyPage.jsx`
Expected: `signup_bonus: '가입 축하금',` 이 **여전히 존재**한다. 기존 유저의 포인트 내역에 원장 행이 남아 있어서, 지우면 내역에 원문 reason(`signup_bonus`)이 그대로 노출된다. **삭제하지 말 것.**

- [ ] **Step 4: 빌드 확인**

Run: `cd web && npm run build`
Expected: 빌드 성공, 미사용 변수 경고 없음

- [ ] **Step 5: 커밋**

```bash
git add web/src/pages/Signup.jsx
git commit -F - <<'EOF'
feat: 가입 축하금 안내 토스트 제거

서버(create_profile)에서 지급을 중단하므로 안내 문구도 함께 뺀다.
MyPage의 signup_bonus 내역 라벨은 기존 유저 원장 행이 남아 있어 유지한다.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 4: 마이그레이션 — RPC 3종 교체

**Files:**
- Create: `web/supabase/migrations/<CLI가 생성한 타임스탬프>_point_policy_v2_and_drop_signup_bonus.sql`

**Interfaces:**
- Consumes: 없음
- Produces: 다음 Task가 **같은 파일에 이어서** 소급 지급·공지 블록을 덧붙인다.

- [ ] **Step 1: 마이그레이션 파일을 CLI로 생성한다**

```bash
cd web && npx supabase migration new point_policy_v2_and_drop_signup_bonus
```

Expected: `web/supabase/migrations/2026XXXXXXXXXX_point_policy_v2_and_drop_signup_bonus.sql` 생성됨. **파일명을 손으로 바꾸지 않는다.**

- [ ] **Step 2: 헤더 + `create_profile`(가입 축하금 제거)을 쓴다**

생성된 파일에 아래를 그대로 넣는다. `create_profile` 본문은 현행 최신본(`20260721071224_nickname_policy.sql`)을 그대로 재현하되 **말미의 보너스 2줄만 뺀 것**이다.

```sql
-- 목적: 포인트 정책 v2 — 가입 축하금 5P 지급 종료, 리뷰 적립 실명 30P·익명 20P(기존 25/15),
--       리뷰 2개 이상 작성자에게 (살아있는 리뷰 수 − 1) × 5P 소급 지급, 공지 문구 동기화.
-- 날짜: 2026-08-08 · 담당: 배경록
-- ⚠️ 배포: 프론트(lib/points·ReviewForm·ExchangeCenter)의 적립가 표기와 한 몸이므로
--          db push 직후 prod 프론트 배포까지 한 번에 진행할 것.
-- ⚠️ 적립가 변경과 소급 지급이 한 트랜잭션이어야 그 사이 들어온 리뷰가 어중간한 금액으로
--    적립되지 않는다 — 파일 전체를 begin/commit으로 감싼다.

begin;

-- ── 1) 가입 축하금 지급 종료 ──
-- 본문은 현행 최신(20260721071224_nickname_policy)을 그대로 재현 + 보너스 2줄만 삭제.
-- 시그니처 불변 → create or replace(DROP 불필요), 기존 grant(authenticated) 유지됨.
-- 이미 지급된 signup_bonus 원장 행·잔액은 건드리지 않는다(회수 없음).
create or replace function create_profile(
  p_nickname        text,
  p_university_id   int,
  p_college_name    text,
  p_department_name text,
  p_track           text,
  p_admission_year  int,
  p_degree_program  text,
  p_academic_status text,
  p_grade           int,
  p_region          text
) returns void
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_college_id int;
  v_department_id int;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  -- 이미 프로필 있으면 재생성하지 않음(더블클릭/재호출 안전). 갱신은 update_profile 담당.
  if exists (select 1 from users u where u.id = v_uid) then
    return;
  end if;

  perform validate_nickname(p_nickname);

  select id into v_college_id from colleges
    where university_id = p_university_id and name = p_college_name limit 1;
  if v_college_id is null then
    select id into v_college_id from colleges where university_id = p_university_id order by id limit 1;
  end if;
  if v_college_id is null then raise exception 'NO_COLLEGE'; end if;
  select id into v_department_id from departments
    where college_id = v_college_id and name = p_department_name limit 1;
  if v_department_id is null then
    select id into v_department_id from departments where college_id = v_college_id order by id limit 1;
  end if;
  if v_department_id is null then raise exception 'NO_DEPARTMENT'; end if;

  insert into users (id, university_id, college_id, department_id, track,
                     nickname, admission_year, degree_program, academic_status, grade, region)
  values (v_uid, p_university_id, v_college_id, v_department_id, p_track,
          trim(p_nickname), p_admission_year,
          p_degree_program::degree_program_e, p_academic_status::academic_status_e,
          p_grade, p_region);
exception
  when unique_violation then raise exception 'NICKNAME_TAKEN';
end $$;
```

- [ ] **Step 3: 같은 파일에 리뷰 적립 RPC 2종을 이어 쓴다**

`write_review_with_points` 본문은 `20260731105714` 그대로, `update_review_with_points` 본문은 **`20260731120439` 그대로**(reason 3종을 포함한 최신본이다 — `20260731105714` 것을 베끼면 `review_policy_grant` 가 정산 합계에서 빠져 이중 보전이 발생한다). 둘 다 적립 상수만 30/20으로 바꾼다.

```sql
-- ── 2) 리뷰 적립 — 실명 30P · 익명 20P ──
-- 본문은 각 최신본(write: 20260731105714 / update: 20260731120439) 그대로, 적립 상수만 25/15 → 30/20.
-- 시그니처 불변. delete_review_with_rollback은 실제 적립 합계(sum)를 회수하므로 수정 불필요.
create or replace function public.write_review_with_points(
  p_worksite_id integer, p_work_year integer, p_work_semester text,
  p_work numeric, p_growth numeric, p_vibe numeric, p_flex numeric, p_recommend numeric,
  p_work_content text, p_opinion text, p_is_anonymous boolean default false
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_review_id integer;
  v_amount integer := case when coalesce(p_is_anonymous, false) then 20 else 30 end;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  perform public.validate_review_work_semester(p_worksite_id, p_work_semester);

  insert into public.reviews (
    user_id, worksite_id, work_year, work_semester,
    score_work, score_growth, score_vibe, score_flex, score_recommend,
    work_content, opinion, is_anonymous
  ) values (
    v_uid, p_worksite_id, p_work_year, p_work_semester,
    p_work, p_growth, p_vibe, p_flex, p_recommend,
    p_work_content, p_opinion, coalesce(p_is_anonymous, false)
  ) returning id into v_review_id;

  insert into public.points (user_id, amount, reason, review_id)
  values (v_uid, v_amount, 'review_write', v_review_id);

  update public.users set point_balance = point_balance + v_amount where id = v_uid;
  return v_review_id;
end;
$$;

-- ⚠️ 정산 합계의 reason 목록에 'review_policy_grant'가 반드시 포함돼야 한다
--    (20260731120439에서 추가된 것 — 빼면 소급 지급분을 못 보고 차액을 또 지급한다).
create or replace function public.update_review_with_points(
  p_review_id integer, p_work_year integer, p_work_semester text,
  p_work numeric, p_growth numeric, p_vibe numeric, p_flex numeric, p_recommend numeric,
  p_work_content text, p_opinion text, p_is_anonymous boolean default false
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_worksite_id integer;
  v_target integer := case when coalesce(p_is_anonymous, false) then 20 else 30 end;
  v_grant integer;
  v_has_write boolean;
  v_delta integer;
  v_balance integer;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;

  select worksite_id into v_worksite_id
  from public.reviews
  where id = p_review_id and user_id = v_uid;
  if not found then raise exception 'REVIEW_NOT_FOUND'; end if;

  perform public.validate_review_work_semester(v_worksite_id, p_work_semester);

  update public.reviews set
    work_year = p_work_year, work_semester = p_work_semester,
    score_work = p_work, score_growth = p_growth, score_vibe = p_vibe,
    score_flex = p_flex, score_recommend = p_recommend,
    work_content = p_work_content, opinion = p_opinion,
    is_anonymous = coalesce(p_is_anonymous, false), updated_at = now()
  where id = p_review_id and user_id = v_uid;

  select coalesce(sum(amount), 0), bool_or(reason = 'review_write')
    into v_grant, v_has_write
  from public.points
  where review_id = p_review_id
    and reason in ('review_write', 'review_anon_switch', 'review_policy_grant');

  if not coalesce(v_has_write, false) then return; end if;

  v_delta := v_target - v_grant;
  if v_delta <> 0 then
    if v_delta < 0 then
      select point_balance into v_balance from public.users where id = v_uid;
      if v_balance + v_delta < 0 then raise exception 'INSUFFICIENT_POINTS'; end if;
    end if;
    insert into public.points (user_id, amount, reason, review_id)
    values (v_uid, v_delta, 'review_anon_switch', p_review_id);
    update public.users set point_balance = point_balance + v_delta where id = v_uid;
  end if;
end;
$$;
```

- [ ] **Step 4: 여기서는 아직 커밋하지 않는다**

`commit;` 이 아직 없어서 파일이 미완성이다. Task 5·6을 마친 뒤 한 번에 커밋한다. 지금은 파일이 저장돼 있는지만 확인한다.

Run: `grep -c "create or replace function" web/supabase/migrations/*_point_policy_v2_and_drop_signup_bonus.sql`
Expected: `3`

---

### Task 5: 마이그레이션 — 소급 지급 블록

**Files:**
- Modify: Task 4에서 만든 마이그레이션 파일 (이어쓰기)

**Interfaces:**
- Consumes: Task 4가 만든 파일. 위 블록에서 적립가가 이미 30/20으로 바뀐 상태여야 한다.
- Produces: 다음 Task가 같은 파일에 공지 블록을 이어 쓴다.

- [ ] **Step 1: 소급 지급 SQL을 파일 끝에 이어 쓴다**

```sql
-- ── 3) 소급 지급 — (살아있는 리뷰 수 − 1) × 5P ──
-- 리뷰를 여러 개 쓴 기여자에게만 보상한다. 1개=0P, 2개=5P, 3개=10P.
-- 대상: user_id 있음 · 삭제 안 됨 · review_write 적립 이력 있음(수정 RPC의 v_has_write 가드와 동일 기준).
--       삭제된 리뷰는 이미 적립분을 회수당했으므로 카운트에서 제외.
-- 지급 방식: 유저 단위 뭉텅이가 아니라 리뷰별 원장 행으로 붙인다 — update/delete RPC가
--       review_id별 적립 합계로 재정산하기 때문. review_id가 null인 행은 그 합계에 안 잡혀
--       옛 리뷰를 수정할 때마다 차액이 또 나가는 이중 보전이 된다.
-- 제외 규칙: 유저별 최소 id 리뷰 1건(rn=1)은 제외 → 그 리뷰만 합계가 구 정책가로 남는다.
--       그 리뷰를 수정하면 update RPC가 차액 +5P를 보전한다(유저당 최대 1회·5P). 정책상 감수.
-- 멱등: 재실행하면 합계가 이미 현행가라 delta<=0 → 0행. db reset 재생 시엔 reviews가 비어 no-op.
-- 회수 안 함: delta<=0 인 리뷰는 대상에서 제외(보전 전용).
with eligible as (
  select r.id as review_id,
         r.user_id,
         coalesce(r.is_anonymous, false) as is_anonymous,
         sum(p.amount) as granted
  from public.reviews r
  join public.points p
    on p.review_id = r.id
   and p.reason in ('review_write', 'review_anon_switch', 'review_policy_grant')
  where r.user_id is not null
    and r.deleted_at is null
  group by r.id, r.user_id, r.is_anonymous
  having bool_or(p.reason = 'review_write')
), ranked as (
  select e.review_id,
         e.user_id,
         row_number() over (partition by e.user_id order by e.review_id) as rn,
         (case when e.is_anonymous then 20 else 30 end) - e.granted as delta
  from eligible e
), targeted as (
  select review_id, user_id, delta
  from ranked
  where rn > 1
    and delta > 0
), granted_rows as (
  insert into public.points (user_id, amount, reason, review_id)
  select user_id, delta, 'review_policy_grant', review_id
  from targeted
  returning user_id, amount
)
update public.users u
set point_balance = u.point_balance + s.total
from (select user_id, sum(amount) as total from granted_rows group by user_id) s
where u.id = s.user_id;
```

- [ ] **Step 2: 로직을 손으로 한 번 검산한다**

아래 케이스를 SQL을 읽으며 확인한다 (실행 아님 — 논리 점검):

| 유저 | 살아있는 리뷰 | 기대 소급액 |
|---|---|---|
| A | 1개 (실명, 합계 25) | **0P** — `rn=1` 이라 `targeted` 에서 빠짐 |
| B | 2개 (실명 25, 익명 15) | **5P** — 두 번째 리뷰만 대상 |
| C | 3개 (전부 실명 25) | **10P** — 2·3번째 각 +5 |
| D | 2개인데 1개는 삭제됨 | **0P** — 삭제분은 `deleted_at is null` 로 빠져 남은 1개가 `rn=1` |
| E | 재실행 | **0P** — 합계가 30/20이라 `delta > 0` 불만족 |

`rn > 1` 조건이 있는지, `delta > 0` 조건이 있는지, `deleted_at is null` 이 있는지 세 가지를 눈으로 확인한다.

- [ ] **Step 3: 아직 커밋하지 않는다**

Task 6에서 공지 블록과 `commit;` 을 마저 쓴다.

---

### Task 6: 마이그레이션 — 공지 문구 동기화 + 새 공지

**Files:**
- Modify: Task 4·5에서 쓰던 마이그레이션 파일 (이어쓰기, `commit;` 으로 마무리)

**Interfaces:**
- Consumes: Task 4·5의 파일
- Produces: 완성된 마이그레이션 파일

- [ ] **Step 1: 현행 정책 공지의 숫자 갱신 SQL을 이어 쓴다**

```sql
-- ── 4) 현행 정책 서술 공지의 숫자 동기화 ──
-- 대상은 '[필독] 근로고래 이용 안내'(20260801050000에서 3건을 통합한 것).
-- ⚠️ 과거 날짜 업데이트 공지('[업데이트] 8월 1일'의 "15P → 25P" 이력)는 건드리지 않는다 —
--    그 시점의 사실 기록이다.
update public.notices
set content = replace(content,
  '닉네임 공개 리뷰 작성 25P, 익명 리뷰 작성 15P',
  '닉네임 공개 리뷰 작성 30P, 익명 리뷰 작성 20P')
where content like '%닉네임 공개 리뷰 작성 25P, 익명 리뷰 작성 15P%';

-- 구 '[필독] 리뷰 작성 방법 안내'는 20260801050000에서 통합·삭제됐으므로 prod에선 0행이지만,
-- db reset 재생 순서(생성 → 갱신 → 삭제)와 무관하게 안전하도록 방어적으로 둔다.
update public.notices
set content = replace(content,
  '닉네임 공개 리뷰는 25P, 익명 리뷰는 15P가 적립됩니다',
  '닉네임 공개 리뷰는 30P, 익명 리뷰는 20P가 적립됩니다')
where content like '%닉네임 공개 리뷰는 25P, 익명 리뷰는 15P가 적립됩니다%';
```

- [ ] **Step 2: 새 공지 upsert 블록을 이어 쓴다**

`20260802120000_update_august_first_notice.sql` 과 같은 제목 기준 do-block 패턴이다.

```sql
-- ── 5) 변경 안내 공지 ──
-- 제목 기준 upsert라 재실행·db reset에 안전하다. is_pinned=false(고정은 필독 공지만),
-- university_id=null(전교 공통·비로그인 공개).
do $$
declare
  v_notice_id integer;
begin
  select id into v_notice_id
  from public.notices
  where university_id is null
    and title = '[업데이트] 8월 8일'
  order by id
  limit 1;

  if v_notice_id is null then
    insert into public.notices (title, content, is_pinned, university_id)
    values (
      '[업데이트] 8월 8일',
      $notice$안녕하세요, 근로고래입니다. 🐳

2026년 8월 8일에 반영된 포인트 정책 변경을 안내드립니다.

1. 리뷰 적립 포인트 상향

• 닉네임 공개 리뷰: 25P → 30P
• 익명 리뷰: 15P → 20P

2. 가입 축하금 지급 종료

가입만으로 지급하던 축하 포인트 5P의 지급을 종료했습니다. 이미 지급받으신 포인트는 회수하지 않으며 그대로 사용하실 수 있습니다. 해당 재원은 위의 리뷰 적립 포인트 상향에 사용됩니다.

3. 기존 리뷰 소급 지급

리뷰를 2개 이상 작성해 주신 분들께 포인트를 소급 지급했습니다. 가장 먼저 작성한 리뷰를 제외한 나머지 리뷰마다 5P씩 지급되어, 리뷰 2개는 5P, 3개는 10P가 적립됩니다.

삭제한 리뷰는 작성 개수에 포함되지 않습니다.

리뷰를 남겨주시는 분들께 더 많은 혜택이 돌아가도록 정책을 조정했습니다. 앞으로도 계속 개선하겠습니다.

감사합니다.
근로고래 드림$notice$,
      false,
      null
    );
  else
    update public.notices
    set content = $notice$안녕하세요, 근로고래입니다. 🐳

2026년 8월 8일에 반영된 포인트 정책 변경을 안내드립니다.

1. 리뷰 적립 포인트 상향

• 닉네임 공개 리뷰: 25P → 30P
• 익명 리뷰: 15P → 20P

2. 가입 축하금 지급 종료

가입만으로 지급하던 축하 포인트 5P의 지급을 종료했습니다. 이미 지급받으신 포인트는 회수하지 않으며 그대로 사용하실 수 있습니다. 해당 재원은 위의 리뷰 적립 포인트 상향에 사용됩니다.

3. 기존 리뷰 소급 지급

리뷰를 2개 이상 작성해 주신 분들께 포인트를 소급 지급했습니다. 가장 먼저 작성한 리뷰를 제외한 나머지 리뷰마다 5P씩 지급되어, 리뷰 2개는 5P, 3개는 10P가 적립됩니다.

삭제한 리뷰는 작성 개수에 포함되지 않습니다.

리뷰를 남겨주시는 분들께 더 많은 혜택이 돌아가도록 정책을 조정했습니다. 앞으로도 계속 개선하겠습니다.

감사합니다.
근로고래 드림$notice$,
        updated_at = now()
    where id = v_notice_id;
  end if;
end
$$;

commit;
```

- [ ] **Step 3: 파일이 온전한지 확인한다**

```bash
MIG=$(ls web/supabase/migrations/*_point_policy_v2_and_drop_signup_bonus.sql)
grep -c "^begin;" "$MIG"                  # 1
grep -c "^commit;" "$MIG"                 # 1
grep -c "create or replace function" "$MIG"   # 3
grep -c "signup_bonus" "$MIG"             # 0  ← 보너스 insert가 남아 있으면 안 된다
grep -n "else 30 end\|else 20 end" "$MIG" # 30/20이 들어간 줄이 보여야 한다
```

Expected: 위 주석의 숫자와 일치. 특히 `signup_bonus` 가 **0건**이어야 한다.

- [ ] **Step 4: 커밋**

```bash
git add web/supabase/migrations/
git commit -F - <<'EOF'
feat(db): 포인트 정책 v2 — 가입 축하금 폐지 + 리뷰 적립 30P/20P + 소급 지급

create_profile에서 가입 축하 5P 지급을 제거하고, 리뷰 적립을 실명 30P·
익명 20P로 올린다. 리뷰를 2개 이상 쓴 유저에게는 가장 오래된 1건을 제외한
리뷰마다 +5P를 소급 지급한다((n-1)*5).

적립가 변경과 소급 지급을 한 트랜잭션에 묶어, 그 사이 들어온 리뷰가
어중간한 금액으로 적립되지 않게 한다.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 7: 마이그레이션 검증

**Files:** 없음 (검증만)

**Interfaces:**
- Consumes: Task 6의 완성된 마이그레이션 파일

- [ ] **Step 1: Docker 사용 가능 여부를 확인한다**

Run: `docker info`
- 성공하면 → Step 2로
- 실패하면(Docker 미설치·미실행) → Step 2·3을 건너뛰고 Step 4로. `web/supabase/README.md §3` 이 "Docker 없으면 sandbox 프로젝트에 db push로 테스트"라고 적어둔 상태다. **prod에 바로 push하지 말고, 이 사실을 사용자에게 보고한다.**

- [ ] **Step 2: 로컬 맨바닥 재구축**

```bash
cd web && npx supabase start && npx supabase db reset
```

Expected: 전 마이그레이션이 순서대로 적용되고 에러 0. 새 마이그레이션의 소급 지급 블록은 `reviews` 가 비어 있어 0행 처리된다(정상).

- [ ] **Step 3: 재구축된 로컬 DB의 RPC가 새 값인지 확인한다**

`npx supabase status` 로 로컬 DB URL을 확인한 뒤, Studio(`http://localhost:54323`)의 SQL 에디터나 psql에서 아래를 실행한다:

```sql
select proname,
       prosrc like '%else 30 end%' as has_30,
       prosrc like '%else 20 end%' as has_20
from pg_proc
where proname in ('write_review_with_points', 'update_review_with_points');

select prosrc like '%signup_bonus%' as still_grants_bonus
from pg_proc
where proname = 'create_profile';
```

Expected: 앞 쿼리 2행 모두 `has_30 = t` · `has_20 = t`, 뒤 쿼리 `still_grants_bonus = f`

> ⚠️ 이건 **로컬 재구축본** 확인이다. prod 반영은 `db push` 전까지 일어나지 않는다.
> Studio·psql 어느 쪽도 못 쓰면 이 단계는 건너뛰고, `db reset` 이 에러 없이 끝난 것 + Task 6 Step 3의 grep 결과로 갈음한다. 건너뛰었다면 Step 4에서 그 사실을 보고한다.

- [ ] **Step 4: 결과를 사용자에게 보고한다**

무엇을 실행했고 무엇이 통과했는지, Docker가 없어 건너뛴 단계가 있으면 그것도 그대로 보고한다. **push는 사용자 승인 전까지 하지 않는다.**

---

### Task 8: 문서 갱신

**Files:**
- Modify: `web/supabase/README.md` (migrations 목록에 항목 추가)
- Modify: `docs/db-schema.md` (§⑨ 상태 표기 + 새 섹션 ⑬)

**Interfaces:**
- Consumes: Task 6의 마이그레이션 파일명(타임스탬프)

- [ ] **Step 1: `web/supabase/README.md` 의 migrations 목록에 항목을 추가한다**

`- `20260806100232_split_mot_green_school_worksites.sql` = ...` 항목 **아래**에 추가한다 (실제 타임스탬프는 Task 4에서 CLI가 만든 것으로 채운다):

```markdown
  - `<타임스탬프>_point_policy_v2_and_drop_signup_bonus.sql` = **push 대기** — **포인트 정책 v2**: ①`create_profile`에서 **가입 축하 5P 지급 제거**(본문은 20260721071224 재현 + 보너스 2줄 삭제, 시그니처 불변 replace. 이미 지급된 `signup_bonus` 원장·잔액은 **회수 안 함** — 잔액 부족 유저 처리와 민원 소지 때문) ②리뷰 적립 **실명 30P·익명 20P**(기존 25/15) — `write_review_with_points`·`update_review_with_points` replace. ⚠️ update 본문은 반드시 **20260731120439** 것을 베낄 것(reason 목록에 `review_policy_grant` 포함 — 20260731105714 것을 베끼면 소급분을 못 보고 이중 보전) ③**소급 지급 `(살아있는 리뷰 수 − 1) × 5P`** — 유저별 최소 id 리뷰 1건을 제외한 각 리뷰에 +5P(`reason='review_policy_grant'`, `review_id` 지정). 유저 단위 뭉텅이가 아니라 리뷰별로 붙이는 이유는 update/delete RPC가 `review_id`별 합계로 재정산하기 때문(null이면 옛 리뷰 수정 시마다 이중 보전). ④공지 문구 동기화 + `[업데이트] 8월 8일` 공지 신설. **전체가 begin/commit 한 트랜잭션** — 적립가 변경과 소급 지급 사이에 들어온 리뷰가 어중간한 금액으로 적립되지 않게. 멱등(delta>0 조건 · 제목 기준 upsert), db reset 시 reviews가 비어 소급 블록 no-op. ⚠️ **알려진 틈**: 제외된 "첫 리뷰"는 합계가 구 정책가로 남아, 그 리뷰를 수정하면 update RPC가 차액 +5P를 보전한다(유저당 최대 1회·5P — 정책 변경 비용으로 감수, PM 승인). ⚠️ 프론트(`lib/points`·ReviewForm·ExchangeCenter·Signup 토스트 제거)와 한 몸 — db push 직후 prod 프론트 배포까지 같이. 담당 배경록. spec `docs/superpowers/specs/2026-08-08-point-policy-v2-design.md` · plan `docs/superpowers/plans/2026-08-08-point-policy-v2.md`.
```

- [ ] **Step 2: `docs/db-schema.md` §⑨의 제목에 대체 표기를 단다**

244행:

```markdown
## ⑨ 가입 축하 5p + 광고 daily_cap=2 확정 — **db push 대기 (migration 20260717150000·20260717140000)**
```

를 이렇게 바꾼다:

```markdown
## ⑨ 가입 축하 5p + 광고 daily_cap=2 확정 — **db push 대기 (migration 20260717150000·20260717140000)** · ⚠️ 가입 축하 5p는 **⑬에서 폐지됨(2026-08-08)**, daily_cap은 20260731105714에서 1로 변경됨
```

- [ ] **Step 3: `docs/db-schema.md` 의 `## 기존 스키마 (현재 live 상태)` 섹션 **바로 위**에 ⑬을 추가한다**

```markdown
## ⑬ 포인트 정책 v2 — 가입 축하금 폐지 + 리뷰 적립 30P/20P (migration `<타임스탬프>_point_policy_v2_and_drop_signup_bonus`)

스키마 변경 **없음** — RPC 본문과 데이터만 바뀐다.

- **가입 축하금 폐지**: `create_profile`에서 `signup_bonus` 원장 insert + `point_balance` +5 두 줄 제거(⑨에서 도입한 것). 시그니처 불변 replace. **이미 지급된 원장 행·잔액은 회수하지 않는다** — 잔액이 부족한 유저에게서 차감하려면 음수 방지 로직이 필요하고 민원 소지가 크다. 따라서 `points.reason` 의 `signup_bonus` 값과 `MyPage.jsx` 의 '가입 축하금' 라벨은 **계속 살아 있어야 한다**(지우면 기존 유저 내역에 원문 reason이 노출된다).
- **리뷰 적립 상향**: 실명 25P → **30P**, 익명 15P → **20P**. `write_review_with_points`·`update_review_with_points` 의 상수만 변경(시그니처 불변). `delete_review_with_rollback` 은 실제 적립 합계를 회수하므로 무수정.
- **소급 지급 `(살아있는 리뷰 수 − 1) × 5P`**: 1개=0P, 2개=5P, 3개=10P. 대상은 `user_id is not null` + `deleted_at is null` + `review_write` 원장이 있는 리뷰. 유저별 최소 `id` 1건을 제외한 각 리뷰에 `reason='review_policy_grant'` +5P 행을 붙인다. **뭉텅이 지급이 아니라 리뷰별로 붙이는 이유** — `update_review_with_points`·`delete_review_with_rollback` 이 `review_id` 별 적립 합계로 재정산하므로, `review_id` 가 null이면 옛 리뷰를 수정할 때마다 차액이 또 나간다.
  - ⚠️ **알려진 틈**: 제외된 "첫 리뷰"는 합계가 구 정책가로 남아, 그 리뷰를 수정하면 차액 +5P가 보전된다(유저당 최대 1회·5P). `(n−1)×5` 규칙을 유지하는 대가로 감수한 것(PM 승인).
- **트랜잭션**: 파일 전체가 `begin`/`commit`. 적립가 변경과 소급 지급 사이에 리뷰가 들어오면 어중간한 금액으로 적립되기 때문.
- **공지**: 현행 정책 서술 공지(`[필독] 근로고래 이용 안내`)의 숫자 갱신 + `[업데이트] 8월 8일` 신설. 과거 날짜 업데이트 공지의 "15P → 25P" 이력은 사실 기록이라 유지.
- **프론트 짝**: `web/src/lib/points.js` 에 `PUBLIC_REVIEW_POINTS`/`ANONYMOUS_REVIEW_POINTS`/`reviewPoints()` 신설(기존엔 `ReviewForm.jsx` 지역 상수 + `ExchangeCenter.jsx` 문자열 리터럴로 이중 소스), `Signup.jsx` 가입 축하 토스트 제거. **db push 직후 prod 프론트 배포까지 한 묶음.**

spec `docs/superpowers/specs/2026-08-08-point-policy-v2-design.md` · plan `docs/superpowers/plans/2026-08-08-point-policy-v2.md`
```

- [ ] **Step 4: 커밋**

```bash
git add web/supabase/README.md docs/db-schema.md
git commit -F - <<'EOF'
docs: 포인트 정책 v2 마이그레이션 기록

web/supabase/README.md 마이그레이션 목록에 항목을 추가하고,
db-schema.md에 섹션 ⑬을 더한다. 가입 축하 5p를 도입한 ⑨에는
폐지 표기를 단다.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

## 배포 (사용자가 직접 — 에이전트가 실행하지 않는다)

1. 디스코드에 한 마디 (CLAUDE.md §3-1)
2. `cd web && npx supabase migration list` — **대기 목록부터 확인.** `db push` 는 원격 이력에 없는 파일을 전부 순서대로 적용한다. 팀 공유 DB라 남의 미적용분이 쌓여 있을 수 있다.
3. `cd web && npx supabase db push`
4. **즉시** prod 프론트 배포: `main` 머지 → `prod` 머지 → `git push origin prod`

간극 동안엔 프론트가 옛 표기(25P/15P)를 보여주면서 서버는 새 금액(30P/20P)을 적립한다. 유저에게 불리한 방향은 아니지만 혼선이 있으므로 간극을 짧게 가져간다.
