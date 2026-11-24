# 교내 국가근로 근무지 시드 (고려대 본교 학부) — 설계

- 날짜: 2026-07-16 · 담당: 배경록
- 관련: `CLAUDE.md §3`, `web/supabase/README.md`
- 선행 논의: 2026-07-15 설계 합의(메모리 `project-national-oncampus-worksite-seed`) — "DB 구현은 백엔드와 상의 후" 보류 상태였음

## 목적

정식 출시 전, 고려대 본교 학부의 **교내 국가근로 근무지**를 앱에 올려 유저가 리뷰를 미리 쌓게 한다.
소스는 `붙임. '24~'26년 연도별 유형별 근로지 현황.xlsx`(국가장학재단 명부).

## 범위

당초 "리뷰·근무지·공고 전부 wipe 후 재적재"로 출발했으나, 확인 결과 지울 대상이 사실상 없다:

| 대상 | 현재 | 이번 작업 |
|---|---|---|
| `reviews` | **0건** (2026-07-16 확인) | 건드리지 않음 |
| `worksites` `type='national'` (교외) | 6,647개 | 건드리지 않음 |
| `worksites` `type='school'` (KUPID 교내) | 25개 | 건드리지 않음 — **새 KUPID 크롤 시점에 교체** |
| `worksites` `national`+`on_campus` | **0개** | **← 명부 57개 신규 insert** |

데이터는 순수 추가다. 다만 아래 "지역 필터" 항목 때문에 **검색 RPC 한 줄 수정이 함께 간다.**

**이번 범위 밖(별건):**
- KUPID 교내 학교근로 재크롤 → 그 시점에 `school` 25개 delete + insert 교체
- 교외 국가근로 갱신

## 데이터

명부에서 `기관명 = '고려대학교(본교) 학부'` AND `유형 = '일반교내'` → 160행.
`근로지명` 기준 dedup(**최신 연도 우선**) → **57개 근무지**.

연도별 근로지 수는 2024:52 / 2025:55 / 2026:53인데 합집합이 57 — 대부분 매년 반복되는 고정 부서다.
2026 목록에 없는 4곳(노동대학원행정팀·정경대학 평화연구소·체육지원팀·학생지원팀(공통))도 **포함한다**: 24/25년 근무자가 리뷰를 쓸 수 있어야 하고, `is_active=false`("모집완료") 표시와도 일관된다.

검증 완료(2026-07-16): 57행 널·빈 문자열 0, 홑따옴표 0(SQL 리터럴 이스케이프 불필요), `근로지명` 최대 28자 / 주소 최대 46자 — 컬럼 길이 제한 내.

### `worksites` 매핑

| 컬럼 | 값 | 비고 |
|---|---|---|
| `university_id` | `1` | 고려대학교/서울 (유일 행) |
| `type` | `'national'` | 국가근로장학금 제도 |
| `location_type` | `'on_campus'` | **이 조합은 현재 DB에 0개** |
| `organization_name` | `'고려대학교(본교) 학부'` | 명부 기관명 그대로 |
| `workplace_name` | 명부 `근로지명` | |
| `region` | **`NULL`** | 교내는 지역 필터 대상이 아니다 — 아래 참조 |
| `address` | 명부 `소재지(주소)`에서 `[02841] ` 우편번호 접두 제거 | 기존 national 포맷과 일치 |

### 지역 필터 — RPC 조건 수정 (`search_worksite_cards`)

교내 근무지의 `region`은 **NULL이 맞다.** 유저는 자기 학교 소속이라 교내 근무지를 지역으로 거를 일이 없고, 교내에 지역을 박아 넣으면 학교를 추가할 때마다 지역을 일일이 채워야 하는 부채가 된다.

문제는 현재 조건이 그걸 지탱하지 못한다는 것이다:

```sql
-- 현재 (20260708110000)
and (p_regions is null or w.type <> 'national' or w.region = any(p_regions))
```

