# 회원가입 이메일 OTP 인증 재설계 — 설계 문서(Spec)

**날짜:** 2026-06-27 · **담당:** detail_choi_2 작업자
**상태:** 설계 승인 대기 → 승인 후 구현 계획(writing-plans)으로 전환

---

## 1. 목적 (Goal)

회원가입 흐름에서 **이메일 인증(6자리 OTP 코드)을 맨 앞으로** 옮기고, **프로필 DB 행 저장을 맨 마지막으로** 옮긴다.

- 인증되지 않은 사람의 프로필 행이 DB에 미리 생기지 않도록 한다.
- 매직링크가 아니라 **앱 안에서 코드를 입력**하는 방식(앱을 떠나는 왕복 없음).

---

## 2. 현재 동작 (As-Is) — 이 설계의 출발점

> 현재 코드는 이미 Supabase Auth로 전환돼 있다(2026-06-24 cutover). 회원가입 1줄 흐름:

1. **로그인 화면**([Login.jsx](../../../web/src/pages/Login.jsx)): 이메일 입력 → `email_registered` RPC로 가입여부 조회 → 미가입이면 비밀번호+재입력 → 프로필 단계로 전환하며 `<Signup/>` 마운트.
2. **회원가입 화면**([Signup.jsx](../../../web/src/pages/Signup.jsx)): 프로필(닉네임·지역·학교 → 학적 → 단과대/학과/계열) 입력 → 마지막에 `signUpUser` 호출.
3. **`signUpUser`**([authQueries.js](../../../web/src/data/authQueries.js)): `supabase.auth.signUp(email, password, { data: 프로필전체 })` — 프로필을 **user metadata로** 통째 전달.
4. **DB 트리거 `handle_new_user`**([20260626152144_relax_signup_domain.sql](../../../web/supabase/migrations/20260626152144_relax_signup_domain.sql)): `auth.users` INSERT 시 자동 실행 → `*.ac.kr` 도메인 검사 + 단과대/학과 이름→id 해석 + **`public.users` 프로필 행 즉시 insert** + 닉네임 중복(`NICKNAME_TAKEN`) 검사.
5. **이메일 확인**(prod 대시보드 "Confirm email" ON): Supabase가 확인 메일(현재 링크) 발송. 확인 전까지 세션 없음 → Signup이 "인증 메일 보냈어요" 안내(`setSent`).
6. **세션 반영**([AuthContext.jsx](../../../web/src/components/AuthContext.jsx)): `getSession` + `onAuthStateChange` → `fetchMe`(프로필 + 지갑) → `user`.

**As-Is의 한계:** 인증이 맨 뒤, 프로필 행은 인증 전(트리거)에 생성됨. 목적과 반대.

### 관련 기존 자산
- `email_registered(text)` RPC: 이메일 가입여부 boolean ([20260626153426_email_registered_check.sql](../../../web/supabase/migrations/20260626153426_email_registered_check.sql)).
- `_wallet()`·RLS·`update_profile()` 등은 2026-06-24 cutover에서 `auth.uid()` 기반으로 정립됨([20260624025109_auth_rls_cutover.sql](../../../web/supabase/migrations/20260624025109_auth_rls_cutover.sql)).
- `config.toml`: `auth.email.otp_length = 6`, `otp_expiry = 3600`(1시간), `auth.rate_limit.email_sent = 2`(시간당, 커스텀 SMTP 없을 때).

---

## 3. 확정된 결정 (브레인스토밍 결과)

| # | 결정 | 비고 |
|---|------|------|
| D1 | **단계 순서: 이메일 → 비번 → OTP → 프로필 → 저장** | 비번이 OTP보다 먼저(= `signUp`이 비번 필요). |
| D2 | **OTP = Supabase native 이메일 OTP** | 커스텀 OTP 인프라 불필요. 메일 템플릿을 코드(`{{ .Token }}`)로. 매직링크 ❌. |
| D3 | **미완료(인증O·프로필X) 처리 = 이어쓰기** | 다음 접속 시 프로필 입력 단계로 라우팅. 계정 삭제 없음(교착 회피). |
| D4 | **OTP 입력 = Signup의 첫 단계(step 0)** | Login은 이메일+비번만, 나머지는 Signup이 소유. |
| D5 | **Google SMTP 설정 = 이 작업 범위에 포함** | 기본 2통/시간 한도로는 테스트 불가. |
| D6 | **프로필 행 저장 = 맨 마지막 `create_profile` RPC** | 트리거의 insert는 제거. |

---

## 4. 접근법 (Approach) — 대안 비교

