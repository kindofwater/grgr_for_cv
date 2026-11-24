# 대학별 포인트 정책 — 서울대 5분 열람권 + 광고 적립 2P

- 날짜: 2026-08-08
- 담당: 배경록
- 상태: 설계 승인 대기

## 배경

서울대는 아직 리뷰가 적다. 리뷰가 모이는 선순환을 만들기 위해 서울대에 한해 열람권 최소 상품을
1시간 → **5분**으로, 광고 적립을 5P → **2P**로 한시 조정한다. 리뷰가 쌓이면 되돌린다.

지금 두 시스템 모두 대학별 차등을 지원하지 않는다. `pass_price(p_days)`는 `immutable`이고 대학
인자가 없으며 1시간은 `activate_pass` 본문에 `interval '1 hour'`로 박혀 있다. `ad_reward_config`는
`check (id = 1)`로 단일 행이 강제된 전역 설정이다. 즉 이 작업은 값 조정이 아니라 **차등이라는 개념을
새로 넣는 일**이다.

**되돌릴 것을 전제로 짓는다.** 원복이 RPC 본문 replace를 요구하면 안 된다 — 이 저장소는 본문 복사로
로직이 조용히 사라지는 사고를 이미 두 번 겪었다(대학 스코프 검사가 `20260725120000`에서 유실되어
2026-08-08 `20260808120745`로 복구).

## 변경 내용

### 1. 대학별 정책 표 (신규)

```sql
create table public.university_point_policy (
  university_id     int primary key references public.universities(id) on delete cascade,
  hour_pass_minutes int not null default 60 check (hour_pass_minutes between 1 and 1440),
  ad_reward_points  int check (ad_reward_points >= 0),  -- null이면 전역 ad_reward_config 사용
  note              text,                                -- 이 행이 왜 있는지
  updated_at        timestamptz not null default now()
);
```

- RLS 활성 + 정책 0건. 읽기는 아래 헬퍼(내부 전용)로만. 클라이언트 직접 접근 차단.
  (`worksite_popularity_scores`와 같은 방식)
- 시드 1행: `(2, 5, 2, '서울대 리뷰 부족 — 리뷰 선순환을 위한 한시 조정. 되돌릴 때 이 행을 삭제')`
- **`ad_reward_config`는 건드리지 않는다.** `check (id = 1)`을 유지한 채 전역 기본값 자리로 두고,
  이 표는 오버라이드만 얹는다. 전역 기본이 바뀌면 오버라이드 없는 학교는 자동으로 따라간다.

### 2. 공유 헬퍼 2개 — 드리프트 구조적 차단

```sql
public.hour_pass_minutes_for(p_uid uuid) returns int   -- 없으면 60
public.ad_reward_points_for(p_uid uuid)  returns int   -- 없으면 ad_reward_config.reward_points
```

`language sql`·`stable`·`set search_path = public`. **security definer 아님** — 전부 definer RPC
안에서만 호출되므로 그 컨텍스트를 그대로 쓴다. 클라 grant는 회수한다(`validate_nickname`과 같은 취급).

호출자 4개가 모두 `security definer`인 것을 확인했다(`get_ad_reward_status` 20260802002643 ·
`claim_ad_reward` 20260713164934 · `activate_pass` 20260801071450 · `_wallet` 20260801074833).
⚠️ **앞으로 이 헬퍼를 security invoker RPC에서 부르면 안 된다** — `university_point_policy`는 RLS 활성에
정책 0건이라 일반 사용자 컨텍스트에서는 0행을 보고 조용히 기본값(60분·전역 5P)으로 폴백한다.
막히는 게 아니라 **틀린 값이 나온다.**

**이 헬퍼가 설계의 핵심이다.** 값을 세 RPC가 각자 계산하면 한쪽만 고치는 순간 화면과 지급이
어긋난다(화면엔 5P, 실제론 2P). 헬퍼 하나를 세 곳이 부르면 그 사고가 구조적으로 불가능해진다.

