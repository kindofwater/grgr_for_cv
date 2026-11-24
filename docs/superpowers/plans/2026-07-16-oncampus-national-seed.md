# 교내 국가근로 근무지 시드 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 고려대 본교 학부의 교내 국가근로 근무지 57개를 명부에서 시드해, 출시 전 유저가 리뷰를 쌓을 수 있게 한다.

**Architecture:** 마이그레이션 SQL 한 파일에 4가지를 담는다 — ①`postings.is_placeholder` 컬럼 ②`search_worksite_cards` 지역 조건 수정 ③`id=6660` region 픽스 ④worksites 57행 + placeholder postings 57행 insert. 프론트는 지역 필터 안내 문구 한 줄만 바뀐다. 데이터는 순수 추가라 교외 6,647개·`school` 25개·리뷰는 무손상.

**Tech Stack:** Supabase CLI 마이그레이션(SQL), Postgres, React(Vite)

**Spec:** `docs/superpowers/specs/2026-07-16-oncampus-national-seed-design.md`

## Global Constraints

- **`db push`는 이번 범위 밖이다.** SQL 작성·커밋까지만. push는 디스코드 공유·백엔드 상의 후 배경록이 직접 (CLAUDE.md §3.1·§3.3, 메모리 `project-national-oncampus-worksite-seed`).
- 브랜치: `main`에 그대로 커밋 (2026-07-16 확인). push 안 함.
- 마이그레이션 파일 맨 위 헤더 2줄 필수: `-- 목적: …` / `-- 날짜: 2026-07-16 · 담당: 배경록` (CLAUDE.md §3.2)
- 멱등해야 한다 — `db reset`·재push에서 중복 insert 금지. `worksites`에 유니크 제약이 없어 `on conflict` 불가 → `where not exists`.
- **Docker가 없어 로컬 `db reset` 검증은 불가능하다.** 검증은 push 후 수동 (Task 3).
- 시드 `region`은 **NULL** — 교내에 지역을 박지 않는다.

---

### Task 1: 마이그레이션 SQL 작성

**Files:**
- Create: `web/supabase/migrations/20260716180000_oncampus_national_seed.sql`
- Reference (수정 금지, 본문 복사 원본): `web/supabase/migrations/20260713172824_search_rpc_limits_and_timeout.sql:15-110`

**Interfaces:**
- Produces: `postings.is_placeholder boolean not null default false` — 미래 KUPID 크롤이 `delete from postings where worksite_id=X and is_placeholder=true`로 껍데기만 수술 제거할 때 쓴다.
- Modifies: `search_worksite_cards(text,text,int,int,text[],text[],text[],text[],text[],int[],int[],boolean[])` — **시그니처 불변** → `create or replace`, `DROP` 불필요, grant 재부여 불필요.

⚠️ **`search_worksite_cards` 본문은 반드시 `20260713172824`에서 복사한다.** `20260708110000`(지역 필터)이 아니다 — 그 뒤 `20260713172824`가 limit/offset 상한을 추가했으므로, 옛 파일에서 복사하면 **그 보안 픽스가 조용히 롤백된다.** 바뀌는 건 `p_regions` 한 줄뿐이다.

- [ ] **Step 1: 57행 시드 SQL 생성**

`web/`이 아닌 리포 루트에서 실행. 출력을 Step 2의 마이그레이션 파일에 붙인다.

```bash
cd "c:/새 폴더" && python -X utf8 -c "
import pandas as pd
d = pd.read_excel(\"붙임. '24~'26년 연도별 유형별 근로지 현황.xlsx\", sheet_name=0)
s = d[(d['기관명'] == '고려대학교(본교) 학부') & (d['유형'] == '일반교내')].copy()
s['addr'] = s['소재지(주소)'].astype(str).str.replace(r'^\[\d{5}\]\s*', '', regex=True).str.strip()
s = s.sort_values('연도', ascending=False).drop_duplicates('근로지명', keep='first').sort_values('근로지명')
def q(v): return \"'\" + str(v).replace(\"'\", \"''\") + \"'\"
print(',\n'.join(f'  ({q(r[\"근로지명\"])}, {q(r[\"addr\"])})' for _, r in s.iterrows()))
"
```

기대 출력: **57행**, 첫 줄이 `('간호대학행정팀', '서울 성북구 안암로 145 고려대학교 간호대학'),`.
dedup은 **최신 연도 우선**(`sort_values('연도', ascending=False)` + `keep='first'`) — 같은 부서가 24/25/26에 반복 등장하므로 가장 최근 주소를 쓴다.