이 마이그레이션의 **의도는 "교내는 지역 필터 무시"** 였다(헤더에 그렇게 적혀 있다). 당시엔 `national`+`on_campus`가 0개라 **"교내" == "school"이 우연히 참**이었고, 그래서 `type`으로 조건을 썼다. 이번 시드가 그 우연을 깨는 첫 데이터다 — `type='national'`이면서 교내이므로, region이 NULL이면 지역 필터를 켠 유저에게 57개가 통째로 사라진다.

조건을 원래 의도대로 `location_type` 기준으로 고친다:

```sql
-- 수정
and (p_regions is null or w.location_type = 'on_campus' or w.region = any(p_regions))
```

시그니처 불변 → `create or replace`, `DROP` 불필요. `20260708110000`과 같은 방식이다.

**부수 영향 — 정확히 1행.** `id=6660` 미래성장연구원(`school`/`off_campus`/`region=NULL`)은 지금 `type<>'national'`이라 필터를 우회하지만, 수정 후엔 교외로 분류돼 필터 대상이 되고 region이 없어 사라진다. 주소에 "서울 강남구"로 명시돼 있으므로 `region='서울'` UPDATE로 정리한다. 나머지 6,647개 교외 국근장은 region이 전부 채워져 있어 무영향(`national & region IS NULL` = 0 확인).

> 새 KUPID 크롤러는 **`off_campus` 근무지의 `region`을 반드시 채워야 한다.** 비면 지역 필터에서 조용히 사라진다. (`school` 25개는 크롤 시 교체되므로 6660 픽스는 그때까지의 임시 정리다.)

**UI 문구도 함께 고친다** — `web/src/components/AdvancedSearch.jsx:13`:
`'지역은 국가근장에만 적용돼요'` → `'지역은 교외 근무지에만 적용돼요'`. 수정된 동작과 일치하고 유저에게 더 정확하다.

### `postings` — placeholder 1개/근무지

공고 없는 worksite는 앱에 안 뜬다. 게이트가 3중으로 공고 ≥1을 요구한다:
①검색 RPC의 `join rep`(INNER) ②자동완성의 `exists postings` ③상세의 `infoReady = worksite && posting`.
게이트를 푸는 대신(검색 본류라 blast radius가 큼) **껍데기 posting 1개**로 통과시킨다.

| 컬럼 | 값 | 근거 |
|---|---|---|
| `worksite_id` | FK | 유일한 NOT NULL |
| `is_active` | `false` | 배지 "모집완료" — 이 데이터에 맞는 라벨. 홈(`fetchHomePostings`)은 is_active 필터 없이 정렬만 하므로 노출됨 |
| `is_placeholder` | `true` | **신규 컬럼** — 아래 참조 |
| `work_duration_type` | `'long'` | 국가근로 규칙값 |
| `eligible_degree` | `0` (학부만) | 국가근로 규칙값 |
| `eligible_status` | `0` (재학만) | 국가근로 규칙값 |

나머지 컬럼은 null/기본값.

**자격 컬럼에 규칙값을 박는 이유:** 기본값(3=미정 / `unknown`)으로 두면 유저가 "학부생만"·"장기" 필터를 켜는 순간 57개가 전부 사라진다(필터가 opt-in이라 평소엔 뜨지만 켜면 탈락). `20260708100000_national_backfill`이 KOSAF 임포터의 미정값을 같은 규칙값으로 백필한 선례를 따른다.

### `is_placeholder` 컬럼 (postings 신규)

지금 쓰려는 게 아니라 **미래 교체용 안전표식**이다.
공고 시즌에 크롤로 진짜 공고를 넣을 때 `delete from postings where worksite_id = X and is_placeholder = true` 후 insert 한다.
그땐 유저 리뷰가 이미 붙어 있어 통짜 wipe가 불가능하고, 껍데기만 수술 제거해야 한다. 플래그가 없으면 "null 패턴"으로 추측해야 해서 위험하다.
리뷰는 `worksite_id`에 붙으므로 postings만 교체해도 리뷰는 무손상이다.

## 실행 — 마이그레이션 SQL 한 개

한 파일에 4가지를 담고 `db push`로 실행한다:
1. `is_placeholder` 컬럼 추가
2. `search_worksite_cards` 지역 조건 수정 (`create or replace`)
3. `id=6660` region 픽스
4. worksites 57행 + placeholder postings 57행 insert

