# 근로고래 API 명세

> 팀원 간 인터페이스 정의.
> 근로고래 프론트는 Supabase를 직접 호출한다.
> 그래서 함수 · RPC · 데이터 shape 기준으로 적는다.
> 실제 구현: `web/src/data/worksiteQueries.js`, `web/src/lib/`

## Auth+RLS 컷오버 — **적용됨 (2026-06-24 prod 반영, migration 20260624025109)**

> **`20260624025109_auth_rls_cutover.sql`은 2026-06-24 prod push·적용 완료.** §4·§7의 변경 내용은 현재 live 상태다. 자체 `password_hash` 인증(`verify_login`/`register_user`)은 제거됐고 Supabase Auth가 사용 중이다.

## 읽는 법
- 종류 컬럼 — 무슨 동작인지 표시:
  - `SELECT` 조회 · `INSERT`/`UPDATE` 변경 · `RPC` 트랜잭션 · `순수` 서버 호출 없음
- 입력 / 반환의 `Shape` 링크는 [3. 데이터 Shape](#3-데이터-shape)로 점프.
- 담당 — 리뷰작성 폼([6](#6-reviewform-연동-계약-유진-담당))은 유진 담당, 인증([7](#7-인증auth-연동-계약-현수-담당))은 현수 담당, 나머지 data layer는 본인.

## 목차
1. [공통 상수](#1-공통-상수)
2. [기능 명세](#2-기능-명세)
3. [데이터 Shape](#3-데이터-shape)
4. [Supabase RPC 명세](#4-supabase-rpc-명세)
5. [라우트 계약](#5-라우트-계약)
6. [ReviewForm 연동 계약 (유진 담당)](#6-reviewform-연동-계약-유진-담당)
7. [인증(Auth) 연동 계약 (현수 담당)](#7-인증auth-연동-계약-현수-담당)

---

## 1. 공통 상수

`DEMO_USER_EMAIL`은 컷오버로 제거됨 — 신원은 `supabase.auth.getUser()`/`auth.uid()`로 확인한다(§7 참조).

---

## 2. 기능 명세

### 2-1. 데이터 조회 — `data/worksiteQueries.js`

| 기능 | 함수 | 종류 | 입력 | 반환 |
|------|------|------|------|------|
| 현재 유저 가져오기 | `fetchCurrentUser()` | SELECT | — | [`User`](#user) |
| 근무지 정보 가져오기 | `fetchWorksite(id)` | SELECT | `id` | [`Worksite`](#worksite) |
| 대표 공고 가져오기 | `fetchRepresentativePosting(worksiteId)` | SELECT | `worksiteId` | [`Posting`](#posting) \| `null` |
| 리뷰 목록 가져오기 | `fetchReviews(worksiteId)` | RPC | `worksiteId` | [`Review[]`](#review) (user_id 미포함, 익명 마스킹) |
| 내가 쓴 리뷰 id 가져오기 | `fetchMyReviewIds(worksiteId)` | SELECT | `worksiteId` | `Set<number>` |
| 내 리뷰 가져오기 | `fetchMyReviewForWorksite(worksiteId)` | SELECT | `worksiteId` | [`Review`](#review) \| `null` (prefill용, 전체 컬럼) |
| 작성한 학기 가져오기 | `fetchWrittenSemesters()` | SELECT | — | [`Semester[]`](#semester) |
| 도움됨 표시한 id 가져오기 | `fetchMyHelpfulIds(worksiteId)` | SELECT | `worksiteId` | `Set<number>` |
| 일일 고유 조회 기록 | `incrementViewCount(worksiteId)` | RPC | `worksiteId` | `void` (fire-and-forget, 실패 무시) |

> ⚠️ 컷오버 후: `userId` 파라미터가 제거됨 — 신원은 서버 측 `auth.uid()`로 자동 확인. `fetchReviews`는 `list_worksite_reviews` RPC를 사용(직접 SELECT 아님). `incrementViewCount`는 `increment_worksite_view` RPC 사용.

### 2-2. 리뷰 작성·수정·삭제 — `data/worksiteQueries.js`

| 기능 | 함수 | 종류 | 입력 | 반환 | 에러 |
|------|------|------|------|------|------|
| 리뷰 작성 (실명 +25 / 익명 +15) | `createReview(payload)` | RPC | [`CreateReviewPayload`](#createreviewpayload) | `reviewId: number` | `23505` 해당 학기 중복 |
| 리뷰 수정 | `updateReview(reviewId, fields)` | RPC | `reviewId,` [`ReviewFields`](#reviewfields) | `void` | `INSUFFICIENT_POINTS` |
| 리뷰 삭제 (실명 −25 / 익명 −15) | `deleteReview(reviewId)` | RPC | `reviewId` | `void` | `INSUFFICIENT_POINTS` 잔액부족 |

> ⚠️ 컷오버 후: `userId` 파라미터가 제거됨 — RPC 내부에서 `auth.uid()` 사용. 작성/수정/삭제는 **포인트 증감과 원자 트랜잭션** — RPC로 처리(§4).

### 2-3. 상호작용 — `data/worksiteQueries.js`

| 기능 | 함수 | 종류 | 입력 | 반환 |
|------|------|------|------|------|
| 도움됐어요 토글 | `toggleHelpful(reviewId)` | RPC | `reviewId` | `helpful_count: number` (변경 후 값) |
| 리뷰 신고 | `reportReview(reviewId, reason)` | RPC | `reviewId,` [`ReportReason`](#reportreason) | `void` |

> ⚠️ 컷오버 후: `userId`/`reporterId` 파라미터가 제거됨 — 신원은 `auth.uid()`. `reportReview`는 직접 INSERT에서 `report_review` RPC로 전환.

### 2-4. 순수 유틸 (서버 호출 없음) — `lib/`

| 기능 | 함수 | 파일 | 반환 |
|------|------|------|------|
| 작성 가능 학기 계산 | `availableSemesters({admissionYear, now, written})` | `semesters.js` | [`Semester[]`](#semester) (최신순, 작성·입학전 제외) |
| 점수 집계 | `computeScoreSummary(reviews)` | `scores.js` | [`ScoreSummary`](#scoresummary) |
| 시급 포맷팅 | `formatWage(wage)` | `scores.js` | `'11,270원'`(예시) / `'별도 확인'`(null) |
| 빈값 대시 처리 | `dash(value)` | `scores.js` | `value` / `'-'`(빈값) |
| 최소학년 라벨 만들기 | `formatMinGrade(minGrade)` | `scores.js` | `'상관없음'`(≤1) / `'2학년 이상'` |
| 학위 라벨 만들기 | `eligibleDegreeLabel(n)` | `scores.js` | `'학부생 가능'`(0)·`'대학원생 가능'`(1)·`'학부생/대학원생 가능'`(2) / `null` |
| 재학상태 라벨 만들기 | `eligibleStatusLabel(n)` | `scores.js` | `'재학생 가능'`(0)·`'휴학생 가능'`(1)·`'재학생/휴학생 가능'`(2) / `null` |

**상수** (`semesters.js`)
```js
SEMESTER_ORDER = ['1학기', '여름방학', '2학기', '겨울방학']
```

---

## 3. 데이터 Shape

> 위 표의 입력/반환이 가리키는 객체 모양.

### User
`fetchCurrentUser()` 반환.
```ts
{
  id: string                              // UUID (컷오버 후 — auth.users.id와 동일)
  nickname: string
  region: string | null                   // 거주 지역 (예: 서울). null이면 미설정
  university_id: number                    // 소속 학교 ID
  university_name: string                  // 소속 학교명 (예: 고려대학교)
  university_campus: string | null         // 캠퍼스명 (멀티캠퍼스만, 단일이면 null)
  admission_year: number                  // 입학연도 (예: 2022)
  degree_program: 'undergrad' | 'graduate'
  academic_status: 'enrolled' | 'leave' | 'completed' | 'deferred_graduation'
  grade: number                           // 학년 (1~6)
  track: string                           // 계열 (예: '이공계열')
  point_balance: number
  pass_expires_at: string | null          // ISO 8601(timestamptz). null이면 열람권 없음
}
// ⚠️ 컷오버 후: id가 int→UUID로 변경. email·password_hash 필드 제거됨.
// update_profile RPC 반환도 동일 shape(비번 제외).
```

### Worksite
`fetchWorksite(id)` 반환.
```ts
{
  id: number
  organization_name: string
  workplace_name: string
  type: 'national' | 'school'
  location_type: 'on_campus' | 'off_campus'
  region: string | null
  address: string | null
  view_count: number
}
```

### Posting
`fetchRepresentativePosting(worksiteId)` 반환. 활성 공고 우선, 그다음 최신 1건. 없으면 `null`.
```ts
{
  id: number
  source_url: string | null
  job_category: string | null
  preferred_track: string | null
  preferred_college: string | null
  preferred_dept: string | null
  recruit_count: number | null
  min_grade: number | null          // formatMinGrade로 표시
  eligible_degree: 0 | 1 | 2 | null  // eligibleDegreeLabel
  eligible_status: 0 | 1 | 2 | null  // eligibleStatusLabel
  job_description: string | null
  preference_notes: string | null
  extra_notes: string | null
  hourly_wage: number | null         // formatWage로 표시
  work_period_text: string | null
  work_duration_type: string | null
  work_time_text: string | null
  recruitment_period_text: string | null
  contact_name: string | null
  contact_phone: string | null
  contact_email: string | null
  is_active: boolean
  created_at: string                 // ISO 8601
}
```

### Review
`fetchReviews()` 반환 배열의 원소. **user_id 미포함(익명 마스킹).**
```ts
{
  id: number
  score_work: number        // 0.5~5.0
  score_growth: number
  score_vibe: number
  score_flex: number
  score_recommend: number
  work_content: string
  opinion: string
  is_anonymous: boolean
  helpful_count: number
  work_year: number
  work_semester: '1학기' | '여름방학' | '2학기' | '겨울방학' | null  // 익명이면 null
  author_nickname: string   // 익명이면 '익명'
  created_at: string        // ISO 8601
}
// ⚠️ 컷오버 후: list_worksite_reviews RPC 반환 shape (직접 SELECT 아님).
//   author_nickname: is_anonymous=true 이면 '익명', false 이면 users.nickname.
//   work_semester: is_anonymous=true 이면 null.
//   author: { track, grade } 필드는 삭제됨(RPC 반환에 없음).
```
> `fetchMyReviewForWorksite()`는 `select('*')`라 위 필드 + `user_id` 등 **전체 컬럼**을 반환(수정 폼 prefill용). 컷오버 후 RLS로 본인 행만 읽힘.

### CreateReviewPayload
`createReview(payload)` 입력. RPC `write_review_with_points` 파라미터와 1:1.
```ts
// ⚠️ 컷오버 후 — p_user_id 제거됨
{
  p_worksite_id: number
  p_work_year: number
  p_work_semester: '1학기' | '여름방학' | '2학기' | '겨울방학'
  p_work: number          // score_work, 0.5~5.0
  p_growth: number        // score_growth
  p_vibe: number          // score_vibe
  p_flex: number          // score_flex
  p_recommend: number     // score_recommend
  p_work_content: string  // 30~1000자
  p_opinion: string       // 50~2000자
  p_is_anonymous: boolean   // 익명 여부(기본 false)
}
```

### ReviewFields
`updateReview(reviewId, fields)`의 `fields`. 본인 것만 수정됨(RLS + RPC 내부 `user_id = auth.uid()` 검증).
```ts
{
  score_work: number
  score_growth: number
  score_vibe: number
  score_flex: number
  score_recommend: number
  work_content: string
  opinion: string
  is_anonymous: boolean  // 익명 여부
}
```

### Semester
```ts
{ year: number, semester: '1학기' | '여름방학' | '2학기' | '겨울방학' }
```

### ScoreSummary
`computeScoreSummary(reviews)` 반환. 리뷰 0개면 `count: 0`, 나머지 `null`.
```ts
{
  count: number
  overall: number | null        // score_recommend 평균
  work: number | null
  growth: number | null
  vibe: number | null
  flex: number | null
  recommendRate: number | null  // recommend ≥ 4.0 비율(%)
}
```

### ReportReason
`reportReview()`의 `reason`. 아래 5개 중 하나.
```ts
'허위/과장 후기' | '욕설/비방' | '광고/스팸' | '개인정보 노출' | '기타'
```

---

## 4. Supabase RPC 명세

> **아래 변경 내용은 2026-06-24 prod 적용 완료 (migration 20260624025109).** 구 시그니처(p_user_id 포함)는 제거됐고 아래가 현재 live 시그니처다.
>
> SQL 정본: `web/supabase/migrations/20260624025109_auth_rls_cutover.sql`

### 제거되는 RPC (컷오버 후 폐기)

| RPC | 대체 |
|-----|------|
| `verify_login(email, password)` | `supabase.auth.signInWithPassword({ email, password })` |
| `register_user(...)` | `supabase.auth.signUp({ email, password, options: { data: {...} } })` + `handle_new_user` 트리거 |
| `set_password(email, new_password)` | Supabase Auth 비밀번호 재설정(GoTrue) |

---

### `write_review_with_points` → `int` (review_id)
리뷰 작성 + 포인트(실명 +25 / 익명 +15 — 2026-07-31 정책 개편, migration 20260731105714). `createReview()` 내부에서 사용.

> ⚠️ 컷오버 후: `p_user_id` 제거 — 신원은 `auth.uid()`. anon 실행 권한 없음(authenticated-only).

| 파라미터 | 타입 | 설명 |
|----------|------|------|
| p_worksite_id | int | 근무지 ID |
| p_work_year | int | 근무 연도 |
| p_work_semester | text | 근무 학기 |
| p_work | numeric | 업무 점수 (0.5~5.0) |
| p_growth | numeric | 자기계발 점수 |
| p_vibe | numeric | 분위기 점수 |
| p_flex | numeric | 시간유연성 점수 |
| p_recommend | numeric | 추천 점수 |
| p_work_content | text | 업무 내용 (30~1000자) |
| p_opinion | text | 의견 (50~2000자) |
| p_is_anonymous | boolean | 익명 여부(기본 false) |

### `update_review_with_points` → `void`
리뷰 수정 + 익명 토글 시 포인트 차액(±10)을 정규값(실명 25/익명 15)으로 스냅. 정산 합계는 reason `review_write`+`review_anon_switch`+`review_policy_grant`(소급 보전, migration 20260731120439) 기준 — 개편 전 리뷰도 소급 지급으로 이미 현행가라 수정 시 추가 지급 없음. `updateReview()` 내부에서 사용. 포인트 이력 없는 리뷰는 지급 안 함. 회수로 잔액 음수면 `INSUFFICIENT_POINTS`.

> ⚠️ 컷오버 후: `p_user_id` 제거 — 신원은 `auth.uid()`. authenticated-only.

| 파라미터 | 타입 |
|----------|------|
| p_review_id | int |
| p_work_year / p_work_semester / p_work / p_growth / p_vibe / p_flex / p_recommend / p_work_content / p_opinion | (write와 동일) |
| p_is_anonymous | boolean |

### `delete_review_with_rollback` → `void`
리뷰 삭제 + 그 리뷰가 실제로 받은 적립합 회수(현행 정책 기준 실명 −25 / 익명 −15 — 개편 전 적립분은 당시 적립합만큼 회수). 잔액 부족 시 `INSUFFICIENT_POINTS` 예외.

> ⚠️ 컷오버 후: `p_user_id` 제거 — 신원은 `auth.uid()`. authenticated-only.

| 파라미터 | 타입 |
|----------|------|
| p_review_id | int |

### `toggle_helpful` → `int` (helpful_count)
도움됐어요 원자 토글. DB가 현재 count를 계산해 반환.

> ⚠️ 컷오버 후: `p_user_id` 제거 — 신원은 `auth.uid()`. authenticated-only.

| 파라미터 | 타입 |
|----------|------|
| p_review_id | int |

### `update_profile` → `table`
프로필 수정. 본인 행만 업데이트(`auth.uid()` 검증). authenticated-only.

> ⚠️ 컷오버 후: `p_user_id` 제거, 반환 `id` 타입이 `int`→`uuid`로 변경.

| 파라미터 | 타입 |
|----------|------|
| p_region | text |
| p_admission_year | int |
| p_degree_program | text |
| p_academic_status | text |
| p_grade | int |

**반환**: 업데이트된 유저 행(`id uuid, nickname, region, admission_year, degree_program, academic_status, grade, track, point_balance, pass_expires_at`)

### `_wallet` → `jsonb`
내 포인트 잔액·패스 상태 조회. authenticated-only.

> ⚠️ 컷오버 후: `p_user_id(int)` 제거 — 무인자(`_wallet()`), 신원은 `auth.uid()`.

**반환**: `{ point_balance: int, pass_balances: object, pass_expires_at: string | null }`

### `purchase_pass(p_days)` → `jsonb`
열람권 구매. 포인트 차감 + pass_balances 증가. 잔액 부족 시 `INSUFFICIENT_POINTS`. authenticated-only.

> ⚠️ 컷오버 후: `p_user_id` 제거.

| 파라미터 | 타입 |
|----------|------|
| p_days | int |

**반환**: `_wallet()` 와 동일 shape

### `refund_pass(p_days)` → `jsonb`
열람권 환불. 포인트 복원 + pass_balances 감소. 재고 없으면 `NO_PASS_STOCK`. authenticated-only.

> ⚠️ 컷오버 후: `p_user_id` 제거.

| 파라미터 | 타입 |
|----------|------|
| p_days | int |

**반환**: `_wallet()` 와 동일 shape

### `activate_pass(p_days)` → `jsonb`
열람권 활성화. pass_balances 차감 + pass_expires_at 연장(1시간권 `p_days=0`은 1시간, 그 외 p_days일). 재고 없으면 `NO_PASS_STOCK`. authenticated-only.

> ⚠️ 컷오버 후: `p_user_id` 제거.

| 파라미터 | 타입 |
|----------|------|
| p_days | int |

**반환**: `_wallet()` 와 동일 shape

### `change_nickname(p_nickname)` → `jsonb`
20P를 사용해 현재 사용자의 닉네임을 즉시 변경한다. 기존 `validate_nickname()` 규칙을 그대로 적용하며, 닉네임 검증·포인트 차감·닉네임 변경·포인트 원장·내부 변경 이력 기록은 한 트랜잭션에서만 성공한다. 실패하면 포인트도 차감되지 않는다. authenticated-only.

| 파라미터 | 타입 |
|----------|------|
| p_nickname | text |

**에러:** `NICKNAME_INVALID`, `NICKNAME_RESERVED`, `NICKNAME_UNCHANGED`, `NICKNAME_TAKEN`, `INSUFFICIENT_POINTS`

**반환**: `_wallet()` shape + `{ nickname: string }`

> 비밀번호 재확인은 교환센터의 닉네임 변경 흐름에서 Supabase Auth 재인증으로 처리한다. 공개 리뷰의 작성자 닉네임은 `users.nickname` 동적 JOIN이라 과거 비익명 리뷰도 다음 조회부터 새 닉네임으로 표시된다.

### `watch_ad_reward` — **제거됨 (2026-06-25 적용)**

> ⚠️ `watch_ad_reward()`는 리워드 광고 서버 마이그레이션(`20260624170000`) 적용(2026-06-25) 시 `DROP FUNCTION IF EXISTS watch_ad_reward()` 로 제거됨.
> 대체: `start_ad_view()` + `claim_ad_reward(p_token)` (아래 §4-2 참고).

---

### 신규 RPC (컷오버 후 추가 — 2026-06-24 prod 적용 완료)

### `list_worksite_reviews(p_worksite_id)` → `table`
근무지 리뷰 목록 조회. **익명 마스킹** — `user_id` 미반환, `is_anonymous=true` 이면 `author_nickname='익명'` / `work_semester=null`. **블라인드 마스킹** — `is_blinded=true` 이면 내용·점수·작성자·근로학기를 서버에서 `null`로 반환(목록엔 placeholder 슬롯으로 남음). authenticated-only.

| 파라미터 | 타입 |
|----------|------|
| p_worksite_id | int |

**반환**: `[{ id, work_year, work_semester, score_recommend, score_work, score_growth, score_vibe, score_flex, work_content, opinion, is_anonymous, helpful_count, author_nickname, created_at, is_blinded }]`

### `increment_worksite_view(p_worksite_id)` → `void`
로그인 사용자의 근무지 조회를 기록한다. 같은 사용자·근무지 조합은 KST 날짜별 1회만 `worksites.view_count`에 누적되므로 새로고침이나 재방문으로 조회수가 연속 증가하지 않는다. 비로그인 조회는 집계하지 않는다. authenticated-only.

홈의 '많이 찾아본 근장'은 최근 30일의 고유 조회 기록에 `0.5^(경과시간/7일)` 가중치를 적용한 점수로 정렬한다. 이 점수는 매시간 5분에 갱신되는 `worksite_popularity_scores` 캐시에서 읽는다.

| 파라미터 | 타입 |
|----------|------|
| p_worksite_id | int |

### `report_review(p_review_id, p_reason)` → `void`
리뷰 신고. `reporter_id = auth.uid()` 자동 설정. authenticated-only.

| 파라미터 | 타입 |
|----------|------|
| p_review_id | int |
| p_reason | text ([`ReportReason`](#reportreason)) |

---

## 4-2. 리워드 광고 서버 RPC — **적용됨 (2026-06-25 LIVE, migration 20260624170000)**

> **2026-06-25 prod 적용·동작 확인(LIVE).**
> 모두 `SECURITY DEFINER`, `authenticated`만 실행 가능 (anon 권한 없음). 담당: 현수(kindofwater).

### `start_ad_view()` → `jsonb`
광고 1개를 랜덤 선택해 `ad_views` 행을 생성하고 1회용 토큰을 반환.

> 비인증(`auth.uid()` null) 시 `NOT_AUTHENTICATED` 예외.
> 일일 캡(`ad_reward_config.daily_cap`) 초과 또는 `cooldown_minutes` 미경과 시 `CAP_REACHED` 예외.
> 활성 광고(`ads.is_active = true`) 없으면 `NO_ADS` 예외.

**인자:** 없음

**반환:**
```json
{
  "ad": {
    "id": 1,
    "title": "김밥천국 안암점",
    "media_path": "seed-ad-1.jpg",
    "media_type": "photo",
    "target_url": "https://instagram.com/example_shop",
    "min_view_seconds": 5
  },
  "token": "<uuid>"
}
```

### `get_ad_reward_status()` → `jsonb`
광고 시청 기록을 생성하지 않고 현재 사용자의 오늘 보상 가능 여부를 조회한다. 교환센터는 `available=false`이면 광고 카드를 비활성화한다. 반환값은 `available`, `unavailable_reason`, `daily_cap`, `claimed_today`, `remaining_today`, `reward_points`, `cooldown_until`을 포함한다. authenticated-only.

### `claim_ad_reward(p_token)` → `jsonb`
토큰 유효성·최소 시청 시간(`ads.min_view_seconds`)·일일 캡을 검증한 후 `ad_reward_config.reward_points`를 지갑에 적립.

| 파라미터 | 타입 | 설명 |
|----------|------|------|
| `p_token` | `uuid` | `start_ad_view()`가 반환한 1회용 토큰 |

**에러 코드:**
| 코드 | 의미 |
|------|------|
| `NOT_AUTHENTICATED` | 세션 없음(`auth.uid()` null) |
| `INVALID_TOKEN` | 토큰 없음 / 이미 사용된 토큰 / 다른 유저의 토큰 |
| `TOO_SOON` | `min_view_seconds` 미경과 |
| `CAP_REACHED` | 일일 캡 초과 |

**반환:** `_wallet()` 와 동일 shape (`point_balance`, `pass_balances`, `pass_expires_at`)

### `log_ad_click(p_ad_id)` → `void`
광고 클릭을 `ad_clicks`에 기록. fire-and-forget 가능 (실패 시 클라이언트가 무시해도 됨).

| 파라미터 | 타입 | 설명 |
|----------|------|------|
| `p_ad_id` | `int` | 클릭한 광고 ID |

### `adMediaUrl(path)` → `string` (`data/adQueries.js`)
`ad-media` 버킷의 공개 URL을 만드는 헬퍼. Storage 접근도 data 레이어 경유 — 페이지는 `supabase`를 직접 import하지 않는다.

---

### 변경 없는 RPC

### `get_review_stats` → `table`
근무지 목록의 리뷰 집계. 홈 카드 점수 표시용.

| 파라미터 | 타입 |
|----------|------|
| worksite_ids | int[] |

**반환**: `[{ worksite_id: int, avg_score: numeric, review_count: bigint }]`

### `get_worksite_score_cards` → `table`
(변경 없음 — 시그니처 유지)

### `pass_price(p_days)` → `int`
열람권 가격 조회. 2026-07-31 개편(migration 20260731105714): `0(=1시간권)→5P · 7→20P · 30→35P`, 그 외 null. `p_days=0`은 1시간권 센티널 — 시간 단위 상품이 더 생기면 hours 단위로 리팩터.

---

## 4-1. RLS 요약 (컷오버 후 — 2026-06-24 prod 적용 완료)

컷오버 마이그레이션(`20260624025109`) 적용으로 **전 테이블 RLS ON**. 직접 SELECT는 본인 행만 읽힘.

| 테이블 | 정책 요약 |
|--------|----------|
| `users` | `authenticated` 본인 행만 SELECT/UPDATE |
| `reviews` | `authenticated` 본인 행만 SELECT (목록 조회는 `list_worksite_reviews` RPC) |
| `points` | `authenticated` 본인 행만 SELECT |
| `ad_views` | `authenticated` 본인 행만 SELECT |
| `review_helpful` | `authenticated` 본인 행만 SELECT |
| `reports` | 클라이언트 정책 없음 (service_role/관리자만) |
| `worksites`, `postings`, `universities`, `colleges`, `departments` | anon + authenticated 읽기 전용 |
| `notices` | 공통 공지(`university_id IS NULL`)는 anon + authenticated 읽기 허용. 학교 공지는 로그인한 해당 학교 사용자만 읽기 허용 |

---

## 5. 라우트 계약

| 경로 | 컴포넌트 | 설명 |
|------|----------|------|
| `/home` | `Home` | 홈 |
| `/login` | `Login` | 로그인 |
| `/worksite/:id` | `WorksiteDetail` | 근무지 상세 |
| `/worksite/:id/review` | `ReviewForm` | 리뷰 작성 (**유진 담당**) |
| `/worksite/:id/review/edit` | `ReviewForm` | 리뷰 수정 (**유진 담당**) |

`:id` = `worksite_id` (number)

---

## 6. ReviewForm 연동 계약 (유진 담당)

> 리뷰 작성/수정 페이지는 별도 작업 중. 아래 계약을 맞춰야 WorksiteDetail과 연결됨.

### 진입 방식
```js
// WorksiteDetail에서 navigate
navigate(`/worksite/${worksiteId}/review`)       // 작성
navigate(`/worksite/${worksiteId}/review/edit`)  // 수정
```

### ReviewForm이 써야 하는 함수
- [`fetchCurrentUser()`](#2-1-데이터-조회) — 유저 정보 (admission_year 필요)
- [`fetchWrittenSemesters()`](#2-1-데이터-조회) — 이미 쓴 학기 제외용
- [`fetchMyReviewForWorksite(worksiteId)`](#2-1-데이터-조회) — 수정 시 prefill
- [`createReview(payload)`](#2-2-리뷰-작성수정삭제) — 작성 제출
- [`updateReview(reviewId, fields)`](#2-2-리뷰-작성수정삭제) — 수정 제출
- [`availableSemesters({admissionYear, now, written})`](#2-4-순수-유틸-서버-호출-없음--lib) — 드롭다운

> ⚠️ 컷오버 후: `userId` 파라미터가 모든 호출에서 제거됨.

### 검증 규칙
| 필드 | 범위 |
|------|------|
| 별점 4개 + 추천점수 | **0.5 ~ 5.0** (0.5 단위) |
| 업무내용 | **30 ~ 1000자** |
| 의견 | **50 ~ 2000자** |

### 완료 후 이동
```js
navigate('/worksite/' + worksiteId)
// WorksiteDetail이 자동으로 reviews 재조회함
```

### 에러 처리
- `23505` 에러: "이미 해당 학기에 작성한 리뷰가 있어요"
- `INSUFFICIENT_POINTS`: 삭제 시 포인트 부족 (deleteReview에서 발생)

---

## 7. 인증(Auth) 연동 계약 (현수 담당)

> ⚠️ 아래는 2026-06-24 prod 적용 완료(migration 20260624025109) — 현재 live. 자체 password_hash 인증(`verify_login`/`register_user`)은 제거, Supabase Auth 사용 중.

### 컷오버 전 vs 컷오버 후

| | 컷오버 전 (폐기) | 컷오버 후 (현재 live) |
|--|-------------|-------------|
| 로그인 | `verify_login(email, password)` RPC | `supabase.auth.signInWithPassword({ email, password })` |
| 회원가입 | `register_user(...)` RPC | `supabase.auth.signUp({ email, password, options: { data: {...} } })` |
| 비밀번호 변경 | `set_password(email, new_password)` RPC | Supabase Auth GoTrue (비밀번호 재설정) |
| 유저 식별 | `DEMO_USER_EMAIL` 하드코딩 / DB email 조회 | `supabase.auth.getUser()` → `auth.uid()` |
| 세션 | `isLoggedIn` UI 토글 | Supabase Auth 세션 |
| 열람권 상태 | `hasPass` UI 토글 | `user.pass_expires_at` |

### 회원가입 흐름 (현재 live)

```js
await supabase.auth.signUp({
  email,     // @korea.ac.kr 도메인 강제 (universities.signup_enabled = true)
  password,
  options: {
    data: {
      nickname,           // string (UNIQUE)
      university_id,      // int
      college_name,       // string
      department_name,    // string
      track,              // string (예: '이공계열')
      admission_year,     // int
      degree_program,     // 'undergrad' | 'graduate'
      academic_status,    // 'enrolled' | 'leave' | 'completed' | 'deferred_graduation'
      grade,              // int (1~6)
      region,             // string | null
    }
  }
})
// → handle_new_user 트리거가 auth.users INSERT 후 public.users 행을 자동 생성
```

**트리거 검증 — `handle_new_user`:**
- `universities.signup_enabled = true` 인 학교만 가입 허용. 현재 MVP: 고려대(`korea.ac.kr`).
- 이메일 도메인이 `universities.email_domain`과 불일치 시 `DOMAIN_NOT_ALLOWED` 예외.
- 학교 없음: `NO_UNIVERSITY`, 미허용 학교: `SCHOOL_NOT_ENABLED`, 닉네임 중복: `NICKNAME_TAKEN`.

### 로그인 성공 후 흐름 (현재 live)

```
로그인 성공
  → Supabase 세션 생성 (supabase.auth.signInWithPassword)
  → navigate('/home')
  → Home이 fetchCurrentUser()로 유저 정보 조회
```

**비로그인 접근 시:**
```
/home, /worksite/:id 등 보호된 페이지 접근
  → 세션 없음 감지 (supabase.auth.getUser() → null)
  → navigate('/login')
```

### `fetchCurrentUser()` 교체 계약 (현재 live)

Auth가 붙으면 `worksiteQueries.js`의 `fetchCurrentUser()`를 아래처럼 교체. 반환 [`User`](#user) shape는 **id 타입(uuid)만 변경**.

```js
// 컷오버 후
export async function fetchCurrentUser() {
  const { data: { user: authUser } } = await supabase.auth.getUser()
  if (!authUser) return null  // 비로그인
  const { data } = await supabase.from('users').select('...').eq('id', authUser.id).single()
  return data
}
```

### 전역 auth 상태 관리 (현재 live)

```jsx
// App.jsx 또는 AuthContext에서 관리
const [session, setSession] = useState(null)

useEffect(() => {
  supabase.auth.getSession().then(({ data: { session } }) => setSession(session))
  const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
    setSession(session)
  })
  return () => subscription.unsubscribe()
}, [])
```

**컷오버 시 제거되는 것들:**
- `Home.jsx`의 `isLoggedIn` useState + dev-toggle 버튼
- `WorksiteDetail.jsx`의 `hasPass` useState + dev-toggle 버튼
- `DEMO_USER_EMAIL` 상수
- `verify_login`, `register_user`, `set_password` RPC 호출부

### 라우트 변경 (현재 live)

| 경로 | 변경 |
|------|------|
| `/login` | 실제 로그인 로직 연결 |
| `/signup` | 회원가입 (신규 라우트 추가 필요) |
| `/home` 외 | 비로그인 시 `/login` 리다이렉트 |

**App.jsx에 보호 라우트 추가 예시:**
```jsx
// 로그인 안 하면 /login으로
<Route path="/home" element={session ? <Home /> : <Navigate to="/login" />} />
<Route path="/worksite/:id" element={session ? <WorksiteDetail /> : <Navigate to="/login" />} />
```
