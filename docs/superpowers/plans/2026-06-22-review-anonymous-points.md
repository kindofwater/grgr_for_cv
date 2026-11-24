# 리뷰 익명 작성 + 차등 포인트 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 기존 리뷰 작성 폼에 익명 옵션을 추가하고, 작성자 표시를 가리며, 차등 포인트(실명 15P/익명 5P)를 대칭 레저 모델로 처리한다.

**Architecture:** dodo의 미머지·스테일 브랜치(`feature/review-form`)에서 익명 부분만 현재 main에 이식 + 차등 포인트는 신규. DB는 단일 정본 마이그레이션(컬럼·4-col unique·write/update/delete RPC 3종). 프론트는 폼 체크박스 + 확인 모달 + data 레이어 + 삭제 카피 + 문서.

**Tech Stack:** React 19 + Vite, Supabase(Postgres) RPC, vitest(순수 JS만 — 컴포넌트 테스트 하네스 없음 → UI/DB는 수동·SQL 검증).

**근거 spec:** [docs/superpowers/specs/2026-06-22-review-anonymous-points-design.md](../specs/2026-06-22-review-anonymous-points-design.md)

## Global Constraints

- 포인트: 실명 작성 **+15**, 익명 작성 **+5**, 수정 전환 **±10**, 삭제 = **그 리뷰가 실제로 받은 적립합** 회수.
- `points.reason` 값: `'review_write'`, `'review_anon_switch'`(신규), `'review_delete'`.
- 새 unique 제약명: **`reviews_user_worksite_year_semester_key`** on `(user_id, worksite_id, work_year, work_semester)`.
- 기본값 `is_anonymous = false`(실명).
- 체크박스 카피: `익명으로 작성하기` / `작성자 닉네임과 근무 학기가 공개되지 않아요. (-10P)`.
- 확인 모달 노출 조건: `isAnonymous && (!isEdit || !originalIsAnonymous)`.
- `authorLabel` 우선순위 **익명 > 탈퇴 > 닉네임** 유지(코드 변경 없음). `fetchReviews`의 `author:users!user_id(...)` 조인 **유지 필수**(dodo의 nickname 제거 이식 금지).
- DB 변경은 **단일 마이그레이션**. push 전 디스코드 공유 + 변경자가 직접 `supabase db push`(CLAUDE.md §3). 함수 옛 시그니처는 `drop` 선행(§3.4).
- 커밋 자주. **푸시 안 함**(브랜치 `feat/review-anonymous-points`).
- live reviews 데이터는 전부 더미 → 충돌 시 `delete from public.reviews` 무방.

## File Structure

- **Create** `web/supabase/migrations/<ts>_review_anonymous_points.sql` — 컬럼·unique·RPC 3종 정본.
- **Modify** `web/src/data/worksiteQueries.js` — createReview 주석·fetchMyReviewById select·fetchMyReviewForPeriod 인자+필터·updateReview를 RPC로.
- **Modify** `web/src/components/ConfirmModal.jsx` — 옵션 `className` prop.
- **Modify** `web/src/components/ReviewFormFields.jsx` — 익명 체크박스 + props.
- **Modify** `web/src/pages/ReviewForm.jsx` — 상태·edit 로드·handleSubmit 분할·에러문구·모달·호출부.
- **Modify** `web/src/pages/ReviewForm.css` — `.anonymous-*` 블록.
- **Modify** `web/src/pages/MyPage.jsx` — 삭제 확인 카피 중립화.
- **Modify** `docs/db-schema.md`, `docs/api-spec.md`, `web/src/data/README.md` — 문서 동기화(CLAUDE.md §5).

---

### Task 1: DB 마이그레이션 (컬럼 · 4-col unique · RPC 3종)

**Files:**
- Create: `web/supabase/migrations/<생성ts>_review_anonymous_points.sql`

**Interfaces:**
- Produces (RPC 시그니처 — 이후 data 레이어가 의존):
  - `write_review_with_points(p_user_id int, p_worksite_id int, p_work_year int, p_work_semester text, p_work numeric, p_growth numeric, p_vibe numeric, p_flex numeric, p_recommend numeric, p_work_content text, p_opinion text, p_is_anonymous boolean default false) returns int`
  - `update_review_with_points(p_user_id int, p_review_id int, p_work_year int, p_work_semester text, p_work numeric, p_growth numeric, p_vibe numeric, p_flex numeric, p_recommend numeric, p_work_content text, p_opinion text, p_is_anonymous boolean default false) returns void`
  - `delete_review_with_rollback(p_user_id int, p_review_id int) returns void`

- [ ] **Step 1: 마이그레이션 파일 생성**

Run: `cd web && npx supabase migration new review_anonymous_points`
Expected: `web/supabase/migrations/<timestamp>_review_anonymous_points.sql` 생성(빈 파일).

- [ ] **Step 2: SQL 작성** — 생성된 파일에 아래 전체를 붙여넣는다.

