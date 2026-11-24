# Supabase Auth + RLS 클린 컷오버 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 자체 `password_hash` 인증을 Supabase Auth로 클린 컷오버하고, 신원을 UUID화한 뒤 전 테이블 RLS + `auth.uid()` 기반 RPC로 서버 신뢰 신원을 확보한다.

**Architecture:** `public.users.id`를 `auth.users.id`(uuid)와 1:1로 묶는 표준 profiles 패턴. 가입은 `supabase.auth.signUp` + `handle_new_user` 트리거가 프로필 행 생성(@korea.ac.kr 도메인 검증). 모든 `p_user_id` RPC는 인자를 버리고 `auth.uid()`로 신원을 도출하며, 전 테이블 RLS + users 컬럼 GRANT로 특권 컬럼을 2중 방어한다. DB·클라이언트가 함께 깨지는 big-bang 컷오버이므로 한 브랜치에서 로컬 `db reset`로 검증 후 일괄 반영한다.

**Tech Stack:** Supabase(Postgres + GoTrue Auth + PostgREST), Supabase CLI 마이그레이션, React + Vite, `@supabase/supabase-js`, Vitest(`web/src/lib/*.test.js`).

**근거 스펙:** [docs/superpowers/specs/2026-06-24-supabase-auth-rls-cutover-design.md](../specs/2026-06-24-supabase-auth-rls-cutover-design.md) · 조사: 워크플로 `auth-rls-migration-inventory`.

## Global Constraints

> 모든 태스크의 요구사항에 아래가 암묵적으로 포함된다. 값은 스펙에서 그대로 가져온 것.

- **⛔ 팀 사인오프 전 코드/DB push 금지.** 본 계획은 6/16 "Render 인증서버" 결정을 대체하는 **제안**. 인증·RPC·DB는 **현수(kindofwater) 영역** — 착수·푸시 주체·순서를 디스코드로 먼저 합의(CLAUDE.md §3.1, [[feedback-coordinate-before-editing-others-files]]).
- **클린 컷오버**: 보존 데이터 0. 테스트 유저 전원 재가입.
- **신원**: `public.users.id` = `auth.users.id` (uuid, 1:1, `on delete cascade`). int↔uuid 매핑테이블 없음.
- **이메일 확인 ON**. **가입 도메인 = @korea.ac.kr만(MVP)**, 확장은 `universities.signup_enabled` 플래그(데이터 주도).
- **DROP**: `public.users.email`·`password_hash` 컬럼, `verify_login`/`register_user`/`set_password`, `pgcrypto`.
- **리뷰 열람 = 인증 필수**(게스트 브라우징 X).
- **특권 컬럼**(`point_balance`/`pass_balances`/`pass_expires_at`/`is_admin`)은 직접 UPDATE 금지 — DEFINER RPC로만.
- **마이그레이션 규칙**: 파일 헤더 2줄(`-- 목적:` / `-- 날짜: YYYY-MM-DD · 담당:`), 시그니처 변경 시 `drop function if exists` 먼저, 로컬 `cd web && npx supabase db reset`로 맨바닥 재구축 검증, 디스코드 사전공유 후 `db push`(작성자가). 스키마 변경 시 `docs/db-schema.md`·관련 README 동시 갱신.
- **②리워드 광고 서버는 범위 밖**: 본 계획은 `watch_ad_reward`에 `auth.uid()`만 입힌다. 쿨다운/캡/완료검증·소재는 별도 스펙(②).

---

## File Structure

**신규**
- `web/supabase/migrations/<ts>_auth_rls_cutover.sql` — 컷오버 단일 마이그레이션(Phase 1 전체). 한 파일에 순서대로(드롭→신원→트리거→RPC→RLS).

**수정 (DB 정본)**
- 없음(기존 마이그레이션은 불변; 신규 마이그레이션이 위에 덮음).

**수정 (클라이언트)**
- `web/src/supabase.js` — auth 옵션.
- `web/src/components/AuthContext.jsx` — 세션·프로필·지갑 하이드레이션(핵심 재작성).
- `web/src/data/authQueries.js` · `exchangeQueries.js` · `worksiteQueries.js` · `mypageQueries.js` — RPC 인자 제거·Auth 전환.
- `web/src/pages/Login.jsx` · `Signup.jsx` · `MyPage.jsx` · `ExchangeCenter.jsx` · `AdView.jsx` · `WorksiteDetail.jsx` · `ReviewForm.jsx` · `Home.jsx` · `App.jsx`.
- `web/src/components/AppLayout.jsx` — 지갑 프리패치 정리.

**문서**
- `docs/db-schema.md` · `web/supabase/README.md` · `README.md`(마이그레이션 표) · `docs/frontend.md`.

> 이 컷오버는 DB와 클라가 동시에 깨지므로 **하나의 브랜치에서 끝까지** 진행하고 로컬에서 E2E 검증 후 반영한다. 독립 서브시스템이 아니라 단일 컷오버라 plan 분리는 하지 않되, 실행은 Phase 단위 체크포인트로 끊는다.

---

## Phase 0 — Supabase Auth 설정 (수동, 대시보드)

### Task 0: Auth 프로젝트 설정 문서화 + 로컬 config

**Files:**
- Modify: `web/supabase/config.toml` (로컬 스택 auth 설정)
- Doc: `web/supabase/README.md` (대시보드 수동 절차 기록)

**Interfaces:**
- Produces: 확인메일 ON·Site URL·redirect 화이트리스트가 설정된 Auth. 이후 모든 클라 Auth 호출의 전제.

- [ ] **Step 1: 로컬 `config.toml`에 auth 활성화**

```toml
[auth]
enabled = true
site_url = "http://localhost:5173"
additional_redirect_urls = ["http://localhost:5173"]
[auth.email]
enable_signup = true
enable_confirmations = true   # 이메일 확인 ON
```

- [ ] **Step 2: prod 대시보드 수동 절차를 README에 기록**(실제 클릭은 현수/배경록이 사인오프 후)