- **(채택) Supabase native 이메일 OTP**: `signUp`이 코드 메일 발송 → `verifyOtp`로 검증. 추가 인프라 0(설정에 OTP 이미 존재). 발송은 Supabase가 하므로 SMTP만 붙이면 됨.
- (기각) 커스텀 OTP: 코드 테이블 + Edge Function 직접 구현. native로 충분한데 과잉.
- (기각) 매직링크: 사용자가 앱을 떠나 메일 링크 클릭 → 돌아오는 왕복 + "세션 있는데 프로필 없음" 재진입 처리 복잡. 사용자 요구로 제외.

> **OTP와 SMTP의 관계(중요):** "native OTP"는 *코드 생성·검증 로직*을 Supabase가 대신해 준다는 뜻이다. 그 코드가 담긴 **메일을 실제로 발송하는 수단**은 별개이며 그게 SMTP다. Supabase 내장 발송기는 시간당 2통이라(§2) 테스트조차 어렵다 → **Google SMTP를 붙여 발송 한도를 올린다**(§6.7). 즉 OTP=두뇌, SMTP=배달 트럭, 둘 다 필요.

---

## 5. 새 흐름 (To-Be)

```
[Login]  이메일 입력 → email_registered → 미가입
         → 비밀번호 + 재입력(일치 검사)
         → <Signup/> 마운트 (email, password 전달)

[Signup step 0 = OTP]
         (마운트 시) signUpAuth(email, password)  → Supabase가 6자리 코드 생성,
                                                     SMTP(Gmail)로 코드 메일 발송
         → 코드 입력칸 표시 → verifyEmailOtp(email, code)
         → 성공 시 세션 생성(이메일 인증 완료)

[Signup step 1~3 = 프로필]
         닉네임·지역·학교 → 입학연도·학위·학년·학적 → 단과대/학과/계열

[Signup 완료]
         createProfile(프로필) RPC → public.users 행 insert(여기서 처음 생성)
         → /home
```

**이어쓰기(D3):** 앱 로드 시 `세션 있음 + 프로필 없음`이면 Signup을 **프로필 단계부터**(OTP 건너뜀, 이미 인증됨) 띄우고, 완성 전엔 다른 라우트 접근 차단.

---

## 6. 컴포넌트 / 단위별 설계

### 6.1 DB — 트리거 슬림화
- **`handle_new_user` 트리거**: 프로필 insert·단과대/학과 해석·닉네임 검사 **전부 제거**. 남기는 것은 **`*.ac.kr` 도메인 검사뿐**(비.ac.kr → `DOMAIN_NOT_ALLOWED` raise로 `signUp` 차단). 시그니처 동일(`create or replace`) → 기존 grant/트리거 보존.
- 이유: 새 `signUp`은 프로필 metadata를 안 싣는다. 트리거가 프로필을 만들 근거가 없다.

### 6.2 DB — `create_profile` RPC (신규)
- **시그니처(안):**
  `create_profile(p_nickname text, p_university_id int, p_college_name text, p_department_name text, p_track text, p_admission_year int, p_degree_program text, p_academic_status text, p_grade int, p_region text)` → 저장된 프로필 행 반환.
- **동작:** `security definer`, `v_uid := auth.uid()`. 단과대/학과 이름→id 해석(기존 트리거 로직 이식). `users` 행 insert(`id = v_uid`). 닉네임 중복 시 `NICKNAME_TAKEN`. **이미 프로필이 있으면**(더블클릭/재호출) 새로 만들지 않고 **기존 행을 반환**(재호출 안전). 프로필 *갱신*은 기존 `update_profile` RPC가 담당.
- **권한:** `authenticated`에 grant, `anon` 회수.

### 6.3 프론트 — 데이터 함수 분해 ([data/authQueries.js](../../../web/src/data/authQueries.js))
- `signUpAuth(email, password)` → `supabase.auth.signUp({ email, password })` (metadata 없음). 코드 메일 발송.
- `verifyEmailOtp(email, token)` → `supabase.auth.verifyOtp({ email, token, type })` (type 값 `'signup'`/`'email'` 구현 시 확정).
- `resendOtp(email)` → `supabase.auth.resend({ type, email })`.
- `createProfile(payload)` → `create_profile` RPC 래퍼.
- 기존 `signUpUser`는 제거(또는 위로 대체).

### 6.4 프론트 — Login ([pages/Login.jsx](../../../web/src/pages/Login.jsx))
- 역할 축소: 이메일(가입여부 분기) + 비밀번호+재입력까지만. 검증 후 `<Signup email password/>` 마운트.
- 회원가입 비번 단계 UI(2필드·일치 검사)는 현재 구현 유지.