```sql
-- 목적: 리뷰 익명 작성/수정 + 차등 포인트(익명 5P/실명 15P, 대칭 레저). 컬럼·4-col unique·RPC 3종 정본 재구축.
-- 날짜: 2026-06-22 · 담당: 배경록
-- 참고: feature/review-form(dodo)의 DB 변경(컬럼·flat15 RPC·4-col unique)을 대체하는 정본.

-- (1) is_anonymous 컬럼 — 데이터 보존(if not exists)
alter table public.reviews
  add column if not exists is_anonymous boolean not null default false;

-- (2) 중복 기준 = (user, worksite, year, semester).
--     live 제약명 불명(드리프트) → 이름 추측 대신 reviews의 모든 unique 제약을 일괄 drop 후 정본 1개 add(이름 무관·멱등).
do $$
declare r record;
begin
  for r in
    select conname from pg_constraint
    where conrelid = 'public.reviews'::regclass and contype = 'u'
  loop
    execute format('alter table public.reviews drop constraint %I', r.conname);
  end loop;
end $$;

alter table public.reviews
  add constraint reviews_user_worksite_year_semester_key
  unique (user_id, worksite_id, work_year, work_semester);

-- (3) write RPC — 차등 포인트(익명 5 / 실명 15). 옛 11-arg + dodo 12-arg(flat15) 모두 drop 후 재생성.
drop function if exists public.write_review_with_points(
  integer, integer, integer, text, numeric, numeric, numeric, numeric, numeric, text, text);
drop function if exists public.write_review_with_points(
  integer, integer, integer, text, numeric, numeric, numeric, numeric, numeric, text, text, boolean);

create or replace function public.write_review_with_points(
  p_user_id integer, p_worksite_id integer, p_work_year integer, p_work_semester text,
  p_work numeric, p_growth numeric, p_vibe numeric, p_flex numeric, p_recommend numeric,
  p_work_content text, p_opinion text, p_is_anonymous boolean default false
) returns integer language plpgsql as $$
declare
  v_review_id integer;
  v_amount integer := case when coalesce(p_is_anonymous, false) then 5 else 15 end;
begin
  insert into public.reviews (
    user_id, worksite_id, work_year, work_semester,
    score_work, score_growth, score_vibe, score_flex, score_recommend,
    work_content, opinion, is_anonymous)
  values (
    p_user_id, p_worksite_id, p_work_year, p_work_semester,
    p_work, p_growth, p_vibe, p_flex, p_recommend,
    p_work_content, p_opinion, coalesce(p_is_anonymous, false))
  returning id into v_review_id;

  insert into public.points (user_id, amount, reason, review_id)
  values (p_user_id, v_amount, 'review_write', v_review_id);

  update public.users set point_balance = point_balance + v_amount where id = p_user_id;
  return v_review_id;
end $$;

-- (4) update RPC — 수정 시 익명 토글. 정규값(5/15)으로 스냅. 포인트 이력 없는 리뷰엔 지급 안 함(게이트).
drop function if exists public.update_review_with_points(
  integer, integer, integer, text, numeric, numeric, numeric, numeric, numeric, text, text, boolean);

create or replace function public.update_review_with_points(
  p_user_id integer, p_review_id integer, p_work_year integer, p_work_semester text,
  p_work numeric, p_growth numeric, p_vibe numeric, p_flex numeric, p_recommend numeric,
  p_work_content text, p_opinion text, p_is_anonymous boolean default false
) returns void language plpgsql as $$
declare
  v_target    integer := case when coalesce(p_is_anonymous, false) then 5 else 15 end;
  v_grant     integer;
  v_has_write boolean;
  v_delta     integer;
  v_balance   integer;
begin
  update public.reviews set
    work_year = p_work_year, work_semester = p_work_semester,
    score_work = p_work, score_growth = p_growth, score_vibe = p_vibe,
    score_flex = p_flex, score_recommend = p_recommend,
    work_content = p_work_content, opinion = p_opinion,
    is_anonymous = coalesce(p_is_anonymous, false), updated_at = now()
  where id = p_review_id and user_id = p_user_id;
  if not found then raise exception 'REVIEW_NOT_FOUND'; end if;

  select coalesce(sum(amount), 0), bool_or(reason = 'review_write')
    into v_grant, v_has_write
  from public.points
  where review_id = p_review_id and reason in ('review_write', 'review_anon_switch');

  -- 포인트 적립 이력(write 행)이 없는 리뷰는 토글로 포인트를 새로 지급하지 않음(공짜 지급 버그 차단).
  if not coalesce(v_has_write, false) then
    return;
  end if;

  v_delta := v_target - v_grant;
  if v_delta <> 0 then
    if v_delta < 0 then
      select point_balance into v_balance from public.users where id = p_user_id;
      if v_balance + v_delta < 0 then raise exception 'INSUFFICIENT_POINTS'; end if;
    end if;
    insert into public.points (user_id, amount, reason, review_id)
    values (p_user_id, v_delta, 'review_anon_switch', p_review_id);
    update public.users set point_balance = point_balance + v_delta where id = p_user_id;
  end if;
end $$;

-- (5) delete RPC — 실제 적립합만큼 회수(하드코딩 15 제거).
create or replace function public.delete_review_with_rollback(p_user_id integer, p_review_id integer)
returns void language plpgsql as $$
declare
  v_grant   integer;
  v_balance integer;
begin
  select coalesce(sum(amount), 0) into v_grant
  from public.points
  where review_id = p_review_id and reason in ('review_write', 'review_anon_switch');

  select point_balance into v_balance from public.users where id = p_user_id;
  if v_balance < v_grant then raise exception 'INSUFFICIENT_POINTS'; end if;

  insert into public.points (user_id, amount, reason, review_id)
  values (p_user_id, -v_grant, 'review_delete', p_review_id);

  delete from public.reviews where id = p_review_id and user_id = p_user_id;
  if not found then raise exception 'REVIEW_NOT_FOUND'; end if;

  update public.users set point_balance = point_balance - v_grant where id = p_user_id;
end $$;
```