기록할 항목: Authentication → Providers → Email (Confirm email **ON**) · URL Configuration(Site URL, Redirect URLs) · SMTP(확인메일 발송원, 미설정 시 Supabase 기본 발송기 한도 주의) · (가능 시) 허용 이메일 도메인 제한. **도메인 강제의 정본은 Task 5 트리거**임을 명시.

- [ ] **Step 3: 검증**

Run: `cd web && npx supabase start` 후 `npx supabase status`
Expected: `API URL`/`GoTrue` 기동, `auth` 스키마 존재. (Docker 필요 — 없으면 이 Task는 prod 사인오프 시점으로 보류하고 Phase 1을 `db reset` 대신 SQL 리뷰로 검증.)

- [ ] **Step 4: Commit**

```bash
git add web/supabase/config.toml web/supabase/README.md
git commit -m "chore(auth): 로컬 Supabase Auth 설정(확인메일 ON) + prod 절차 문서화"
```

---

## Phase 1 — DB 마이그레이션 (단일 파일, 현수 영역)

> 한 마이그레이션 파일에 Task 1→9를 **순서대로** 작성한다. 각 Task = 그 파일의 한 섹션. Task별 "검증"은 그 시점까지 작성분으로 `db reset`이 깨지지 않는지 확인하는 것(파일을 점진 작성).

### Task 1: 마이그레이션 스캐폴드 + 커스텀 인증 DROP

**Files:**
- Create: `web/supabase/migrations/<ts>_auth_rls_cutover.sql`

**Interfaces:**
- Produces: 마이그레이션 파일. 이후 Task가 같은 파일에 append.

- [ ] **Step 1: 파일 생성 + 헤더 + 커스텀 인증 드롭**

```bash
cd web && npx supabase migration new auth_rls_cutover
```
생성된 파일 맨 위:
```sql
-- 목적: 자체 password_hash 인증 → Supabase Auth 클린 컷오버 (UUID 신원·전 테이블 RLS·auth.uid RPC·@korea.ac.kr 가입)
-- 날짜: 2026-06-24 · 담당: 현수(kindofwater)
-- ⚠️ 클린 컷오버: 아래 TRUNCATE로 기존 행 전부 삭제됨. 사인오프 후에만 push.

-- ── 1. 커스텀 인증 제거 (시그니처 변경/삭제는 DROP 먼저) ──
drop function if exists verify_login(text, text);
drop function if exists register_user(text,text,text,int,text,text,text,int,text,text,int,text);
drop function if exists register_user(text,text,text,int,text,text,text,int,text,text,int);
drop function if exists set_password(text, text);
```

- [ ] **Step 2: 검증**

Run: `cd web && npx supabase db reset`
Expected: 에러 없이 재구축(드롭은 `if exists`라 안전).

- [ ] **Step 3: Commit**

```bash
git add web/supabase/migrations/*_auth_rls_cutover.sql
git commit -m "feat(auth): 컷오버 마이그레이션 스캐폴드 + 커스텀 인증 함수 DROP"
```

### Task 2: 데이터 wipe + users.id UUID화 + auth.users FK

**Files:**
- Modify: 같은 마이그레이션 파일(append)

**Interfaces:**
- Produces: `public.users.id uuid PK references auth.users(id) on delete cascade`. 이후 FK Task가 이 타입에 맞춤.

- [ ] **Step 1: TRUNCATE + 신원 재구축 SQL append**

```sql
-- ── 2. 클린 wipe + 신원 UUID화 ──
truncate table reviews, review_helpful, points, ad_views, reports, users restart identity cascade;

-- 6개 FK 제약 먼저 드롭(컬럼 타입 변경 위해)
alter table reviews        drop constraint reviews_user_id_fkey;
alter table review_helpful drop constraint review_helpful_user_id_fkey;
alter table ad_views       drop constraint ad_views_user_id_fkey;
alter table points         drop constraint points_user_id_fkey;
alter table reports        drop constraint reports_reporter_id_fkey;
alter table reports        drop constraint reports_reported_user_id_fkey;

-- users PK int → uuid (빈 테이블)
alter table users drop constraint users_pkey;
alter table users alter column id drop default;
drop sequence if exists users_id_seq;
alter table users alter column id type uuid using gen_random_uuid();
alter table users add primary key (id);
alter table users add constraint users_id_fkey foreign key (id) references auth.users(id) on delete cascade;
```

> ⚠️ 제약명은 Postgres 기본 규칙 추정값. `db reset` 실패 시 `\d+ <table>`로 실제 제약명 확인 후 교정(드리프트 가능성, 스펙 §A 참고).

- [ ] **Step 2: 검증**

Run: `cd web && npx supabase db reset`
Expected: 성공. `psql`로 `\d users` → `id` 타입 `uuid`, `auth.users` 참조 FK 존재.

- [ ] **Step 3: Commit**

```bash
git add web/supabase/migrations/*_auth_rls_cutover.sql
git commit -m "feat(auth): users.id를 auth.users(id) uuid로 재구축"
```

### Task 3: 폐기 컬럼 DROP + 6개 FK uuid화 + 제약 재생성

**Files:**
- Modify: 같은 마이그레이션 파일(append)

**Interfaces:**
- Consumes: Task 2의 `users.id uuid`.
- Produces: 모든 user FK가 uuid. reviews 유니크 `(user_id, work_year, work_semester)` uuid.

- [ ] **Step 1: 컬럼 드롭 + FK 재작성 SQL append**

