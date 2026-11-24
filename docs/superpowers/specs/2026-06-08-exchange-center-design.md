# 교환센터 (열람권 교환) 설계

작성일: 2026-06-08
브랜치: `feature/exchange-center`

## 1. 목적 / 배경

근로고래의 핵심 가치 루프는 **리뷰 작성 → 포인트 획득 → 열람권으로 남의 리뷰 열람**이다.
현재 리뷰 작성(+15P)과 열람 잠금(`hasPass`)은 있으나 그 사이를 잇는 **교환**이 없어, 실사용자가
열람권을 얻을 방법이 없다(`hasPass`가 개발용 토글). 교환센터가 이 루프를 완성한다.

## 2. 확정된 정책 / 결정

- **열람권 모델: 2단계** (mockup·스키마와 일치)
  - 교환하기: 포인트 → 재고(`users.pass_balances`) +1
  - 사용하기: 재고 −1 → 활성(`users.pass_expires_at`) 연장
- **가격** (정책): 7일 열람권 10P, 30일 열람권 20P
- **적립**: 리뷰 작성 +15P(기구현), 광고 시청 +5P
- **광고**: 실제 SDK 없음 → mock(플레이스홀더 + 시청완료 버튼). **적립 횟수 제한 없음(MVP)**
- **환불: 미사용 재고만, 전액 환불** (활성화된 열람권은 환불 불가 — 시간 비례 환불은 범위 밖)
- **DB 운영**: `DB/2026-06-08_exchange.sql`을 **팀원 누구나** 실행 (CLAUDE.md §3: 공유 → `DB/` 누적 → 디스코드 기록). SQL 파일은 `YYYY-MM-DD_주제.sql` 타임스탬프 네이밍.

## 3. 아키텍처 개요

포인트·열람권을 바꾸는 모든 동작은 **원자 트랜잭션이 필수**다(중간 실패 시 포인트만 빠지거나
열람권만 생기는 불일치). 따라서 기존 패턴(`write_review_with_points`, `delete_review_with_rollback`)과
동일하게 **Supabase RPC(SECURITY DEFINER)**로 구현한다. 클라이언트 다중 update는 사고 위험으로 배제.

```
ExchangeCenter.jsx / AdView.jsx   (pages, 화면)
        │  호출
data/exchangeQueries.js           (RPC·SELECT 래퍼)
        │  .rpc()
DB/2026-06-08_exchange.sql                   (원자 RPC 4종)  ← Supabase
        │  반환: 갱신된 지갑
AuthContext.login(updatedUser)    (전역 상태 동기화)
```

## 4. 데이터 모델 (기존 스키마 활용, 변경 없음)

- `users.point_balance INT CHECK (>= 0)` — 보유 포인트
- `users.pass_balances JSONB DEFAULT '{}'` — 미사용 재고. 예: `{"7": 2, "30": 1}` (키 = 유효기간 일수)
- `users.pass_expires_at TIMESTAMP` — 현재 활성 열람권 만료 시각(없으면 NULL)
- `points(user_id, amount, reason, review_id, ad_view_id, created_at)` — 포인트 원장. `reason`은 VARCHAR(50), CHECK 없음 → `pass_purchase` / `pass_refund` / `ad_view` 자유 기록 가능
- `ad_views(id, user_id, created_at)` — 광고 시청 기록

> 스키마 자체는 그대로 두고 RPC만 추가한다.

## 5. 백엔드 — RPC 4종 (`DB/2026-06-08_exchange.sql`)

가격은 **서버에서 결정**한다(클라이언트가 보낸 금액 신뢰 금지). 모든 함수는 갱신된 지갑
(`point_balance`, `pass_balances`, `pass_expires_at`)을 반환한다. 동시성·음수 방지를 위해
**조건부 UPDATE**(WHERE에 잔액/재고 조건)를 쓰고, 영향 행이 0이면 예외를 던진다.

| RPC | 시그니처 | 동작(원자) | 예외 |
|---|---|---|---|
| 구매 | `purchase_pass(p_user_id int, p_days int)` | `point_balance -= price` (단 `>= price`), `pass_balances[days] += 1`, `points(-price, 'pass_purchase')` | `INSUFFICIENT_POINTS` |
| 환불 | `refund_pass(p_user_id int, p_days int)` | `pass_balances[days] -= 1` (단 `>= 1`), `point_balance += price`, `points(+price, 'pass_refund')` | `NO_PASS_STOCK` |
| 사용 | `activate_pass(p_user_id int, p_days int)` | `pass_balances[days] -= 1` (단 `>= 1`), `pass_expires_at = GREATEST(now, COALESCE(pass_expires_at, now)) + p_days일` | `NO_PASS_STOCK` |
| 광고 | `watch_ad_reward(p_user_id int)` | `ad_views` insert, `point_balance += 5`, `points(+5, 'ad_view', ad_view_id)` | — |

