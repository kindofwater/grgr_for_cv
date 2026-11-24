# 회원탈퇴(Account Withdrawal) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 로그인한 사용자가 마이페이지 프로필 탭에서 "탈퇴합니다" 문구 타이핑으로 계정을 즉시·최종 삭제하고, 30일 재가입 쿨다운을 적용한다.

**Architecture:** 방식 B — `security definer` RPC(`delete_account`, 소유자 postgres)가 `auth.users` 행을 직접 삭제한다. FK cascade로 `public.users`(→ 포인트 CASCADE 소멸·열람권 컬럼 소멸·리뷰 `SET NULL` 익명)가 정리된다. 삭제 전 이메일 sha256 해시를 `withdrawn_emails`에 저장하고, `handle_new_user` 트리거가 가입 시 30일 쿨다운을 검사해 차단한다. 프론트는 data-layer 함수(`deleteAccount`) 하나로 추상화해 나중에 A(Edge Function)로 교체가 쉽도록 한다.

**Tech Stack:** Supabase(Postgres, RLS, pgcrypto) · Supabase CLI 마이그레이션 · React(Vite) · supabase-js

**정본 spec:** `docs/superpowers/specs/2026-07-10-account-withdrawal-design.md`

## Global Constraints

- **DB 변경 워크플로우(CLAUDE.md #3, 필수):** 변경 전 **디스코드 팀 공유** → `cd web && npx supabase migration new <주제>` → SQL 작성(파일 맨 위 헤더 2줄 필수: `-- 목적:` / `-- 날짜: YYYY-MM-DD · 담당:`) → 검증 → **`supabase db push`는 변경한 사람이 직접**. SQL 에디터 수동 편집 금지.
- **로컬 검증 제약:** 이 프로젝트는 **Docker 없이 수동 baseline** 운영 → 로컬 `db reset` 불가. 검증은 **db push 후 Supabase SQL 에디터 + throwaway 학교이메일 계정 E2E**로 한다.
- **SECURITY DEFINER 하드닝(기존 패턴 준수):** `set search_path = ''`(또는 명시) + 테이블 **완전수식**(`auth.users`, `public.…`, `extensions.…`) + `revoke execute … from anon, public` + 필요한 롤에만 `grant`.
- **삭제 방식 = B(RPC).** 프론트는 `data/authQueries.js`의 `deleteAccount()` **한 함수로만** 호출(호출부는 RPC/Edge를 모름). 나중에 A로 교체 시 이 함수 본문만 변경.
- **재가입 쿨다운 30일**, 이메일은 **sha256 해시만** 보관(평문 금지).
- **탈퇴 확인 = "탈퇴합니다" 문구 정확 타이핑** 시에만 실행.
- **포인트·열람권 = 전액 소멸**(기존 `points` FK `CASCADE` + 열람권 컬럼 삭제로 자동 충족 — 스키마 변경 불필요).
- **리뷰 = 익명 보존**(기존 `reviews.user_id … on delete set null` — 스키마 변경 불필요).
- **범위 밖(별도/후순위):** 세션 보안(프로필탭 비번 재인증·유휴 자동 로그아웃)은 이 계획에 포함하지 않음(spec B절, 별도 계획).

---

## 사전 확인 (검증 완료 사실 — 구현 근거)

- `postgres`가 `auth.users` **DELETE 권한 보유** = 라이브 `has_table_privilege('postgres','auth.users','DELETE')` → `true`.
- FK 체인(cutover 마이그레이션 `20260624025109`):
  - `users.id → auth.users(id)` **ON DELETE CASCADE** (line 29)
  - `reviews.user_id → users(id)` **ON DELETE SET NULL** (line 44)
  - `points.user_id → users(id)` **ON DELETE CASCADE** (line 48) · `review_helpful` CASCADE · `ad_views` SET NULL · `reports.reporter_id/reported_user_id` SET NULL
  - user 참조 FK는 이 6개가 전부(cutover가 users.id를 int→uuid로 바꾸며 전부 재구축) — **RESTRICT 없음 → 삭제 안 막힘**.
- 열람권 = `users.pass_balances`(jsonb)·`users.pass_expires_at`(컬럼) → users 행 삭제 시 소멸(baseline line 66–67).
- `pgcrypto`(`extensions.digest`) 설치됨(baseline).
- 가입 검사 지점 = `public.handle_new_user()` 트리거(`after insert on auth.users`) — 이미 `raise exception 'DOMAIN_NOT_ALLOWED'`로 가입을 막는 패턴 사용 중(여기에 쿨다운 검사 추가).

## Prerequisites (코드 아님 · 착수 전 게이트)

- [ ] **P1. 디스코드 팀 공유** — "회원탈퇴 백엔드(마이그레이션: `withdrawn_emails` 테이블 + `delete_account` RPC + `handle_new_user` 쿨다운) 배경록이 착수. auth 스키마 건드림." (CLAUDE.md #3-1)
- [ ] **P2. 브랜치 결정** — 사용자에게 물어보기: `main`에 직접 vs 기능 브랜치(예: `feat/account-withdrawal`). (CLAUDE.md 커밋 규칙)
- [ ] **P3. points 처리 확정** — 기본값 **기존 `CASCADE` 유지**(탈퇴 시 포인트 기록 삭제 = "소멸", 스키마 변경 없음). 감사/어뷰징용 익명 원장을 원하면 `points.user_id`를 `SET NULL`로 바꾸는 별도 결정 — 본 계획은 **CASCADE 유지**로 진행.

---

## Task 1: 백엔드 마이그레이션 — 쿨다운 테이블 + `delete_account` RPC + `handle_new_user` 쿨다운 검사

**Files:**
- Create: `web/supabase/migrations/<timestamp>_account_withdrawal.sql` (파일명은 `npx supabase migration new`가 생성)

**Interfaces:**
- Produces: RPC `public.delete_account() returns void` (authenticated 전용) · 테이블 `public.withdrawn_emails(email_hash text pk, withdrawn_at timestamptz)` · `handle_new_user`가 `WITHDRAWN_COOLDOWN` raise.
- Consumes: 기존 FK(cutover) · `extensions.digest` · `auth.uid()` · `auth.users`.

- [ ] **Step 1: 마이그레이션 파일 생성**

Run:
```bash
cd web && npx supabase migration new account_withdrawal
```
Expected: `web/supabase/migrations/<timestamp>_account_withdrawal.sql` 생성(빈 파일).

- [ ] **Step 2: 마이그레이션 SQL 작성**

생성된 파일에 아래를 그대로 작성:

```sql
-- 목적: 회원탈퇴 — 재가입 쿨다운(30일) 테이블 + delete_account RPC(방식 B: auth.users 직접 삭제) + handle_new_user 쿨다운 검사
-- 날짜: 2026-07-10 · 담당: 배경록

-- ── 1. 탈퇴 이메일 해시 테이블 (재가입 쿨다운 판정 전용 · 개인정보 최소화: 평문 대신 sha256) ──
create table if not exists public.withdrawn_emails (
  email_hash   text primary key,
  withdrawn_at timestamptz not null default now()
);
-- 직접 접근 차단: RLS on + 정책 0개 → authenticated/anon 은 못 읽/씀.
-- security definer 함수(소유자 postgres)는 RLS 우회하므로 정상 동작.
alter table public.withdrawn_emails enable row level security;

-- ── 2. delete_account: 본인(auth.uid()) 계정 삭제 ──
-- 순서: 만료해시 청소 → 이메일 해시 저장 → auth.users 삭제(cascade: public.users → points CASCADE 소멸·열람권 컬럼 소멸·reviews SET NULL 익명)
create or replace function public.delete_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := auth.uid();
  v_email text;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;

  select email into v_email from auth.users where id = v_uid;
  if v_email is null then raise exception 'USER_NOT_FOUND'; end if;

  -- 30일 지난 해시 파기(기회적 청소)
  delete from public.withdrawn_emails where withdrawn_at <= now() - interval '30 days';

  -- 재가입 차단용 해시 저장(평문 아님)
  insert into public.withdrawn_emails (email_hash, withdrawn_at)
  values (encode(extensions.digest(lower(trim(v_email)), 'sha256'), 'hex'), now())
  on conflict (email_hash) do update set withdrawn_at = excluded.withdrawn_at;

  -- 계정 삭제 → FK cascade 로 나머지 정리
  delete from auth.users where id = v_uid;
end $$;

revoke execute on function public.delete_account() from anon, public;
grant execute on function public.delete_account() to authenticated;

-- ── 3. handle_new_user: 기존 도메인 검사 + 재가입 쿨다운(30일) 차단 추가 ──
-- (auth.users after-insert 트리거는 이미 존재 — create or replace 로 함수 본문만 교체, 트리거는 그대로 유지)
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if lower(split_part(new.email, '@', 2)) not like '%.ac.kr' then
    raise exception 'DOMAIN_NOT_ALLOWED';
  end if;
  -- 재가입 쿨다운: 30일 내 탈퇴 이메일이면 raise → auth.users insert 롤백(가입 차단)
  if exists (
    select 1 from public.withdrawn_emails w
    where w.email_hash = encode(extensions.digest(lower(trim(new.email)), 'sha256'), 'hex')
      and w.withdrawn_at > now() - interval '30 days'
  ) then
    raise exception 'WITHDRAWN_COOLDOWN';
  end if;
  return new;
end $$;
revoke execute on function public.handle_new_user() from anon, public;
```

- [ ] **Step 3: SQL 정적 리뷰(눈으로)**

체크리스트: ① `search_path` 하드닝(`delete_account`는 `''`+완전수식, `handle_new_user`는 `public`+`extensions.digest` 완전수식) ② `grant`는 `delete_account`만 `authenticated`, 나머지 회수 ③ `withdrawn_emails` RLS on·정책 0 ④ 해시는 `sha256`·평문 저장 없음 ⑤ `on conflict` 위해 `email_hash` PK 존재.

- [ ] **Step 4: db push (⚠️ 게이트: P1 디스코드 공유 완료 후, 변경자=배경록이 직접)**

Run:
```bash
cd web && npx supabase db push
```
Expected: `Applying migration <timestamp>_account_withdrawal.sql...` 성공, 에러 없음.

- [ ] **Step 5: 스키마 검증 (Supabase SQL 에디터, postgres 롤)**

```sql
-- 함수·테이블·권한 존재 확인
select proname, proacl from pg_proc where proname = 'delete_account';            -- authenticated 에 execute
select relname, relrowsecurity from pg_class where relname = 'withdrawn_emails'; -- relrowsecurity = true
select count(*) from pg_policies where tablename = 'withdrawn_emails';           -- 0
```
Expected: `delete_account` 존재(authenticated grant), `withdrawn_emails` RLS on·정책 0.

- [ ] **Step 6: cascade/SET NULL 동작 검증 (throwaway 계정)**

앱에서 throwaway 학교이메일(예: `zz-test@korea.ac.kr`)로 가입 → 리뷰 1개 작성 → 그 유저의 `auth.uid()`(=users.id) 확인. SQL 에디터에서:
```sql
-- (테스트 유저 uuid를 :u 로 가정) 직접 삭제로 cascade 확인
delete from auth.users where id = '<test-uuid>';
select count(*) from public.users   where id = '<test-uuid>';                 -- 0 (users cascade)
select user_id  from public.reviews where worksite_id = <해당> ;               -- 방금 리뷰 user_id = NULL (SET NULL 익명)
select count(*) from public.points  where user_id = '<test-uuid>';            -- 0 (points cascade)
```
Expected: users 0행 · 리뷰 `user_id` NULL · points 0행.

- [ ] **Step 7: 쿨다운 차단 검증**

SQL 에디터에서 방금 이메일 해시 삽입(수동 시뮬레이션):
```sql
insert into public.withdrawn_emails (email_hash, withdrawn_at)
values (encode(extensions.digest(lower('zz-test@korea.ac.kr'), 'sha256'), 'hex'), now())
on conflict (email_hash) do update set withdrawn_at = now();
```
그 다음 앱에서 **같은 이메일로 재가입 시도** → `WITHDRAWN_COOLDOWN` 에러로 **차단**되는지 확인. (검증 후 `delete from public.withdrawn_emails where …` 로 테스트 해시 정리)
Expected: 재가입 실패(WITHDRAWN_COOLDOWN).

- [ ] **Step 8: 커밋**

```bash
git add web/supabase/migrations/<timestamp>_account_withdrawal.sql
git commit -m "feat(withdrawal): delete_account RPC + 재가입 쿨다운 30일 마이그레이션(방식 B)"
```

---

## Task 2: 프론트 data-layer — `deleteAccount()` (A 교체용 추상화 지점)

**Files:**
- Modify: `web/src/data/authQueries.js` (파일 끝에 추가)

**Interfaces:**
- Consumes: Task 1의 RPC `delete_account`.
- Produces: `deleteAccount(): Promise<void>` — 성공 시 로컬 세션까지 정리.

- [ ] **Step 1: `deleteAccount` 함수 추가**

`web/src/data/authQueries.js` 맨 끝에:
```js
// 회원 탈퇴 — delete_account RPC(방식 B: security-definer가 auth.users 삭제 → cascade/SET NULL) 호출 후 로컬 세션 정리.
// ⚠️ 나중에 A(Edge Function)로 교체 시 이 함수 "본문만" supabase.functions.invoke('delete-account')로 바꾸면 됨(호출부 불변).
export async function deleteAccount() {
  const { error } = await supabase.rpc('delete_account')
  if (error) throw error
  await supabase.auth.signOut()   // 삭제 후 로컬 세션 즉시 제거(잔존 access token 무력화)
}
```

- [ ] **Step 2: 빌드 확인**

Run:
```bash
cd web && npm run build
```
Expected: `built in …` 성공(문법 에러 없음).

- [ ] **Step 3: 커밋**

```bash
git add web/src/data/authQueries.js
git commit -m "feat(withdrawal): deleteAccount data-layer (RPC 호출+signOut, A 교체 추상화)"
```

---

## Task 3: `WithdrawModal` 컴포넌트 (문구 타이핑 확인)

**Files:**
- Create: `web/src/components/WithdrawModal.jsx`
- Modify: `web/src/components/Modal.css` (withdraw 전용 클래스 추가)
- Modify: `web/src/components/README.md` (현재 파일 표에 한 줄 추가)

**Interfaces:**
- Consumes: `./Modal.css`(`.modal-overlay`/`.modal`/`.modal-actions`).
- Produces: `<WithdrawModal onConfirm={() => Promise} onCancel={() => void} />` — "탈퇴합니다" 정확 입력 시에만 `onConfirm` 활성.

- [ ] **Step 1: 컴포넌트 작성**

`web/src/components/WithdrawModal.jsx`:
```jsx
import { useState } from 'react'
import './Modal.css'

const CONFIRM_PHRASE = '탈퇴합니다'

// 회원 탈퇴 확인 모달 — 되돌릴 수 없어(유예 없음) 문구 타이핑으로 이중 확인.
// 사라지는 것 안내 + "탈퇴합니다" 정확 입력 시에만 버튼 활성. onConfirm: 부모가 deleteAccount 실행.
export default function WithdrawModal({ onConfirm, onCancel }) {
  const [phrase, setPhrase] = useState('')
  const [loading, setLoading] = useState(false)
  const [err, setErr] = useState('')

  const canConfirm = phrase.trim() === CONFIRM_PHRASE && !loading

  async function handleConfirm() {
    if (!canConfirm) return
    setLoading(true); setErr('')
    try {
      await onConfirm()   // 성공 시 부모가 리다이렉트 → 이 모달은 언마운트됨
    } catch (e) {
      setErr('탈퇴 처리 중 오류가 났어요. 잠시 후 다시 시도해 주세요.')
      setLoading(false)
    }
  }

  return (
    <div className="modal-overlay" onClick={loading ? undefined : onCancel}>
      <div className="modal modal-withdraw" onClick={(e) => e.stopPropagation()}>
        <p className="mw-title">정말 탈퇴하시겠어요?</p>
        <ul className="mw-list">
          <li>작성한 리뷰는 <b>"탈퇴한 사용자"</b>로 익명 처리돼요(내용은 남아요).</li>
          <li>보유 <b>포인트·열람권은 모두 소멸</b>돼요.</li>
          <li>같은 이메일로는 <b>30일간 재가입할 수 없어요</b>.</li>
          <li><b>되돌릴 수 없어요.</b></li>
        </ul>
        <label className="mw-label">확인을 위해 <b>{CONFIRM_PHRASE}</b> 를 입력해 주세요</label>
        <input
          className="mw-input"
          value={phrase}
          onChange={(e) => setPhrase(e.target.value)}
          placeholder={CONFIRM_PHRASE}
          disabled={loading}
          autoFocus
        />
        {err && <p className="mw-err">{err}</p>}
        <div className="modal-actions">
          <button className="btn-login" onClick={onCancel} disabled={loading}>취소</button>
          <button className="mw-danger" onClick={handleConfirm} disabled={!canConfirm}>
            {loading ? '탈퇴 중…' : '탈퇴하기'}
          </button>
        </div>
      </div>
    </div>
  )
}
```

- [ ] **Step 2: Modal.css 에 withdraw 전용 스타일 추가**

`web/src/components/Modal.css` 끝에:
```css
/* 회원 탈퇴 모달 — 공용 .modal 위에 안내 리스트 + 문구 입력 + 위험 버튼 */
.modal-withdraw { text-align: left; }
.modal-withdraw .mw-title { font-size: 16px; font-weight: 700; color: var(--text-h); margin-bottom: 10px; }
.modal-withdraw .mw-list { margin: 0 0 14px; padding-left: 18px; font-size: 13px; color: var(--text-sub); line-height: 1.6; }
.modal-withdraw .mw-list b { color: var(--text); }
.modal-withdraw .mw-label { display: block; font-size: 13px; color: var(--text-sub); margin-bottom: 6px; }
.modal-withdraw .mw-input { width: 100%; box-sizing: border-box; padding: 8px 10px; border: 1px solid var(--border); border-radius: 8px; font-size: 14px; font-family: inherit; margin-bottom: 4px; }
.modal-withdraw .mw-input:focus { outline: none; border-color: var(--danger); }
.modal-withdraw .mw-err { font-size: 12px; color: var(--danger); margin: 6px 0 0; }
.modal-withdraw .mw-danger { background: var(--danger); border: 1px solid var(--danger); color: white; padding: 6px 14px; border-radius: 6px; font-size: 13px; font-weight: 600; cursor: pointer; font-family: inherit; }
.modal-withdraw .mw-danger:disabled { opacity: .45; cursor: default; }
.modal-withdraw .mw-danger:not(:disabled):hover { filter: brightness(1.05); }
```

- [ ] **Step 3: components README 갱신**

`web/src/components/README.md` "현재 파일" 표에 한 줄 추가:
```markdown
| `WithdrawModal.jsx` | 회원 탈퇴 확인 모달. "탈퇴합니다" 문구 정확 입력 시에만 실행 활성 + 사라지는 것 안내(리뷰 익명·포인트/열람권 소멸·30일 재가입 제한). 스타일은 `Modal.css`(`.modal-withdraw`). props: `onConfirm(()=>Promise)`·`onCancel`. MyPage 프로필 탭에서 사용 |
```

- [ ] **Step 4: 빌드 확인**

Run:
```bash
cd web && npm run build
```
Expected: `built in …` 성공.

- [ ] **Step 5: 커밋**

```bash
git add web/src/components/WithdrawModal.jsx web/src/components/Modal.css web/src/components/README.md
git commit -m "feat(withdrawal): WithdrawModal(문구 타이핑 확인) 컴포넌트"
```

---

## Task 4: MyPage 프로필 탭 배선 — placeholder alert → 실제 탈퇴 플로우

**Files:**
- Modify: `web/src/pages/MyPage.jsx` (`ProfileTab` — import·state·버튼 onClick·모달 렌더)

**Interfaces:**
- Consumes: Task 2 `deleteAccount`, Task 3 `WithdrawModal`, `react-router-dom` `useNavigate`.

- [ ] **Step 1: import 추가**

`MyPage.jsx` 상단 import 구역에(기존 import 옆):
```jsx
import { useNavigate } from 'react-router-dom'
import WithdrawModal from '../components/WithdrawModal'
import { deleteAccount } from '../data/authQueries'
```
> `useNavigate`가 이미 import돼 있으면 중복 추가하지 말 것. `updateProfile`을 이미 `../data/authQueries`에서 가져오고 있으면 그 import에 `deleteAccount`를 합칠 것.

- [ ] **Step 2: `ProfileTab`에 상태·핸들러 추가**

`function ProfileTab({ user, onSaved }) {` 본문 상단(기존 useState들 근처)에:
```jsx
  const navigate = useNavigate()
  const [withdrawOpen, setWithdrawOpen] = useState(false)

  async function handleWithdraw() {
    await deleteAccount()                        // 실패 시 throw → 모달이 에러 표시(모달은 안 닫힘)
    navigate('/login', { replace: true })        // 성공: signOut 됨 → 로그인으로
  }
```

- [ ] **Step 3: 탈퇴 버튼 onClick 교체 + 모달 렌더**

`MyPage.jsx:183` 의 placeholder 버튼을 교체:
```jsx
      <button className="my-withdraw" onClick={() => setWithdrawOpen(true)}>회원 탈퇴</button>
      {withdrawOpen && (
        <WithdrawModal onCancel={() => setWithdrawOpen(false)} onConfirm={handleWithdraw} />
      )}
```
(기존 `onClick={() => alert('회원 탈퇴 기능은 준비 중이에요.')}` 제거)

- [ ] **Step 4: 빌드 확인**

Run:
```bash
cd web && npm run build
```
Expected: `built in …` 성공.

- [ ] **Step 5: E2E 스모크 (localhost, throwaway 계정)**

`npm run dev` → throwaway 학교이메일 가입/로그인 → 마이페이지 프로필 탭 → "회원 탈퇴" → 모달에서 아무거나 입력하면 버튼 비활성, **"탈퇴합니다"** 입력 시 활성 → "탈퇴하기" → 로그인 화면으로 이동. 재로그인 시도 → 실패(계정 없음). 같은 이메일 재가입 → 30일 쿨다운 차단.
Expected: 위 흐름대로 동작.

- [ ] **Step 6: 커밋**

```bash
git add web/src/pages/MyPage.jsx
git commit -m "feat(withdrawal): 마이페이지 프로필 탭 탈퇴 플로우 배선(모달→deleteAccount)"
```

---

## Out of Scope / 후속 (이 계획 밖)

- **쿨다운 에러 친절 메시지:** 재가입 시 `WITHDRAWN_COOLDOWN` 원시 에러가 가입 화면에 뜬다. "최근 탈퇴한 계정이에요. 30일 후 재가입 가능해요" 로 매핑하는 건 **가입 UI(로그인/인증 흐름 = 현수 담당 영역)** 라 별도·조율 후. (관련: 리뷰 작성 친절 에러 메모와 같은 결)
- **해시 30일 자동 파기 보장:** 현재는 `delete_account` 호출 때 기회적 청소만. 활동이 없어도 30일에 파기 보장하려면 **`pg_cron` 일일 잡**(`delete from withdrawn_emails where withdrawn_at <= now() - interval '30 days'`) 추가 — 후속.
- **포인트 익명 원장:** P3에서 CASCADE(삭제) 확정. 정산/어뷰징용 익명 보존이 필요해지면 `points.user_id`를 `SET NULL`로 바꾸는 별도 마이그레이션.
- **탈퇴로 신고 회피 엣지케이스:** 신고당한 유저가 탈퇴하면 `reports.reported_user_id`가 SET NULL로 대상이 사라짐 — MVP 이후 검토(spec E절).
- **세션 보안(spec B절):** 프로필탭 비번 재인증 · 유휴 자동 로그아웃 — 별도 계획.
- **A(Edge Function) 전환:** Edge Function 도입/스키마 이슈 발생 시. `deleteAccount()` 본문만 교체(Task 2 주석 참조).

## 롤백 노트

되돌리기 어려운 prod DB 변경이라 신중히. 문제 시 역마이그레이션:
```sql
drop function if exists public.delete_account();
-- handle_new_user 는 쿨다운 검사 제거 버전으로 create or replace (도메인 검사만 남김)
drop table if exists public.withdrawn_emails;
```
(이미 삭제된 계정은 복구 불가 — E2E는 반드시 throwaway 계정으로.)

---

## Self-Review (작성자 체크)

- **Spec 커버리지:** ①즉시·최종/유예없음=Task1 `delete_account`(대기·복구 없음) ✅ ②재가입 쿨다운 30일+해시=Task1(테이블·handle_new_user) ✅ ③포인트·열람권 소멸=기존 CASCADE+컬럼(P3, Task1 검증) ✅ ④리뷰 익명=기존 SET NULL(Task1 검증) ✅ ⑤문구 타이핑=Task3 `WithdrawModal` ✅ · 개인정보 즉시 파기(auth.users/public.users 삭제)=Task1 ✅ · A 교체 추상화=Task2 ✅.
- **Placeholder 스캔:** 없음(모든 SQL/JSX 전체 코드 · 명령·기대출력 명시). `<timestamp>`/`<test-uuid>`는 CLI·실데이터가 채우는 실제 값(플레이스홀더 아님).
- **타입/이름 일관성:** `delete_account`(RPC)·`deleteAccount`(FE)·`withdrawn_emails`·`WithdrawModal`·`CONFIRM_PHRASE='탈퇴합니다'` — Task 간 일치.
- **세션보안(B)** 은 의도적으로 범위 밖(Out of Scope 명시).