```sql
-- ── 3. 폐기 컬럼 + FK uuid화 ──
alter table users drop column password_hash;
alter table users drop column email;
drop extension if exists pgcrypto;

-- FK 컬럼 타입 uuid (빈 테이블이라 USING NULL/cast 자명)
alter table reviews        alter column user_id          type uuid using null;
alter table review_helpful drop constraint review_helpful_pkey;
alter table review_helpful alter column user_id          type uuid using null;
alter table ad_views       alter column user_id          type uuid using null;
alter table points         alter column user_id          type uuid using null;
alter table reports        alter column reporter_id       type uuid using null;
alter table reports        alter column reported_user_id  type uuid using null;

-- on_delete 의미 보존하여 FK 재생성
alter table reviews        add constraint reviews_user_id_fkey        foreign key (user_id)         references users(id) on delete set null;
alter table review_helpful add constraint review_helpful_user_id_fkey foreign key (user_id)         references users(id) on delete cascade;
alter table review_helpful add primary key (user_id, review_id);
alter table ad_views       add constraint ad_views_user_id_fkey       foreign key (user_id)         references users(id) on delete set null;
alter table points         add constraint points_user_id_fkey         foreign key (user_id)         references users(id) on delete cascade;
alter table reports        add constraint reports_reporter_id_fkey    foreign key (reporter_id)     references users(id) on delete set null;
alter table reports        add constraint reports_reported_user_id_fkey foreign key (reported_user_id) references users(id) on delete set null;

-- reviews 유니크(드리프트 제약명 introspect-drop 후 재생성 — 20260623 패턴)
do $$
declare c text;
begin
  for c in select conname from pg_constraint where conrelid='public.reviews'::regclass and contype='u'
  loop execute format('alter table reviews drop constraint %I', c); end loop;
end $$;
alter table reviews add constraint reviews_user_year_semester_key unique (user_id, work_year, work_semester);
```

- [ ] **Step 2: 검증**

Run: `cd web && npx supabase db reset`
Expected: 성공. `\d reviews` 등에서 6개 FK uuid + 유니크 확인.

- [ ] **Step 3: Commit**

```bash
git commit -am "feat(auth): password_hash/email DROP + user FK 6개 uuid화 + 제약 재생성"
```

### Task 4: 학교 가입 허용 플래그 (signup_enabled)

**Files:**
- Modify: 같은 마이그레이션 파일(append)

**Interfaces:**
- Produces: `universities.signup_enabled boolean`. Task 5 트리거가 읽음.

- [ ] **Step 1: 컬럼 + 고려대 활성화 SQL append**

```sql
-- ── 4. 가입 허용 학교(데이터 주도 확장) ──
alter table universities add column signup_enabled boolean not null default false;
update universities set signup_enabled = true where email_domain = 'korea.ac.kr';
```

> 학교 추가 시: 해당 행 `email_domain` 채우고 `signup_enabled=true` UPDATE만 하면 코드 변경 없이 확장.

- [ ] **Step 2: 검증**

Run: `db reset` 후 `select name, email_domain, signup_enabled from universities;`
Expected: 고려대 `true`, 나머지 `false`.

- [ ] **Step 3: Commit**

```bash
git commit -am "feat(auth): universities.signup_enabled 추가 + 고려대(korea.ac.kr) 활성화"
```

### Task 5: handle_new_user 트리거 (프로필 생성 + 도메인 검증)

**Files:**
- Modify: 같은 마이그레이션 파일(append)

**Interfaces:**
- Consumes: `auth.users` INSERT, `raw_user_meta_data`, `universities.signup_enabled`.
- Produces: 가입 시 `public.users` 행 자동 생성. 클라 Signup이 보내는 metadata 키와 **정확히 일치**해야 함(Task 14와 계약): `nickname, university_id, college_name, department_name, track, admission_year, degree_program, academic_status, grade, region`.

- [ ] **Step 1: 트리거 함수 + 트리거 append**

```sql
-- ── 5. 가입 트리거 (프로필 생성 + @korea.ac.kr 검증) ──
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  m jsonb := new.raw_user_meta_data;
  v_uni_id int := (m->>'university_id')::int;
  v_domain text;
  v_enabled boolean;
  v_college_id int;
  v_department_id int;
begin
  -- 도메인 검증: 선택 학교의 email_domain과 이메일 도메인 일치 + 가입 허용
  select email_domain, signup_enabled into v_domain, v_enabled
    from universities where id = v_uni_id;
  if v_domain is null then raise exception 'NO_UNIVERSITY'; end if;
  if not coalesce(v_enabled, false) then raise exception 'SCHOOL_NOT_ENABLED'; end if;
  if lower(split_part(new.email, '@', 2)) <> lower(v_domain) then
    raise exception 'DOMAIN_NOT_ALLOWED';
  end if;

  -- 단대/학과 이름 → id (없으면 학교의 첫 항목; register_user 로직 이식)
  select id into v_college_id from colleges
    where university_id = v_uni_id and name = (m->>'college_name') limit 1;
  if v_college_id is null then
    select id into v_college_id from colleges where university_id = v_uni_id order by id limit 1;
  end if;
  if v_college_id is null then raise exception 'NO_COLLEGE'; end if;
  select id into v_department_id from departments
    where college_id = v_college_id and name = (m->>'department_name') limit 1;
  if v_department_id is null then
    select id into v_department_id from departments where college_id = v_college_id order by id limit 1;
  end if;
  if v_department_id is null then raise exception 'NO_DEPARTMENT'; end if;

  -- ⚠️ point_balance/is_admin/pass_* 는 metadata에서 절대 읽지 않음(서버 기본값)
  insert into public.users (id, university_id, college_id, department_id, track,
                            nickname, admission_year, degree_program, academic_status, grade, region)
  values (new.id, v_uni_id, v_college_id, v_department_id, m->>'track',
          m->>'nickname', (m->>'admission_year')::int,
          (m->>'degree_program')::degree_program_e, (m->>'academic_status')::academic_status_e,
          (m->>'grade')::int, m->>'region');
  return new;
exception
  when unique_violation then raise exception 'NICKNAME_TAKEN';
end $$;
revoke execute on function public.handle_new_user() from anon, public;

create trigger on_auth_user_created
  after insert on auth.users for each row execute function public.handle_new_user();
```

> 트리거 예외는 `auth.users` INSERT를 롤백 → `signUp`이 해당 메시지로 실패. 클라(Task 14)가 `NICKNAME_TAKEN`/`DOMAIN_NOT_ALLOWED`/`NO_COLLEGE` 등을 구분해 문구화.

- [ ] **Step 2: 검증**

