# Supabase Auth + RLS 클린 컷오버 — 설계서 (제안)

- 날짜: 2026-06-24
- 작성: 배경록(PM) · 검토/구현 주관: **현수(kindofwater) — 인증·RPC·DB 영역**
- 상태: **제안(Proposal)**. 팀 합의 전 코드 착수 금지(설계/조사 문서).
- 관계: **6/16 회의 결정 "인증·메일용 별도 Render 서버 신설"을 대체하는 제안**(`docs/회의록-2026-06-16.md` §회원가입/인증 1–2). @korea.ac.kr-only MVP(회의 결정)는 유지.
- 후속(별도 스펙): **②리워드 광고 서버**(영상/사진·토큰·쿨다운·완료검증) — 본 ①기반 위에 얹음.

---

## 1. 배경 · 동기

"Supabase로 리워드 광고 서버를 만들 수 있나?"에서 출발해 근본 원인에 도달했다:

- 현재 앱은 **Supabase Auth를 쓰지 않는다.** `createClient(url, anonKey)`만 쓰고([web/src/supabase.js](../../../web/src/supabase.js)), 인증은 자체 `users.password_hash` + `verify_login` RPC, 로그인 상태는 **localStorage에 위조 가능한 형태**로 저장한다([AuthContext.jsx](../../../web/src/components/AuthContext.jsx) 주석이 *"서버 권한 판단에 신뢰 금지 — 추후 Supabase Auth + RLS로"* 라고 명시).
- 모든 RPC가 `p_user_id`를 **클라이언트 인자로** 받고 `anon`에 grant됨 → 서버가 "누가 호출했는지" 모른다. 그래서 콘솔에서 `watch_ad_reward({p_user_id})`를 무한 호출해 포인트를 찍을 수 있고, 이는 열람권 페이월(7일=10P, 광고 1회=5P)을 무력화한다.
- 즉 **리워드 광고 보안의 선행조건 = 서버가 신뢰하는 로그인 신원**. 캡·쿨다운·영상검증도 신원 위에서만 의미가 있다.

**결정: 자체 인증을 Supabase Auth로 클린 컷오버**한다. 부수 효과로 메모의 보안 부채(`password_hash` anon 노출)도 종결되고, 6/16에 논의한 "별도 인증/메일 서버(Render)"가 **불필요**해진다(Supabase Auth가 @korea.ac.kr 확인메일·JWT·비번재설정을 네이티브 제공).

## 2. 범위

**포함(①):** 자체 인증 제거 → Supabase Auth 도입(이메일 확인 ON, @korea.ac.kr 제한) → 신원 UUID화 → 전 테이블 RLS → `p_user_id` RPC를 `auth.uid()`로 전환 → 클라이언트 세션/호출부 재작성.

**제외(후속):**
- **②리워드 광고 서버** — 영상/사진 소재·1회용 토큰·시청검증·쿨다운/캡. 별도 스펙. (현수)
- **관리자 콘솔 / `is_admin` 승격 / 리포트·공지 모더레이션** — 미설계.
- **서버측 열람권 페이월 강제** — 현재 클라이언트 계산(`locked = !isPassActive(...)`). 관련 부채, 후속.
- **계정 삭제 시 `auth.users` 동반 삭제** — 소프트삭제(`deleted_at`)만으론 로그인 차단 안 됨(아래 §7).

## 3. 확정된 결정

| # | 결정 | 근거 |
|---|---|---|
| D1 | **클린 컷오버**(데이터 보존 0, 테스트 유저 재가입) | 출시 전 단계(사용자 확인) |
| D2 | `public.users.id` = `auth.users.id`(**uuid 1:1**), 매핑테이블 없음 | 보존 데이터 없어 가장 단순 |
| D3 | **이메일 확인 ON** | 안티-부계정 + 광고/페이월 어뷰징 억제 |
| D4 | **@korea.ac.kr만(MVP)**, 학교 확장은 **데이터 주도** | 6/16 회의 결정 + 기존 `universities.email_domain` 데이터셋 |
| D5 | `public.users.email`·`password_hash` **DROP**(이메일 정본=`auth.users.email`) | 단순화 + 노출부채 종결 |
| D6 | 리뷰 열람 = **인증 필수**(게스트 브라우징 X) | 현 UX가 이미 전부 로그인 게이트 |

