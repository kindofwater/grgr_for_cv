# 포인트 정책 v2 — 가입 축하금 폐지 + 리뷰 적립 상향

- 날짜: 2026-08-08
- 담당: 배경록
- 상태: 설계 승인 완료

## 배경

2026-07-31 개편(`20260731105714_point_policy_rebalance`)으로 리뷰 적립을 실명 25P·익명 15P로
올렸다. 이번에는 가입만 하고 리뷰를 쓰지 않는 계정에 나가는 가입 축하금 5P를 없애고, 그 재원을
리뷰 적립 쪽으로 옮긴다. 포인트를 "가입 보상"이 아니라 "기여 보상"으로 몰아주는 게 목적이다.

## 변경 내용

### 1. 리뷰 적립 상향 — 실명 30P · 익명 20P

| 구분 | 기존 | 변경 |
|---|---|---|
| 닉네임 공개 리뷰 | 25P | **30P** |
| 익명 리뷰 | 15P | **20P** |

- 서버: `write_review_with_points`, `update_review_with_points` 의 적립 상수 `25/15` → `30/20`.
  두 함수 모두 시그니처 불변이므로 `create or replace`(DROP 불필요).
- 프론트: `web/src/pages/ReviewForm.jsx` 의 `PUBLIC_REVIEW_POINTS` / `ANONYMOUS_REVIEW_POINTS`
  상수와 122행 주석.
- 프론트: `web/src/pages/ExchangeCenter.jsx` 의 "닉네임 기재 25P · 익명 15P" 문구와 `+25P` 배지.

`delete_review_with_rollback` 은 실제 적립 합계(`sum(amount)`)를 회수하므로 수정 불필요.

### 2. 가입 축하금 폐지

- 서버: `create_profile` 을 최신본(`20260721071224_nickname_policy.sql`)과 동일하게 재선언하되
  말미의 보너스 2줄(`insert into points ... 'signup_bonus'`, `update users set point_balance ...`)만
  삭제한다. 시그니처 불변.
- 프론트: `web/src/pages/Signup.jsx` 의 `toast('가입 축하 5p를 지급했어요!')` 와 그 위 주석 제거.
- **`web/src/pages/MyPage.jsx` 의 `signup_bonus: '가입 축하금'` 라벨은 유지한다.** 기존 유저의
  포인트 내역에 해당 원장 행이 남아 있어, 라벨을 지우면 내역에 원문 reason이 노출된다.
- 이미 지급된 5P는 회수하지 않는다. 잔액이 부족한 유저에게서 차감하면 음수 방지 로직이 추가로
  필요하고 민원 소지가 크다.

### 3. 소급 지급 — `(살아있는 리뷰 수 − 1) × 5P`

리뷰를 여러 개 쓴 기여자에게만 보상한다. 1개=0P, 2개=5P, 3개=10P.

**대상 리뷰**: `user_id is not null` + `deleted_at is null` + `points` 원장에
`reason='review_write'` 행이 있는 리뷰. 삭제된 리뷰는 이미 적립분을 회수당했으므로 카운트에서
제외한다. 아래의 "리뷰 수"와 "가장 오래된 1건"은 모두 이 대상 집합 안에서만 센다.

**지급 방식**: 유저 단위 뭉텅이 지급이 아니라, 유저별 대상 리뷰 중 **가장 오래된 1건(최소 `id`)을
제외한 나머지 리뷰에 각각 +5P 원장 행**을 붙인다 (`reason='review_policy_grant'`, `review_id` 지정).
실명·익명 모두 정확히 5P씩 올랐으므로 공개 여부와 무관하게 일괄 +5P다.

왜 리뷰별로 붙이는가 — `update_review_with_points` 와 `delete_review_with_rollback` 은
`review_id` 별 적립 합계(`review_write` + `review_anon_switch` + `review_policy_grant`)를 보고
재정산한다. 리뷰에 붙여두면 소급받은 리뷰의 합계가 신 정책가와 같아져 수정 시 delta 0으로
수렴하고, 삭제 시에도 정확한 금액이 회수된다. `review_id`가 null인 뭉텅이 행은 이 합계에 잡히지
않아, 옛 리뷰를 수정할 때마다 차액이 또 지급되는 이중 보전이 발생한다.

**알려진 틈**: 제외된 "첫 리뷰"는 합계가 구 정책가(25P/15P)로 남으므로, 그 리뷰를 수정하면
`update_review_with_points` 가 차액 +5P를 보전한다. 유저당 최대 1회·5P. `(n−1)×5` 규칙을
유지하는 대가로 감수한다.