Run: `db reset` 후 로컬 GoTrue로 가입 시도(아래)
```bash
curl -s "$SUPABASE_URL/auth/v1/signup" -H "apikey: $ANON" -H "Content-Type: application/json" \
 -d '{"email":"tester@korea.ac.kr","password":"test1234","data":{"nickname":"테스터","university_id":1,"college_name":"정경대학","department_name":"경제학과","track":"인문","admission_year":2022,"degree_program":"undergrad","academic_status":"enrolled","grade":2,"region":"서울"}}'
```
Expected: 200 + `select count(*) from public.users` = 1. 비-korea 도메인 가입은 `DOMAIN_NOT_ALLOWED`로 실패.

- [ ] **Step 3: Commit**

```bash
git commit -am "feat(auth): handle_new_user 트리거 — 프로필 생성 + @korea.ac.kr 도메인 검증"
```

### Task 6: p_user_id RPC 10개 → auth.uid() 전환

**Files:**
- Modify: 같은 마이그레이션 파일(append)

**Interfaces:**
- Produces (Task 12·15·16·17과 계약 — 클라가 이 시그니처로 호출):
  - `update_profile(p_region text, p_admission_year int, p_degree_program text, p_academic_status text, p_grade int)`
  - `_wallet()` → jsonb · `purchase_pass(p_days int)` · `refund_pass(p_days int)` · `activate_pass(p_days int)` · `watch_ad_reward()` → 각 jsonb(지갑)
  - `toggle_helpful(p_review_id int)` → int(helpful_count)
  - `write_review_with_points(p_worksite_id int, p_work_year int, p_work_semester text, p_work numeric, p_growth numeric, p_vibe numeric, p_flex numeric, p_recommend numeric, p_work_content text, p_opinion text, p_is_anonymous boolean)` → int
  - `update_review_with_points(p_review_id int, … 동일 점수/내용 인자 …, p_is_anonymous boolean)` · `delete_review_with_rollback(p_review_id int)`

- [ ] **Step 1: 변환 규칙 + 전체 함수 append**

**변환 규칙(모든 함수 공통):** ① 인자에서 `p_user_id` 제거 → ② 본문 첫 줄 `declare v_uid uuid := auth.uid();` + `if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;` → ③ 본문의 `p_user_id`를 전부 `v_uid`로 치환 → ④ 리뷰 3종은 `security definer set search_path = public` 추가(현재 INVOKER) → ⑤ `_wallet(...)` 호출은 `_wallet()`로.

대표 2개(전체 본문):
```sql
-- 지갑 헬퍼
drop function if exists _wallet(int);
create or replace function _wallet()
returns jsonb language sql security definer set search_path = public as $$
  select jsonb_build_object('point_balance', u.point_balance, 'pass_balances',
    coalesce(u.pass_balances,'{}'::jsonb), 'pass_expires_at', u.pass_expires_at)
  from users u where u.id = auth.uid();
$$;

-- 광고 보상(②쿨다운/검증은 범위 밖, 여기선 auth.uid()만)
drop function if exists watch_ad_reward(int);
create or replace function watch_ad_reward()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_ad_id int;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  update users set point_balance = point_balance + 5 where id = v_uid;
  if not found then raise exception 'USER_NOT_FOUND'; end if;
  insert into ad_views (user_id) values (v_uid) returning id into v_ad_id;
  insert into points (user_id, amount, reason, ad_view_id) values (v_uid, 5, 'ad_view', v_ad_id);
  return _wallet();
end $$;
```
나머지 8개(`update_profile`, `purchase_pass`, `refund_pass`, `activate_pass`, `toggle_helpful`, `write_review_with_points`, `update_review_with_points`, `delete_review_with_rollback`)는 각각 `drop function if exists <기존시그니처>;` 후, **위 변환 규칙 ①~⑤를 적용한 본문**으로 `create or replace`. 본문 로직(점수/포인트 계산·INSERT/UPDATE 대상)은 baseline/20260622 버전과 동일하게 유지하되 `p_user_id`만 `v_uid`로.

- [ ] **Step 2: 검증**

Run: `cd web && npx supabase db reset`
Expected: 성공. `\df watch_ad_reward` 인자 0개, `_wallet` 0개 등 시그니처 확인.

- [ ] **Step 3: Commit**

```bash
git commit -am "feat(auth): p_user_id RPC 10개 → auth.uid() 전환(리뷰 3종 DEFINER 승격)"
```

### Task 7: grant 재정리 (anon 회수 → authenticated)

**Files:**
- Modify: 같은 마이그레이션 파일(append)

- [ ] **Step 1: grant 블록 append**

```sql
-- ── 7. 실행 권한: 신원 필요한 RPC는 anon 회수 ──
do $$
declare f text;
begin
  foreach f in array array[
    'update_profile(text,int,text,text,int)','_wallet()','purchase_pass(int)','refund_pass(int)',
    'activate_pass(int)','watch_ad_reward()','toggle_helpful(int)',
    'write_review_with_points(int,int,text,numeric,numeric,numeric,numeric,numeric,text,text,boolean)',
    'update_review_with_points(int,int,text,numeric,numeric,numeric,numeric,numeric,text,text,boolean)',
    'delete_review_with_rollback(int)'
  ]
  loop
    execute format('revoke execute on function %s from anon, public', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
-- 공개 읽기 집계는 anon 유지(정책 결정): get_review_stats, get_worksite_score_cards, pass_price
```
> 함수 시그니처 문자열은 Task 6에서 확정한 인자 타입과 **정확히 일치**해야 함(불일치 시 revoke가 조용히 빗나감).

- [ ] **Step 2: 검증**

Run: `db reset` 후 `select proname, proacl from pg_proc where proname='watch_ad_reward';`
Expected: `anon`에 execute 없음, `authenticated`에 있음.

- [ ] **Step 3: Commit**

```bash
git commit -am "feat(auth): 신원 기반 RPC grant 재정리(anon 회수 → authenticated)"
```

### Task 8: RLS 활성화 + 정책 + users 컬럼 GRANT

**Files:**
- Modify: 같은 마이그레이션 파일(append)

