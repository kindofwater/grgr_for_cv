# 서울대학교 개설 + 교내 국가근로 시드 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** universities에 서울대학교를 개설(가입 오픈)하고, 교내 국가근로 근무지 24개를 명부에서 시드해 노출시킨다.

**Architecture:** 마이그레이션 SQL 한 파일에 4블록 — ①universities 서울대 행(`snu.ac.kr`, `signup_enabled=true`) ②'미분류' colleges/departments 1쌍(가입 트리거 `NO_COLLEGE` 방지) ③worksites 24행(national+on_campus, region NULL) ④placeholder postings 24행. 프론트 수정 0 — 학교 드롭다운은 DB에서 오고, 단과대/학과 드롭다운(고려대 하드코딩)은 fallback으로 '미분류'가 저장돼 가입이 깨지지 않는다. 데이터는 순수 추가라 기존 근무지·리뷰 무손상.

**Tech Stack:** Supabase CLI 마이그레이션(SQL), Postgres

**Spec:** 별도 스펙 문서 없음 — 2026-07-17 대화에서 설계 승인(A안: DB만으로 해결, 프론트·실제 학과 명부는 나중에 사용자가 직접).

## Global Constraints

- **`db push`는 이번 범위 밖.** SQL 작성·커밋까지만. push는 디스코드 공유 후 배경록이 직접 (CLAUDE.md §3).
- **커밋 전 브랜치를 사용자에게 반드시 확인** — 새 브랜치 vs main 직접 (CLAUDE.md Git 규칙). 지난 시드(07-16)는 main 직접이었다.
- 마이그레이션 파일 맨 위 헤더 2줄 필수: `-- 목적: …` / `-- 날짜: 2026-07-17 · 담당: 배경록`
- **Docker가 없어 로컬 `db reset` 검증 불가.** 검증은 grep 자체 점검(Task 1 Step 2) + push 후 수동(Task 3).
- 멱등해야 한다 — `worksites`·`universities`에 유니크 제약이 없어 `on conflict` 불가 → `where not exists`. 재실행 시 `signup_enabled=true`로 수렴하는 UPDATE 포함.
- 시드 `region`은 **NULL** — 교내는 지역 필터 대상이 아니다(`search_worksite_cards`가 `location_type='on_campus'`를 우회, 20260716180000).
- **서울대 `university_id` 하드코딩 금지** — 같은 마이그레이션에서 생성되므로 모든 블록이 `name='서울대학교'` 서브쿼리로 참조한다.
- 시드 데이터 소스는 `붙임. '24~'26년 연도별 유형별 근로지 현황.xlsx`(리포 루트, 첫 번째 시트): `기관명='서울대학교(본교) 학부'` AND `유형='일반교내'` 67행 → 근로지명 dedup(최신 연도 우선) **24개**. 2026-07-17에 추출 완료, 아래 SQL에 임베드됨 — **엑셀을 다시 열 필요 없다.**

---

### Task 1: 마이그레이션 SQL 작성

**Files:**
- Create: `web/supabase/migrations/20260717000000_snu_signup_oncampus_seed.sql`
- Reference (수정 금지, 패턴 원본): `web/supabase/migrations/20260716180000_oncampus_national_seed.sql`

**Interfaces:**
- Consumes: `handle_new_user()` (20260624025109) — `universities.signup_enabled` 검증, colleges/departments 이름 매칭 실패 시 `order by id limit 1` fallback. 이 동작 덕에 '미분류' 1쌍만으로 가입이 성립한다.
- Produces: `universities`의 서울대 행(이름 `'서울대학교'`, campus NULL) — Task 3 검증 쿼리와 미래 서울대 학과 명부 작업이 이 이름으로 조회한다.

- [ ] **Step 1: 마이그레이션 파일 작성**

`web/supabase/migrations/20260717000000_snu_signup_oncampus_seed.sql` 전체 내용:

```sql
-- 목적: 서울대학교 개설(가입 오픈) + 교내 국가근로 근무지 24개 시드 + placeholder posting
-- 날짜: 2026-07-17 · 담당: 배경록
-- 비고: plan docs/superpowers/plans/2026-07-17-snu-oncampus-seed.md
--       ① universities에 서울대학교(snu.ac.kr, signup_enabled=true) — 고려대 외 첫 학교
--       ② colleges/departments '미분류' 1쌍 — handle_new_user의 NO_COLLEGE/NO_DEPARTMENT 방지
--       ③ worksites 24행(national+on_campus, region NULL) ④ placeholder postings 24행
--       기존 데이터(고려대 근무지·리뷰)는 건드리지 않는다 — 순수 추가.

-- ── 1. 서울대학교 개설 ──
-- 가입 화면 학교 드롭다운은 universities 테이블에서 오므로(fetchUniversities) 프론트 수정 없이 노출된다.
-- 단과대/학과 드롭다운은 profileOptions.js의 고려대 목록 하드코딩이라 서울대생에겐 부정확하지만,
-- handle_new_user가 서울대 소속에서 이름 매칭 실패 → 첫 행 fallback → 아래 '미분류'가 저장된다(가입은 안 깨짐).
-- track은 유저가 고른 계열이 그대로 저장된다(m->>'track'). 실제 서울대 단과대/학과 명부와
-- 프론트 정비는 별도 작업 — 가입 오픈까지 텀이 있어 감수하기로 결정(2026-07-17).
insert into universities (name, campus, email_domain, signup_enabled)
select '서울대학교', null, 'snu.ac.kr', true
 where not exists (select 1 from universities where name = '서울대학교');

-- 재실행 수렴: 행이 이미 있어도 가입 오픈 상태를 보장 (멱등)
update universities set signup_enabled = true
 where name = '서울대학교' and not signup_enabled;

-- ── 2. '미분류' 단과대·학과 1쌍 ──
-- 서울대에 colleges/departments가 0행이면 handle_new_user가 NO_COLLEGE 예외로 가입이 깨진다.
-- default_track은 유저 track에 영향 없음(프론트가 하드코딩 목록에서 자동 세팅) — NOT NULL이라 유효값만 채운다.
insert into colleges (university_id, name)
select u.id, '미분류'
  from universities u
 where u.name = '서울대학교'
   and not exists (select 1 from colleges c where c.university_id = u.id and c.name = '미분류');

insert into departments (college_id, name, default_track)
select c.id, '미분류', '인문사회계열'
  from colleges c
  join universities u on u.id = c.university_id
 where u.name = '서울대학교' and c.name = '미분류'
   and not exists (select 1 from departments d where d.college_id = c.id and d.name = '미분류');

-- ── 3. 시드 — worksites 24행 ──
-- 소스: 붙임. '24~'26년 연도별 유형별 근로지 현황.xlsx (기관명='서울대학교(본교) 학부' AND 유형='일반교내')
--       67행(24/25/26 연도별 중복 포함) → 근로지명 dedup(최신 연도 우선) 24개. 우편번호 접두 [0xxxx] 제거.
-- 2026 목록에 없는 2곳(약학대학=2025·자유전공학부=2024)도 포함 — 과거 근무자 리뷰 선적립 목적(고려대 선례와 동일).
-- 간호대학은 연건캠퍼스(종로구 대학로) 주소지만 서울대 교내이므로 on_campus.
-- region은 NULL(교내는 지역 필터 대상 아님 — 20260716180000의 location_type 판정 참고).
-- 멱등: worksites에 유니크 제약이 없어 on conflict 불가 → where not exists.
with uni as (
  select id from universities where name = '서울대학교'
),
seed(workplace_name, address) as (values
  ('간호대학', '서울 종로구 대학로 103 간호대학 (연건동, 서울대학교)'),
  ('경영대학', '서울 관악구 관악로 1, 서울대학교 경영대학'),
  ('공과대학', '서울 관악구 관악로 1, 서울대학교 공과대학'),
  ('규장각한국학연구원', '서울 관악구 관악로 1, 서울대학교 규장각한국학연구원'),
  ('글로벌사회공헌단', '서울 관악구 관악로 1, 서울대학교 글로벌사회공헌단'),
  ('농업생명과학대학', '서울 관악구 관악로 1, 서울대학교 농업생명과학대학'),
  ('미술대학', '서울 관악구 관악로 1, 서울대학교 미술대학'),
  ('사범대학', '서울 관악구 관악로 1, 서울대학교 사범대학'),
  ('사회과학대학', '서울 관악구 관악로 1, 서울대학교 사회과학대학'),
  ('생활과학대학', '서울 관악구 관악로 1, 서울대학교 생활과학대학'),
  ('시설기획과', '서울 관악구 관악로 1, 서울대학교 행정관 시설기획과'),
  ('약학대학', '서울 관악구 관악로 1, 서울대학교 약학대학'),
  ('언어교육원', '서울 관악구 관악로 1, 서울대학교 137-1동 202호'),
  ('음악대학', '서울 관악구 관악로 1, 서울대학교 종합교육연구동 220동 411호 음악대학 교학행정실'),
  ('인문대학', '서울 관악구 관악로 1, 서울대학교 인문대학'),
  ('자연과학대학', '서울 관악구 관악로 1, 서울대학교 자연과학대학'),
  ('자유전공학부', '서울 관악구 관악로 1, 서울대학교 자유전공학부'),
  ('장학복지과', '서울 관악구 관악로 1, 서울대학교 행정관 장학복지과'),
  ('정보화본부', '서울 관악구 관악로 1, 서울대학교 정보화본부'),
  ('중앙도서관', '서울 관악구 관악로 1, 서울대학교 중앙도서관'),
  ('첨단융합학부', '서울 관악구 관악로 1 첨단융합학부'),
  ('평생교육원', '서울 관악구 관악로 1, 54동 107호 서울대학교 (신림동)'),
  ('학부대학', '서울 관악구 관악로 1 학부대학 (신림동, 서울대학교)'),
  ('홍보팀', '서울 관악구 관악로 1 60동 행정관 (신림동, 서울대학교)')
)
insert into worksites (university_id, type, location_type, organization_name, workplace_name, region, address)
select uni.id, 'national', 'on_campus', '서울대학교(본교) 학부', s.workplace_name, null, s.address
  from seed s, uni
 where not exists (
   select 1 from worksites w
    where w.university_id = uni.id
      and w.type = 'national'
      and w.location_type = 'on_campus'
      and w.workplace_name = s.workplace_name
 );

-- ── 4. placeholder postings 24행 (근무지당 1개) ──
-- 공고 없는 worksite는 앱에 안 뜬다 — 게이트 3중(①검색 RPC의 join rep INNER ②자동완성의 exists postings
-- ③상세의 infoReady = worksite && posting)이 공고 ≥1을 요구한다. 껍데기 posting으로 통과시킨다.
-- 자격은 국가근로 규칙값(long/학부만/재학만) — 기본값(3=미정/unknown)으로 두면 유저가 "학부생만"·"장기"
-- 필터를 켜는 순간 24개가 전부 사라진다. 20260716180000 선례와 같은 값.
-- 실제 공고를 넣을 땐 `delete from postings where worksite_id=X and is_placeholder=true` 후 insert.
insert into postings (worksite_id, is_active, is_placeholder, work_duration_type, eligible_degree, eligible_status)
select w.id, false, true, 'long', 0, 0
  from worksites w
  join universities u on u.id = w.university_id
 where u.name = '서울대학교'
   and w.type = 'national'
   and w.location_type = 'on_campus'
   and not exists (
     select 1 from postings p
      where p.worksite_id = w.id and p.is_placeholder = true
   );
```