**멱등성**: 대상 산출식이 "현행 적립가 − 기존 합계 > 0" 이므로 재실행하면 0행이다.
`db reset` 재생 시엔 `reviews` 가 비어 있어 no-op.

**회수는 하지 않는다** — delta가 음수인 리뷰는 대상에서 제외(보전 전용).

### 4. 공지

- **현행 정책을 서술하는 공지**의 숫자를 갱신한다.
  - `[필독] 근로고래 이용 안내`: "닉네임 공개 리뷰 작성 25P, 익명 리뷰 작성 15P" → `30P` / `20P`
  - 리뷰 작성 가이드: "닉네임 공개 리뷰는 25P, 익명 리뷰는 15P가 적립됩니다" → `30P` / `20P`
  - `replace()` + `where content like` 패턴으로 멱등 처리.
- **과거 날짜 업데이트 공지**(`[업데이트] 8월 1일` 안의 "15P → 25P" 이력)는 건드리지 않는다.
  그 시점의 사실 기록이다.
- **새 공지 1건 추가**: `[업데이트] 8월 8일` — 리뷰 적립 상향, 가입 축하금 종료, 소급 지급 기준.
  가입 축하금 종료는 민감 사항이라 명시한다. 제목 기준 upsert로 멱등 처리.

## 파일 목록

| 파일 | 변경 |
|---|---|
| `web/supabase/migrations/<ts>_point_policy_v2_and_drop_signup_bonus.sql` | 신규 — 위 1~4 전부 |
| `web/src/lib/points.js` · `points.test.js` | 적립가 상수 + `reviewPoints()` 신설, 테스트 |
| `web/src/pages/ReviewForm.jsx` | 지역 상수 제거 → lib 참조 |
| `web/src/pages/ExchangeCenter.jsx` | 표기 30P·20P, 배지 +30P |
| `web/src/pages/Signup.jsx` | 가입 축하 토스트 제거 |
| `web/supabase/README.md` · `docs/db-schema.md` | 마이그레이션 기록·정책 현황 갱신 |

적립가는 지금 `ReviewForm.jsx` 의 지역 상수와 `ExchangeCenter.jsx` 의 문자열 리터럴로 **이중 소스**다.
값을 바꾸는 작업이니 `web/src/lib/points.js` 로 모아 테스트를 붙인다 — lib은 순수 함수 + 테스트가
원칙이라(`web/src/lib/README.md`) 이 변경의 유일한 자동 검증 지점이기도 하다.

마이그레이션은 **1개 파일**로 묶는다. 적립가 변경과 소급 지급이 한 트랜잭션에서 끝나야 그 사이에
들어온 리뷰가 어중간한 금액으로 적립되지 않는다.

## 테스트

로컬 `supabase db reset` 으로 맨바닥 재구축이 깨지지 않는지 확인한다(리뷰 테이블이 비어 있어
소급 블록은 no-op). 프론트는 기존 `web/src/lib` 테스트에 적립가 상수를 쓰는 테스트가 없으므로
빌드 통과 + 리뷰 작성 화면의 버튼 문구(+30P/+20P) 수동 확인으로 갈음한다.

## 배포 순서

1. 디스코드 공유
2. `cd web && npx supabase db push`
3. **즉시** prod 프론트 배포 (`main` → `prod` 머지 후 push)

간극 동안 프론트는 옛 리뷰 적립 표기(25P/15P)를 보여주지만 서버는 이미 새 금액(30P/20P)을
적립한다 — 이쪽은 유저에게 불리한 방향이 아니다. 문제는 가입 축하금 쪽이다. 같은 간극 동안 prod는
여전히 옛 `Signup.jsx`를 서빙하고 있어 가입 직후 "가입 축하 5p를 지급했어요!" 토스트가 뜨는데,
`create_profile`은 이미 지급을 멈춘 뒤다. 그 창에서 가입한 유저는 5P를 받았다는 안내를 보고도
실제로는 0P를 받고, 마이페이지 포인트 내역에서 가입 축하금 행을 찾지 못한다. 이 거짓 안내 때문에
간극은 시간 단위가 아니라 분 단위여야 한다.

## 롤백

적립가는 `create or replace` 로 되돌릴 수 있다. 소급 지급된 원장 행은
`reason='review_policy_grant'` 중 `created_at`으로 이번 배치를 식별해 역행 삽입해야 하므로,
사실상 되돌리지 않는 전제로 진행한다(7/31 소급 지급과 같은 reason을 재사용하기 때문).