**Interfaces:**
- Produces: 전 테이블 RLS. 직접 `.from()` 경로가 본인 범위로 제약됨(Task 15~17 클라가 의존).

- [ ] **Step 1: RLS + 정책 append**

```sql
-- ── 8. RLS ──
alter table users          enable row level security;
alter table reviews        enable row level security;
alter table points         enable row level security;
alter table ad_views       enable row level security;
alter table reports        enable row level security;
alter table review_helpful enable row level security;
alter table worksites      enable row level security;
alter table postings       enable row level security;
alter table notices        enable row level security;
alter table universities   enable row level security;
alter table colleges       enable row level security;
alter table departments    enable row level security;

-- 본인 범위
create policy users_select_own   on users          for select to authenticated using (id = auth.uid());
create policy users_update_own   on users          for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
create policy points_select_own  on points         for select to authenticated using (user_id = auth.uid());
create policy adviews_select_own on ad_views       for select to authenticated using (user_id = auth.uid());
create policy helpful_select_own on review_helpful for select to authenticated using (user_id = auth.uid());

-- 리뷰: 직접 select 금지(목록은 마스킹 RPC, Task 9). 작성자 본인 행만 직접 조회 허용.
create policy reviews_select_own on reviews for select to authenticated using (user_id = auth.uid());

-- 공개 카탈로그(읽기)
create policy worksites_read   on worksites    for select to anon, authenticated using (true);
create policy postings_read    on postings     for select to anon, authenticated using (true);
create policy notices_read     on notices      for select to anon, authenticated using (true);
create policy uni_read         on universities for select to anon, authenticated using (true);
create policy colleges_read    on colleges     for select to anon, authenticated using (true);
create policy departments_read on departments  for select to anon, authenticated using (true);
-- reports: 클라 정책 없음(service_role/관리자 RPC만). 쓰기는 Task 9 report_review.

-- 특권 컬럼 2중 방어: 컬럼 GRANT(RLS는 행 단위라 컬럼 못 막음)
revoke update on public.users from authenticated;
grant update (region, admission_year, degree_program, academic_status, grade, track, nickname, updated_at)
  on public.users to authenticated;
```