- [ ] **Step 3: 디스코드 공유** — push 전 "리뷰 익명/차등포인트 단일 마이그레이션 올린다, feature/review-form 별도 머지하지 말 것" 한 줄 공유(CLAUDE.md §3.1).

- [ ] **Step 4: 적용** — Docker 있으면 `npx supabase db reset`(맨바닥 재구축 검증), 없으면 `npx supabase db push`(live·더미).

Run: `cd web && npx supabase db push`
Expected: 에러 없이 적용. (만약 `add constraint ... already exists` 또는 중복데이터로 실패 → 더미라 `delete from public.reviews;` 후 재시도.)

- [ ] **Step 5: 레저 동작 검증(트랜잭션 — 영구 변경 없음)** — Supabase SQL Editor 또는 `psql`에서 아래 블록 실행.

```sql
begin;
do $$
declare
  v_user int := (select id from public.users order by id limit 1);
  v_ws   int := (select id from public.worksites order by id limit 1);
  v_rid  int;
  v_bal0 int; v_bal1 int; v_bal2 int;
  v_content text := '검증용 업무 내용을 30자 이상으로 채우기 위한 더미 텍스트입니다.';
  v_opinion text := '검증용 자유 의견을 50자 이상으로 채우기 위한 더미 텍스트입니다. 포인트 레저 동작 확인용 문장 추가.';
begin
  select point_balance into v_bal0 from public.users where id = v_user;

  -- 익명 작성 → +5
  v_rid := public.write_review_with_points(v_user, v_ws, 2999, '1학기', 5,5,5,5,5, v_content, v_opinion, true);
  select point_balance into v_bal1 from public.users where id = v_user;
  assert v_bal1 - v_bal0 = 5, format('write(anon) expected +5, got %s', v_bal1 - v_bal0);

  -- 익명→실명 수정 → +10 (합계 15)
  perform public.update_review_with_points(v_user, v_rid, 2999, '1학기', 5,5,5,5,5, v_content, v_opinion, false);
  select point_balance into v_bal2 from public.users where id = v_user;
  assert v_bal2 - v_bal1 = 10, format('update(anon->named) expected +10, got %s', v_bal2 - v_bal1);

  -- 삭제 → 실제 적립합(15) 회수 → 시작 잔액 복귀
  perform public.delete_review_with_rollback(v_user, v_rid);
  assert (select point_balance from public.users where id = v_user) = v_bal0, 'delete should restore start balance';

  raise notice 'OK: ledger +5 -> +10 -> delete rollback verified';
end $$;
rollback;
```

Expected: `NOTICE: OK: ledger ...` 출력, assert 실패 없음. (실패 시 메시지가 어느 단계인지 알려줌.)

- [ ] **Step 6: 커밋**

```bash
git add web/supabase/migrations
git commit -m "feat(db): 리뷰 is_anonymous + 차등포인트 RPC 3종(대칭 레저) 단일 마이그레이션"
```

---

### Task 2: data 레이어 (worksiteQueries.js)

**Files:**
- Modify: `web/src/data/worksiteQueries.js`

**Interfaces:**
- Consumes: Task 1의 RPC `update_review_with_points`.
- Produces: `createReview(payload+p_is_anonymous)`, `fetchMyReviewById`(is_anonymous 포함), `fetchMyReviewForPeriod(userId, worksiteId, workYear, workSemester)`, `updateReview(reviewId, userId, fields{...,is_anonymous})`.

- [ ] **Step 1: `fetchMyReviewById` select에 is_anonymous 추가**

`web/src/data/worksiteQueries.js`에서 아래 select를
```js
    .select(`id, work_year, work_semester, score_work, score_growth,
      score_vibe, score_flex, score_recommend, work_content, opinion`)
```
다음으로 바꾼다:
```js
    .select(`id, work_year, work_semester, score_work, score_growth,
      score_vibe, score_flex, score_recommend, work_content, opinion, is_anonymous`)
```

