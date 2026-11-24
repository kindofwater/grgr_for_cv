# 회원가입 이메일 OTP 인증 재설계 — 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 회원가입에서 6자리 이메일 OTP 인증을 맨 앞으로, 프로필 DB 행 저장을 맨 마지막으로 옮긴다.

**Architecture:** `signUp(email,password)`이 Supabase native OTP 코드 메일을 보내고 `verifyOtp`로 앱 안에서 검증한다. DB 트리거는 도메인 검사만 남기고(프로필 insert 제거), 프로필은 인증·입력 완료 후 `create_profile` RPC(`auth.uid()`)로 저장한다. Login이 `<Signup/>`의 단독 소유자로 남고(`profileStep || needsProfile`일 때 렌더), App은 "세션O·프로필X"(resume)를 `/login`으로 리다이렉트만 한다.

**Tech Stack:** React 19 + Vite, react-router-dom 7, @supabase/supabase-js ^2.106, Supabase(Postgres + Auth/GoTrue), Vitest, Supabase CLI.

## Global Constraints

- 설계 문서: `docs/superpowers/specs/2026-06-27-email-otp-signup-design.md` (D1~D6 결정 준수).
- **RLS·anon 정책 변경 금지.** 새 DB 접근은 `security definer` + `auth.uid()` RPC로.
- DB 변경은 `web/supabase/migrations/` 마이그레이션으로만. 파일 맨 위 헤더 2줄 필수(`-- 목적:` / `-- 날짜: 2026-06-27 · 담당: <이름>`). 시그니처 바꾸면 `drop function` 먼저.
- DB 통신은 `web/src/data/`에서만. 페이지·컴포넌트는 supabase 직접 호출 금지.
- 도메인 허용 = `*.ac.kr`. 클라 검증은 기존 `lib/authValidation.isSchoolEmail`.
- 사용자 카피 한국어, 기존 톤 유지.
- 실가입 유저 없음 → 데이터 이전 불필요.
- 이 레이어(Auth/RPC/페이지)는 기존에도 자동 테스트가 없다(lib 순수함수만 vitest). 따라서 검증은 **lint + 수동 시나리오 + 로컬 inbucket 메일 확인**으로 한다(가짜 단위테스트 만들지 않음).
- 작업 브랜치: `detail_choi_2`.

---

## File Structure

- `web/supabase/migrations/<ts>_otp_signup.sql` — **생성**. 트리거 슬림화 + `create_profile` RPC.
- `web/src/data/authQueries.js` — **수정**. `signUpUser` 제거, `signUpAuth`·`verifyEmailOtp`·`resendOtp`·`createProfile` 추가.
- `web/src/components/AuthContext.jsx` — **수정**. `session` 노출 + `needsProfile` 파생.
- `web/src/App.jsx` — **수정**. resume 리다이렉트 가드.
- `web/src/pages/Signup.jsx` — **수정**. step 0 = OTP, 세션-인지 시작단계, 끝에서 `createProfile`, 인터스티셜 제거.
- `web/src/pages/Login.jsx` — **수정**. `profileStep || needsProfile`일 때 `<Signup/>` 렌더.
- (대시보드) Google SMTP + 코드 템플릿 — Task 0(수동).

---

## Task 0: 대시보드 — SMTP·OTP 템플릿 (수동, 코드 아님)

> supabase.com 프로젝트(GRGR)에서 클릭. 이 Task가 끝나야 OTP 메일이 실제로 발송됨.

- [ ] **Step 1:** Authentication → Providers → Email → **Confirm email ON** 유지.
- [ ] **Step 2:** Authentication → Email Templates → **Confirm signup**: 본문을 코드 표시로.
  - 제목 예: `근로고래 이메일 인증 코드`
  - 본문 예: `인증 코드: {{ .Token }} (10분 내 입력)` — `{{ .ConfirmationURL }}`(링크) 제거.
- [ ] **Step 3:** Project Settings → Authentication → SMTP Settings → **Enable Custom SMTP**:
  - Host `smtp.gmail.com` / Port `587` / Username `<gmail 주소>` / Password `<앱 비밀번호 16자리>` / Sender `<gmail 주소>` / Sender name `근로고래`.
- [ ] **Step 4:** 테스트 발송으로 수신 확인.

**산출물:** signUp 시 6자리 코드 메일이 Gmail로 발송됨.

---