### 6.5 프론트 — Signup ([pages/Signup.jsx](../../../web/src/pages/Signup.jsx))
- **step 0 (신규, OTP):** 마운트 시 `signUpAuth(email,password)`로 코드 발송 → 코드 입력칸 + "재전송" → `verifyEmailOtp` 성공 시 step 1로.
  - **단, 이어쓰기 진입(이미 세션 있음)이면 step 0를 건너뛰고 step 1부터.** (이미 인증됨)
- **step 1~3 (기존 프로필):** 그대로.
- **완료:** `signUpUser` → `createProfile`로 교체. "인증 메일 보냈어요" 인터스티셜(`setSent`) **삭제** → 성공 시 `/home`.
- 진척도 바: 총 4단계(OTP+프로필3)로 재계산.

### 6.6 프론트 — AuthContext / App (이어쓰기 게이트)
- `AuthContext`가 **세션 유무**와 **프로필 유무**를 구분 노출(예: `session`, `user(프로필)`, 파생 `needsProfile = !!session && !user`).
- `App`: `needsProfile`면 프로필 완성 화면(Signup의 프로필 단계)으로 라우팅하고 그 외 라우트 접근 차단. `isLoading` 동안은 기존처럼 로딩 표시.

### 6.7 이메일 발송 — SMTP / 템플릿 (대시보드, 이 작업 범위)
- **역할:** Supabase가 만든 OTP 코드를 담은 메일을 **실제 배달**하는 수단(§4 박스 참조). 내장 발송기는 2통/시간이라 부적합.
- **Google SMTP 연결**: Gmail 계정 + 앱 비밀번호 → Supabase SMTP 설정에 입력. 한도: Gmail ~500통/일(운영 대량이면 후속에 전용 발송 서비스로 교체 여지).
- "Confirm signup" 템플릿을 **코드(`{{ .Token }}`)** 표시로 수정.
- "Confirm email"(이메일 확인 필수) ON 유지.

---

## 7. 에러 / 예외 처리

| 상황 | 처리 |
|------|------|
| OTP 틀림/만료(1h) | `verifyEmailOtp` 에러 → 코드 필드 인라인 "코드가 올바르지 않거나 만료됐어요" + **재전송** 버튼 |
| 재전송 rate limit | Supabase `max_frequency`/시간당 한도 → 안내 문구(잠시 후 다시) |
| 닉네임 중복 | `create_profile`의 `NICKNAME_TAKEN` → 닉네임 단계로 복귀 + 인라인 |
| 비.ac.kr 도메인 | 클라(`isSchoolEmail`) + 서버(트리거 `DOMAIN_NOT_ALLOWED`) 이중 차단 |
| 인증 후 프로필 중 이탈 | 이어쓰기(D3): 다음 접속 시 프로필 단계로 |
| 이미 가입된 이메일로 재가입 시도 | Login의 `email_registered`가 로그인 분기로 보냄(가입 분기 안 탐) |

---

## 8. 보안 / 비기능

- RLS·anon 정책은 **이번에 변경하지 않음**(cutover 정립분 유지). 새 `create_profile`은 `security definer` + `auth.uid()`라 RLS 우회 없이 본인 행만 생성.
- `email_registered`의 enumeration 트레이드오프는 기존 결정대로 수용(별도 rate limit은 후속).
- 미완료(인증O·프로필X) auth 계정은 누적될 수 있음 → **주기적 정리(관리 배치)** 는 후속 과제(이번 범위 밖, 문서에만 명시).

---

## 9. 테스트 / 검증 (큰 수술 → 빡세게)

- **단위(vitest/SQL):** `create_profile`(닉네임 중복, 단과대/학과 해석 폴백, 본인 행만 생성).
- **수동 시나리오:**
  1. 정상 가입: 이메일→비번→코드 수신→입력→프로필→홈.
  2. 이어쓰기: 코드 인증 후 새로고침 → 프로필 단계로 복귀 → 완료.
  3. OTP 틀림 / 만료 / 재전송.
  4. 닉네임 중복(마지막 단계 차단).
  5. 비.ac.kr 거부.
  6. 로그인(기존 유저): 이메일→로그인 분기→`signIn`.
- **메일 발송:** Google SMTP로 실제 코드 수신 확인(로컬은 inbucket).

---

## 10. 범위 밖 (Non-Goals)

- 미완료 auth 계정 자동 정리 배치.
- `email_registered` rate limit / 캡차(후속).
- 비밀번호 재설정 흐름(별개).
- 학교 다건 확장(현재 *.ac.kr + 학교 드롭다운은 사실상 고려대).

---

## 11. 구현 시 확정할 디테일 (Open, 차단 아님)

- `verifyOtp`/`resend`의 `type` 값(`'signup'` vs `'email'`) — Supabase 버전 동작 확인.
- 메일 템플릿 토큰 변수명(`{{ .Token }}`) 정확 표기.
- 진척도 바 4단계 표기 방식.
