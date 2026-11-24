# 리뷰 작성 입학연도 제약 삭제 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** 리뷰 폼의 근무 연도를 입학연도와 분리해 올해부터 3년 전까지 4개를
노출하고, 오래된 기존 리뷰는 원래 연도를 유지한 채 수정할 수 있게 한다.

**Architecture:** `lib/semesters.js`에 시간 주입형 순수 함수
`reviewFormYearOptions`를 두고, `ReviewForm`은 현재 수정 대상의
`originalWorkYear`만 레거시 예외로 전달한다. 미래·비정상 연도는 예외에 포함하지
않고 올해로 정규화한다. 이 범위는 프론트 UX 정책이며 DB/RPC 제약으로 승격하지
않는다.

**Tech Stack:** React 19.2.6 · Vite 8.0.12 · Vitest 4.1.8 · 새 의존성 없음

**설계 문서:** `docs/superpowers/specs/2026-07-26-review-year-constraint-design.md`

## Global Constraints

- 작업 브랜치: `feature/review-year-constraint`.
- **DB 변경 없음.** 마이그레이션 생성·`supabase db push`를 하지 않는다.
- 4년 범위는 **정상 UI의 선택 정책**이다. RPC 직접 호출에 대한 서버 무결성
  보장으로 표현하지 않는다.
- 기본 선택지는 `[올해, 올해-1, 올해-2, 올해-3]` 내림차순이다.
- `include` 예외는 기본 범위보다 오래된 **1 이상의 정수 과거 연도**에만
  적용한다. 미래·0 이하·비정수·`NaN`은 무시한다.
- 레거시 예외의 진실원천은 현재 선택값 `workYear`가 아니라 수정 대상으로
  불러온 `originalWorkYear`다.
- `originalWorkYear`는 `reviewId`/`worksiteId` 변경 및 신규 작성 전환 때
  초기화한다.
- `reviewFormSemesterOptions`와 국가근로 학기 필터는 수정하지 않는다.
- 회원가입·프로필의 `admission_year` 입력/저장 로직은 수정하지 않는다.
- 새 npm 의존성이나 컴포넌트 테스트 인프라를 추가하지 않는다.
- 현재 전체 lint 기준선은 **9 errors / 4 warnings**다. 기존 오류를 범위 밖에서
  고치지 않고, 최종 결과가 이보다 늘지 않았는지 비교한다. 이번 작업이
  `semesters.test.js`의 `MAX_REVIEWS` 미사용 경고를 제거하므로 예상치는
  **9 errors / 3 warnings 이하**다.
- 모든 파일 편집은 저장소의 기존 줄바꿈·포맷을 가능한 한 유지한다.

## File Structure

| 파일 | 조치 |
|---|---|
| `web/src/lib/semesters.js` | `REVIEW_YEAR_SPAN`·`reviewFormYearOptions` 추가, `availableSemesters`와 전용 헬퍼 삭제 |
| `web/src/lib/semesters.test.js` | 옛 입학연도 기반 테스트를 새 연도 옵션 테스트로 교체 |
| `web/src/pages/ReviewForm.jsx` | 입학연도 state/가드 제거, `originalWorkYear` 기반 옵션·정규화·제출 검증 배선 |
| `web/src/data/worksiteQueries.js` | 미사용 `fetchWrittenSemesters` 삭제 |
| `web/src/lib/README.md` | `semesters.js` 책임 설명 갱신 |
| `web/src/data/README.md` | `fetchWrittenSemesters` 언급 제거 |

---

## Task 0: 기준선과 사용처 고정

코드를 바꾸기 전에 현재 브랜치·워킹트리와 죽은 코드의 실제 사용처를 다시 확인한다.

- [ ] **Step 1: 브랜치와 워킹트리 확인**

Run:

```powershell
git branch --show-current
git status --short
```

Expected:

- 브랜치 `feature/review-year-constraint`
- 계획/설계 문서 변경 외 예상하지 못한 사용자 변경 없음

- [ ] **Step 2: 삭제 대상 사용처 확인**

Run:

```powershell
rg -n "availableSemesters|currentYearSemester|semesterKey|fetchWrittenSemesters|MAX_REVIEWS" web/src
```

Expected:

- `availableSemesters`·`currentYearSemester`·`semesterKey`는
  `semesters.js`와 `semesters.test.js` 안에서만 사용
- `fetchWrittenSemesters`는 `worksiteQueries.js` 정의와 `data/README.md`
  설명에만 존재