## 4. 설계

### A. 신원 · 스키마 재작성 (UUID 컷오버)

- `public.users.id`: `serial int` → **`uuid`**, `primary key references auth.users(id) on delete cascade`. 즉 `public.users`는 프로필 테이블, `auth.users`가 신원 정본.
- 보존 데이터 없음 → `TRUNCATE reviews, review_helpful, points, ad_views, reports, users RESTART IDENTITY CASCADE;` 후 타입 변경(빈 테이블이라 `USING` 자명).
- **`users(id)` 참조 FK 6개 전부 uuid화**(on_delete 의미 보존):

  | 테이블.컬럼 | on delete | 비고 |
  |---|---|---|
  | reviews.user_id | SET NULL | 탈퇴 시 익명화. nullable |
  | review_helpful.user_id | CASCADE | 복합 PK `(user_id, review_id)` 재생성 |
  | ad_views.user_id | SET NULL | nullable |
  | points.user_id | CASCADE | NOT NULL. 포인트 원장 |
  | reports.reporter_id | SET NULL | nullable |
  | reports.reported_user_id | SET NULL | 같은 테이블 2번째 FK |

- reviews 유니크 `(user_id, work_year, work_semester)`를 uuid로 재생성. **라이브 제약명이 드리프트**되어 있으니(`20260622`→4컬럼→`20260623`→3컬럼 되돌림) `pg_constraint` 인트로스펙션 do-block(20260623 패턴)으로 드롭 후 재생성.
- `password_hash`·`email` 컬럼 DROP, `pgcrypto` DROP(다른 `crypt/gen_salt` 사용처 없음 확인).

### B. 가입 · 로그인 (GoTrue + 트리거 + 학교 도메인 제한)

**가입 흐름**
1. 클라: `supabase.auth.signUp({ email, password, options: { data: { nickname, university_id, college_name, department_name, track, admission_year, degree_program, academic_status, grade, region } } })`.
2. `auth.users` INSERT 시 트리거 **`handle_new_user()`**(`security definer set search_path = public`)가 `NEW.raw_user_meta_data`로 `public.users` 행 생성(`id = NEW.id`). 대학명→`college_id`/`department_id` 해석은 기존 `register_user` 로직 이식.
3. **이메일 확인 ON**: 확인 전 세션 없음. 트리거는 가입 즉시 행 생성(확인 여부와 무관하게 INSERT 시 발화) → 확인 전엔 **로그인만** 막힘. 클라는 "메일을 확인하세요" 인터스티셜 표시, `supabase.js`에 `detectSessionInUrl: true`.