### 3. 서버 RPC 4개 (시그니처 전부 불변 → `create or replace`, `DROP` 불필요)

| RPC | 바뀌는 것 |
|---|---|
| `activate_pass` | `p_days=0`일 때 `hour_pass_minutes_for(uid)` 분 연장 (기존 `interval '1 hour'` 대체) |
| `claim_ad_reward` | `ad_reward_points_for(uid)` 만큼 적립 |
| `get_ad_reward_status` | 같은 값을 `reward_points`로 반환 |
| `_wallet` | 반환 jsonb에 `hour_pass_minutes` 추가 |

⚠️ **`_wallet()`의 `search_path`는 `pg_catalog, pg_temp`다.** 새 헬퍼를 반드시
`public.hour_pass_minutes_for(...)`로 완전 수식해야 한다. 빠뜨리면 런타임에 함수를 못 찾는다.

`pass_price`는 손대지 않는다 — 가격은 5P 그대로다.

### 4. 프론트 — 5분권 표기만

광고 쪽은 **프론트 변경이 전혀 없다.** `get_ad_reward_status()`가 이미 `reward_points`를 반환하고
`ExchangeCenter.jsx`가 `adRewardStatus?.reward_points ?? 5`로 읽고 있어, 서버 값만 바뀌면 화면이
따라온다. (폴백 상수 `?? 5`는 서버 응답 실패 시에만 쓰이므로 그대로 둔다.)

열람권 표기는 `web/src/lib/passes.js`가 1시간을 하드코딩한다:

- `passLabel(days)` → `passLabel(days, minutes = 60)` : 60이면 `'1시간 열람권'`, 아니면 `'5분 열람권'`
- `passDuration(days)` → `passDuration(days, minutes = 60)`
- `nextExpiry(current, days, now)` → `nextExpiry(current, days, now, minutes = 60)`

**기본값 60**이라 기존 호출부는 그대로 동작한다. `ExchangeCenter.jsx`만 `wallet.hour_pass_minutes`를
넘긴다. 라벨 규칙은 60으로 나누어떨어지면 시간 단위, 아니면 분 단위.

`_wallet()`이 초기 로드(`fetchWallet`)와 구매·활성화·환불 응답의 **단일 통로**라, 서버에 필드 하나만
얹으면 교환센터 전 경로가 커버된다.

### 5. 배포 간극 안전성

`_wallet()` 반환은 jsonb라 시그니처가 불변이고, 구 프론트는 모르는 키를 무시한다. 따라서
**DB 먼저 올려도 프론트 먼저 올려도 깨지지 않는다.**

- DB 먼저: 서울대 유저가 잠깐 "1시간 열람권"이라 적힌 상품을 사서 5분을 받는다 ← 불리한 방향
- 프론트 먼저: `hour_pass_minutes`가 없어 기본값 60으로 "1시간"이라 표기, 실제도 1시간 ← 무해

**그래서 프론트를 먼저 배포하고 DB를 나중에 올린다.** 포인트 정책 v2와 순서가 반대다.

### 6. 기존 재고

시행 시점 서울대 유저의 미사용 1시간권 재고는 **0건으로 확인했다**(2026-08-08 Studio 조회). 다만
확인 시점과 마이그레이션 적용 사이에 누가 살 수 있으므로, 적용 시점 재고를 **5P씩 환불하고 키를
제거하는 방어 블록**을 넣는다. 예상 결과는 0행이며, 생기면 5P 주고 산 상품이 말없이 1/12로 깎이는
것을 막는다. (`20260801071450`의 "0 이하 재고 키 제거" 규약을 따른다.)

### 7. 공지

서울대 전용(`university_id = 2`) 공지 1건을 **제목 기준 upsert**로 추가한다.

- 제목: `[안내] 서울대 열람권·적립 한시 조정`
- `is_pinned = false` (고정은 필독 공지만 — `[업데이트] 8월 8일`과 같은 취급)
- 문구 방향: **리뷰가 모이는 선순환을 위한 한시적 조정**임을 밝히고, 리뷰가 쌓이면 되돌린다고 적는다.
  특정 집단을 탓하는 표현은 쓰지 않는다. 바뀌는 값(5분 열람권 5P, 광고 1편 2P)을 명시한다.