- `MAX_REVIEWS`는 `semesters.test.js`의 미사용 import만 존재

- [ ] **Step 3: 자동 테스트 기준선 확인**

Run:

```powershell
cmd /c "cd web && npm run test -- src/lib/semesters.test.js"
```

Expected: `Test Files 1 passed`, 기존 테스트 10개 통과.

---

## Task 1: 연도 옵션 순수 함수 — 테스트 우선

**Files:**

- Modify: `web/src/lib/semesters.test.js`
- Modify: `web/src/lib/semesters.js`

**Interfaces:**

- Produces: `REVIEW_YEAR_SPAN = 4`
- Produces:
  `reviewFormYearOptions({ now: Date, include?: number | null }): number[]`
- Removes: `semesterKey`, `currentYearSemester`, `availableSemesters`

- [ ] **Step 1: 옛 테스트를 제거하고 새 실패 테스트 작성**

`semesters.test.js`에서 다음을 제거한다.

- `availableSemesters`, `semesterKey`, `MAX_REVIEWS` import
- `describe("availableSemesters", ...)` 전체

같은 파일에 아래 테스트를 추가한다.

```js
import {
  REVIEW_YEAR_SPAN,
  reviewFormSemesterOptions,
  reviewFormYearOptions,
} from "./semesters";

const YEAR_NOW = new Date(2026, 6, 26);

describe("reviewFormYearOptions", () => {
  it("올해부터 3년 전까지 4개를 최신순으로 반환", () => {
    const options = reviewFormYearOptions({ now: YEAR_NOW });
    expect(options).toHaveLength(REVIEW_YEAR_SPAN);
    expect(options).toEqual([2026, 2025, 2024, 2023]);
  });

  it("범위보다 오래된 원래 리뷰 연도는 끝에 병합", () => {
    expect(
      reviewFormYearOptions({ now: YEAR_NOW, include: 2020 }),
    ).toEqual([2026, 2025, 2024, 2023, 2020]);
  });

  it("기본 범위 안 연도는 중복 추가하지 않음", () => {
    expect(
      reviewFormYearOptions({ now: YEAR_NOW, include: 2024 }),
    ).toEqual([2026, 2025, 2024, 2023]);
  });

  it("include가 null이면 기본 4개 그대로", () => {
    expect(
      reviewFormYearOptions({ now: YEAR_NOW, include: null }),
    ).toEqual([2026, 2025, 2024, 2023]);
  });

  it("미래·0 이하·비정수·NaN은 예외로 추가하지 않음", () => {
    for (const include of [2027, 0, -1, 2020.5, Number.NaN]) {
      expect(
        reviewFormYearOptions({ now: YEAR_NOW, include }),
      ).toEqual([2026, 2025, 2024, 2023]);
    }
  });
});
```

- [ ] **Step 2: 새 테스트가 실패하는지 확인**

Run:

```powershell
cmd /c "cd web && npm run test -- src/lib/semesters.test.js"
```

Expected: FAIL — `REVIEW_YEAR_SPAN` 또는 `reviewFormYearOptions` export가 아직 없음.

- [ ] **Step 3: 최소 순수 함수 구현**

`semesters.js`에서 `semesterKey`, `currentYearSemester`,
`availableSemesters`를 삭제하고 `SEMESTER_ORDER` 아래에 추가한다.

```js
export const REVIEW_YEAR_SPAN = 4

// 리뷰 폼 근무 연도(최신순). 오래된 기존 리뷰의 원래 연도만 include로 보존한다.
// lib 계약: 의존성 0 · DOM 금지 · 현재 시간은 now로 주입.
export function reviewFormYearOptions({ now, include = null }) {
  const currentYear = now.getFullYear()
  const options = Array.from(
    { length: REVIEW_YEAR_SPAN },
    (_, index) => currentYear - index,
  )
  const oldestDefaultYear = options[options.length - 1]

  if (
    Number.isInteger(include) &&
    include >= 1 &&
    include < oldestDefaultYear
  ) {
    options.push(include)
  }

  return options
}
```

`options`가 이미 내림차순이고 추가되는 값은 항상 마지막 기본값보다 작으므로 별도
정렬은 하지 않는다.

- [ ] **Step 4: 타깃 테스트 통과 확인**

Run:

```powershell
cmd /c "cd web && npm run test -- src/lib/semesters.test.js"
```

Expected: PASS — 연도 옵션 5개 + 기존 학기 옵션 6개, 총 11개 테스트.