- `p_days`는 `{7, 30}`만 허용. 가격 매핑은 함수 내부 CASE(`7→10, 30→20`), 그 외 값은 `INVALID_DAYS` 예외.
- 모두 `SECURITY DEFINER`, `GRANT EXECUTE`는 기존 RPC와 동일 권한(anon/authenticated)으로 맞춘다.
- 파일 끝에 수동 검증용 테스트 쿼리를 주석으로 포함(`auth_login.sql` 방식).
- **보안 메모(상속된 디버트)**: `p_user_id`를 클라이언트가 전달 → 위조 가능. 기존 RPC와 동일한 한계이며,
  Auth/RLS 도입(디버트 #3~5) 시 일괄 보호 대상. 포인트는 돈에 준하므로 우선순위 상향 권장.

## 6. 데이터 계층 — `web/src/data/exchangeQueries.js` (신규)

- `fetchWallet(userId)` — `SELECT point_balance, pass_balances, pass_expires_at FROM users WHERE id=...`
  - (이유: `verify_login`은 `pass_balances`를 반환하지 않아 재고 표시에 별도 조회 필요)
- `purchasePass(userId, days)` / `refundPass(userId, days)` / `activatePass(userId, days)` / `watchAdReward(userId)` — 각 RPC 래퍼. 에러 메시지는 호출부에서 분기.

## 7. 프론트 — 페이지 2개 (mockup `screen-shop` / `screen-ad` 기준)

### `pages/ExchangeCenter.jsx` (`/exchange`)
- 사이드바: 내 포인트 / 7·30일 열람권 재고(n장) / 열람 가능 기한(`pass_expires_at`)
- 열람권 카드(7일·30일): **교환하기**(구매) · **사용하기**(활성) · **환불**(재고>0일 때만 노출, 신규 — mockup엔 없음)
- 적립 섹션: 근장 리뷰 작성하기(→`/home` 또는 근장찾기), 광고 시청하기(→`/ad`)
- 마운트 시 `fetchWallet`로 최신 지갑 로드. 비로그인 시 `/login` 리다이렉트.

### `pages/AdView.jsx` (`/ad`)
- mock 광고 플레이스홀더(진행 바). "시청 완료 — +5P 받기" → `watchAdReward` → `/exchange` 복귀.
- "건너뛰기(포인트 미지급)" → `/exchange` 복귀.

## 8. 상태 동기화 (중요)

구매/환불/사용/광고 RPC가 돌려준 지갑으로 **AuthContext 유저를 갱신**한다
(`login({ ...authUser, ...wallet })`). 이로써:
- 네비 "내 포인트" 즉시 반영
- 상세페이지 `hasPass`(= `pass_expires_at` 기반)가 전역에서 일치 → 데모 토글(#5 디버트) 자연 해소

## 9. 라우팅 / 네비 연결

- `App.jsx`에 `/exchange`, `/ad` 라우트 추가(AuthProvider 안).
- 현재 죽어있는 **"교환센터" 링크**(`Home.jsx`, `WorksiteDetail.jsx`) → `navigate('/exchange')` 연결.
- 네비 "내 포인트 nP" 표시는 선택적으로 추가(mockup 참고).

## 10. 에러 처리

- `INSUFFICIENT_POINTS` → "포인트가 부족해요."
- `NO_PASS_STOCK` → "보유한 열람권이 없어요."
- `INVALID_DAYS` 및 기타 → "처리 중 오류가 발생했어요: {원시메시지}" (friendly-errors는 별도 TODO와 함께)

## 11. 테스트

- 순수 헬퍼를 `lib/`로 분리해 vitest 단위 테스트:
  - `passPrice(days)` (7→10, 30→20, 그 외 throw)
  - `nextExpiry(current, days, now)` — `GREATEST(now, current)+days` 동일 로직(클라이언트 표시·검증용)
- RPC는 DB 없이는 단위 테스트 불가 → `DB/2026-06-08_exchange.sql` 내 검증 쿼리 주석 + Supabase 수동 확인.

## 12. 범위 밖 (YAGNI)

- 실제 광고 SDK, 광고 일일 제한
- 포인트 내역 화면(마이페이지에서 다룸)
- 활성화된 열람권의 시간 비례 환불
- Auth/RLS 하드닝(별도 디버트 작업)

## 13. 변경 파일 요약

- 신규: `DB/2026-06-08_exchange.sql`, `web/src/data/exchangeQueries.js`, `web/src/pages/ExchangeCenter.jsx`(+css), `web/src/pages/AdView.jsx`(+css), `web/src/lib/passes.js`(+test)
- 수정: `web/src/App.jsx`(라우트), `web/src/pages/Home.jsx`·`WorksiteDetail.jsx`(교환센터 링크), `web/src/auth/AuthContext.jsx`(필요 시 지갑 머지 헬퍼)
- 문서: `docs/legacy/policy.md`(광고 제한 문구 정리·환불 정책 추가), `docs/README_supabase.md`(DB 공동 담당)