- [ ] **Step 2: 마이그레이션 파일 작성**

`web/supabase/migrations/20260716180000_oncampus_national_seed.sql`:

```sql
-- 목적: 고려대 본교 학부 교내 국가근로 근무지 57개 시드(명부) + placeholder posting — 출시 전 리뷰 선적립
-- 날짜: 2026-07-16 · 담당: 배경록
-- 비고: spec docs/superpowers/specs/2026-07-16-oncampus-national-seed-design.md
--       ① postings.is_placeholder 컬럼(미래 크롤 교체용 안전표식)
--       ② search_worksite_cards 지역 조건을 location_type 기준으로 수정 — 아래 근거
--       ③ id=6660 region 픽스(②의 부수 영향, 1행)
--       ④ worksites 57행 + placeholder postings 57행 (멱등: where not exists)
--       교외 national 6647개·school 25개·reviews(0건)는 건드리지 않는다. school 25개는 새 KUPID 크롤 시 교체.

-- ── 1. is_placeholder — 미래 교체용 안전표식 ──
-- 지금 쓰는 플래그가 아니다. 공고 시즌에 크롤로 진짜 공고를 넣을 때
--   delete from postings where worksite_id = X and is_placeholder = true;
-- 로 껍데기만 수술 제거하기 위한 것. 그땐 리뷰가 이미 붙어 있어 통짜 wipe가 불가능하고,
-- 플래그가 없으면 "null 패턴"으로 추측해야 해서 위험하다.
-- 리뷰는 worksite_id에 붙으므로 postings만 교체해도 리뷰는 무손상.
alter table postings add column if not exists is_placeholder boolean not null default false;

comment on column postings.is_placeholder is
  '공고 없는 근무지를 노출시키기 위한 껍데기 posting 표식. 실제 공고 크롤 시 이 행만 지우고 교체한다.';

-- ── 2. search_worksite_cards — 지역 필터를 location_type 기준으로 ──
-- 기존 조건: (p_regions is null or w.type <> 'national' or w.region = any(p_regions))
-- 20260708110000의 의도는 "교내는 지역 필터 무시"였고(그 헤더 참고), 당시엔 national+on_campus가
-- 0개라 "교내" == "school"이 우연히 참이어서 type으로 판정해도 맞았다.
-- 이 마이그레이션의 시드가 그 전제를 깬다(national이면서 on_campus). region이 NULL인 교내 57개가
-- 지역 필터를 켠 유저에게 통째로 사라지므로, 원래 의도대로 location_type 기준으로 고친다.
-- 교내에 region을 채우는 우회는 쓰지 않는다 — 학교를 추가할 때마다 지역을 채우는 부채가 된다.
--
-- ⚠️ 본문은 현행 최신(20260713172824_search_rpc_limits_and_timeout)을 그대로 재현 +
--    p_regions 한 줄만 변경. 20260708110000에서 복사하면 limit/offset 상한이 롤백된다.
--    시그니처 동일 → create or replace(DROP 불필요), 기존 grant(authenticated·anon) 유지됨.
create or replace function search_worksite_cards(
  p_query  text default null,
  p_sort   text default 'recommend',
  p_limit  int  default 20,
  p_offset int  default 0,
  p_types     text[] default null,
  p_locations text[] default null,
  p_regions   text[] default null,
  p_durations text[] default null,
  p_tracks    text[] default null,
  p_degrees   int[]  default null,
  p_statuses  int[]  default null,
  p_actives   boolean[] default null
)
returns table(
  worksite_id        int,
  organization_name  varchar,
  workplace_name     varchar,
  region             varchar,
  address            text,
  type               worksite_type_e,
  location_type      location_type_e,
  view_count         int,
  is_active          boolean,
  preferred_track    varchar,
  eligible_degree    smallint,
  eligible_status    smallint,
  work_duration_type duration_type_e,
  review_count       bigint,
  avg_recommend      numeric,
  avg_work           numeric,
  avg_growth         numeric,
  avg_vibe           numeric,
  avg_flex           numeric,
  recommend_rate     int,
  total_count        bigint
)
language sql
security definer
as $$
  with rep as (
    select distinct on (p.worksite_id)
      p.worksite_id, p.preferred_track, p.eligible_degree,
      p.eligible_status, p.work_duration_type
    from postings p
    where p.deleted_at is null
    order by p.worksite_id, p.is_active desc, p.created_at desc
  ),
  ws_active as (
    select worksite_id, bool_or(is_active) as is_active
    from postings where deleted_at is null group by worksite_id
  ),
  stats as (
    select worksite_id,
           count(*) as review_count,
           round(avg(score_recommend)::numeric,1) as avg_recommend,
           round(avg(score_work)::numeric,1)      as avg_work,
           round(avg(score_growth)::numeric,1)    as avg_growth,
           round(avg(score_vibe)::numeric,1)      as avg_vibe,
           round(avg(score_flex)::numeric,1)      as avg_flex,
           round(100.0*count(*) filter (where score_recommend>=4.0)/count(*))::int as recommend_rate
    from reviews where deleted_at is null and not is_blinded group by worksite_id
  ),
  joined as (
    select w.id as worksite_id, w.organization_name, w.workplace_name,
           w.region, w.address, w.type, w.location_type, w.view_count,
           coalesce(a.is_active,false) as is_active,
           r.preferred_track, r.eligible_degree, r.eligible_status, r.work_duration_type,
           coalesce(s.review_count,0) as review_count,
           s.avg_recommend, s.avg_work, s.avg_growth, s.avg_vibe, s.avg_flex, s.recommend_rate
    from worksites w
    join rep r           on r.worksite_id = w.id
    left join ws_active a on a.worksite_id = w.id
    left join stats s    on s.worksite_id = w.id
    where w.deleted_at is null
      and ( p_query is null or p_query = '' or
            w.organization_name ilike '%'||p_query||'%' or
            w.workplace_name    ilike '%'||p_query||'%' )
      and (p_actives   is null or coalesce(a.is_active,false) = any(p_actives))
      and (p_types     is null or w.type          = any(p_types::worksite_type_e[]))
      and (p_locations is null or w.location_type = any(p_locations::location_type_e[]))
      and (p_regions   is null or w.location_type = 'on_campus' or w.region = any(p_regions))
      and (p_durations is null or r.work_duration_type = any(p_durations::duration_type_e[]))
      and (p_tracks    is null or r.preferred_track     = any(p_tracks))
      and (p_degrees   is null or r.eligible_degree::int = any(p_degrees))
      and (p_statuses  is null or r.eligible_status::int = any(p_statuses))
  )
  select *, count(*) over() as total_count
  from joined
  order by
    case when p_sort='reviews'   then review_count end desc nulls last,
    case when p_sort='recommend' then avg_recommend end desc nulls last,
    worksite_id
  limit  least(greatest(coalesce(p_limit, 20), 0), 50)
  offset least(greatest(coalesce(p_offset, 0), 0), 10000);
$$;

-- ── 3. id=6660 region 픽스 — 2의 부수 영향 ──
-- 미래성장연구원(school/off_campus/region NULL)은 기존 조건에선 type <> 'national'이라 지역 필터를
-- 우회했지만, 수정 후엔 교외로 분류돼 필터 대상이 되고 region이 없어 지역 필터 시 사라진다.
-- 주소에 "서울 강남구"로 명시돼 있으므로 채운다. 나머지 교외 6647개는 region이 전부 있어 무영향.
-- (school 25개는 새 KUPID 크롤 시 교체되므로 이건 그때까지의 임시 정리.
--  ⚠️ 새 크롤러는 off_campus의 region을 반드시 채울 것 — 비면 지역 필터에서 조용히 사라진다.)
update worksites
   set region = '서울', updated_at = now()
 where type = 'school' and location_type = 'off_campus' and region is null;

-- ── 4. 시드 — worksites 57행 + placeholder postings 57행 ──
-- 소스: 붙임. '24~'26년 연도별 유형별 근로지 현황.xlsx (기관명='고려대학교(본교) 학부' AND 유형='일반교내')
--       160행 → 근로지명 dedup(최신 연도 우선) 57개. 우편번호 접두 [02841] 제거.
-- 2026 목록에 없는 4곳(노동대학원행정팀·정경대학 평화연구소·체육지원팀·학생지원팀(공통))도 포함 —
-- 24/25년 근무자가 리뷰를 쓸 수 있어야 하고, is_active=false("모집완료") 표시와 일관된다.
-- region은 NULL(교내는 지역 필터 대상 아님 — 위 2 참고).
-- 멱등: worksites에 유니크 제약이 없어 on conflict 불가 → where not exists.
with seed(workplace_name, address) as (values
  -- ↓↓↓ Step 1의 생성 출력 57행을 여기에 붙인다 ↓↓↓
  ('간호대학행정팀', '서울 성북구 안암로 145 고려대학교 간호대학'),
  ('건축팀', '서울 성북구 안암로 145 고려대학교'),
  -- … (전체 57행)
  ('학생지원팀(공통)', '서울 성북구 안암동5가 1-2번지 고려대학교안암캠퍼스 중앙광장')
  -- ↑↑↑ 마지막 행엔 쉼표 없음 ↑↑↑
)
insert into worksites (university_id, type, location_type, organization_name, workplace_name, region, address)
select 1, 'national', 'on_campus', '고려대학교(본교) 학부', s.workplace_name, null, s.address
  from seed s
 where not exists (
   select 1 from worksites w
    where w.university_id = 1
      and w.type = 'national'
      and w.location_type = 'on_campus'
      and w.workplace_name = s.workplace_name
 );

-- placeholder posting 1개/근무지.
-- 공고 없는 worksite는 앱에 안 뜬다 — 게이트 3중(①검색 RPC의 join rep INNER ②자동완성의 exists postings
-- ③상세의 infoReady = worksite && posting)이 공고 ≥1을 요구한다. 게이트를 푸는 건 검색 본류라
-- blast radius가 커서 껍데기 posting으로 통과시킨다.
-- 자격은 국가근로 규칙값(long/학부만/재학만) — 기본값(3=미정/unknown)으로 두면 유저가 "학부생만"·"장기"
-- 필터를 켜는 순간 57개가 전부 사라진다. 20260708100000_national_backfill의 선례와 같은 값.
insert into postings (worksite_id, is_active, is_placeholder, work_duration_type, eligible_degree, eligible_status)
select w.id, false, true, 'long', 0, 0
  from worksites w
 where w.university_id = 1
   and w.type = 'national'
   and w.location_type = 'on_campus'
   and not exists (
     select 1 from postings p
      where p.worksite_id = w.id and p.is_placeholder = true
   );
```