- [ ] **Step 2: `fetchMyReviewForPeriod`에 worksiteId 인자+필터 추가**

아래 함수를
```js
export async function fetchMyReviewForPeriod(userId, workYear, workSemester) {
  const { data, error } = await supabase
    .from('reviews')
    .select('id, worksite_id')
    .eq('user_id', userId)
    .eq('work_year', workYear)
    .eq('work_semester', workSemester)
    .is('deleted_at', null)
    .maybeSingle()
  if (error) throw error
  return data
}
```
다음으로 바꾼다(시그니처 + `.eq('worksite_id', ...)` 둘 다):
```js
export async function fetchMyReviewForPeriod(userId, worksiteId, workYear, workSemester) {
  const { data, error } = await supabase
    .from('reviews')
    .select('id, worksite_id')
    .eq('user_id', userId)
    .eq('worksite_id', worksiteId)
    .eq('work_year', workYear)
    .eq('work_semester', workSemester)
    .is('deleted_at', null)
    .maybeSingle()
  if (error) throw error
  return data
}
```

- [ ] **Step 3: `createReview` 주석에 p_is_anonymous 추가**

```js
export async function createReview(payload) {
  // payload 키: p_user_id, p_worksite_id, p_work_year, p_work_semester,
  //   p_work, p_growth, p_vibe, p_flex, p_recommend, p_work_content, p_opinion, p_is_anonymous
  const { data, error } = await supabase.rpc('write_review_with_points', payload)
  if (error) throw error
  return data
}
```

- [ ] **Step 4: `updateReview`를 RPC 호출로 교체**

아래 함수를
```js
export async function updateReview(reviewId, userId, fields) {
  const { error } = await supabase.from('reviews').update(fields).eq('id', reviewId).eq('user_id', userId)
  if (error) throw error
}
```
다음으로 바꾼다:
```js
export async function updateReview(reviewId, userId, fields) {
  const { error } = await supabase.rpc('update_review_with_points', {
    p_user_id: userId,
    p_review_id: reviewId,
    p_work_year: fields.work_year,
    p_work_semester: fields.work_semester,
    p_work: fields.score_work,
    p_growth: fields.score_growth,
    p_vibe: fields.score_vibe,
    p_flex: fields.score_flex,
    p_recommend: fields.score_recommend,
    p_work_content: fields.work_content,
    p_opinion: fields.opinion,
    p_is_anonymous: fields.is_anonymous,
  })
  if (error) throw error
}
```

- [ ] **Step 5: `fetchReviews`는 절대 건드리지 않음 확인** — `author:users!user_id ( nickname, track, grade )` 조인과 `is_anonymous` select가 그대로 있는지 눈으로 확인(탈퇴 감지·표시 우선순위 의존). dodo의 nickname 제거를 이식하지 말 것.

- [ ] **Step 6: lint + 커밋**

Run: `cd web && npm run lint`
Expected: 에러 없음.
```bash
git add web/src/data/worksiteQueries.js
git commit -m "feat(data): 리뷰 작성/수정/조회에 is_anonymous + updateReview를 RPC로"
```

---

### Task 3: ConfirmModal에 className prop (공용, 하위호환)

**Files:**
- Modify: `web/src/components/ConfirmModal.jsx`

**Interfaces:**
- Produces: `<ConfirmModal message confirmText onConfirm onCancel className?>` — `className` 옵션(기본 `''`)을 모달 박스에 적용.

- [ ] **Step 1: className prop 추가**

`web/src/components/ConfirmModal.jsx` 전체를 다음으로 바꾼다:
```jsx
export default function ConfirmModal({ message, confirmText = '삭제', onConfirm, onCancel, className = '' }) {
  return (
    <div className="login-modal-overlay" onClick={onCancel}>
      <div className={`login-modal ${className}`.trim()} onClick={(e) => e.stopPropagation()}>
        <p>{message}</p>
        <div className="login-modal-actions">
          <button className="btn-login" onClick={onCancel}>취소</button>
          <button className="btn-signup-nav" onClick={onConfirm}>{confirmText}</button>
        </div>
      </div>
    </div>
  )
}
```

- [ ] **Step 2: 기존 호출부 회귀 확인** — `className`을 안 넘기는 기존 호출부(MyPage·ExchangeCenter·WorksiteDetail)는 `''`라 `login-modal`만 적용돼 동일 동작. lint 통과 확인.

Run: `cd web && npm run lint`
Expected: 에러 없음.

- [ ] **Step 3: 커밋**

```bash
git add web/src/components/ConfirmModal.jsx
git commit -m "feat(ui): ConfirmModal 옵션 className prop(하위호환)"
```

---

### Task 4: 익명 체크박스 (ReviewFormFields.jsx)

**Files:**
- Modify: `web/src/components/ReviewFormFields.jsx`