## Task 1: DB — 트리거 슬림화 + `create_profile` RPC

**Files:**
- Create: `web/supabase/migrations/<timestamp>_otp_signup.sql`

**Interfaces:**
- Produces (RPC): `create_profile(p_nickname text, p_university_id int, p_college_name text, p_department_name text, p_track text, p_admission_year int, p_degree_program text, p_academic_status text, p_grade int, p_region text) returns void`. 본인(`auth.uid()`) 프로필 행 생성. 이미 있으면 no-op. 닉네임 중복 시 `NICKNAME_TAKEN`.
- Changes: `handle_new_user` 트리거가 프로필 insert를 더 이상 하지 않음(도메인 검사만).

- [ ] **Step 1: 마이그레이션 파일 생성**

Run: `cd web && npx supabase migration new otp_signup`

- [ ] **Step 2: SQL 작성** (헤더 2줄 포함)

```sql
-- 목적: 회원가입 OTP 재설계 — 트리거는 도메인 검사만, 프로필 저장은 create_profile RPC(맨 마지막)로.
-- 날짜: 2026-06-27 · 담당: <이름>

-- [1] 트리거 슬림화: 프로필 insert·단과/학과 해석·닉네임 검사 제거, *.ac.kr 검사만 유지.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if lower(split_part(new.email, '@', 2)) not like '%.ac.kr' then
    raise exception 'DOMAIN_NOT_ALLOWED';
  end if;
  return new;
end $$;
revoke execute on function public.handle_new_user() from anon, public;

-- [2] create_profile: 프로필 입력 완료 후 호출. 본인(auth.uid()) 행 생성.
drop function if exists create_profile(text,int,text,text,text,int,text,text,int,text);
create function create_profile(
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
          p_nickname, p_admission_year,
          p_degree_program::degree_program_e, p_academic_status::academic_status_e,
          p_grade, p_region);
exception
  when unique_violation then raise exception 'NICKNAME_TAKEN';
end $$;
revoke execute on function create_profile(text,int,text,text,text,int,text,text,int,text) from anon, public;
grant execute on function create_profile(text,int,text,text,text,int,text,text,int,text) to authenticated;
```

- [ ] **Step 3: 검증** — Docker 있으면 `npx supabase db reset` 무에러 통과 확인. 없으면 sandbox 프로젝트에 `db push`.
- [ ] **Step 4: prod 반영** — 디스코드 공지 후 `npx supabase db push`.
- [ ] **Step 5: 커밋**

```bash
git add web/supabase/migrations/*_otp_signup.sql
git commit -m "feat(db): slim handle_new_user to domain-check + add create_profile RPC"
```

---

## Task 2: data — Auth 래퍼 교체

**Files:**
- Modify: `web/src/data/authQueries.js`

**Interfaces:**
- Consumes: `../supabase`, Task 1의 `create_profile` RPC.
- Produces:
  - `signUpAuth(email, password)` → `{ user, session }` (코드 메일 발송, 세션 없음)
  - `verifyEmailOtp(email, token)` → `{ user, session }` (성공 시 세션)
  - `resendOtp(email)` → void
  - `createProfile(payload)` → void (payload 키: nickname, university_id, college_name, department_name, track, admission_year, degree_program, academic_status, grade, region)
- Removes: `signUpUser`.

- [ ] **Step 1: `signUpUser` 제거 + 새 래퍼 추가**

`signUpUser` 함수를 아래로 교체:

```js
// 회원가입 1: 계정 생성 + OTP 코드 메일 발송 (프로필 metadata 없음). 세션은 verify 후 생김.
export async function signUpAuth(email, password) {
  const { data, error } = await supabase.auth.signUp({
    email: email.trim().toLowerCase(), password,
  })
  if (error) throw error
  return data
}

// 회원가입 2: 메일로 받은 6자리 코드 검증 → 성공 시 세션 생성.
export async function verifyEmailOtp(email, token) {
  const { data, error } = await supabase.auth.verifyOtp({
    email: email.trim().toLowerCase(), token, type: 'signup',
  })
  if (error) throw error
  return data
}

// 코드 재전송.
export async function resendOtp(email) {
  const { error } = await supabase.auth.resend({ type: 'signup', email: email.trim().toLowerCase() })
  if (error) throw error
}

// 회원가입 3(마지막): 프로필 행 저장. auth.uid() 기준. 닉네임 중복 시 NICKNAME_TAKEN.
export async function createProfile(p) {
  const { error } = await supabase.rpc('create_profile', {
    p_nickname: p.nickname, p_university_id: p.university_id,
    p_college_name: p.college_name, p_department_name: p.department_name, p_track: p.track,
    p_admission_year: p.admission_year, p_degree_program: p.degree_program,
    p_academic_status: p.academic_status, p_grade: p.grade, p_region: p.region,
  })
  if (error) throw error
}
```