- [ ] **Step 3: SQL 문법·행수 자체 점검**

Docker가 없어 `db reset`을 못 돌리므로 눈으로 확인한다:

```bash
cd "c:/새 폴더" && grep -c "^  ('" web/supabase/migrations/20260716180000_oncampus_national_seed.sql
```
기대: `57`

```bash
cd "c:/새 폴더" && grep -n "w.type <> 'national'" web/supabase/migrations/20260716180000_oncampus_national_seed.sql
```
기대: **출력 없음** (옛 조건이 남아 있으면 안 됨)

```bash
cd "c:/새 폴더" && grep -n "least(greatest(coalesce(p_limit" web/supabase/migrations/20260716180000_oncampus_national_seed.sql
```
기대: 1줄 — limit 상한이 살아있는지(옛 파일에서 복사했다면 없다)

`values` 목록 마지막 행에 쉼표가 없는지 육안 확인.

- [ ] **Step 4: 커밋**

```bash
cd "c:/새 폴더" && git add web/supabase/migrations/20260716180000_oncampus_national_seed.sql && git commit -m "feat(db): 교내 국가근로 근무지 57개 시드 + placeholder posting

명부(고려대 본교 학부·일반교내 160행 → 근로지명 dedup 57개)를 national+on_campus
worksite로 시드하고, 근무지당 껍데기 posting 1개(is_active=false)로 공고 게이트를 통과시킨다.
출시 전 리뷰 선적립이 목적.

is_placeholder 컬럼은 미래 교체용 안전표식 — 공고 시즌에 크롤로 진짜 공고를 넣을 때
껍데기만 골라 지우기 위한 것(그땐 리뷰가 붙어 있어 통짜 wipe 불가).

search_worksite_cards의 지역 필터 조건도 함께 고친다: 'w.type <> national'로 교내를
판정하던 것은 national+on_campus가 0개일 때만 우연히 맞던 것이고, 이 시드가 그 전제를
깬다. 원래 의도대로 location_type 기준으로 바꿔야 교내 region을 NULL로 둘 수 있다.
부수 영향은 id=6660 1행뿐 → region='서울' 픽스.

db push는 아직 하지 않는다(디스코드 공유·백엔드 상의 후).

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: 지역 필터 안내 문구 수정

**Files:**
- Modify: `web/src/components/AdvancedSearch.jsx:13`

**Interfaces:**
- Consumes: Task 1의 RPC 조건 변경 (`location_type = 'on_campus'` 우회). 문구는 그 동작을 설명한다.

- [ ] **Step 1: 문구 교체**

기존:
```jsx
  { key: 'region', label: '지역', options: REGIONS, note: '지역은 국가근장에만 적용돼요' },