**학교 도메인 제한 (@korea.ac.kr-only → 데이터 주도 확장)**
- 데이터셋: `universities.email_domain`(이미 존재, [baseline.sql:33](../../../web/supabase/migrations/20260609000000_baseline.sql#L33), 시드 = 고려대 `korea.ac.kr` [import_to_supabase.py:31](../../../crawling_scripts/import_to_supabase.py#L31)).
- `universities`에 **`signup_enabled boolean not null default false`** 추가, **고려대만 `true`**.
- 트리거가 검증: 선택 `university_id`의 `email_domain`이 `NEW.email` 도메인과 **일치 AND 해당 학교 `signup_enabled = true`**. 불일치/미허용 → 가입 거부.
- **학교 추가 = 코드 변경 없이 `signup_enabled` 플래그 true + email_domain 확인**(데이터 주도). 보조로 Supabase Auth 허용 도메인 설정도 korea.ac.kr로 제한.

**⚠️ 트리거 주의 (보안 핵심)**
- `raw_user_meta_data`는 **클라이언트가 보낸 신뢰불가 값** → 트리거는 `point_balance/is_admin/pass_*`를 **절대 읽지 않는다**(서버 기본값만).
- enum 캐스팅(`degree_program`/`academic_status`)·대학명 해석·닉네임 유니크 위반은 트리거 안에서 검증. **트리거가 예외를 던지면 `auth.users` INSERT가 롤백되어 `signUp`이 불투명하게 실패** → 에러 표면화 설계 필요(`NICKNAME_TAKEN`/`NO_COLLEGE`/`DOMAIN_NOT_ALLOWED` 등을 클라가 구분할 수 있게).

**로그인 / 로그아웃 / 세션**
- 로그인: `verify_login` RPC → `supabase.auth.signInWithPassword({ email, password })`.
- ⚠️ **이메일-우선 2단계 로그인(`checkEmailExists`)은 Supabase Auth가 원천 미지원**(안티-이뉴머레이션). 로그인 UX를 **재설계**(바로 비번칸, 또는 `signIn` 에러로 분기). 1:1 치환 불가.
- 로그아웃: `supabase.auth.signOut()`.
- 세션 복원: `getSession()`(비동기) + `onAuthStateChange`.
- 비번 재설정: `resetPasswordForEmail` / `updateUser`(GoTrue). 자체 `set_password` 제거.

### C. RLS + RPC 보안 (auth.uid() 전환)

**RPC: `p_user_id` 제거 → `auth.uid()`** (대상 10개)
- 공통: 인자에서 `p_user_id` 삭제, 본문 시작에 `v_uid uuid := auth.uid(); if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;`. 시그니처 변경이므로 **`drop function if exists` 먼저**.
- 대상: `update_profile`, `_wallet`, `purchase_pass`, `refund_pass`, `activate_pass`, `watch_ad_reward`, `toggle_helpful`, `write_review_with_points`, `update_review_with_points`, `delete_review_with_rollback`.
- 리뷰 3종은 현재 **SECURITY INVOKER** → `security definer set search_path = public`로 승격(포인트 원장·잔액을 한 트랜잭션에서 안전 변경).
- grant 정리: 위 전부 `revoke execute ... from anon, public; grant execute ... to authenticated;`.
- `get_worksite_score_cards`에 누락된 `set search_path = public` 추가(하드닝).
- 읽기전용 공개집계(`get_review_stats`, `get_worksite_score_cards`, `pass_price`)는 anon 유지 가능(정책 결정).

**RLS 정책 (전 테이블 ON; 정책 없으면 기본 거부)**

| 테이블 | SELECT | INSERT | UPDATE/DELETE |
|---|---|---|---|
| users | 본인 행(`id = auth.uid()`). 타인 공개필드(닉네임 등)는 **DEFINER RPC로만** 노출 | 없음(트리거만) | 본인 행 + **컬럼 GRANT로 특권컬럼 차단**(아래) |
| reviews | 인증 사용자 읽기. **단 `user_id` 베이스 노출 금지** → 목록은 DEFINER RPC/뷰로(익명 시 닉네임·학기 가림) | `write_review_with_points`(DEFINER, `user_id=auth.uid()`)만 | 리뷰 RPC만(직접 정책 X) |
| points | 본인 원장(`user_id = auth.uid()`) | 없음(RPC만) | 없음(append-only) |
| ad_views | 본인(`user_id = auth.uid()`) | 없음(RPC만) | 없음 |
| reports | 없음(민감) — 관리자 service_role | `report_review`(DEFINER, `reporter_id=auth.uid()`)만 | 없음 |
| review_helpful | 본인(`user_id = auth.uid()`) | 없음(`toggle_helpful`만) | 없음 |
| worksites | anon+auth 공개 | 없음 | 없음(view_count는 RPC) |
| universities/colleges/departments | anon+auth 공개(가입 지원) | 없음 | 없음 |
| postings | anon+auth 공개 | 없음 | 없음 |
| notices | anon+auth 공개 | 없음(관리자) | 없음 |

- **특권 컬럼 2중 방어(컬럼 GRANT)**: RLS는 행 단위라 컬럼을 못 막는다. 따라서:
  `revoke update on public.users from authenticated;`
  `grant update (region, admission_year, degree_program, academic_status, grade, track, nickname, updated_at) on public.users to authenticated;`
  → `point_balance/pass_balances/pass_expires_at/is_admin/id/created_at/deleted_at`은 GRANT에서 빠져 **직접 UPDATE 자체가 거부**(RLS `WITH CHECK` 위 추가 방어). 이 컬럼들은 오직 DEFINER RPC로만 변경.
- **깨지는 직접 anon 쓰기 2곳 → RPC화**: `incrementViewCount`(worksites UPDATE) → `increment_worksite_view(p_worksite_id)`; `reportReview`(reports INSERT, 클라가 reporter_id 전달) → `report_review(p_review_id, p_reason)`(`reporter_id=auth.uid()`). `devExpirePass`는 DEV 전용 → **폐기**.

### D. 클라이언트 재작성

- **`web/src/supabase.js`**: `createClient(url, key, { auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true } })`.
- **`web/src/components/AuthContext.jsx`(핵심 재작성)**: localStorage `'honeyjang.user'` 제거. 마운트 시 `getSession()`, `onAuthStateChange` 구독(StrictMode 이중호출 → cleanup 필수), **`isLoading` 플래그** 추가. `signInWithPassword`는 프로필/지갑을 안 주므로 **SIGNED_IN/복원마다 `public.users` 프로필 + 지갑(point_balance/pass_*)을 `auth.uid()`로 fetch해 `context.user`에 머지**(소비처: AccountMenu·MyPage·WorksiteDetail·Search·Home·ReviewForm). 기존 `login({...user,...wallet})`는 **Supabase를 건드리지 않는 로컬 머지 세터**로 교체.
- **데이터 레이어**: 전 RPC 호출에서 `user.id` 인자 제거. `authQueries`(verifyLogin→signInWithPassword, registerUser→signUp, checkEmailExists 제거, updateProfile 무인자), `exchangeQueries`(purchase/refund/activate/watchAd 무인자, fetchWallet 무인자, devExpirePass 제거), `worksiteQueries`(리뷰·helpful 무인자, report/viewCount RPC화, fetchReviews는 익명 마스킹 RPC), `mypageQueries`(원장/내리뷰 RLS 본인범위).
- **페이지**: Login(UX 재설계), Signup(signUp+메타데이터, 확인메일 인터스티셜), MyPage·ExchangeCenter·AdView·WorksiteDetail·ReviewForm·Home(인자 제거 + 머지세터). `App.jsx`: 세션 비동기 복원 레이스 → `isLoading` 가드/ProtectedRoute(로그인 사용자가 새로고침 시 `/login`으로 튕기는 것 방지).

### E. 마이그레이션 · 롤아웃 (CLAUDE.md §3 준수)

순서가 잡힌 단일(또는 소수) 마이그레이션:
1. 커스텀 인증 DROP: `verify_login`, `register_user`(11·12인자 전부), `set_password`, seed-password backfill, `password_hash` REVOKE 라인.
2. 데이터 wipe + 신원 재구축(D2): TRUNCATE → users.id uuid화 → `auth.users` FK.
3. 컬럼 DROP: `password_hash`, `email`, `pgcrypto`.
4. FK 6개 uuid화 + on_delete 보존 + 복합PK/유니크 재생성.
5. `handle_new_user` 트리거 + `on_auth_user_created`.
6. `p_user_id` RPC 10개 재작성(`auth.uid()`) + 리뷰 3종 DEFINER 승격.
7. grant 정리(anon/public 회수 → authenticated).
8. 전 테이블 RLS ON + 정책 + users 컬럼 GRANT.
9. `increment_worksite_view`·`report_review` 신설, `devExpirePass` 폐기.

**필수 절차**: 파일 헤더 2줄(`목적`/`날짜·담당`), **`drop function if exists` 먼저**, 로컬 `cd web && npx supabase db reset`로 맨바닥 재구축 검증(로컬 스택의 `auth` 스키마 포함). → 디스코드 사전공유 → `db push`(작성자가). **`verify_login`/`register_user` 드롭은 현수 영역 → 푸시 순서 합의.** PostgREST 스키마 캐시 reload, 로컬 시드 유저는 `auth.users`로 재시드 필요. `docs/db-schema.md`·`web/supabase/README.md`·관련 폴더 README 동시 갱신.

## 5. 미결 / 팀 협의

- **현수 협의(필수)**: 본 제안은 6/16의 "Render 인증서버"를 Supabase Auth로 대체. 인증 RPC 드롭/트리거 작성·푸시 주체와 순서, 클라 컷오버와의 타이밍.
- 리뷰 목록을 anon에도 보일지(D6은 인증필수 가정) — 확정 시 공개 RPC grant 범위 결정.
- `public.users.email` 미러를 정말 버릴지(D5: 버림) — 관리/조인 편의 vs 이뉴머레이션 표면.
- 브랜치 정책(CLAUDE.md): 대규모 다중파일 변경 → 별도 기능 브랜치 권장.

## 6. ②리워드 광고 서버와의 경계 (다음 스펙에서 6/16과 정합)

본 ①은 `watch_ad_reward`에 `auth.uid()`만 입힌다(누가 호출했는지 보장). **광고 어뷰징 차단(쿨다운/캡/완료검증)과 소재 처리는 ②**. ②착수 전 6/16 결정과 **반드시 정합**시킬 것:
- **소재 형식**: 회의 "사진 5초로 충분, 영상 불필수"(29) ↔ 구두로 받은 "영상". → 사진/영상 확정.
- **시청 캡**: 회의 "횟수 제한 안 걸어도 될 듯"(미결) ↔ 구두로 받은 "빡빡한 캡". → 캡 유무·수치 확정.
- 회의 결정: Adsterra 미사용(27), 로컬 광고(주변 가게) 우선·인스타 리다이렉트(28), 광고 등록 스캐폴딩은 현수(다 못하면 경록 인계).

## 7. 알려진 함정 (조사 `auth-rls-migration-inventory` 발췌)

- 이메일 확인 ON이면 트리거가 **확인 전에도** 행 생성(원하면 `email_confirmed_at` UPDATE 트리거로 분기 — 별도 설계).
- `is_admin` 승격 경로 부재: RLS+컬럼GRANT로 자가설정 차단되므로 **service_role/SQL로만 승격**. 관리자 콘솔 미설계.
- **소프트삭제 한계**: `users.deleted_at` 설정해도 `auth.users`는 여전히 로그인됨 → 계정삭제는 `auth.users` 삭제/차단(admin API) 동반 필요.
- Storage/Realtime/Edge Function 현재 없음 — 마이그레이션 대상 아님(추후 아바타/광고이미지 추가 시 Storage RLS 필요).
- 익명 마스킹은 목록 RPC뿐 아니라 **집계 함수(`get_review_stats`/`get_worksite_score_cards`) 내부에서도** 보장돼야(둘 다 reviews RLS 우회).

---

## 부록: 근거 인벤토리 (read-only 조사)

**users 특권 컬럼**(자가편집 금지, DEFINER RPC로만): `point_balance`, `pass_balances`, `pass_expires_at`, `is_admin`, `password_hash`(삭제), `email`(삭제→auth), `id`/`created_at`/`updated_at`/`deleted_at`(시스템).

**`p_user_id` 신뢰경계 RPC(전환 대상)**: write/update/delete_review_with_points, toggle_helpful, _wallet, purchase_pass, refund_pass, activate_pass, watch_ad_reward, update_profile. (현재 anon이 임의 `p_user_id`로 타인 포인트 사용·지갑 조회·프로필 수정·광고적립 가능.)

**제거 대상**: `verify_login`, `register_user`, `set_password`, `pgcrypto`, `password_hash`/`email` 컬럼, `checkEmailExists`(직접 users 읽기), AuthContext localStorage 세션, seed-password backfill. (비번 스킴 = bcrypt `crypt(pw, gen_salt('bf',10))`; 클린 컷오버라 import 없이 DROP.)

**RLS-OFF 의존 직접쓰기(컷오버로 깨짐)**: `devExpirePass`(폐기), `incrementViewCount`(RPC화), `reportReview`(RPC화), mypage 원장/리뷰 스캔(본인범위 RLS).

> 전체 조사 원본: 워크플로 `auth-rls-migration-inventory`(FK 6 · RPC 18 · anon grant 전수 · 클라 호출부 전 파일 · 제거목록). 필요 시 재실행.