- [ ] **Step 5: 삭제 대상이 lib/test에서 사라졌는지 확인**

Run:

```powershell
rg -n "availableSemesters|currentYearSemester|semesterKey|MAX_REVIEWS" web/src/lib
```

Expected: 출력 없음.

- [ ] **Step 6: 커밋**

```powershell
git add web/src/lib/semesters.js web/src/lib/semesters.test.js
git commit -m "feat(review): 리뷰 폼 연도 옵션을 최근 4년으로 고정"
```

---

## Task 2: `ReviewForm` 배선 — 입학연도 제거와 레거시 수정 보존

**Files:**

- Modify: `web/src/pages/ReviewForm.jsx`

**Interfaces:**

- Consumes: `reviewFormYearOptions`
- State: `originalWorkYear: number | null`
- Removes: `admissionYear`, `setAdmissionYear`, 입학연도 진입/제출 가드

- [ ] **Step 1: import와 초기 연도 스냅샷 정리**

`../lib/semesters` import에 `reviewFormYearOptions`를 추가한다.

파일 상단의 전역 시간 접근 함수:

```js
function getInitialYear() {
  return String(new Date().getFullYear());
}
```

를 삭제한다. 컴포넌트 안에서는 이미 고정 스냅샷 `now`가 있으므로 다음처럼 같은
값으로 초기화한다.

```js
const now = useMemo(() => new Date(), []);
const currentYear = now.getFullYear();

const [workYear, setWorkYear] = useState(() => String(currentYear));
```

- [ ] **Step 2: state와 파생 옵션 교체**

삭제:

```js
const [admissionYear, setAdmissionYear] = useState(null);
```

추가:

```js
const [originalWorkYear, setOriginalWorkYear] = useState(null);
```

기존 입학연도 기반 `yearOptions` 배열을 아래로 교체한다.

```js
const yearOptions = useMemo(
  () => reviewFormYearOptions({ now, include: originalWorkYear }),
  [now, originalWorkYear],
);
```

- [ ] **Step 3: 로딩 시작 시 라우트별 레거시 예외 초기화**

`loadFormData()`가 로딩 상태를 초기화하는 부분에서 이전 수정 대상의 예외를 지운다.
신규 작성으로 전환된 경우에는 연도도 올해로 초기화한다.

```js
setIsUserLoading(true);
setUserError(null);
setOriginalWorkYear(null);
if (!isEdit) setWorkYear(String(currentYear));
```

이 초기화는 수정 리뷰 A의 2020년 예외가 수정 리뷰 B나 신규 작성 폼에 남는 것을
막는다. 다른 입력 필드의 라우트 전환 초기화는 이번 변경 범위가 아니다.

- [ ] **Step 4: 입학연도 진입 가드와 기존 클램프 삭제**

`loadFormData()`에서 아래를 삭제한다.

- `if (!authUser?.admission_year) { ... return; }`
- `setAdmissionYear(authUser.admission_year)`
- `selectedYear < authUser.admission_year`를 검사하던 `setWorkYear` 콜백 전체

`setCurrentUser(authUser)`와 `setWorksite(nextWorksite)`는 그대로 유지한다.

- [ ] **Step 5: 수정 리뷰의 원래 연도 저장과 로딩 시 정규화**

수정 리뷰 존재 확인 직후, 나머지 폼 state를 채우기 전에 다음 로직을 넣는다.

```js
const fetchedWorkYear = Number(review.work_year);
const validOriginalWorkYear =
  Number.isInteger(fetchedWorkYear) && fetchedWorkYear >= 1
    ? fetchedWorkYear
    : null;
const fetchedYearOptions = reviewFormYearOptions({
  now,
  include: validOriginalWorkYear,
});
const normalizedWorkYear = fetchedYearOptions.includes(fetchedWorkYear)
  ? fetchedWorkYear
  : currentYear;

setOriginalWorkYear(validOriginalWorkYear);
setWorkYear(String(normalizedWorkYear));
```

기존의 단순 `setWorkYear(String(review.work_year))`는 제거한다.

동작:

- 2020년 기존 리뷰 → 옵션에 2020 추가, 값 유지
- 2024년 기존 리뷰 → 기본 옵션만, 값 유지
- 2027년/비정상 기존 값 → 옵션에 미포함, 올해로 정규화

- [ ] **Step 6: 제출 가드에서 입학연도 의존 제거**

기존:

```js
if (userError || !admissionYear || !currentUser || !worksiteId) {
```

교체:

```js
if (userError || !currentUser || !worksiteId) {
```

그 다음 필수 정보 가드 바로 아래에 연도 검증을 추가한다.

```js
const selectedWorkYear = Number(workYear);
if (!yearOptions.includes(selectedWorkYear)) {
  setWorkYear(String(currentYear));
  toast("선택할 수 없는 근로 연도라 올해로 조정했어요. 학기를 다시 확인해 주세요.", "error");
  return;
}
```

이 검증은 보안 경계가 아니라 비정상 UI state가 RPC payload로 흘러가는 것을 막는
마지막 프론트 방어선이다.

- [ ] **Step 7: 드롭다운 변경 시에도 허용 옵션으로 정규화**

`ReviewFormFields`에 넘기는 `setWorkYear` 콜백을 다음 의미로 교체한다.

```js
setWorkYear={(year) => {
  const selectedYear = Number(year);
  const normalizedYear = yearOptions.includes(selectedYear)
    ? selectedYear
    : currentYear;
  setDuplicateReview(null);
  setWorkYear(String(normalizedYear));
}}
```

사용자가 오래된 원래 연도에서 범위 안 연도로 바꿔도
`originalWorkYear`는 변경하지 않는다. 따라서 드롭다운을 다시 열면 원래 연도로
돌아갈 수 있다.

- [ ] **Step 8: 정적 검색과 빌드**

Run:

```powershell
rg -n "admissionYear|setAdmissionYear|admission_year|getInitialYear" web/src/pages/ReviewForm.jsx
cmd /c "cd web && npm run build"
```

Expected:

- `ReviewForm.jsx` 검색 출력 없음
- Vite build 성공

- [ ] **Step 9: 타깃 lint 비교**

Run:

```powershell
cmd /c "cd web && npx eslint src/pages/ReviewForm.jsx src/lib/semesters.js src/lib/semesters.test.js"
```

Expected:

- 기존 `ReviewForm.jsx`의 `react-hooks/set-state-in-effect` 오류 2개 이외 새 오류 없음
- `MAX_REVIEWS` 미사용 경고는 사라짐

- [ ] **Step 10: 커밋**

```powershell
git add web/src/pages/ReviewForm.jsx
git commit -m "feat(review): 입학연도와 근무 연도 선택을 분리"
```

---

## Task 3: 옛 데이터 흐름과 README 정리

**Files:**

- Modify: `web/src/data/worksiteQueries.js`
- Modify: `web/src/data/README.md`
- Modify: `web/src/lib/README.md`

- [ ] **Step 1: `fetchWrittenSemesters` 최종 사용처 재확인**

Run:

```powershell
rg -n "fetchWrittenSemesters" web/src
```

Expected: `worksiteQueries.js` 정의와 `data/README.md` 설명만 출력.

- [ ] **Step 2: 미사용 쿼리 삭제**

`worksiteQueries.js`에서 `fetchWrittenSemesters()` 함수와 그 주석을 삭제한다.
리뷰 작성·수정에 실제로 쓰는 다음 함수는 유지한다.

- `fetchMyReviewById`
- `fetchMyReviewForPeriod`
- `createReview`
- `updateReview`

- [ ] **Step 3: README 갱신**

`web/src/data/README.md`의 `worksiteQueries.js` 행에서
`fetchWrittenSemesters`를 제거한다.

`web/src/lib/README.md`의 `semesters.js` 행을 다음 의미로 갱신한다.

```markdown
| `semesters.js` | 학기 순서(`SEMESTER_ORDER`), 리뷰 폼 최근 4년 옵션(`reviewFormYearOptions`, 오래된 수정 리뷰 원래 연도 예외), 연도·국가근로 유형별 가능 학기(`reviewFormSemesterOptions`) |
```

- [ ] **Step 4: 죽은 코드가 전부 사라졌는지 확인**

Run:

```powershell
rg -n "availableSemesters|currentYearSemester|semesterKey|fetchWrittenSemesters|MAX_REVIEWS" web/src
```

Expected: 출력 없음.

- [ ] **Step 5: 커밋**

```powershell
git add web/src/data/worksiteQueries.js web/src/data/README.md web/src/lib/README.md
git commit -m "refactor(review): 입학연도 기반 학기 선택 잔재 제거"
```

---

## Task 4: 전체 자동 검증과 수동 회귀

- [ ] **Step 1: 연도 옵션 타깃 테스트**