> 리뷰 목록은 `reviews_select_own`만으로는 타인 리뷰가 안 보임 → Task 9의 마스킹 RPC(DEFINER, RLS 우회)가 공개 목록을 책임진다. 이게 D6(인증 필수) + 익명 보호(debt #6)를 동시 충족.

- [ ] **Step 2: 검증(부정 테스트)**

Run: `db reset` 후 authenticated 역할로 `update users set point_balance=999 where id=auth.uid();`
Expected: 컬럼 GRANT에 `point_balance` 없으므로 **거부**(permission denied for column). `update users set region='x'`는 통과.

- [ ] **Step 3: Commit**

```bash
git commit -am "feat(auth): 전 테이블 RLS + 본인범위 정책 + users 특권컬럼 GRANT 차단"
```

### Task 9: 마스킹 리뷰목록 RPC + view/report RPC

**Files:**
- Modify: 같은 마이그레이션 파일(append)

**Interfaces:**
- Produces (Task 16 클라 계약): `list_worksite_reviews(p_worksite_id int)` → 리뷰 목록(익명 시 `user_id`·`nickname`·학기 가림, `user_id` 미노출) · `increment_worksite_view(p_worksite_id int)` · `report_review(p_review_id int, p_reason text)`.

- [ ] **Step 1: 3개 RPC append**

```sql
-- ── 9. 공개 리뷰목록(익명 마스킹) + view/report ──
create or replace function list_worksite_reviews(p_worksite_id int)
returns table (id int, work_year int, work_semester text, score_recommend numeric,
               score_work numeric, score_growth numeric, score_vibe numeric, score_flex numeric,
               work_content text, opinion text, is_anonymous boolean, helpful_count int,
               author_nickname text, created_at timestamptz)
language sql security definer set search_path = public as $$
  select r.id, r.work_year,
         case when r.is_anonymous then null else r.work_semester end,
         r.score_recommend, r.score_work, r.score_growth, r.score_vibe, r.score_flex,
         r.work_content, r.opinion, r.is_anonymous, r.helpful_count,
         case when r.is_anonymous then '익명' else u.nickname end,
         r.created_at
  from reviews r left join users u on u.id = r.user_id
  where r.worksite_id = p_worksite_id and r.deleted_at is null
  order by r.created_at desc;
$$;  -- user_id를 반환하지 않음 → 익명 신원 노출 차단

create or replace function increment_worksite_view(p_worksite_id int)
returns void language plpgsql security definer set search_path = public as $$
begin update worksites set view_count = view_count + 1 where id = p_worksite_id; end $$;

create or replace function report_review(p_review_id int, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_reported uuid;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  select user_id into v_reported from reviews where id = p_review_id;
  insert into reports (reporter_id, reported_user_id, review_id, reason)
  values (v_uid, v_reported, p_review_id, p_reason);
end $$;

grant execute on function list_worksite_reviews(int)  to anon, authenticated; -- 목록은 마스킹돼 안전(정책상 authenticated만 원하면 anon 제거)
grant execute on function increment_worksite_view(int) to anon, authenticated;
revoke execute on function report_review(int, text) from anon, public;
grant  execute on function report_review(int, text) to authenticated;
```

- [ ] **Step 2: 검증**

Run: `db reset` 후 `select * from list_worksite_reviews(1);`
Expected: 결과에 `user_id` 컬럼 없음. 익명 행은 `author_nickname='익명'`, `work_semester` null.

- [ ] **Step 3: Commit + Phase 1 전체 재구축 확인**

```bash
cd web && npx supabase db reset   # 맨바닥에서 Task1~9 전부 재구축
git commit -am "feat(auth): 익명 마스킹 리뷰목록 RPC + view/report RPC화"
```

---

## Phase 2 — 클라이언트 컷오버

### Task 10: supabase.js auth 옵션

**Files:**
- Modify: `web/src/supabase.js`

**Interfaces:**
- Produces: 세션 영속·자동갱신·URL 토큰 감지가 켜진 client. 이후 모든 Auth 호출의 전제.

- [ ] **Step 1: 옵션 추가**

```js
export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
})
```

- [ ] **Step 2: 검증**

Run: `cd web && npm run dev` → 콘솔 에러 없음. (기능 검증은 Task 11 이후.)

- [ ] **Step 3: Commit**

```bash
git commit -am "feat(auth): supabase client에 Auth 세션 옵션 추가"
```

### Task 11: AuthContext 재작성 (세션 + 프로필/지갑 하이드레이션)

**Files:**
- Modify: `web/src/components/AuthContext.jsx`
- Create: `web/src/data/profileQueries.js` (프로필+지갑 fetch 분리)

**Interfaces:**
- Consumes: `supabase.auth`.
- Produces: `useAuth()` → `{ user, isLoading, mergeUser, logout }`. `user`는 `auth.uid()` 프로필+지갑(nickname/point_balance/pass_expires_at/region/admission_year/grade/degree_program/track) 머지본. `mergeUser(patch)`는 Supabase 미접근 로컬 머지(기존 `login({...})` 대체).

- [ ] **Step 1: 프로필/지갑 fetch 함수**

```js
// web/src/data/profileQueries.js
import { supabase } from '../supabase'
// 본인 프로필+지갑(RLS 본인범위). users select + _wallet RPC 병합.
export async function fetchMe() {
  const { data: rows, error } = await supabase.from('users')
    .select('id, nickname, region, admission_year, degree_program, academic_status, grade, track, university_id')
    .limit(1)
  if (error) throw error
  const profile = rows?.[0] ?? null
  if (!profile) return null
  const { data: wallet, error: wErr } = await supabase.rpc('_wallet')
  if (wErr) throw wErr
  return { ...profile, ...wallet }
}
```

- [ ] **Step 2: AuthContext 재작성**

```jsx
import { createContext, useContext, useEffect, useState } from 'react'
import { supabase } from '../supabase'
import { fetchMe } from '../data/profileQueries'

const AuthContext = createContext(null)

export function AuthProvider({ children }) {
  const [user, setUser] = useState(null)
  const [isLoading, setIsLoading] = useState(true)

  useEffect(() => {
    let active = true
    async function hydrate(session) {
      if (!session) { if (active) { setUser(null); setIsLoading(false) } ; return }
      try { const me = await fetchMe(); if (active) setUser(me ? { id: session.user.id, ...me } : null) }
      finally { if (active) setIsLoading(false) }
    }
    supabase.auth.getSession().then(({ data }) => hydrate(data.session))
    const { data: sub } = supabase.auth.onAuthStateChange((_e, session) => hydrate(session))
    return () => { active = false; sub.subscription.unsubscribe() }
  }, [])

  const mergeUser = (patch) => setUser((u) => (u ? { ...u, ...patch } : u))
  const logout = () => supabase.auth.signOut()

  return <AuthContext.Provider value={{ user, isLoading, mergeUser, logout }}>{children}</AuthContext.Provider>
}
// eslint-disable-next-line react-refresh/only-export-components
export function useAuth() { return useContext(AuthContext) }
```

- [ ] **Step 3: 검증**

Run: `cd web && npm run build`
Expected: 빌드 성공(타입/문법). 런타임 검증은 Task 13·14 이후 E2E.

- [ ] **Step 4: Commit**

```bash
git add web/src/components/AuthContext.jsx web/src/data/profileQueries.js
git commit -m "feat(auth): AuthContext를 Supabase 세션+프로필/지갑 하이드레이션으로 재작성"
```

### Task 12: authQueries Auth 전환

**Files:**
- Modify: `web/src/data/authQueries.js`

**Interfaces:**
- Produces: `signUpUser(payload)` → `supabase.auth.signUp`(메타데이터에 프로필) · `signIn(email,password)` → `signInWithPassword` · `updateProfile({region,...})`(무 user_id). `checkEmailExists`/`verifyLogin`/`registerUser` 제거.

- [ ] **Step 1: 재작성**

```js
import { supabase } from '../supabase'
export async function fetchUniversities() { /* 기존 그대로 */ }

export async function signIn(email, password) {
  const { data, error } = await supabase.auth.signInWithPassword({ email: email.trim().toLowerCase(), password })
  if (error) throw error
  return data
}
export async function signUpUser(p) {
  const { data, error } = await supabase.auth.signUp({
    email: p.email.trim().toLowerCase(), password: p.password,
    options: { data: {
      nickname: p.nickname, university_id: p.university_id, college_name: p.college_name,
      department_name: p.department_name, track: p.track, admission_year: p.admission_year,
      degree_program: p.degree_program, academic_status: p.academic_status, grade: p.grade, region: p.region,
    } },
  })
  if (error) throw error
  return data
}
export async function updateProfile({ region, admission_year, degree_program, academic_status, grade }) {
  const { data, error } = await supabase.rpc('update_profile', {
    p_region: region, p_admission_year: admission_year, p_degree_program: degree_program,
    p_academic_status: academic_status, p_grade: grade })
  if (error) throw error
  return data?.[0] ?? null
}
```

- [ ] **Step 2: 검증**

Run: `cd web && npm run build`
Expected: 성공. `checkEmailExists`/`verifyLogin`/`registerUser` 참조가 남아 있으면 빌드/그렙으로 발견 → Task 13·14에서 정리.

- [ ] **Step 3: Commit**

```bash
git commit -am "feat(auth): authQueries를 signUp/signInWithPassword/auth.uid update_profile로 전환"
```

### Task 13: Login.jsx — 이메일-우선 UX 제거

**Files:**
- Modify: `web/src/pages/Login.jsx`

**Interfaces:**
- Consumes: `signIn`(Task 12). 세션은 `onAuthStateChange`가 컨텍스트에 반영(직접 `login()` 호출 제거).

- [ ] **Step 1: 단일 폼으로 재작성**

이메일+비밀번호를 한 화면에서 받고 `signIn(email, password)` 호출. 성공 시 `navigate('/home')`(컨텍스트는 자동). 실패(`Invalid login credentials`)는 인라인 문구. `checkEmailExists` 2단계 분기 제거.

```jsx
async function onSubmit(e) {
  e.preventDefault()
  try { await signIn(email, password); navigate('/home') }
  catch (err) { setError(err.message.includes('Invalid') ? '이메일 또는 비밀번호가 올바르지 않아요.'
                                                          : '로그인 중 오류가 발생했어요.') }
}
```

- [ ] **Step 2: 검증(로컬 E2E)**

Run: 로컬 dev + Task 5에서 만든 `tester@korea.ac.kr` 계정(확인메일 ON이면 Inbucket/로그에서 확인 링크 처리)으로 로그인.
Expected: 로그인 → `/home`, navbar에 닉네임 표시(컨텍스트 머지 동작).

- [ ] **Step 3: Commit**

```bash
git commit -am "feat(auth): Login을 단일 폼 signInWithPassword로 재작성(email-first 제거)"
```

### Task 14: Signup.jsx — signUp + 확인메일 인터스티셜

**Files:**
- Modify: `web/src/pages/Signup.jsx`

**Interfaces:**
- Consumes: `signUpUser(payload)`(Task 12) — payload 키가 Task 5 트리거 metadata와 **정확히 일치**.

- [ ] **Step 1: 제출 흐름 교체**

`registerUser` → `signUpUser`. 확인메일 ON이라 `signUp` 성공 시 세션 없음 → "메일을 확인해 주세요" 상태 화면 표시(자동 `navigate('/home')` 제거). 에러 매핑: `User already registered`→이메일 중복, `NICKNAME_TAKEN`→닉네임 중복, `DOMAIN_NOT_ALLOWED`→"@korea.ac.kr 이메일만 가입 가능", `NO_COLLEGE`/`NO_DEPARTMENT`→학과 정보 오류.

```jsx
try {
  await signUpUser(payload)
  setSent(true)   // "메일 확인" 인터스티셜
} catch (err) {
  const map = { 'User already registered':'이미 가입된 이메일이에요.',
    'NICKNAME_TAKEN':'이미 쓰는 닉네임이에요.', 'DOMAIN_NOT_ALLOWED':'@korea.ac.kr 이메일만 가입할 수 있어요.' }
  setError(map[err.message] ?? '가입 중 오류가 발생했어요.')
}
```

- [ ] **Step 2: 검증(로컬 E2E)**

Run: 신규 `me@korea.ac.kr` 가입 → 확인메일 화면. 비-korea 이메일 → `DOMAIN_NOT_ALLOWED` 문구. 중복 닉네임 → `NICKNAME_TAKEN` 문구.
Expected: 각 경로 문구 정상, `public.users` 행 생성(확인 전에도).

- [ ] **Step 3: Commit**

```bash
git commit -am "feat(auth): Signup을 supabase.auth.signUp + 확인메일 인터스티셜로 전환"
```

### Task 15: 교환센터/광고 호출부 — id 인자 제거

**Files:**
- Modify: `web/src/data/exchangeQueries.js` · `web/src/pages/ExchangeCenter.jsx` · `web/src/pages/AdView.jsx` · `web/src/components/AppLayout.jsx`

**Interfaces:**
- Consumes: Task 6 무인자 RPC. `mergeUser`(Task 11).

- [ ] **Step 1: data 레이어 무인자화**

```js
export async function fetchWallet() { const { data, error } = await supabase.rpc('_wallet'); if (error) throw error; return data }
export async function purchasePass(days) { const { data, error } = await supabase.rpc('purchase_pass', { p_days: days }); if (error) throw error; return data }
export async function refundPass(days)   { const { data, error } = await supabase.rpc('refund_pass',   { p_days: days }); if (error) throw error; return data }
export async function activatePass(days) { const { data, error } = await supabase.rpc('activate_pass', { p_days: days }); if (error) throw error; return data }
export async function watchAdReward()    { const { data, error } = await supabase.rpc('watch_ad_reward'); if (error) throw error; return data }
// devExpirePass 제거(RLS로 깨짐, DEV 전용)
```

- [ ] **Step 2: 페이지 호출부 수정**

ExchangeCenter/AppLayout/AdView에서 `fetchWallet(user.id)`→`fetchWallet()`, `activatePass(user.id,d)`→`activatePass(d)`, `watchAdReward(user.id)`→`watchAdReward()`. `login({...user,...w})`→`mergeUser(w)`.

- [ ] **Step 3: 검증(로컬 E2E)**

Run: 로그인 후 교환센터에서 포인트 적립/열람권 구매·활성화, `/ad` 시청 보상.
Expected: 지갑 갱신 반영, 콘솔에서 타인 `p_user_id` 호출 시 `NOT_AUTHENTICATED`.

- [ ] **Step 4: Commit**

```bash
git commit -am "feat(auth): 교환센터/광고 호출부 auth.uid()화 + devExpirePass 제거"
```

### Task 16: 리뷰/근무지 호출부 — id 제거 + RPC화

**Files:**
- Modify: `web/src/data/worksiteQueries.js` · `web/src/pages/WorksiteDetail.jsx` · `web/src/pages/ReviewForm.jsx`

**Interfaces:**
- Consumes: Task 6 리뷰 RPC, Task 9 `list_worksite_reviews`/`increment_worksite_view`/`report_review`.

- [ ] **Step 1: data 레이어 수정**

`fetchReviews`(worksite) → `supabase.rpc('list_worksite_reviews',{p_worksite_id})`(작성자 마스킹 + user_id 미노출). 리뷰 작성/수정/삭제·`toggle_helpful`에서 user_id 인자 제거. `reportReview(...)`→`supabase.rpc('report_review',{p_review_id,p_reason})`. `incrementViewCount`→`supabase.rpc('increment_worksite_view',{p_worksite_id})`. `fetchMyReviewIds/fetchMyHelpfulIds/fetchMyReviewForPeriod`는 RLS 본인범위 select(인자에서 user_id 제거).

- [ ] **Step 2: 페이지 수정**

WorksiteDetail/ReviewForm에서 `authUser.id` 전달 제거. 잠금상태 `locked = !isPassActive(authUser?.pass_expires_at)`는 컨텍스트 머지에 의존(유지). 중복키(23505) 에러 처리 유지.

- [ ] **Step 3: 검증(로컬 E2E)**

Run: 근무지 상세 진입(조회수 증가), 리뷰 작성(+15P)/익명 작성(+5P)/수정/삭제(회수), 도움됐어요 토글, 신고. 익명 리뷰가 닉네임/학기 가려지는지 확인.
Expected: 전부 동작, 익명 마스킹 확인, 콘솔에서 user_id 위조 불가.

- [ ] **Step 4: Commit**

```bash
git commit -am "feat(auth): 리뷰/근무지 호출부 auth.uid()화 + 목록/신고/조회수 RPC화"
```

### Task 17: 마이페이지 호출부 + App 가드

**Files:**
- Modify: `web/src/data/mypageQueries.js` · `web/src/pages/MyPage.jsx` · `web/src/pages/Home.jsx` · `web/src/App.jsx`

**Interfaces:**
- Consumes: RLS 본인범위, `useAuth().isLoading`.

- [ ] **Step 1: mypage 무인자화**

`fetchPointHistory(userId)`/`fetchMyReviews(userId)` → user_id 인자 제거(RLS 본인범위 select). MyPage 프로필 저장은 `updateProfile({...})`→`mergeUser(updated)`. Home `fetchUserProfile(authUser.id)`도 본인범위로.

- [ ] **Step 2: 새로고침 레이스 가드**

`App.jsx`(또는 공통 가드)에서 `const { isLoading } = useAuth()`; 로딩 중엔 스플래시/널 렌더 → 페이지의 `if(!user) navigate('/login')`가 복원 전에 튕기지 않게. 구 localStorage 키 `honeyjang.user` 잔재 1회 제거(`localStorage.removeItem('honeyjang.user')`).

- [ ] **Step 3: 검증(로컬 E2E)**

Run: 로그인 상태에서 **새로고침** → `/login`으로 안 튕기고 유지. 마이페이지 포인트내역/내리뷰/프로필수정 동작.
Expected: 세션 복원 레이스 없음.

- [ ] **Step 4: Commit**

```bash
git commit -am "feat(auth): 마이페이지 본인범위화 + 세션복원 레이스 가드 + 구 localStorage 정리"
```

---

## Phase 3 — E2E 검증 · 문서 · 반영(게이트)

### Task 18: 전체 시나리오 E2E + RLS 부정 테스트

**Files:**
- (검증 전용, 코드 변경 없음 또는 발견 버그 수정)

- [ ] **Step 1: 해피패스**

가입(@korea.ac.kr)→확인메일→로그인→근무지 조회→리뷰 작성(+15P)→열람권 구매/활성화→`/ad` 보상→로그아웃→새로고침 복원.

- [ ] **Step 2: 부정 테스트(콘솔)**

브라우저 콘솔에서: 비로그인 `supabase.rpc('watch_ad_reward')` → `NOT_AUTHENTICATED`; 로그인 후 `supabase.from('users').update({point_balance:999})` → 컬럼 GRANT 거부; `supabase.from('points').select('*')` → 본인 행만; 비-korea 도메인 signUp → `DOMAIN_NOT_ALLOWED`.
Expected: 전부 차단/제약. 실패 케이스는 해당 Task로 돌아가 수정.

- [ ] **Step 3: Commit(있으면)**

```bash
git commit -am "test(auth): 컷오버 E2E + RLS 부정 테스트 통과, 발견 버그 수정"
```

### Task 19: 문서 갱신

**Files:**
- Modify: `docs/db-schema.md` · `web/supabase/README.md` · `README.md` · `docs/frontend.md`

- [ ] **Step 1:** db-schema에 users.id uuid·signup_enabled·삭제 컬럼·신규 RPC·RLS 정책 반영. README 마이그레이션 표에 컷오버 추가. frontend.md에 Supabase Auth 세션 흐름 반영.

- [ ] **Step 2: Commit**

```bash
git commit -am "docs(auth): 컷오버 후 스키마/RPC/RLS/세션흐름 문서 갱신"
```

### Task 20: 반영 (⛔ 팀 사인오프 게이트)

- [ ] **Step 1:** 디스코드 사전공유 — 컷오버 범위·파괴적(TRUNCATE)·푸시 순서. **현수와 `verify_login`/`register_user` 드롭 타이밍 합의.**
- [ ] **Step 2:** `cd web && npx supabase db push`(작성자가) → prod 대시보드 Auth 설정(Task 0) 적용 → PostgREST 스키마 reload.
- [ ] **Step 3:** 클라 배포 → prod 스모크(가입/로그인/리뷰/포인트). 구 유저는 재가입 안내.

---

## Self-Review (작성자 점검)

- **스펙 커버리지:** 신원 UUID(Task 2-3)·이메일확인(Task 0,14)·@korea.ac.kr(Task 4-5)·email/password_hash DROP(Task 3)·RPC auth.uid()(Task 6-7)·RLS+컬럼GRANT(Task 8)·익명 마스킹(Task 9)·클라 전부(Task 10-17)·문서(Task 19)·게이트(Task 20). 스펙 §4 A~E 전부 대응됨.
- **범위 밖 명시:** ②광고 쿨다운/캡/소재, 관리자 콘솔, 서버측 페이월 강제, 계정삭제 시 auth.users 동반삭제 — 본 계획 제외(스펙 §2·§7).
- **타입 일관성:** `mergeUser`(Task 11)가 Task 15-17에서 동일 사용, 무인자 RPC 시그니처가 Task 6↔7↔클라 일치, 트리거 metadata 키(Task 5)↔`signUpUser` payload(Task 12,14) 일치.
- **알려진 리스크:** 제약명 드리프트(Task 2-3 주의문), 트리거 예외의 불투명 전파(Task 5,14 매핑), Docker 없는 환경의 `db reset` 한계(Task 0 대안).