**Interfaces:**
- Consumes: 부모(ReviewForm)가 `isAnonymous`, `setIsAnonymous`, `isSubmitting` 전달.
- Produces: 제출 버튼 위 익명 체크박스 UI.

- [ ] **Step 1: props 추가** — 구조분해 목록에서
```js
  isUserLoading,
  userError,
  isSubmitting,
  isSubmitDisabled,
```
를 다음으로 바꾼다:
```js
  isUserLoading,
  userError,
  isSubmitting,
  isAnonymous,
  setIsAnonymous,
  isSubmitDisabled,
```

- [ ] **Step 2: 체크박스 JSX 삽입** — 제출 버튼
```jsx
        <button
          className="btn-submit"
          disabled={isSubmitDisabled}
          onClick={onSubmit}
        >
```
바로 **위**에 다음을 삽입한다:
```jsx
        <label className="anonymous-review-option">
          <input
            type="checkbox"
            checked={isAnonymous}
            disabled={isSubmitting}
            onChange={(event) => setIsAnonymous(event.target.checked)}
          />
          <span className="anonymous-review-copy">
            <strong>익명으로 작성하기</strong>
            <span>작성자 닉네임과 근무 학기가 공개되지 않아요. (-10P)</span>
          </span>
        </label>

```

- [ ] **Step 3: lint + 커밋**

Run: `cd web && npm run lint`
Expected: 에러 없음.
```bash
git add web/src/components/ReviewFormFields.jsx
git commit -m "feat(review): 작성 폼 익명 체크박스"
```

---

### Task 5: 폼 페이지 배선 + 모달 + 에러문구 + CSS (ReviewForm.jsx / .css)

**Files:**
- Modify: `web/src/pages/ReviewForm.jsx`
- Modify: `web/src/pages/ReviewForm.css`

**Interfaces:**
- Consumes: Task 2(`updateReview`/`createReview`/`fetchMyReviewForPeriod`), Task 3(`ConfirmModal` className), Task 4(체크박스 props).

- [ ] **Step 1: ConfirmModal import 추가** — 파일 상단 import 블록에 추가:
```js
import ConfirmModal from "../components/ConfirmModal";
```

- [ ] **Step 2: 상태 추가** — 아래 줄
```js
  const [isSubmitting, setIsSubmitting] = useState(false);
```
다음에 추가:
```js
  const [isAnonymous, setIsAnonymous] = useState(false);
  const [originalIsAnonymous, setOriginalIsAnonymous] = useState(false);
  const [showAnonymousConfirm, setShowAnonymousConfirm] = useState(false);
```

- [ ] **Step 3: edit 로드 시 익명값 초기화** — edit 분기에서
```js
          setWorkContent(review.work_content ?? "");
          setOpinion(review.opinion ?? "");
```
다음으로 바꾼다:
```js
          setWorkContent(review.work_content ?? "");
          setOpinion(review.opinion ?? "");
          setIsAnonymous(Boolean(review.is_anonymous));
          setOriginalIsAnonymous(Boolean(review.is_anonymous));
```

- [ ] **Step 4: 중복체크 useEffect의 호출부에 worksiteId 추가** — `checkExistingReview` 안의
```js
        const existingReview = await fetchMyReviewForPeriod(
          currentUser.id,
          Number.parseInt(workYear, 10),
          workSemester,
        );
```
다음으로 바꾼다:
```js
        const existingReview = await fetchMyReviewForPeriod(
          currentUser.id,
          Number(worksiteId),
          Number.parseInt(workYear, 10),
          workSemester,
        );
```

- [ ] **Step 5: 에러 헬퍼 2개 갱신(새 제약명 + INSUFFICIENT_POINTS)** — `reviewSaveErrorMessage`를
```js
function reviewSaveErrorMessage(error) {
  const errorText = [
    error?.code,
    error?.message,
    error?.details,
    error?.hint,
  ]
    .filter(Boolean)
    .join(" ");

  if (
    error?.code === "23505" ||
    errorText.includes("reviews_user_id_work_year_work_semester_key")
  ) {
    return "이미 이 학기에 작성한 리뷰가 있어요. 기존 리뷰를 수정해 주세요.";
  }

  return `리뷰 저장에 실패했습니다: ${error?.message ?? "알 수 없는 오류"}`;
}
```
다음으로 바꾼다:
```js
function reviewSaveErrorMessage(error) {
  const errorText = [
    error?.code,
    error?.message,
    error?.details,
    error?.hint,
  ]
    .filter(Boolean)
    .join(" ");

  if (errorText.includes("INSUFFICIENT_POINTS")) {
    return "포인트가 부족해 익명으로 바꿀 수 없어요.";
  }

  if (
    error?.code === "23505" ||
    errorText.includes("reviews_user_id_work_year_work_semester_key") ||
    errorText.includes("reviews_user_worksite_year_semester_key")
  ) {
    return "이미 이 학기에 작성한 리뷰가 있어요. 기존 리뷰를 수정해 주세요.";
  }

  return `리뷰 저장에 실패했습니다: ${error?.message ?? "알 수 없는 오류"}`;
}
```