- [ ] **Step 2: 자체 점검 (Docker 없음 — grep으로)**

```bash
cd "c:/Users/bedso/Desktop/coding/GGGorae/honeyjang" && grep -c "^  ('" web/supabase/migrations/20260717000000_snu_signup_oncampus_seed.sql
```
기대: `24`

```bash
cd "c:/Users/bedso/Desktop/coding/GGGorae/honeyjang" && grep -c "where not exists" web/supabase/migrations/20260717000000_snu_signup_oncampus_seed.sql
```
기대: `4` (universities·colleges·departments·worksites — postings의 `and not exists`는 미포함)

육안 확인 3가지:
1. `values` 목록 마지막 행 `('홍보팀', …)`에 쉼표 없음
2. `signup_enabled`가 `true`로 들어가는 곳이 insert 1곳 + update 1곳뿐
3. 헤더 2줄(`-- 목적:` / `-- 날짜:`)이 파일 맨 위

- [ ] **Step 3: 브랜치 확인 후 커밋**

**먼저 사용자에게 묻는다**: 새 브랜치 vs `main` 직접 (지난 시드는 main 직접). 확인 후:

```bash
cd "c:/Users/bedso/Desktop/coding/GGGorae/honeyjang" && git add web/supabase/migrations/20260717000000_snu_signup_oncampus_seed.sql && git commit -m "feat(db): 서울대학교 개설(가입 오픈) + 교내 국가근로 근무지 24개 시드

universities에 서울대학교(snu.ac.kr, signup_enabled=true)를 추가한다 — 고려대 외 첫 학교.
가입 트리거의 NO_COLLEGE 예외를 막기 위해 '미분류' 단과대·학과 1쌍을 함께 시드한다.
단과대/학과 드롭다운은 고려대 목록 하드코딩이라 서울대생 선택은 fallback으로 '미분류'가
저장된다 — 실제 명부·프론트 정비는 별도 작업(가입 오픈까지 텀이 있어 감수, 2026-07-17 결정).

근무지는 명부(서울대 본교 학부·일반교내 67행 → 근로지명 dedup 24개)를 national+on_campus로
시드하고, 근무지당 껍데기 posting 1개(is_active=false)로 공고 게이트를 통과시킨다.

db push는 아직 하지 않는다(디스코드 공유 후 배경록이 직접).

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: 문서 갱신

**Files:**
- Modify: `docs/db-schema.md` (§⑤ 다음에 §⑥ 추가 — 파일 상단 섹션 목록 순서 유지)
- Modify: `web/supabase/README.md` (마이그레이션 목록 맨 아래, `20260716190000` 항목 다음)

**Interfaces:**
- Consumes: Task 1의 마이그레이션 파일명 `20260717000000_snu_signup_oncampus_seed.sql` — 두 문서 모두 이 이름으로 기재.

- [ ] **Step 1: db-schema.md에 §⑥ 추가**

`docs/db-schema.md`의 §⑤(`region 정규화 + CHECK 제약`) 섹션 끝, `## 기존 스키마` 앞에 삽입:

```markdown
## ⑥ 서울대학교 개설 + 교내 국가근로 24개 시드 — **db push 대기 (migration 20260717000000)**

- **`universities`에 서울대학교** (campus NULL, `email_domain='snu.ac.kr'`, **`signup_enabled=true`**) — 고려대 외 첫 학교. 가입 화면 학교 드롭다운은 DB에서 오므로 프론트 수정 없이 노출된다.
- **'미분류' colleges/departments 1쌍** — `handle_new_user`의 `NO_COLLEGE`/`NO_DEPARTMENT` 방지. 단과대/학과 드롭다운(`profileOptions.js`)은 고려대 목록 하드코딩이라 서울대생이 뭘 고르든 이름 매칭 실패 → fallback으로 '미분류' 저장(`track`은 본인 선택 유지). **실제 서울대 학과 명부·프론트 정비는 별도 작업** — 가입 오픈까지 텀이 있어 감수(2026-07-17 결정). 유저는 나중에 프로필 수정(`update_profile`)으로 바꿀 수 있다.
- **worksites 24행** (`type='national'`, `location_type='on_campus'`, `region=NULL`) + **placeholder postings 24행** (`is_active=false`, `long`/`0`/`0`) — 명부 67행(연도 중복) → 근로지명 dedup(최신 연도 우선) 24개. §④ 고려대 시드와 동일 패턴. 간호대학은 연건캠퍼스 주소지만 교내로 분류.
```

- [ ] **Step 2: web/supabase/README.md 마이그레이션 목록에 항목 추가**

`20260716190000_normalize_worksite_region.sql` 항목 바로 아래에 삽입:

```markdown
  - `20260717000000_snu_signup_oncampus_seed.sql` = **push 대기** — **서울대학교 개설 + 교내 국가근로 근무지 24개 시드**. ①universities에 서울대(snu.ac.kr, `signup_enabled=true` — 고려대 외 첫 학교) ②'미분류' colleges/departments 1쌍(`handle_new_user` NO_COLLEGE 방지 — 단과대/학과 드롭다운은 고려대 하드코딩이라 서울대생은 fallback으로 '미분류' 저장, 실제 명부·프론트 정비는 별도 작업) ③worksites 24행(명부 `기관명='서울대학교(본교) 학부'`·`유형='일반교내'` 67행 → dedup 24, national+on_campus, region NULL) ④placeholder postings 24행(`is_active=false`, long/0/0). 순수 추가 — 기존 데이터 무손상. 멱등(`where not exists` + `signup_enabled` 수렴 UPDATE). 담당 배경록. plan `docs/superpowers/plans/2026-07-17-snu-oncampus-seed.md`.
```

- [ ] **Step 3: 커밋**

```bash
cd "c:/Users/bedso/Desktop/coding/GGGorae/honeyjang" && git add docs/db-schema.md web/supabase/README.md && git commit -m "docs(db): 서울대 개설+시드 마이그레이션(20260717000000) 문서 반영

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: push 후 검증 (⚠️ 이번 범위 밖 — 디스코드 공유 후 배경록이 직접)

**이 태스크는 실행하지 않는다.** 아래는 push 시점에 쓸 체크리스트다.

- [ ] **push 전: 대기 마이그레이션 확인** — `db push`는 원격 이력에 없는 파일을 전부 적용한다(20260716170000 항목의 교훈). 남의 미적용분이 없는지 본다:

```bash
cd "c:/Users/bedso/Desktop/coding/GGGorae/honeyjang/web" && npx supabase migration list
```

- [ ] **push 후: 행수 확인**

```sql
select id, signup_enabled from universities where name = '서울대학교';          -- 1행, true
select count(*) from colleges c join universities u on u.id=c.university_id
 where u.name='서울대학교';                                                     -- 1
select count(*) from worksites w join universities u on u.id=w.university_id
 where u.name='서울대학교';                                                     -- 24
select count(*) from postings p join worksites w on w.id=p.worksite_id
  join universities u on u.id=w.university_id
 where u.name='서울대학교' and p.is_placeholder;                                -- 24
select count(*) from worksites where location_type='off_campus' and region is null;  -- 0 (회귀 없음)
```

- [ ] **grgr.kr 수동 확인**
  - 검색 "중앙도서관" → 서울대 카드 노출 (고려대 '도서관 학술정보서비스팀'과 별개 카드)
  - 고급검색 지역=서울 → 서울대 교내 24개가 지역과 무관하게 계속 뜨는지 (region NULL이어도 교내 우회)
  - 고급검색 학부생 + 장기 필터 → 24개 생존 (자격 규칙값 확인)
  - 상세 페이지 진입 → 빈 화면 아님 (공고 게이트 통과), "모집완료" 표시
  - 회원가입 1단계 학교 드롭다운에 "서울대학교" 표시

- [ ] **가입 스모크 (선택)** — snu.ac.kr 메일이 있을 때만: OTP 가입 진행 → `users` 행의 college/department가 '미분류'로 저장되는지. 없으면 첫 실가입자가 사실상 스모크 테스트임을 팀에 공유.

- [ ] **문서 상태 갱신** — 검증 완료 후 `docs/db-schema.md` §⑥과 `web/supabase/README.md` 항목의 "push 대기"를 "적용됨(LIVE)"로.

---

## 롤백

데이터는 순수 추가라 되돌리기 쉽다. **서울대 유저·리뷰가 생기기 전에만** 아래 순서로 (reviews.worksite_id는 RESTRICT — 리뷰가 붙으면 worksite 삭제가 막힌다):

```sql
-- 가입만 급히 닫기 (데이터 유지)
update universities set signup_enabled = false where name = '서울대학교';

-- 전체 롤백 (FK 역순)
delete from postings  where worksite_id in (select w.id from worksites w join universities u on u.id=w.university_id where u.name='서울대학교');
delete from worksites where university_id = (select id from universities where name='서울대학교');
delete from departments where college_id in (select c.id from colleges c join universities u on u.id=c.university_id where u.name='서울대학교');
delete from colleges  where university_id = (select id from universities where name='서울대학교');
delete from universities where name='서울대학교';   -- 서울대 users가 있으면 RESTRICT로 실패(정상)
```