- [ ] **Step 2: lint**

Run: `cd web && npx eslint src/data/authQueries.js`
Expected: 통과(exit 0). (이 시점 Signup이 아직 `signUpUser` import 중이면 다음 Task에서 교체 — Task 5와 함께 빌드 확인.)

- [ ] **Step 3: 커밋**

```bash
git add web/src/data/authQueries.js
git commit -m "feat(data): split signup into signUpAuth/verifyEmailOtp/resendOtp/createProfile"
```

---

## Task 3: AuthContext — 세션 노출 + needsProfile

**Files:**
- Modify: `web/src/components/AuthContext.jsx`

**Interfaces:**
- Consumes: 기존 `fetchMe`, `supabase`.
- Produces: `useAuth()` → `{ user, session, isLoading, needsProfile, mergeUser, logout }`. `needsProfile = !isLoading && !!session && !user` (인증됐지만 프로필 없음).

- [ ] **Step 1: session 상태 추가 + needsProfile 노출**

`AuthProvider` 본문을 아래로 교체(핵심: `session` 상태 추가, hydrate에서 세팅, value에 `session`·`needsProfile` 추가):

```jsx
export function AuthProvider({ children }) {
  const [user, setUser] = useState(null)
  const [session, setSession] = useState(null)
  const [isLoading, setIsLoading] = useState(true)

  useEffect(() => {
    let active = true
    async function hydrate(s) {
      if (active) setSession(s)
      if (!s) { if (active) { setUser(null); setIsLoading(false) } return }
      try {
        const me = await fetchMe()
        if (active) setUser(me ? { id: s.user.id, ...me } : null)
      } catch {
        if (active) setUser(null)
      } finally {
        if (active) setIsLoading(false)
      }
    }
    supabase.auth.getSession().then(({ data }) => hydrate(data.session))
    const { data: sub } = supabase.auth.onAuthStateChange((_event, s) => {
      setTimeout(() => hydrate(s), 0)
    })
    return () => { active = false; sub.subscription.unsubscribe() }
  }, [])

  const mergeUser = (patch) => setUser((u) => (u ? { ...u, ...patch } : u))
  const logout = () => supabase.auth.signOut()
  const needsProfile = !isLoading && !!session && !user

  return (
    <AuthContext.Provider value={{ user, session, isLoading, needsProfile, mergeUser, logout }}>
      {children}
    </AuthContext.Provider>
  )
}
```

- [ ] **Step 2: lint**

Run: `cd web && npx eslint src/components/AuthContext.jsx`
Expected: 통과.

- [ ] **Step 3: 커밋**

```bash
git add web/src/components/AuthContext.jsx
git commit -m "feat(auth): expose session + needsProfile from AuthContext"
```

---

## Task 4: App — resume 리다이렉트 가드

**Files:**
- Modify: `web/src/App.jsx`

**Interfaces:**
- Consumes: Task 3의 `needsProfile`.
- Behavior: `needsProfile && pathname !== '/login'` 이면 `/login`으로 리다이렉트(거기서 Login이 `<Signup/>` 프로필 단계 렌더 — Task 6).

- [ ] **Step 1: 가드 컴포넌트 추가**

`react-router-dom` import에 `useLocation` 추가. `AppRoutes` 안 `<Routes>` 바로 위에 가드를 둔다:

```jsx
import { BrowserRouter, Routes, Route, Navigate, useLocation } from 'react-router-dom'
// ...
function ProfileGate({ children }) {
  const { needsProfile } = useAuth()
  const location = useLocation()
  // 인증O·프로필X(미완료 가입)면 프로필 완성(Login이 렌더)으로 보냄. /login 에선 Login이 직접 처리.
  if (needsProfile && location.pathname !== '/login') {
    return <Navigate to="/login" replace />
  }
  return children
}
```

그리고 `<BrowserRouter>` 안에서 `<Routes>`를 `<ProfileGate>`로 감싼다:

```jsx
    <BrowserRouter>
      <ProfileGate>
        <Routes>
          {/* ...기존 라우트 그대로... */}
        </Routes>
      </ProfileGate>
    </BrowserRouter>
```

- [ ] **Step 2: lint**

Run: `cd web && npx eslint src/App.jsx`
Expected: 통과.

- [ ] **Step 3: 커밋**

```bash
git add web/src/App.jsx
git commit -m "feat(auth): redirect incomplete-signup sessions to /login (resume gate)"
```

---

## Task 5: Signup — OTP step 0 + 세션-인지 + createProfile

**Files:**
- Modify: `web/src/pages/Signup.jsx`

**Interfaces:**
- Consumes: Task 2(`signUpAuth`·`verifyEmailOtp`·`resendOtp`·`createProfile`), `useAuth()`의 `session`.
- Props: `{ email, password }` (fresh 가입용). resume 진입 시 props 없이도 동작(이메일은 `session.user.email`).

- [ ] **Step 1: import·상태 교체**

상단 import에서 `signUpUser` → 새 함수들로, `useAuth` 추가:

```jsx
import { fetchUniversities, signUpAuth, verifyEmailOtp, resendOtp, createProfile } from '../data/authQueries'
import { useAuth } from '../components/AuthContext'
import { nicknameError } from '../lib/authValidation'
```

컴포넌트 시그니처·초기 상태(세션-인지 시작단계):

```jsx
function Signup({ email: emailProp, password }) {
  const { session } = useAuth()
  const verified = !!session                       // 이미 인증됨(resume 또는 OTP 통과 후)
  const email = emailProp || session?.user?.email || ''
  const [otp, setOtp] = useState('')
  const [otpErr, setOtpErr] = useState(null)
  const [otpSending, setOtpSending] = useState(false)
  // step: 0=OTP(미인증일 때만), 1=닉/학교, 2=학적, 3=단과/학과/계열
  const [profileSubStep, setProfileSubStep] = useState(verified ? 1 : 0)
  // ...기존 상태들(nickname, region, school, universities, *Err, admissionYear, ...) 그대로...
```

> `sent`(인터스티셜) 상태와 그 JSX 블록은 **삭제**한다(인증이 앞으로 와서 불필요).

- [ ] **Step 2: 마운트 시 OTP 코드 발송(미인증일 때만)**

기존 `useEffect`(학교 목록 로드) 아래에 추가:

```jsx
  // 미인증 fresh 가입이면 마운트 시 계정 생성 + 코드 메일 발송 (1회).
  useEffect(() => {
    if (verified) return
    let alive = true
    ;(async () => {
      try {
        await signUpAuth(email, password)
      } catch (e) {
        if (!alive) return
        const m = e?.message || ''
        if (m.includes('already registered')) setOtpErr('이미 가입된 이메일이에요. 로그인 화면에서 로그인해 주세요.')
        else setOtpErr('인증 메일 발송에 실패했어요. 잠시 후 다시 시도해주세요.')
      }
    })()
    return () => { alive = false }
  }, [])  // eslint-disable-line react-hooks/exhaustive-deps
```

- [ ] **Step 3: OTP 검증·재전송 핸들러 추가**

```jsx
  async function handleVerifyOtp() {
    if (!otp.trim()) { setOtpErr('코드를 입력해주세요.'); return }
    setOtpSending(true)
    try {
      await verifyEmailOtp(email, otp.trim())
      setOtpErr(null)
      setProfileSubStep(1)   // 인증 완료 → 프로필 단계 (세션은 onAuthStateChange가 반영)
    } catch (e) {
      setOtpErr('코드가 올바르지 않거나 만료됐어요.')
    } finally {
      setOtpSending(false)
    }
  }

  async function handleResendOtp() {
    setOtpSending(true)
    try { await resendOtp(email); setOtpErr('코드를 다시 보냈어요.') }
    catch { setOtpErr('재전송이 너무 잦아요. 잠시 후 다시 시도해주세요.') }
    finally { setOtpSending(false) }
  }
```

- [ ] **Step 4: 마지막 제출을 `createProfile`로 교체**

기존 `handleProfileSubmit`의 3단계 제출부(현재 `signUpUser` 호출)를 교체:

