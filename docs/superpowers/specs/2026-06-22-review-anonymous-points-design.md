# 리뷰 익명 작성 + 차등 포인트 — 설계 (spec)

- 날짜: 2026-06-22
- 담당: 배경록(PM, 전체) — 도유진(dodo) 합의하에 작성/수정·RPC·포인트까지 인수
- 상태: 설계 확정 대기(이 문서 리뷰 후 writing-plans로 구현 계획 작성)
- ⚠️ **후속 변경(2026-06-23, 배경록):** 중복 기준 unique 키를 4-col `(user, worksite, year, semester)` → **3-col `(user, work_year, work_semester)`로 되돌림** = "한 학기당 리뷰 1개(근무지 불문)". 마이그레이션 `20260623000000_review_unique_per_semester.sql`(제약명 `reviews_user_year_semester_key`). 프론트도 `fetchMyReviewForPeriod`에서 worksite 필터 제거 + 중복판정의 same-worksite 게이트 제거. **아래 §4.1(2)·§4.2·§4.4·§8 #8~9의 4-col 서술은 이 결정으로 대체됨.**

## 1. 목표
기존 리뷰 작성 폼에 **익명 작성** 옵션을 추가하고, 작성자 표시(닉네임·근로학기)를 가리며,
**차등 포인트**(실명 15P / 익명 5P)를 **대칭 레저 모델**로 정확히 처리한다.

## 2. 배경·핵심 발견 (조사 결과)
- 리뷰 작성 폼([ReviewForm.jsx](../../../web/src/pages/ReviewForm.jsx), [ReviewFormFields.jsx](../../../web/src/components/ReviewFormFields.jsx))은 이미 동작. **익명만 얹으면 됨.**
- **dodo가 이미 익명 기능을 전부 구현**했으나 `feature/review-form`(commit `9ae21b3`)에 **미머지·스테일** 상태:
  - DB: `is_anonymous` 컬럼 + 12-arg `write_review_with_points`(단, **flat +15**, 차등 없음) + unique 키를 `(user, worksite, year, semester)`로 변경. **이미 live에 직접 push됨**(리포 마이그레이션엔 없음 = 드리프트).
  - 프론트: `익명으로 작성하기` 체크박스(`(-10P)` 카피 포함) + `ConfirmModal`("익명으로 제출할까요? … 10P가 차감됩니다") + 작성/수정 와이어링.
  - **UI 카피는 -10P를 약속하지만 백엔드(RPC)는 flat 15라 실제 차감을 안 함** → 차등 포인트 미완성.
  - 브랜치가 main의 Dropdown 통일·상세표시 작업 *이전*에 갈라져 매우 스테일(`Dropdown.jsx` 삭제, `Home.jsx` 리라이트, `fetchReviews`에서 nickname 제거 등). **통째 머지 금지.**
- live `reviews` 데이터는 **전부 더미** → 마이그레이션 과감하게 가능(단 컬럼은 보존형으로).

## 3. 결정 사항 (확정)
1. **범위**: 폼 + data 레이어 + RPC + 차등 포인트 전부 배경록.
2. **포인트 모델 = 대칭 레저**:
   - 실명 작성 +15, 익명 작성 +5
   - 수정 실명→익명 −10(회수), 익명→실명 +10(지급)
   - 삭제 시 **그 리뷰가 실제로 받은 합계**만큼 회수(익명 −5, 실명 −15, 전환 이력 자동 반영)
   - `points` 테이블을 장부(ledger)로 사용 → 항상 일관·비게임.
3. **통합 방식**: 스테일 브랜치 머지 ❌. dodo의 **익명 부분만 현재 main에 이식** + 차등 포인트 신규.
4. **DB**: **단일 정본 마이그레이션** 하나로 컬럼·제약·RPC 3종 재구축(데이터 보존형).
5. **UX**: 제출 버튼 위 체크박스 + 포인트 차이 명시(dodo 카피 재사용) + `ConfirmModal` 재확인.