```

변경:
```jsx
  { key: 'region', label: '지역', options: REGIONS, note: '지역은 교외 근무지에만 적용돼요' },
```

기존 문구는 부정확해진다 — 수정 후 교내 국가근로도 국가근장이지만 지역 필터를 받지 않는다. "교외"가 실제 동작(`location_type`)과 일치하고 유저에게도 더 정확하다.

- [ ] **Step 2: 빌드 확인**

```bash
cd "c:/새 폴더/web" && npm run build
```
기대: 에러 없이 완료.

- [ ] **Step 3: 커밋**

```bash
cd "c:/새 폴더" && git add web/src/components/AdvancedSearch.jsx && git commit -m "fix(search): 지역 필터 안내 문구를 실제 동작에 맞게 — '교외 근무지에만'

RPC 조건이 type 기준에서 location_type 기준으로 바뀌면서 교내 국가근로도
지역 필터를 받지 않게 됐다. '국가근장에만'은 이제 부정확하다.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: push 후 검증 (⚠️ 이번 범위 밖 — 디스코드 공유·백엔드 상의 후)

**이 태스크는 실행하지 않는다.** `db push`는 배경록이 직접, 팀 공유 후에 한다(CLAUDE.md §3.1·§3.3). 아래는 그때 쓸 체크리스트다.