Run:

```powershell
cmd /c "cd web && npm run test -- src/lib/semesters.test.js"
```

Expected: 11개 테스트 모두 통과.

- [ ] **Step 2: 전체 단위테스트**

Run:

```powershell
cmd /c "cd web && npm run test"
```

Expected: 모든 Vitest 테스트 통과.

- [ ] **Step 3: 프로덕션 빌드**

Run:

```powershell
cmd /c "cd web && npm run build"
```

Expected: Vite build 성공, 새 의존성·DB 산출물 없음.

- [ ] **Step 4: 전체 lint 기준선 비교**

Run:

```powershell
cmd /c "cd web && npm run lint"
```

Expected:

- 기존 오류 수가 9개보다 늘지 않음
- 경고 수가 기존 4개보다 늘지 않고, `MAX_REVIEWS` 제거로 3개 이하가 예상됨
- 이번 diff에서 새 lint 오류 없음

- [ ] **Step 5: diff 품질 확인**

Run:

```powershell
git diff --check
git diff --stat
git status --short
```

Expected:

- whitespace 오류 없음
- 마이그레이션·package 파일 변경 없음
- File Structure에 적은 소스/README와 설계·계획 문서만 변경

- [ ] **Step 6: 신규 작성 수동 검증**

개발 서버를 실행한다.

```powershell
cmd /c "cd web && npm run dev"
```

확인:

1. 신규 리뷰 연도 옵션이 올해부터 3년 전까지 정확히 4개이며 내림차순
2. 사용자 입학연도보다 이른 범위 안 연도를 선택 가능
3. 선택한 연도·학기로 저장 성공
4. 올해는 현재 학기까지만, 과거 연도는 4학기 전부 노출
5. 국가근로 `semester`/`vacation` 필터가 기존대로 유지

- [ ] **Step 7: 수정 모드와 라우트 전환 수동 검증**

오래된 리뷰 fixture 또는 개발 데이터로 확인:

1. 기본 4년보다 오래된 리뷰를 열면 원래 연도가 다섯 번째 옵션으로 유지
2. 범위 안 연도로 바꾼 뒤 드롭다운에서 원래 연도로 복귀 가능
3. 저장 후 서버 오류 없이 수정 완료
4. 오래된 수정 리뷰에서 다른 수정 리뷰로 이동할 때 이전 예외 연도가 남지 않음
5. 수정 화면에서 신규 작성 화면으로 이동할 때 옵션이 다시 기본 4개
6. 미래 연도 fixture를 열면 미래가 옵션에 추가되지 않고 올해로 정규화

- [ ] **Step 8: 입학연도 누락 mock 검증**

DB의 `users.admission_year`는 `NOT NULL`이므로 실제 계정 행을 훼손하지 않는다.
개발 mock/React DevTools 등으로 `authUser` 객체에서 `admission_year`만 누락한 상태를
재현해 다음을 확인한다.

1. `"입학연도 정보가 없습니다."` 오류가 나타나지 않음
2. 폼이 활성화되고 기본 4개 연도가 표시됨
3. 제출의 필수 정보 가드가 입학연도 때문에 막히지 않음

---

## Completion Criteria

- 신규 리뷰의 근무 연도 옵션은 입학연도와 무관하게 최근 4년이다.
- 오래된 기존 리뷰는 원래 연도를 유지하고 다른 연도로 갔다가 복귀할 수 있다.
- 미래·비정상 연도는 옵션에 포함되지 않고 올해로 정규화된다.
- 수정 대상/신규 작성 전환 시 이전 레거시 예외가 남지 않는다.
- `ReviewForm.jsx`에 `admission_year` 의존이 없다.
- `availableSemesters` 계열과 `fetchWrittenSemesters` 잔재가 없다.
- 국가근로 학기 필터와 학기당 1리뷰 서버 제약에 회귀가 없다.
- 타깃/전체 테스트와 build가 통과하고 lint 기준선이 악화되지 않는다.
- DB 마이그레이션·`db push`·새 의존성이 없다.

## 범위 밖

- RPC에서 최근 4년을 강제하는 서버 검증
- 오래된 리뷰의 서버측 수정 예외 정책
- 회원가입·프로필의 입학연도 입력 제거
- `reviewFormSemesterOptions`의 기존 월별 학기 정책 변경
- 기존 저장소 lint 오류 수정
- 프로필 수정 게이트의 비밀번호 재설정 흐름