- 되돌릴 때 이 공지도 함께 정리한다(§되돌리기).

## 감수한 것

- **같은 5P로 고려대 60분 / 서울대 5분** — 시간당 단가 12배 차이다. 커뮤니티가 좁아 비교될 수 있다.
  공지의 "한시적" 프레이밍이 유일한 완충이다.
- **레버가 절반만 막는다** — 7일권(20P)·30일권(35P)은 서울대도 동일 가격이라 포인트가 있으면
  우회된다. 다만 광고 적립이 2P라 모으는 속도가 40%로 떨어져 실질적으로는 느려진다.
- **조치의 실제 작용점은 "서울대 리뷰가 적다"가 아니다** — 교외 국가근장 6,647개가 `university_id=0`
  공용이고 근무지 RLS가 `university_id = 0 or 내대학`이라, 서울대 유저는 고려대 유저가 쓴 공용 근무지
  리뷰를 전부 읽는다. 따라서 이 변경은 "볼 게 없으니 짧게"가 아니라 열람 총량 조절에 가깝다.
  공지에 "서울대는 리뷰가 적어서"라고 쓰지 않기로 한 이유다.

## 파일 목록

| 파일 | 변경 |
|---|---|
| `web/supabase/migrations/<ts>_university_point_policy.sql` | 신규 — 표·헬퍼 2개·RPC 4개·재고 방어·공지 |
| `web/src/lib/passes.js` · `passes.test.js` | `minutes` 인자 추가(기본 60), 라벨 규칙, 테스트 |
| `web/src/pages/ExchangeCenter.jsx` | `wallet.hour_pass_minutes`를 passes 함수에 전달 (`expiryMonthDayLabel` 시그니처 포함) |
| `web/src/pages/MyPage.jsx` | 지갑 카드의 `passLabel` 호출에 같은 값 전달 |
| `web/supabase/README.md` · `web/src/lib/README.md` | 마이그레이션 기록 · `passes.js` 설명 갱신 |

`MyPage`도 `ExchangeCenter`와 같은 `fetchWallet()`을 쓰므로 값은 자동으로 온다. 다만 초기 상태를
`AuthContext`의 `user`에서 시드하는데 거기엔 이 필드가 없어, 첫 렌더는 60분으로 그렸다가 응답 후
바뀐다. 지갑 카드가 로딩 후 갱신되는 기존 동작과 같은 성격이라 그대로 둔다.

마이그레이션은 **1개 파일**, `begin`/`commit` 한 트랜잭션으로 묶는다. 표·헬퍼·RPC가 서로를 참조하므로
중간 상태가 노출되면 안 된다.

## 테스트

- `web/src/lib/passes.test.js`에 `minutes` 분기 테스트를 추가한다: 기본값 60일 때 기존 라벨·만료가
  그대로인지(회귀), 5일 때 `'5분 열람권'`·만료 +5분인지.
- 서버는 로컬 `db reset` 검증이 불가하다(이 환경에 Docker 없음). 읽기 검토 + push 후 실측으로 갈음한다.
  push 직후 서울대 계정으로 교환센터를 열어 `hour_pass_minutes=5`·`reward_points=2`가 내려오는지 본다.

## 배포 순서

1. 디스코드 공유
2. **prod 프론트 배포 먼저** (`main` → `prod` 머지 후 push) — 간극 동안 기본값 60으로 동작해 무해
3. `npx supabase migration list`로 대기 목록 확인 → `npx supabase db push`

## 되돌리기

```sql
delete from public.university_point_policy where university_id = 2;
```

한 줄이다. 헬퍼가 없는 행을 60분·전역 5P로 폴백하므로 RPC는 손댈 필요가 없다. 프론트도
`hour_pass_minutes`가 60으로 내려와 "1시간 열람권"으로 자동 복귀한다. 되돌릴 때 공지도 함께 정리한다.