그리고 `isDuplicateReviewError`의 `return (...)`를
```js
  return (
    error?.code === "23505" ||
    errorText.includes("reviews_user_id_work_year_work_semester_key")
  );
```
다음으로 바꾼다:
```js
  return (
    error?.code === "23505" ||
    errorText.includes("reviews_user_id_work_year_work_semester_key") ||
    errorText.includes("reviews_user_worksite_year_semester_key")
  );
```

- [ ] **Step 6: handleSubmit을 검증+모달/submitReview로 분할** — 기존 `async function handleSubmit() { ... }` 전체(잔액 검증·try/catch 포함)를 다음 **두 함수**로 교체한다:
```js
  function handleSubmit() {
    if (isUserLoading) {
      setNotice("정보를 불러오는 중입니다. 잠시 후 다시 시도해 주세요.");
      return;
    }

    if (userError || !admissionYear || !currentUser || !worksiteId) {
      setNotice("필수 정보를 확인할 수 없어 리뷰를 저장할 수 없습니다.");
      return;
    }

    if (
      !scoreWork ||
      !scoreGrowth ||
      !scoreVibe ||
      !scoreFlex ||
      !scoreRecommend
    ) {
      setNotice("모든 별점을 선택해 주세요.");
      return;
    }

    if (workContent.trim().length < 30) {
      setNotice("실제 업무 내용은 30자 이상 작성해 주세요.");
      return;
    }

    if (opinion.trim().length < 50) {
      setNotice("자유 의견은 50자 이상 작성해 주세요.");
      return;
    }

    // 익명으로 전환(포인트 감소)되는 경우만 확인 모달: 신규 익명 / 실명→익명.
    if (isAnonymous && (!isEdit || !originalIsAnonymous)) {
      setShowAnonymousConfirm(true);
      return;
    }

    submitReview();
  }

  async function submitReview() {
    setIsSubmitting(true);
    setDuplicateReview(null);

    try {
      if (isEdit) {
        if (!reviewId) {
          throw new Error("수정할 리뷰를 찾을 수 없습니다.");
        }

        await updateReview(reviewId, currentUser.id, {
          work_year: Number.parseInt(workYear, 10),
          work_semester: workSemester,
          score_work: scoreWork,
          score_growth: scoreGrowth,
          score_vibe: scoreVibe,
          score_flex: scoreFlex,
          score_recommend: scoreRecommend,
          work_content: workContent.trim(),
          opinion: opinion.trim(),
          is_anonymous: isAnonymous,
        });
      } else {
        await createReview({
          p_user_id: currentUser.id,
          p_worksite_id: Number(worksiteId),
          p_work_year: Number.parseInt(workYear, 10),
          p_work_semester: workSemester,
          p_work: scoreWork,
          p_growth: scoreGrowth,
          p_vibe: scoreVibe,
          p_flex: scoreFlex,
          p_recommend: scoreRecommend,
          p_work_content: workContent.trim(),
          p_opinion: opinion.trim(),
          p_is_anonymous: isAnonymous,
        });
      }

      navigate(`/worksite/${worksiteId}`);
    } catch (error) {
      const isDuplicate = isDuplicateReviewError(error);

      if (isDuplicate && currentUser) {
        try {
          const existingReview = await fetchMyReviewForPeriod(
            currentUser.id,
            Number(worksiteId),
            Number.parseInt(workYear, 10),
            workSemester,
          );
          setDuplicateReview(existingReview);
          setNotice("이미 해당 학기에 작성한 리뷰가 있어요.");
        } catch {
          setDuplicateReview(null);
        }
      } else {
        setNotice(reviewSaveErrorMessage(error));
      }
    } finally {
      setIsSubmitting(false);
    }
  }
```

- [ ] **Step 7: ReviewFormFields에 익명 props 전달** — JSX의
```jsx
        isUserLoading={isUserLoading}
        userError={userError}
        isSubmitting={isSubmitting}
        isSubmitDisabled={
```
를 다음으로 바꾼다:
```jsx
        isUserLoading={isUserLoading}
        userError={userError}
        isSubmitting={isSubmitting}
        isAnonymous={isAnonymous}
        setIsAnonymous={setIsAnonymous}
        isSubmitDisabled={
```

- [ ] **Step 8: 확인 모달 렌더** — `{notice && ( <Toast ... /> )}` 블록 **다음**, 닫는 `</>` 직전에 추가:
```jsx
      {showAnonymousConfirm && (
        <ConfirmModal
          className="anonymous-confirm-modal"
          confirmText="제출"
          message={
            isEdit ? (
              <>
                <strong>익명으로 수정할까요?</strong>
                적립된 10P가 회수돼요.
              </>
            ) : (
              <>
                <strong>익명으로 제출할까요?</strong>
                닉네임·근무 학기가 공개되지 않고, 실명보다 10P 적은 5P가 적립돼요.
              </>
            )
          }
          onConfirm={() => {
            setShowAnonymousConfirm(false);
            submitReview();
          }}
          onCancel={() => setShowAnonymousConfirm(false)}
        />
      )}
```