**시드와 RPC 픽스를 묶는 이유:** 서로의 전제다. 따로 가면 "시드만 들어가고 RPC 미적용" 구간에 57개가 지역 필터에서 사라진다.

**왜 스크립트가 아닌가:** `web/.env.local`엔 anon 키뿐이고, RLS 컷오버 이후 anon으론 insert가 막힌다(`postings`는 SELECT조차 `permission denied`). 기존 `crawling_scripts/import_to_supabase.py`는 anon 키를 쓰므로 **지금 그대로는 돌아가지 않는다.** 스크립트로 가려면 service_role 키를 새로 발급해야 하는데, 57행엔 과하고 키 노출 리스크(특히 `VITE_` 접두어를 붙이면 프론트 번들에 그대로 실림)만 생긴다. 마이그레이션은 service_role 키가 아예 필요 없고, `CLAUDE.md §3`과 정확히 일치하며, 공지 insert(`20260716130000`)라는 선례도 있다.

SQL 에디터 수동 편집은 `CLAUDE.md`가 금지한다.

### 멱등성

`db reset`·재push에서 중복되지 않아야 한다.

- 컬럼: `alter table postings add column if not exists is_placeholder boolean not null default false`
- worksites: `where not exists (select 1 from worksites where university_id=1 and type='national' and location_type='on_campus' and workplace_name = <값>)`
- postings: worksite를 `workplace_name`으로 되찾아 `where not exists (... is_placeholder = true)`

`worksites`에 유니크 제약이 없으므로(명부 dedup이 필요했던 이유) `on conflict`를 쓸 수 없다. `where not exists`로 방어한다.

### 검증

push 후:
1. `select count(*) from worksites where type='national' and location_type='on_campus'` → 57
2. `select count(*) from postings where is_placeholder` → 57
3. **회귀 확인(가장 중요)**: 지역 필터 켠 검색이 기존 교외 국근장 6,647개에 대해 이전과 동일한 결과를 내는지 — `worksites` 테이블의 지역별 exact count와 RPC `total_count`를 대조한다.
   ⚠️ 분포를 잴 땐 **반드시 `count='exact'`**. PostgREST는 행 반환을 1000개에서 자르므로, `.limit(3000)` 후 클라에서 세면 1000개 표본을 전체 분포로 착각한다.
4. 고급검색에서 지역=서울 필터 → 교내 57개가 **지역과 무관하게 계속 뜨는지**
5. 고급검색에서 학부생 + 장기 필터 → 57개가 살아있는지
6. 상세 페이지 진입 → 빈 화면이 아닌지(게이트 통과 확인)
7. "간호대학행정팀" 검색 → 카드 2개(국가근로/교내근로). 아래 참조 — 정상이다.

## 알려진 결과 — 부서 중복 노출

명부 57개와 기존 KUPID `school` 25개에 같은 부서가 여럿 겹친다(간호대학행정팀·경영대학행정팀·이과대학행정팀·학부대학행정팀·보건과학대학행정팀 등).
검색 시 **카드 2개가 뜨고 리뷰도 둘로 갈린다.** 이건 **의도된 동작**이다(2026-07-16 결정) — 국가근로와 교내근로는 별개 제도라 근로조건·시급이 다르고, `type`이 다르니 별개 worksite가 맞다. 합치려면 제도 구분을 posting 레벨로 내려야 해서 스키마·RPC를 크게 건드려야 한다.

## 후속 (별건, 나중)

- 초기엔 교내 국근장이 전부 `is_active=false`라 `fetchHomePostings`의 `order(is_active).limit(20)`가 사실상 삽입순으로 20개를 노출한다(무의미하고 SQL이 순서를 보장하지도 않음). 리뷰가 쌓이면 `view_count`/`review_count` 2차 정렬 고려. 검색 RPC엔 이미 `worksite_id` tie-breaker가 있고 홈에만 없다.
- 실제 공고의 학기 구조화(`work_year`/`work_semester` 컬럼)
- KUPID 교내 학교근로 재크롤 → `school` 25개 교체 (⚠️ `off_campus` region 채울 것)