```jsx
    // 3단계 검증 통과 후:
    setLoading(true)
    try {
      await createProfile({
        nickname: nickname.trim() || email.split('@')[0],
        university_id: Number(school),
        college_name: college, department_name: department, track,
        admission_year: Number(admissionYear), degree_program: degreeProgram,
        academic_status: academicStatus, grade: Number(grade), region,
      })
      navigate('/home')   // 세션 이미 있음 → AuthContext가 프로필 하이드레이션
    } catch (err) {
      const m = err?.message || ''
      if (m.includes('NICKNAME_TAKEN')) { setNicknameErr('이미 사용 중인 닉네임입니다.'); setProfileSubStep(1) }
      else if (m.includes('NO_COLLEGE') || m.includes('NO_DEPARTMENT')) { alert('학과 정보를 다시 확인해 주세요.') }
      else alert('회원가입 중 오류가 발생했어요. 잠시 후 다시 시도해주세요.')
    } finally {
      setLoading(false)
    }
```

- [ ] **Step 5: step 0(OTP) UI 추가**

`return`의 `<div className="sp-left">` 안, `{profileSubStep === 1 && ...}` **앞에** 추가:

```jsx
          {profileSubStep === 0 && (
            <div className="sp-group">
              <div className={`sp-field-label${otpErr ? ' is-error' : ''}`}>{otpErr ?? '인증 코드'}</div>
              <div className={`email-field${otpErr ? ' has-error' : ''}`}>
                <div className="email-control">
                  <input
                    type="text" inputMode="numeric" id="signup-otp"
                    className="email-input" placeholder=" " value={otp}
                    onChange={(e) => { setOtp(e.target.value); if (otpErr) setOtpErr(null) }}
                    onKeyDown={(e) => { if (e.key === 'Enter') handleVerifyOtp() }}
                    autoFocus
                  />
                  <label htmlFor="signup-otp" className="email-label">{otpErr ?? `${email} 로 보낸 6자리 코드`}</label>
                </div>
              </div>
              <button type="button" className="btn-text-link" onClick={handleResendOtp} disabled={otpSending} style={{ marginTop: '8px', textDecoration: 'underline' }}>
                코드 재전송
              </button>
            </div>
          )}
```

그리고 우측 제출 버튼(ArrowButton) 라벨/동작을 step 0에선 "인증"으로:

```jsx
          <ArrowButton
            label={profileSubStep === 0 ? '인증' : (profileSubStep < 3 ? '다음' : '완료')}
            onClick={profileSubStep === 0 ? handleVerifyOtp : handleProfileSubmit}
            disabled={loading || otpSending}
          />
```

- [ ] **Step 6: 진척도 바 4단계화 + 뒤로가기 1단계 처리**

진척도 바 `width` 계산을 4단계 기준으로:

```jsx
        style={{ width: progressFilled ? `${((profileSubStep + 1) / 4) * 100}%` : '0%' }}
```

`handleBack`에서 step 1에서 뒤로 → step 0(OTP)로(미인증일 때만), 아니면 `onBack`:

```jsx
  function handleBack() {
    setNicknameErr(null); setSchoolErr(null)
    if (profileSubStep > (verified ? 1 : 0)) setProfileSubStep(profileSubStep - 1)
    else onBack?.()
  }
```

- [ ] **Step 7: 빌드·lint 확인**

Run: `cd web && npx eslint src/pages/Signup.jsx && npm run build`
Expected: lint 통과 + 빌드 성공(이제 `signUpUser` 참조 없음).

- [ ] **Step 8: 커밋**

```bash
git add web/src/pages/Signup.jsx
git commit -m "feat(signup): OTP step0 (verify) + create_profile at end, drop interstitial"
```

---

## Task 6: Login — needsProfile일 때 Signup 렌더

**Files:**
- Modify: `web/src/pages/Login.jsx`

**Interfaces:**
- Consumes: Task 3의 `needsProfile`.
- Behavior: `profileStep || needsProfile`면 `<Signup/>` 렌더(resume는 props 없이 → Signup이 세션에서 이메일·프로필단계 결정). 이메일/비번 UI는 `!profileStep && !needsProfile`일 때만.

- [ ] **Step 1: useAuth에서 needsProfile 가져오기**

`Login` 본문 상단:

```jsx
import { useAuth } from '../components/AuthContext'
// ...
function Login() {
  const { needsProfile } = useAuth()
  // ...기존 상태 그대로...
```

- [ ] **Step 2: 렌더 분기 교체**