## 4. 상세 설계

### 4.1 DB 마이그레이션 (단일 파일)
`web/supabase/migrations/<생성ts>_review_anonymous_points.sql`
(`cd web && npx supabase migration new review_anonymous_points`로 생성 — main 최신 `20260619000000` 뒤)

헤더 2줄 필수:
```
-- 목적: 리뷰 익명 작성/수정 + 차등 포인트(익명 5P/실명 15P, 대칭 레저). 컬럼·unique·RPC 3종 정본 재구축.
-- 날짜: 2026-06-22 · 담당: 배경록
```

SQL 본문:

```sql
-- (1) is_anonymous 컬럼 — 데이터 보존(if not exists)
alter table public.reviews
  add column if not exists is_anonymous boolean not null default false;

-- (2) 중복 기준 = (user, worksite, year, semester).
--     ⚠ live 제약명이 불명(드리프트). baseline은 reviews_user_id_work_year_work_semester_key,
--        dodo가 직접 올린 4-col은 auto-name이 다를 수 있음(예: reviews_user_id_worksite_id_work_year_work_semester_key).
--     → 이름을 추측하지 말고, reviews의 모든 unique '제약'을 제거 후 정본 1개만 add(이름 무관·멱등).
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
-- 참고: dodo는 unique '제약'으로 생성했고 baseline도 table-level unique → pg_constraint로 모두 커버.
--       (혹시 unique INDEX로 만들었다면 pg_indexes도 확인 필요 — 현재는 해당 없음.)

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

-- (4) update RPC — 수정 시 익명 토글. 정규값(5/15)으로 스냅(delta = target - 현재 적립합).
--     방어적 drop(혹시 live 드리프트로 다른 시그니처 존재 시 create or replace 실패 방지). 현재 live엔 없음 확인됨.
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
  -- 소유권 검증 겸 수정(소유 아니면 0행 → not found)
  update public.reviews set
    work_year = p_work_year, work_semester = p_work_semester,
    score_work = p_work, score_growth = p_growth, score_vibe = p_vibe,
    score_flex = p_flex, score_recommend = p_recommend,
    work_content = p_work_content, opinion = p_opinion,
    is_anonymous = coalesce(p_is_anonymous, false), updated_at = now()
  where id = p_review_id and user_id = p_user_id;
  if not found then raise exception 'REVIEW_NOT_FOUND'; end if;

  -- 현재까지 그 리뷰가 받은 적립합 + write 적립행 존재 여부
  select coalesce(sum(amount), 0), bool_or(reason = 'review_write')
    into v_grant, v_has_write
  from public.points
  where review_id = p_review_id and reason in ('review_write', 'review_anon_switch');

  -- ⚠ 포인트 적립 이력이 없는(포인트 시스템 이전) 리뷰는 토글로 포인트를 새로 '지급'하지 않음.
  --   (이 게이트가 없으면 v_grant=0 → v_delta=+target 으로 5/15를 공짜 지급하는 버그.)
  if not coalesce(v_has_write, false) then
    return;
  end if;

  v_delta := v_target - v_grant;  -- 합계를 정확히 5 또는 15로 스냅(레거시 flat15도 자동 교정)
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

설계 노트:
- 보안 모델은 기존과 동일(SECURITY INVOKER, 명시 grant 없이 PUBLIC 실행 — 기존 RPC와 일치). RLS 부재(debt #4)는 본 작업 범위 밖.
- `reason` 신규 값 `review_anon_switch`(18자, varchar(50) OK).
- `points.review_id`는 `on delete set null` → 삭제 회수행 기록 후 삭제해도 이력 안전.
- write는 옛 11-arg `drop`(오버로드 방지, CLAUDE.md §3.4) + `create or replace`(드리프트 견고). update는 방어적 `drop` 후 `create or replace`. delete는 동일 시그니처라 `create or replace`.
- **멱등성 주의**: 대부분 멱등이나, write의 `create or replace`는 옛 11-arg가 안 지워졌으면 오버로드가 남을 수 있음 → 11-arg `drop`이 선행돼야 함(맨바닥/드리프트 모두 OK 확인됨).
- reviews는 **hard-delete**(코드 어디서도 `deleted_at`를 set 안 함). update/delete RPC가 `deleted_at` 필터를 안 거는 건 의도적·무해. 추후 soft-delete 도입 시 read/RPC 동시 변경 필요.

### 4.2 data 레이어 — [worksiteQueries.js](../../../web/src/data/worksiteQueries.js)
- `createReview`: payload에 `p_is_anonymous` 키 추가(주석도 갱신). RPC 스프레드라 코드 변경은 호출부에서 키만 추가.
- `fetchMyReviewById`: select에 `is_anonymous` 추가(dodo와 동일).
- `fetchMyReviewForPeriod(userId, worksiteId, workYear, workSemester)`: **worksiteId 인자 추가 + 쿼리 본문에 `.eq('worksite_id', worksiteId)` 추가**(시그니처만 바꾸면 안 됨 — 새 4-col 키에선 같은 학기에 다른 근무지 리뷰가 여러 개 가능 → `.maybeSingle()`이 PGRST116로 터짐). 호출부 2곳(ReviewForm.jsx 중복체크 useEffect·catch) 모두 worksiteId 전달.
- `updateReview(reviewId, userId, fields)`: 단순 table update → **RPC `update_review_with_points` 호출로 교체**. 호출 시그니처는 유지(내부에서 fields→p_* 매핑):
  ```js
  await supabase.rpc('update_review_with_points', {
    p_user_id: userId, p_review_id: reviewId,
    p_work_year: fields.work_year, p_work_semester: fields.work_semester,
    p_work: fields.score_work, p_growth: fields.score_growth, p_vibe: fields.score_vibe,
    p_flex: fields.score_flex, p_recommend: fields.score_recommend,
    p_work_content: fields.work_content, p_opinion: fields.opinion,
    p_is_anonymous: fields.is_anonymous,
  })
  ```
- `deleteReview`: 호출부 동일(내부 RPC 본문만 바뀜).
- **`fetchReviews`는 변경 안 함** — dodo의 nickname 제거는 표시 코드와 충돌. is_anonymous 시 nickname 마스킹은 현재 UI(ReviewCard)에서만 → **debt #6(payload 마스킹) 미해결·악화 없음**.

### 4.3 프론트 — 폼 (dodo 익명 부분만 이식)
**[ReviewFormFields.jsx](../../../web/src/components/ReviewFormFields.jsx)**
- props `isAnonymous`, `setIsAnonymous` 추가.
- 제출 버튼 바로 위에 dodo의 `.anonymous-review-option` 체크박스 이식:
  - 카피: `익명으로 작성하기` / `작성자 닉네임과 근무 학기가 공개되지 않아요. (-10P)`
  - `disabled`는 **`isSubmitting`만** 사용(dodo의 `isDuplicateLocked` 결합은 **이식 안 함** — 스테일 범위 밖).

**[ReviewForm.jsx](../../../web/src/pages/ReviewForm.jsx)**
- `import ConfirmModal`.
- state: `isAnonymous`(기본 false), `originalIsAnonymous`(수정 델타/모달 판정), `showAnonymousConfirm`.
- edit 로드 시 `setIsAnonymous(Boolean(review.is_anonymous))` + `setOriginalIsAnonymous(...)`.
- `handleSubmit`: 검증 후 **포인트가 줄어드는 경우에만 모달** → `showModal = isAnonymous && (!isEdit || !originalIsAnonymous)`
  - 신규 익명 / 실명→익명 = 모달. 익명→익명(변화 없음)·익명→실명·실명→실명 = 모달 없음.
  - (dodo는 `if (isAnonymous)`로 익명→익명에도 "10P 차감" 모달이 떠 오해 소지 → 위 조건으로 수정.)
- `ConfirmModal` 카피(정정) — `message`는 ReactNode 허용(`<p>{message}</p>`)이라 `<strong>`+`<br/>`로 2줄 전달:
  - 신규 익명: `익명으로 제출할까요?` / `닉네임·근무 학기가 공개되지 않고, 실명보다 10P 적은 5P가 적립돼요.`
  - 실명→익명: `익명으로 수정할까요?` / `적립된 10P가 회수돼요.`

**[ConfirmModal.jsx](../../../web/src/components/ConfirmModal.jsx) — 작은 확장 필요(공용)**
- 현재 props `{message, confirmText='삭제', onConfirm, onCancel}` + 박스에 `.login-modal` 하드코딩 → dodo의 `.anonymous-confirm-modal` CSS가 **적용 안 됨**.
- **옵션 `className` prop 추가**(기본 `""`, 박스에 `` `login-modal ${className}` `` 적용). 하위호환(기존 호출부 영향 없음) — MyPage·ExchangeCenter·WorksiteDetail 그대로 동작.
- 호출 시 `confirmText="제출"`, `className="anonymous-confirm-modal"`.
- 익명→실명 수정 성공 시 토스트 `10P가 적립됐어요.`(선택, 가벼운 안내).
- `createReview`에 `p_is_anonymous`, `updateReview` fields에 `is_anonymous` 전달.
- 중복 처리: `fetchMyReviewForPeriod`에 worksiteId 전달(2곳: useEffect 중복체크 + catch).

**[ReviewForm.css](../../../web/src/pages/ReviewForm.css)**
- dodo의 `.anonymous-review-option`(:has 상태 포함)·`.anonymous-review-copy`·`.anonymous-confirm-modal` 블록 이식.

### 4.4 에러 처리 — [ReviewForm.jsx](../../../web/src/pages/ReviewForm.jsx)
- **제약명 변경 반영**: `isDuplicateReviewError`/`reviewSaveErrorMessage`의 옛 이름
  `reviews_user_id_work_year_work_semester_key` → **새 이름 `reviews_user_worksite_year_semester_key`** 추가(안 하면 중복 감지 깨짐). code `23505`는 그대로 사용.
- `INSUFFICIENT_POINTS`(수정 회수·삭제) → 친절 문구(예: "포인트가 부족해 익명으로 바꿀 수 없어요.").

### 4.5 추가 호출부 (삭제 카피)
- **[MyPage.jsx](../../../web/src/pages/MyPage.jsx)** 삭제 확인 문구가 `적립한 15P가 회수됩니다`로 하드코딩 → 차등 포인트에선 익명 리뷰는 5P만 회수라 **거짓말이 됨**. → **중립 문구 `적립한 포인트가 회수됩니다`** 로 변경(또는 리뷰의 is_anonymous로 5/15 동적). 
- **[WorksiteDetail.jsx](../../../web/src/pages/WorksiteDetail.jsx)** 삭제 문구엔 금액이 없어 OK(확인됨). 변경 불필요.
- 표시쪽 [ReviewCard.jsx](../../../web/src/components/ReviewCard.jsx)·`fetchReviews`는 **이미 익명 마스킹·"익명" 라벨 구현 완료** → 코드 변경 없음. 단 **작성자 라벨 우선순위는 §4.7로 명문화·고정**하고, `fetchReviews`의 `author:users!user_id(...)` 조인을 **유지해야** 탈퇴(author null) 감지가 동작(= dodo의 nickname 제거를 이식하지 않는 또 다른 이유).

### 4.7 작성자 라벨 표시 우선순위 (익명/탈퇴)
배경: `reviews.user_id`는 `on delete set null`(baseline 125, "탈퇴 시 NULL") → 작성자 탈퇴 시 `fetchReviews`의 author 조인이 null. 회원탈퇴는 현재 placeholder([MyPage.jsx](../../../web/src/pages/MyPage.jsx) "준비 중")지만 FK·라벨은 이미 대비됨.

**[ReviewCard.jsx](../../../web/src/components/ReviewCard.jsx) `authorLabel(r)` 우선순위 (남의 리뷰 기준) — 현재 구현 그대로 고정:**
1. `isMine` → "내 리뷰" (+ `is_anonymous`면 "익명" 태그) — authorLabel 이전, 카드에서 분기.
2. **`is_anonymous` → "익명"** ← 최우선. 탈퇴 여부와 무관하게 익명 선택을 보장(탈퇴 사실도 숨김).
3. `!author`(user_id NULL = 탈퇴) → "탈퇴한 사용자".
4. `author.nickname` → "{nickname}님".
5. (nickname 없음) → "익명" fallback.

**우선순위 근거 (익명 > 탈퇴 — 이 순서가 중요):**
- 익명 리뷰는 작성자가 탈퇴해도 동일하게 "익명" → 익명성·탈퇴사실 모두 보호. 익명 리뷰는 작성자 상태와 무관하게 항상 같은 모습.
- **forward-compat**: 추후 debt #6(서버측 익명 마스킹: 익명이면 author NULL로 응답) 적용 시 익명 리뷰도 author가 null이 됨. `is_anonymous`를 author-null보다 **먼저** 검사하므로 익명 리뷰가 "탈퇴한 사용자"로 오표시되지 않음. (순서를 뒤집으면 그날 버그.)
- 비익명 리뷰의 작성자가 탈퇴 → 닉네임이 사라지므로 "탈퇴한 사용자"(닉네임 노출 불가).

**부수 표시(근로학기·작성일):** `!is_anonymous || isMine`일 때만 노출 → 익명은 숨김, 탈퇴(비익명)는 노출(작성자 식별만 사라지고 리뷰 내용·시점은 유효). 현재 동작 유지.

**범위:** 코드 변경 없음(이미 올바름). 본 절은 규칙을 **고정·문서화**하고, 위 의존성(author 조인 유지)을 보장하기 위한 것.

### 4.6 문서 갱신 (CLAUDE.md §5 — 스키마·RPC 변경 시 필수)
- **[docs/db-schema.md](../../db-schema.md)**: reviews에 `is_anonymous boolean` 추가, UNIQUE를 `(user_id, worksite_id, work_year, work_semester)`로 갱신.
- **[docs/api-spec.md](../../api-spec.md)**: `write_review_with_points`에 `p_is_anonymous` + 차등 포인트(5/15), **`update_review_with_points` 항목 신규 추가**, `delete_review_with_rollback`을 "실제 적립합 회수"로 수정, `review_anon_switch` reason 기재.
- **[web/src/data/README.md](../../../web/src/data/README.md)**: RPC 목록에 `update_review_with_points` 추가, `updateReview`가 table update→RPC로 바뀜 반영.

## 5. 엣지 케이스
- **레거시 flat-15 익명 리뷰**(dodo live RPC로 익명인데 15 받은 경우): 수정하면 `v_delta = target - grant`로 합계를 5/15로 **자동 교정**.
- **잔액 음수 방지**: 회수(−delta)·삭제 시 `balance + delta < 0`이면 `INSUFFICIENT_POINTS`.
- **수정으로 기간 충돌**: unique(user,worksite,year,semester) 위반 → `23505` → 기존 중복 UI로 처리.
- **포인트 0행 리뷰**(포인트 시스템 이전, `review_write` 행 없음):
  - 삭제 → `v_grant=0` 회수 0, 안전.
  - 수정 → **게이트(`v_has_write`)로 포인트 지급 안 함**. (게이트 없으면 `v_delta=+target`로 5/15 공짜 지급 버그 — §4.1 (4)에서 차단.)
- **동시 수정/삭제**: 같은 리뷰 동시 처리 시 레이스 가능 — 현 범위에선 단일 트랜잭션으로 충분(고동시성 아님). 필요 시 `select ... for update`는 후속.

## 6. 범위 밖 / 미해결
- debt #6(익명인데 nickname이 payload에 실림) — 서버측 마스킹은 별도 작업.
- dodo의 비-익명 스테일 변경(Home·Dropdown 삭제·Login·Search 등) — 이식 안 함.
- RLS 부재(debt #4) — 별도.
- 광고/패스 등 다른 live 드리프트 함수(`watch_ad_reward` 등) — 별도.

## 7. 리스크·팀 조율 (CLAUDE.md §3)
- **push 전 디스코드 공유**(§3.1). dodo가 `feature/review-form`를 별도로 머지하지 않도록 합의 — 본 단일 마이그레이션이 정본.
- **live 드리프트**: dodo가 직접 올린 컬럼·RPC·제약이 이미 live에 존재 → 본 마이그레이션은 전부 멱등/`drop if exists` 기반이라 재적용 안전. 함수 충돌 시 `drop` 후 재push.
- **db reset 검증**(§3.2): Docker 없이 baseline이라 로컬 reset이 어려울 수 있음 → 검증 방법 디스코드 합의. 더미 데이터라 위험 낮음.
- **함수 시그니처 변경**: write의 옛 11-arg는 반드시 `drop`(§3.4).
- **제약명 추측 제거**: §4.1 (2)를 DO 블록(모든 unique 제약 일괄 drop)으로 처리 → live 제약명이 무엇이든 안전(중복 제약·leftover 함정 회피). 추가 안전을 원하면 push 전 `select conname from pg_constraint where conrelid='public.reviews'::regclass and contype='u'`로 실제 이름 확인.
- **중복 더미 데이터**: 새 4-col unique add 시 기존 더미 행이 충돌하면 `add constraint` 실패 가능. baseline엔 reviews seed 없음(맨바닥 reset 시 0행 → 안전). live에서 실패하면 더미라 `delete from public.reviews` 후 재push(데이터 손실 무방 — 전부 더미).
- 마이그레이션 헤더에 **"feature/review-form의 DB 변경을 대체(정본)"** 명시 → 추후 혼동 방지.

## 8. 테스트 (수동 시나리오)
1. 실명 작성 → +15, 카드에 닉네임·학기 노출.
2. 익명 작성 → +5, 카드에 "익명", 학기 숨김, 제출 전 모달.
3. 실명→익명 수정 → −10(합계 5), 모달.
4. 익명→실명 수정 → +10(합계 15), 모달 없음.
5. 익명→익명 수정(점수만) → 포인트 변화 0, 모달 없음.
6. 삭제(익명) → −5 / 삭제(실명) → −15.
7. 잔액 부족 시 익명 전환·삭제 → 친절 에러.
8. 같은 **학기** 중복 작성 → `23505` 중복 안내(제약명 `reviews_user_year_semester_key`).
9. **다른 근무지+같은 학기** 작성 → **차단**(3-col 키 = 한 학기 1리뷰) — "이미 이 학기에 작성한 리뷰" 안내 + 기존 리뷰로 이동.
10. 포인트 이력 없는 리뷰 수정(익명 토글) → 포인트 변화 0(게이트 동작).
11. **작성자 라벨 우선순위**(§4.7): 익명+작성자탈퇴 → "익명"(탈퇴 아님) / 비익명+탈퇴 → "탈퇴한 사용자" / 비익명+정상 → "{닉네임}님". (탈퇴는 user_id NULL 수동 세팅으로 시뮬레이션 가능.)

## 9. 후속(별도 이슈)
- debt #6 서버측 익명 마스킹(익명이면 author NULL 뷰/RPC).
- dodo `feature/review-form`의 나머지 가치 있는 변경 선별 이식(있다면).
