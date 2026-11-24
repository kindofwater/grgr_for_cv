# 근장찾기 고급검색(필터) 설계

- 날짜: 2026-06-27
- 담당: (작업자)
- 대상: `web/src/pages/Search.jsx` (근장찾기) — "고급검색 ▾" 토글
- 선행: `2026-06-27-search-server-side-design.md`(서버측 검색 RPC). 이 spec은 그 `search_worksite_cards` RPC를 **확장**한다.

---

## 0. 배경 / 문제

현재 [Search.jsx](../../../web/src/pages/Search.jsx)의 "고급검색 ▾" 버튼은 **핸들러 없는 빈 껍데기**(debt-C). 펼침 패널·필터 동작이 전혀 없다.

## 1. 목표 (범위)

토글을 누르면 search-head 아래로 필터 패널이 펼쳐지고, 선택한 태그에 맞는 근무지만 결과로 보이게 한다. 필터는 **"반영하여 검색"을 눌러야** 적용된다(실시간 아님). 검색어와 **AND로 결합**된다.

비범위:
- 점수 서버 게이팅(debt-B), 리뷰쓰기 버튼 재디자인(#2) — 별건.
- 우대(계열) 목록 완성 — `PREFFEREDTRACK` 배열은 작업자가 추후 채운다(현재 `추가예정` placeholder 포함).

## 2. 상호작용 명세

### 2.1 그룹 / 선택 방식
| 그룹 | 버튼(라벨) | 선택 |
|------|-----------|------|
| 근장유형 | 국가근장 / 학교근장 | **다중(OR)** |
| 교내외 | 교외 / 교내 | **다중(OR)** |
| 지역 | `REGIONS`(서울/경기/…17시도) | **다중(OR)** |
| 기간 | 장기 / 단기 | **단일(라디오)** |
| 우대 | `PREFFEREDTRACK`(인문계열/의약계열/…) | **다중(OR)** |
| 학위 | 학부생만 / 대학원생만 | **단일(라디오)** |
| 학적 | 재학생만 / 휴학생만 | **단일(라디오)** |

- 그룹 내 선택 0개 = 그 차원 **무필터**(상관없음).
- 단일(라디오) 그룹: 한 번에 하나. 켜진 버튼을 다시 누르면 off(무필터).
- 그룹 간 = **AND**. 그룹 내 다중 = **OR**.

### 2.2 필터 의미 (매핑)
필터는 **대표공고 1개**(active 우선 → 최신, 화면 태그가 나오는 그 공고) 기준으로 검사한다.

| 그룹 | 컬럼(기준) | 라벨 → 값 |
|------|-----------|-----------|
| 근장유형 | `worksite.type` | 국가근장→`national`, 학교근장→`school` |
| 교내외 | `worksite.location_type` | 교외→`off_campus`, 교내→`on_campus` |
| 지역 | `worksite.region` | 라벨=값 (예 서울→`서울`) |
| 기간 | 대표공고 `work_duration_type` | 장기→`long`, 단기→`short` |
| 우대 | 대표공고 `preferred_track` | 라벨=값 (예 이공계열→`이공계열`) |
| 학위 | 대표공고 `eligible_degree` | 학부생만→`{0,2,3}`, 대학원생만→`{1,2,3}` |
| 학적 | 대표공고 `eligible_status` | 재학생만→`{0,2,3}`, 휴학생만→`{1,2,3}` |

> **학위/학적은 "지원 가능" 의미.** "학부생만" 버튼은 *학부생이 지원 가능한* 공고(학부전용 0 + 둘다 2 + 미정 3)를 잡는다. 반대 전용(대학원생만=1)만 제외. 라벨은 "학부생만" 그대로 두되 동작은 지원가능 기준(사용자 직관 우선).

### 2.3 지역 ↔ 국가근장
- 지역 필터는 `worksite.region in (...)` 만 검사한다.
- 학교근장은 `region`이 비어 있어(태그도 안 뜸) 지역 필터를 걸면 **자동으로 국가근장만** 남는다 — 별도 강제 로직 없음.
- 지역 라벨 옆 **(?)** 인라인 버튼 → 작은 말풍선(~100px, 모달 아님): **"지역은 국가근장에만 적용돼요"**. 재클릭/바깥클릭으로 닫힘. 순수 안내.
- ⚠️ **검증 필요(구현 중 1회):** 학교근장 `worksite.region`이 실제로 전부 NULL/빈값인지 확인. 값이 있으면 학교근장도 지역으로 잡혀 안내와 어긋남 → 그 경우 지역 필터에 `type='national'` 가드를 추가한다.

### 2.4 적용 / 초기화 / 결합
- **반영하여 검색**: pending 선택을 적용 필터로 확정 → 1페이지부터 재검색. 패널은 **열어둔다**.
- **초기화**: 고급검색 선택 + **검색어까지 전부 비우고** 완전 초기 상태(전체 결과)로. 패널은 열어둔 채 비워진다.
- 패널을 열면 pending 선택은 **현재 적용된 필터로 초기화**된다(지금 뭐가 걸렸는지 보이고 거기서 수정).
- **검색어 결합**: 적용 필터는 검색어와 **AND**. 검색어 Enter/버튼도 현재 적용 필터와 함께 검색된다.
- 필터는 실시간 아님(버튼만 토글되고, 반영 전엔 결과 안 바뀜).

## 3. 컴포넌트 / 데이터 흐름

```
[Search.jsx] (page)
  ├ 토글 "고급검색 (n) ▾"  ←n=적용 필터 개수
  ├ <AdvancedSearch onApply={...} onReset={...} />   (펼침 패널)
  │     └ pending 선택 상태 관리 → 반영 시 onApply(selection)
  └ appliedFilters state → buildSearchFilters → searchWorksiteCards({query, sort, page, perPage, filters})
```

- **`components/AdvancedSearch.jsx`** (+ `.css`): 패널 UI + pending 선택 상태. props:
  - `initial` — 현재 적용된 selection(패널 열 때 pending 초기값으로).
  - `onApply(selection)` — "반영하여 검색" 클릭 시 현재 선택 전달.
  - `onReset()` — "초기화" 클릭.
  - 옵션은 `lib/profileOptions`의 `REGIONS`·`PREFFEREDTRACK`, 나머지는 고정 라벨.
  - 버튼 off = `.btn-login`(투명+파란테두리), on = `.btn-signup-nav`(파란배경+흰글씨) 톤 재사용(전용 클래스로 복제).
  - 하단 [반영하여 검색](채운 버튼) · [초기화](테두리 버튼). 지역 (?) 말풍선.
- **`Search.jsx`**: `showAdvanced`(패널 토글), `appliedFilters`(적용된 selection) state. 토글에 적용 필터 개수 배지. `searchWorksiteCards` 호출 시 `filters: buildSearchFilters(appliedFilters)` 동봉. 검색어 effect deps에 `appliedFilters` 추가. 초기화 시 `appliedFilters=빈`, `query/submittedQuery=''`.

> 의존성 방향 준수: page(Search) → component(AdvancedSearch) → lib(profileOptions, searchFilters). 역참조 없음.

## 4. lib 순수함수 (`lib/searchFilters.js` + 테스트)

```
buildSearchFilters(selection) → {
  p_types, p_locations, p_regions, p_durations, p_tracks, p_degrees, p_statuses
}
```
입력 `selection`(UI 라벨 보관):
```js
{
  type: string[],      // ['국가근장', ...]
  location: string[],  // ['교외', ...]
  region: string[],    // ['서울', ...]
  duration: string|null,  // '단기' | '장기' | null
  track: string[],     // ['이공계열', ...]
  degree: string|null, // '학부생만' | '대학원생만' | null
  status: string|null, // '재학생만' | '휴학생만' | null
}
```
규칙:
- 빈 배열 / null → 해당 `p_*` = **null**(무필터).
- type: 국가근장→`national`, 학교근장→`school`.
- location: 교외→`off_campus`, 교내→`on_campus`.
- region/track: 라벨 그대로 값 (passthrough).
- duration(단일): 단기→`['short']`, 장기→`['long']`.
- degree(단일): 학부생만→`[0,2,3]`, 대학원생만→`[1,2,3]`.
- status(단일): 재학생만→`[0,2,3]`, 휴학생만→`[1,2,3]`.

출력 예: `selection.degree='학부생만', region=['서울','경기']` → `{ p_degrees:[0,2,3], p_regions:['서울','경기'], 나머지 null }`.

테스트: 각 매핑, 빈 그룹→null, 학위/학적 확장, 단일 라디오 scalar→배열.

## 5. DB (`search_worksite_cards` 확장 — 새 마이그레이션)

기존 RPC(4인자)에 배열 필터 7개 추가. **시그니처 변경 → `DROP FUNCTION IF EXISTS` 먼저** 후 재생성(CLAUDE.md §3-4).

신규 시그니처:
```sql
search_worksite_cards(
  p_query text default null,
  p_sort  text default 'recommend',
  p_limit int default 20,
  p_offset int default 0,
  p_types     text[] default null,
  p_locations text[] default null,
  p_regions   text[] default null,
  p_durations text[] default null,
  p_tracks    text[] default null,
  p_degrees   int[]  default null,
  p_statuses  int[]  default null
)
```
`joined` CTE의 `where`에 필터 추가(전부 "null이면 무시"):
```sql
and (p_types     is null or w.type          = any(p_types::worksite_type_e[]))
and (p_locations is null or w.location_type = any(p_locations::location_type_e[]))
and (p_regions   is null or w.region        = any(p_regions))
and (p_durations is null or r.work_duration_type = any(p_durations::duration_type_e[]))
and (p_tracks    is null or r.preferred_track     = any(p_tracks))
and (p_degrees   is null or r.eligible_degree::int = any(p_degrees))
and (p_statuses  is null or r.eligible_status::int = any(p_statuses))
```
- worksite 필드(type/location/region)는 `w`, 대표공고 필드(duration/track/degree/status)는 `r`(rep CTE) 기준 → "대표공고 기준" 일관.
- enum 컬럼은 `text[]`→enum[] 캐스트. degree/status는 `::int` 캐스트로 `int[]` 비교.
- 나머지(dedup·정렬·페이징·총개수)는 기존과 동일.
- 재생성 후 `grant execute on function search_worksite_cards(text,text,int,int,text[],text[],text[],text[],text[],int[],int[]) to authenticated;`

## 6. data 계층 (`worksiteQueries.js`)

`searchWorksiteCards`에 `filters` 인자 추가:
```js
export async function searchWorksiteCards({ query, sort, page, perPage, filters }) {
  const f = filters ?? {}
  const { data, error } = await supabase.rpc('search_worksite_cards', {
    p_query: escapeLike(query ?? ''),
    p_sort: sort,
    p_limit: perPage,
    p_offset: (page - 1) * perPage,
    p_types: f.p_types ?? null,
    p_locations: f.p_locations ?? null,
    p_regions: f.p_regions ?? null,
    p_durations: f.p_durations ?? null,
    p_tracks: f.p_tracks ?? null,
    p_degrees: f.p_degrees ?? null,
    p_statuses: f.p_statuses ?? null,
  })
  if (error) throw error
  const rows = data ?? []
  const total = rows.length ? Number(rows[0].total_count) : 0
  return { cards: rows.map(toCard), total }
}
```
`filters` 미전달 시 전부 null(=기존 동작) → 호환 유지.

## 7. UI 세부

- 토글 라벨: 적용 필터 0개면 `고급검색 ▾`, n개면 `고급검색 (n) ▾`. **n = 적용된 선택지(버튼) 총 개수** (그룹 수 아님 — 예 지역 서울+경기 + 단기 = 3). 펼침 시 `▴`.
- 패널: search-head 아래. 각 줄 `라벨 | [버튼 wrap]`. 모바일에서 버튼 wrap.
- 버튼: off/on 두 톤. 클릭으로 토글. 단일 그룹은 같은 그룹 내 하나만 on.
- 지역 (?): 인라인 작은 버튼, 클릭 시 말풍선. 위치는 (?) 근처 absolute, z-index로 떠 있게.
- 하단: [반영하여 검색][초기화].

## 8. 엣지 / 에러

- 필터 조합 결과 0 → 기존 빈 상태 문구(`검색 결과가 없어요.`).
- 모순 조합(예 유형=학교근장 + 지역=서울): region이 학교근장엔 없어 결과 0 — 정상(말풍선이 사전 안내).
- `PREFFEREDTRACK`의 `추가예정` placeholder는 실제 track이 아니라 결과 0 → 작업자가 배열을 실제 계열로 채우면 자동 해결.
- enum 캐스트: 프론트는 유효 값만 보냄(라벨 매핑 고정) → 캐스트 에러 없음.

## 9. 테스트 / 검증

- `lib/searchFilters.test.js`: `buildSearchFilters` 매핑·확장·빈그룹 null.
- DB: sandbox `db push` 후 RPC를 필터 인자로 호출해 동작 확인(읽기전용 select).
- 수동: 그룹별 토글(다중/단일), 반영 시 결과 변화, 초기화 전체리셋, 검색어+필터 AND, 지역 (?) 말풍선, 토글 배지 개수, 잠금 계정에서도 필터 동작(점수만 더미).

## 10. 마이그레이션 운영 (CLAUDE.md §3)

1. 디스코드 공유.
2. `migration new advanced_search_filters` → `DROP FUNCTION IF EXISTS search_worksite_cards(text,text,int,int);` + 신규 정의 + grant. 헤더 2줄.
3. sandbox `db push` 검증.
4. 본인이 prod `db push`(push 전 디스코드).