기존 `{!profileStep && ( ...이메일/비번 카드... )}` 의 조건을 `{!profileStep && !needsProfile && (` 로 바꾸고, 맨 아래 Signup 마운트 줄을 교체:

```jsx
          {(profileStep || needsProfile) && (
            <Signup email={email} password={password} onBack={() => setProfileStep(false)} />
          )}
```

> resume(`needsProfile`)일 때 `email`/`password` props는 빈 값이지만 Signup이 세션 기반(프로필 단계부터)으로 동작하므로 사용 안 함. `onBack`은 resume에선 의미 없으나 무해.

- [ ] **Step 3: 빌드·lint 확인**

Run: `cd web && npx eslint src/pages/Login.jsx && npm run build`
Expected: 통과.

- [ ] **Step 4: 커밋**

```bash
git add web/src/pages/Login.jsx
git commit -m "feat(login): render Signup when needsProfile (resume) too"
```

---

## Task 7: 수동 통합 검증 (Task 0~6 + db push 완료 후)

**Files:** (없음 — 실행/관찰)

> 자동 테스트가 없는 레이어라 시나리오를 직접 돌린다. `cd web && npm run dev` 후 `http://localhost:5173`.

- [ ] **S1 정상 가입:** 새 `*.ac.kr` 이메일 → 비번+재입력 → "인증" → 메일(Gmail/inbucket)에서 6자리 코드 → 입력 → 프로필 3단계 → 완료 → `/home` 진입 + 닉네임 표시.
- [ ] **S2 이어쓰기:** S1에서 코드 인증 직후(프로필 입력 중) **새로고침** → `/login`으로 보내지고 프로필 단계부터 다시(이메일/비번/코드 재입력 없음) → 완료 → `/home`.
- [ ] **S3 OTP 실패:** 틀린 코드 → "코드가 올바르지 않거나 만료됐어요" 인라인. "코드 재전송" → 새 코드 수신.
- [ ] **S4 닉네임 중복:** 이미 쓰는 닉네임으로 마지막 완료 → 닉네임 단계로 복귀 + 인라인 에러.
- [ ] **S5 비.ac.kr 거부:** `@gmail.com` → 이메일 단계에서 인라인 차단(클라). (서버: signUpAuth 시 `DOMAIN_NOT_ALLOWED`.)
- [ ] **S6 기존 로그인:** 가입된 이메일 → 로그인 분기 → 비번 → `signIn` → `/home`.
- [ ] **결과 기록:** 실패 시나리오는 콘솔/네트워크 로그와 함께 보고.

---

## Self-Review

**1. Spec coverage:**
- D1 순서(이메일→비번→OTP→프로필→저장): Login(이메일·비번) → Task5 Signup(step0 OTP → 프로필 → createProfile). ✅
- D2 native OTP: Task2 `verifyEmailOtp(type:'signup')` + Task0 템플릿. ✅
- D3 이어쓰기: Task3 `needsProfile` + Task4 가드 + Task6 Login 렌더 + Task5 세션-인지 시작. ✅
- D4 OTP=Signup step0: Task5. ✅
- D5 Google SMTP: Task0. ✅
- D6 프로필 저장 맨 마지막 RPC: Task1 `create_profile` + Task5 호출, 트리거 insert 제거. ✅
- 에러 처리(§7): OTP 실패/재전송/닉중복/도메인 → Task5·Task7. ✅
- 보안(§8): RLS 불변, create_profile은 definer+auth.uid(). ✅

**2. Placeholder scan:** 헤더 `담당: <이름>`은 실행자가 채움(마이그레이션 규칙). 그 외 코드/명령 실제 내용. 자동테스트 부재는 Global Constraints에 명시(가짜 테스트 안 만듦). ✅

**3. Type consistency:** `create_profile` 인자(10개, 이름·타입)와 Task2 `createProfile` 호출의 `p_*` 매핑 일치. `needsProfile` 정의(Task3)와 사용(Task4·6) 일치. `verifyEmailOtp(email, token)`·`signUpAuth(email,password)` 시그니처가 Task5 호출과 일치. ✅

**주의(구현 중 확인):** `verifyOtp`/`resend`의 `type:'signup'`이 현재 Supabase 버전에서 동작하는지 S1에서 확인(안 되면 `'email'`로). 메일 템플릿 변수 `{{ .Token }}` 표기 확인.