- [ ] **Step 9: CSS 블록 추가** — `web/src/pages/ReviewForm.css`의 `.btn-submit {` 규칙 **바로 위**에 다음 전체를 삽입:
```css
.anonymous-review-option {
  display: flex;
  align-items: center;
  gap: 12px;
  min-height: 64px;
  margin: 0 0 10px;
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 12px 14px;
  background: var(--bg);
  color: var(--text);
  cursor: pointer;
}

.anonymous-review-option:has(input:disabled) {
  cursor: not-allowed;
}

.anonymous-review-option:has(input:checked) {
  border-color: var(--primary-mid);
  background: var(--primary-light);
}

.anonymous-review-option input {
  flex: 0 0 auto;
  appearance: none;
  width: 18px;
  height: 18px;
  margin: 0;
  border: 1px solid var(--border-strong);
  border-radius: 4px;
  background: var(--card);
  cursor: inherit;
}

.anonymous-review-option input:checked {
  border-color: var(--primary);
  background: var(--primary);
  box-shadow: inset 0 0 0 4px var(--card);
}

.anonymous-review-option input:focus-visible {
  outline: 2px solid var(--primary);
  outline-offset: 2px;
}

.anonymous-review-copy {
  display: flex;
  min-width: 0;
  flex-direction: column;
  gap: 3px;
}

.anonymous-review-copy strong {
  font-size: 14px;
  font-weight: 600;
}

.anonymous-review-copy span {
  color: var(--text-muted);
  font-size: 12px;
  line-height: 1.45;
}

.anonymous-confirm-modal {
  max-width: 320px;
  padding: 22px 24px;
}

.anonymous-confirm-modal p {
  margin-bottom: 12px;
  color: var(--text-sub);
  font-size: 13px;
  font-weight: 400;
  line-height: 1.65;
}

.anonymous-confirm-modal p strong {
  display: block;
  margin-bottom: 8px;
  color: var(--text);
  font-size: 16px;
  font-weight: 700;
  line-height: 1.4;
}

.anonymous-confirm-modal .login-modal-actions {
  flex-direction: row-reverse;
  gap: 14px;
}

```

- [ ] **Step 10: lint + 수동 동작 확인(dev)**

Run: `cd web && npm run lint`
Expected: 에러 없음.

Run: `cd web && npm run dev` → 로그인 후 근무지 상세 → 리뷰 작성:
- 익명 체크 시 카피·하이라이트 표시, 제출 시 "익명으로 제출할까요?" 모달.
- 실명 제출은 모달 없이 저장.
- 기존 리뷰 수정 진입 시 체크 상태가 저장값으로 복원.
Expected: 위 동작 정상.

- [ ] **Step 11: 커밋**

```bash
git add web/src/pages/ReviewForm.jsx web/src/pages/ReviewForm.css
git commit -m "feat(review): 익명 작성/수정 배선 + 확인 모달 + 차등포인트 에러문구"
```

---

### Task 6: 마이페이지 삭제 카피 중립화 (MyPage.jsx)

**Files:**
- Modify: `web/src/pages/MyPage.jsx`

- [ ] **Step 1: 삭제 확인 문구 변경** — `removeReview` 안의
```js
    ask('이 리뷰를 삭제할까요? (적립한 15P가 회수됩니다)', '삭제', async () => {
```
를 다음으로 바꾼다(익명 리뷰는 5P만 회수라 고정 15P 표기는 부정확):
```js
    ask('이 리뷰를 삭제할까요? (적립한 포인트가 회수됩니다)', '삭제', async () => {
```

- [ ] **Step 2: lint + 커밋**

Run: `cd web && npm run lint`
Expected: 에러 없음.
```bash
git add web/src/pages/MyPage.jsx
git commit -m "fix(mypage): 리뷰 삭제 카피 중립화(익명 5P/실명 15P 차등 대응)"
```

---

### Task 7: 문서 동기화 (CLAUDE.md §5)

**Files:**
- Modify: `docs/db-schema.md`
- Modify: `docs/api-spec.md`
- Modify: `web/src/data/README.md`

- [ ] **Step 1: db-schema.md — reviews 테이블에 is_anonymous + unique 갱신**

`reviews` 블록(`user_id ... ON DELETE SET NULL` 줄 근처)에 컬럼 한 줄을 추가한다(opinion 컬럼 줄 다음 등 reviews 컬럼 목록 안):
```
  is_anonymous    BOOLEAN NOT NULL DEFAULT false     -- 익명 작성 여부(true면 작성자 닉네임·근로학기 숨김)
```
그리고 reviews의 `UNIQUE (user_id, work_year, work_semester)` 줄을 다음으로 바꾼다:
```
  UNIQUE (user_id, worksite_id, work_year, work_semester)   -- 근무지+학기당 1리뷰 (user_id NULL은 복수 허용)
```