```bash
cd "c:/새 폴더/web" && npx supabase db push
```

- [ ] **행수 확인**

```sql
select count(*) from worksites where type='national' and location_type='on_campus';  -- 57
select count(*) from postings where is_placeholder;                                   -- 57
select count(*) from worksites where location_type='off_campus' and region is null;   -- 0
```

- [ ] **회귀 확인 — 가장 중요**

검색 RPC는 6,672개 전 근무지의 경로다. 지역 필터가 교외에 대해 이전과 같은지 대조한다.
⚠️ **반드시 `count='exact'`로 잴 것** — PostgREST는 행 반환을 1000개에서 자르므로, `.limit(3000)` 후 클라에서 세면
1000개 표본을 전체 분포로 착각한다(이 작업 중 실제로 그 실수가 있었다).

실측 결과(2026-07-16 push 후, 17개 지역 전부 테이블 count == RPC total_count):
서울 988 / 경기 1441 / 대구 470 / 광주 439 / 인천 357 / 충남 259 / 대전 215 / 충북 277 / 경남 345 /
부산 408 / 전남 369 / 경북 344 / 전북 223 / 강원 195 / 울산 131 / 제주 89 / 세종 65 = 6,615
(교외 총계 6,647과 32행 차이 = region 미정규화 행 — 아래 별건 참고)

```sql
select region, count(*) from worksites
 where type='national' and location_type='off_campus' and deleted_at is null
 group by region order by count(*) desc;
```

- [ ] **grgr.kr 수동 확인**
  - 고급검색 지역=서울 → 교내 57개가 **지역과 무관하게 계속 뜨는지**
  - 고급검색 학부생 + 장기 필터 → 57개가 살아있는지 (자격 규칙값이 먹었는지)
  - 상세 페이지 진입 → 빈 화면이 아닌지 (공고 게이트 통과)
  - "간호대학행정팀" 검색 → **카드 2개**(국가근로/교내근로). **이건 정상이다** — 별개 제도라 의도된 동작(2026-07-16 결정).
  - 홈에 "모집완료" 배지로 노출되는지

- [ ] **문서 갱신** (CLAUDE.md §5 — 스키마 바꾸면 README·docs 같이)
  - `web/supabase/README.md` — 마이그레이션 목록에 `20260716180000` 항목 추가(적용 상태·담당·요지)
  - `docs/db-schema.md` — `postings.is_placeholder` 컬럼 + `search_worksite_cards` 지역 조건 변경 반영

---

## 롤백

데이터는 순수 추가라 되돌리기 쉽다.

```sql
-- 시드만 제거 (리뷰가 붙기 전에만 안전 — 붙은 뒤엔 worksite를 지우면 리뷰가 cascade로 날아간다)
delete from postings where is_placeholder and worksite_id in (
  select id from worksites where university_id=1 and type='national' and location_type='on_campus');
delete from worksites where university_id=1 and type='national' and location_type='on_campus';
-- RPC는 20260713172824의 본문으로 create or replace 하면 원복
```

⚠️ **리뷰가 하나라도 붙은 뒤엔 worksite delete를 하지 말 것** — `reviews.worksite_id`가 `on delete cascade`다.