- [ ] **Step 2: api-spec.md — write/delete 갱신 + update 신규 + payload**

`### CreateReviewPayload`의 ts 블록 마지막 필드 다음에 추가:
```
  p_is_anonymous: boolean   // 익명 여부(기본 false)
```
`### \`write_review_with_points\``의 설명줄 "리뷰 작성 + 포인트 +15."을 다음으로 바꾼다:
```
리뷰 작성 + 포인트(실명 +15 / 익명 +5). `createReview()` 내부에서 사용. 입력은 [`CreateReviewPayload`](#createreviewpayload).
```
그 파라미터 표 마지막에 행 추가:
```
| p_is_anonymous | boolean | 익명 여부(기본 false) |
```
`### \`delete_review_with_rollback\``의 "리뷰 삭제 + 포인트 −15."을 다음으로 바꾼다:
```
리뷰 삭제 + 그 리뷰가 실제로 받은 적립합 회수(실명 −15 / 익명 −5). 잔액 부족 시 `INSUFFICIENT_POINTS` 예외.
```
`delete_review_with_rollback` 섹션 **앞**에 신규 섹션을 추가:
```
### `update_review_with_points` → `void`
리뷰 수정 + 익명 토글 시 포인트 차액(±10)을 정규값(실명 15/익명 5)으로 스냅. `updateReview()` 내부에서 사용. 포인트 이력 없는 리뷰는 지급 안 함. 회수로 잔액 음수면 `INSUFFICIENT_POINTS`.

| 파라미터 | 타입 |
|----------|------|
| p_user_id | int |
| p_review_id | int |
| p_work_year / p_work_semester / p_work / p_growth / p_vibe / p_flex / p_recommend / p_work_content / p_opinion | (write와 동일) |
| p_is_anonymous | boolean |
```

- [ ] **Step 3: data/README.md — worksiteQueries 행 갱신**

`(d) 현재 파일` 표의 `worksiteQueries.js` 행에서 `write_review_with_points`(rpc) 부분을 `write_review_with_points`(rpc), `update_review_with_points`(rpc, 수정+차등포인트)로 바꾸고 `updateReview`가 table update→RPC로 바뀐 점을 한 마디 덧붙인다.

- [ ] **Step 4: 커밋**

```bash
git add docs/db-schema.md docs/api-spec.md web/src/data/README.md
git commit -m "docs: 리뷰 is_anonymous·차등포인트·update RPC 반영(db-schema·api-spec·data README)"
```

---

### Task 8: 통합 수동 QA (spec §8 시나리오)

**Files:** (없음 — 검증만)

- [ ] **Step 1: dev 서버에서 시나리오 전부 확인**

Run: `cd web && npm run dev`
다음을 확인(spec §8):
1. 실명 작성 → 카드에 닉네임·학기 노출, 포인트 +15.
2. 익명 작성 → 제출 모달, 카드 "익명"·학기 숨김, +5.
3. 실명→익명 수정 → 모달, 합계 5(−10).
4. 익명→실명 수정 → 모달 없음, 합계 15(+10).
5. 익명→익명 수정(점수만) → 모달 없음, 포인트 변화 0.
6. 삭제: 익명 −5 / 실명 −15(마이페이지 포인트 내역 확인).
7. 잔액 부족 시 익명 전환·삭제 → "포인트가 부족..." 문구.
8. 같은 근무지+기간 중복 작성 → 중복 안내.
9. 다른 근무지+같은 기간 작성 → 허용(중복 안내 없음).
10. 포인트 이력 없는 리뷰(write 행 없음) 수정·익명 토글 → 포인트 변화 0(게이트 동작). 시뮬: SQL로 points의 해당 review_id `review_write` 행 삭제 후 수정.
11. 작성자 라벨: 익명+탈퇴 시뮬(해당 리뷰 user_id를 SQL로 NULL) → "익명"(탈퇴 아님) / 비익명+탈퇴 → "탈퇴한 사용자".

Expected: 모두 통과. 실패 시 해당 Task로 돌아가 수정.

- [ ] **Step 2: 최종 lint**

Run: `cd web && npm run lint`
Expected: 에러 없음.

> 참고(배포): DB 마이그레이션 `supabase db push`는 **변경자(배경록)가 직접**, push 전 디스코드 공유(CLAUDE.md §3.3). 코드 푸시는 별도 합의 후.

---

## 부록: 범위 밖(이 플랜에서 하지 않음)
- debt #6(익명인데 nickname이 payload에 실림) 서버측 마스킹.
- 회원탈퇴 실제 구현(현재 placeholder).
- dodo `feature/review-form`의 비-익명 변경(Home·Dropdown·Login 등) 이식.
