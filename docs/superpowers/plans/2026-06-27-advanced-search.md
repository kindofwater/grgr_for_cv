# 근장찾기 고급검색(필터) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** "고급검색 ▾" 토글로 펼쳐지는 필터 패널을 만들어, 선택한 태그(유형·교내외·지역·기간·우대·학위·학적)에 맞는 근무지만 서버에서 걸러 보여준다.

**Architecture:** UI 패널은 `components/AdvancedSearch.jsx`로 분리(pending 선택 관리). 라벨→RPC값 변환은 `lib/searchFilters.js` 순수함수로 빼서 테스트. `search_worksite_cards` RPC에 배열 필터 파라미터를 추가(DROP+재생성)하고, `Search.jsx`가 적용 필터를 검색어와 AND로 합쳐 호출한다.

**Tech Stack:** React 19 + Vite, react-router-dom 7, Supabase, Vitest 4, Supabase CLI 마이그레이션.

## Global Constraints

- DB 통신은 `web/src/data/`에서만. (CLAUDE.md §2)
- DB 변경은 마이그레이션으로만. 헤더 2줄 필수(`-- 목적:` / `-- 날짜: YYYY-MM-DD · 담당:`). 시그니처 변경 시 `DROP FUNCTION IF EXISTS …` 먼저. (CLAUDE.md §3)
- 의존성 방향: `pages → components / data / lib`. 역참조 금지.
- 선행 RPC: `search_worksite_cards(text,text,int,int)` (마이그레이션 `20260627065818_search_worksite_rpc.sql`). 이 플랜은 그걸 확장한다.
- 옵션 상수: `lib/profileOptions.js`의 `REGIONS`, `PREFFEREDTRACK`(미완 — 작업자가 추후 채움).
- 버튼 on/off 톤: `.btn-login`(투명+파란테두리=off) / `.btn-signup-nav`(파란배경+흰글씨=on) 참고(전용 클래스로 복제).
- 모든 명령은 `web/`에서. 커밋 메시지 끝: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`
- 작업 브랜치: `detail_choi_2`.

---

## File Structure

- `web/src/lib/searchFilters.js` (신규) — `buildSearchFilters(selection)` 순수함수.
- `web/src/lib/searchFilters.test.js` (신규) — 단위 테스트.
- `web/supabase/migrations/<ts>_advanced_search_filters.sql` (신규) — RPC DROP+재생성(필터 파라미터 추가).
- `web/src/data/worksiteQueries.js` (수정) — `searchWorksiteCards`에 `filters` 인자.
- `web/src/components/AdvancedSearch.jsx` (신규) — 필터 패널.
- `web/src/components/AdvancedSearch.css` (신규) — 패널 스타일.
- `web/src/pages/Search.jsx` (수정) — 토글·적용필터·배지·초기화 통합.
- `web/src/components/README.md` / `web/src/pages/README.md` (수정) — 문서 갱신.

---

## Task 1: lib/searchFilters.js — buildSearchFilters (TDD)

**Files:**
- Create: `web/src/lib/searchFilters.js`
- Test: `web/src/lib/searchFilters.test.js`

**Interfaces:**
- Consumes: 없음(순수).
- Produces: `buildSearchFilters(selection) → { p_types, p_locations, p_regions, p_durations, p_tracks, p_degrees, p_statuses }` (각 값은 배열 또는 null).
  - `selection` = `{ type:string[], location:string[], region:string[], duration:string|null, track:string[], degree:string|null, status:string|null }`

- [ ] **Step 1: 실패 테스트 작성**

`web/src/lib/searchFilters.test.js`:
```js
// web/src/lib/searchFilters.test.js
import { describe, it, expect } from 'vitest'
import { buildSearchFilters } from './searchFilters'

const EMPTY = { type: [], location: [], region: [], duration: null, track: [], degree: null, status: null }

describe('buildSearchFilters', () => {
  it('빈 선택은 전부 null', () => {
    expect(buildSearchFilters(EMPTY)).toEqual({
      p_types: null, p_locations: null, p_regions: null,
      p_durations: null, p_tracks: null, p_degrees: null, p_statuses: null,
    })
  })

  it('유형/교내외 라벨 → enum 값 배열', () => {
    const f = buildSearchFilters({ ...EMPTY, type: ['국가근장', '학교근장'], location: ['교외'] })
    expect(f.p_types).toEqual(['national', 'school'])
    expect(f.p_locations).toEqual(['off_campus'])
  })

  it('지역/우대는 라벨 그대로 passthrough', () => {
    const f = buildSearchFilters({ ...EMPTY, region: ['서울', '경기'], track: ['이공계열'] })
    expect(f.p_regions).toEqual(['서울', '경기'])
    expect(f.p_tracks).toEqual(['이공계열'])
  })

  it('기간 단일 → 배열', () => {
    expect(buildSearchFilters({ ...EMPTY, duration: '단기' }).p_durations).toEqual(['short'])
    expect(buildSearchFilters({ ...EMPTY, duration: '장기' }).p_durations).toEqual(['long'])
  })

  it('학위 지원가능 확장', () => {
    expect(buildSearchFilters({ ...EMPTY, degree: '학부생만' }).p_degrees).toEqual([0, 2, 3])
    expect(buildSearchFilters({ ...EMPTY, degree: '대학원생만' }).p_degrees).toEqual([1, 2, 3])
  })

  it('학적 지원가능 확장', () => {
    expect(buildSearchFilters({ ...EMPTY, status: '재학생만' }).p_statuses).toEqual([0, 2, 3])
    expect(buildSearchFilters({ ...EMPTY, status: '휴학생만' }).p_statuses).toEqual([1, 2, 3])
  })
})
```

- [ ] **Step 2: 실패 확인**

Run: `cd web && npx vitest run src/lib/searchFilters.test.js`
Expected: FAIL — `searchFilters.js` 없어 import 에러.

- [ ] **Step 3: 구현 작성**

`web/src/lib/searchFilters.js`:
```js
// 고급검색 선택(UI 라벨) → search_worksite_cards RPC 필터 파라미터. 순수함수. UI/DB 의존 없음.

const TYPE_MAP = { '국가근장': 'national', '학교근장': 'school' }
const LOC_MAP = { '교외': 'off_campus', '교내': 'on_campus' }
const DUR_MAP = { '단기': 'short', '장기': 'long' }
// 학위/학적: "지원 가능" 의미 — 반대 전용만 제외(2=둘다·3=미정 포함)
const DEGREE_MAP = { '학부생만': [0, 2, 3], '대학원생만': [1, 2, 3] }
const STATUS_MAP = { '재학생만': [0, 2, 3], '휴학생만': [1, 2, 3] }

// 빈 배열 → null
function arr(a) { return a && a.length ? a : null }
// 라벨 배열 → 값 배열(매핑), 빈 건 제외
function mapArr(labels, map) {
  const vals = (labels ?? []).map((l) => map[l]).filter((v) => v != null)
  return vals.length ? vals : null
}

export function buildSearchFilters(selection) {
  const s = selection ?? {}
  return {
    p_types: mapArr(s.type, TYPE_MAP),
    p_locations: mapArr(s.location, LOC_MAP),
    p_regions: arr(s.region),                      // 라벨=값
    p_durations: s.duration ? [DUR_MAP[s.duration]] : null,
    p_tracks: arr(s.track),                         // 라벨=값
    p_degrees: s.degree ? DEGREE_MAP[s.degree] : null,
    p_statuses: s.status ? STATUS_MAP[s.status] : null,
  }
}
```

- [ ] **Step 4: 통과 확인**

Run: `cd web && npx vitest run src/lib/searchFilters.test.js`
Expected: PASS (6 it 통과).

- [ ] **Step 5: 커밋**

```bash
git add web/src/lib/searchFilters.js web/src/lib/searchFilters.test.js
git commit -m "고급검색 lib: buildSearchFilters(선택→RPC 필터 파라미터) + 테스트

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: DB 마이그레이션 — search_worksite_cards 필터 확장

**Files:**
- Create: `web/supabase/migrations/<생성 타임스탬프>_advanced_search_filters.sql`

**Interfaces:**
- Consumes: 기존 `search_worksite_cards(text,text,int,int)`, 테이블 worksites/postings/reviews.
- Produces: `search_worksite_cards(text,text,int,int,text[],text[],text[],text[],text[],int[],int[])` — 필터 7종 추가, 반환 컬럼·정렬·페이징·총개수는 기존과 동일.

- [ ] **Step 1: 마이그레이션 파일 생성**

Run: `cd web && npx supabase migration new advanced_search_filters`
Expected: `web/supabase/migrations/<ts>_advanced_search_filters.sql` 생성. 경로 출력.

- [ ] **Step 2: SQL 작성**

생성된 파일에 아래 전체 붙여넣기(`담당`은 실제 작업자명):
```sql
-- 목적: 근장찾기 고급검색 — search_worksite_cards에 배열 필터(유형/교내외/지역/기간/우대/학위/학적) 추가
-- 날짜: 2026-06-27 · 담당: <이름>
-- 비고: 시그니처 변경(인자 추가) → 옛 4인자 함수 DROP 먼저. 필터는 전부 null이면 무시. 대표공고(r) 기준.

drop function if exists search_worksite_cards(text, text, int, int);

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
  p_statuses  int[]  default null
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
    from reviews where deleted_at is null group by worksite_id
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
      and (p_types     is null or w.type          = any(p_types::worksite_type_e[]))
      and (p_locations is null or w.location_type = any(p_locations::location_type_e[]))
      and (p_regions   is null or w.region        = any(p_regions))
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
  limit p_limit offset p_offset;
$$;

grant execute on function search_worksite_cards(text,text,int,int,text[],text[],text[],text[],text[],int[],int[]) to authenticated;
```

- [ ] **Step 3: 검증 (sandbox/Docker)**

디스코드 공유 후 sandbox `npx supabase db push`(또는 Docker `db reset`). 그 다음 읽기전용 확인:
```sql
-- 무필터(기존 동작 유지)
select worksite_id, total_count from search_worksite_cards(null,'recommend',5,0);
-- 국가근장 + 단기
select worksite_id, type, work_duration_type
from search_worksite_cards(null,'recommend',20,0, array['national'], null, null, array['short'], null, null, null);
-- 학부생 지원가능(0,2,3)
select worksite_id, eligible_degree
from search_worksite_cards(null,'recommend',20,0, null,null,null,null,null, array[0,2,3], null);
```
Expected: 무필터는 기존과 동일. 필터 호출은 조건 맞는 행만, `total_count`는 필터 적용된 전체수.

- [ ] **Step 4: 학교근장 region 검증노트 확인**

Run (읽기전용):
```sql
select count(*) from worksites where type='school' and region is not null and region <> '';
```
Expected: **0** 이어야 spec 가정(지역=국가근장 자동한정) 유지. 0이 아니면 `joined`의 region 필터를 `(p_regions is null or (w.type='national' and w.region = any(p_regions)))`로 바꾸고 재push.

- [ ] **Step 5: prod 반영 + 커밋**

push 전 디스코드 한 마디 → `cd web && npx supabase db push`.
```bash
git add web/supabase/migrations/
git commit -m "검색 RPC 필터 확장: 유형/교내외/지역/기간/우대/학위/학적 (DROP+재생성)

search_worksite_cards에 배열 필터 7종 추가. 전부 null이면 무시, 대표공고(r) 기준.
학위/학적은 확장된 정수배열로 받음(지원가능). authenticated grant.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: data 계층 — searchWorksiteCards에 filters 인자

**Files:**
- Modify: `web/src/data/worksiteQueries.js`

**Interfaces:**
- Consumes: RPC 새 시그니처(Task 2), `escapeLike`/`toCard`(기존).
- Produces: `searchWorksiteCards({ query, sort, page, perPage, filters })` — `filters` = `buildSearchFilters` 출력 또는 undefined(미전달 시 무필터).

- [ ] **Step 1: searchWorksiteCards 교체**

[worksiteQueries.js](../../../web/src/data/worksiteQueries.js)의 `searchWorksiteCards` 함수를 아래로 교체:
```js
export async function searchWorksiteCards({ query, sort, page, perPage, filters }) {
  const f = filters ?? {}
  const { data, error } = await supabase.rpc('search_worksite_cards', {
    p_query: escapeLike(query ?? ''),
    p_sort: sort,                         // 'recommend' | 'reviews'
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

- [ ] **Step 2: 테스트 + lint**

Run: `cd web && npx vitest run && npx eslint src/data/worksiteQueries.js`
Expected: 테스트 PASS, eslint 에러 없음.

- [ ] **Step 3: 커밋**

```bash
git add web/src/data/worksiteQueries.js
git commit -m "data: searchWorksiteCards에 filters 인자(고급검색 RPC 파라미터 전달)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: AdvancedSearch 컴포넌트 + CSS

**Files:**
- Create: `web/src/components/AdvancedSearch.jsx`
- Create: `web/src/components/AdvancedSearch.css`

**Interfaces:**
- Consumes: `REGIONS`, `PREFFEREDTRACK`(`lib/profileOptions`).
- Produces: `<AdvancedSearch initial={selection} onApply={(selection)=>{}} onReset={()=>{}} />`
  - `selection` shape: `{ type, location, region, track: string[], duration, degree, status: string|null }`.

- [ ] **Step 1: 컴포넌트 작성**

`web/src/components/AdvancedSearch.jsx`:
```jsx
import { useEffect, useRef, useState } from 'react'
import { REGIONS, PREFFEREDTRACK } from '../lib/profileOptions'
import './AdvancedSearch.css'

const MULTI = ['type', 'location', 'region', 'track']  // 다중(OR)
// 단일: duration, degree, status

const EMPTY = { type: [], location: [], region: [], duration: null, track: [], degree: null, status: null }

const GROUPS = [
  { key: 'type', label: '근장유형', options: ['국가근장', '학교근장'] },
  { key: 'location', label: '교내외', options: ['교외', '교내'] },
  { key: 'region', label: '지역', options: REGIONS, note: '지역은 국가근장에만 적용돼요' },
  { key: 'duration', label: '기간', options: ['장기', '단기'] },
  { key: 'track', label: '우대', options: PREFFEREDTRACK },
  { key: 'degree', label: '학위', options: ['학부생만', '대학원생만'] },
  { key: 'status', label: '학적', options: ['재학생만', '휴학생만'] },
]

export default function AdvancedSearch({ initial, onApply, onReset }) {
  const [sel, setSel] = useState(() => ({ ...EMPTY, ...(initial ?? {}) }))
  const [hintOpen, setHintOpen] = useState(false)
  const hintRef = useRef(null)

  // 패널 열릴 때(적용필터 바뀔 때) pending을 적용상태로 동기화
  useEffect(() => { setSel({ ...EMPTY, ...(initial ?? {}) }) }, [initial])

  // 말풍선 바깥 클릭 닫기
  useEffect(() => {
    function onDoc(e) { if (hintRef.current && !hintRef.current.contains(e.target)) setHintOpen(false) }
    document.addEventListener('mousedown', onDoc)
    return () => document.removeEventListener('mousedown', onDoc)
  }, [])

  function isOn(key, opt) {
    return MULTI.includes(key) ? sel[key].includes(opt) : sel[key] === opt
  }
  function toggle(key, opt) {
    setSel((prev) => {
      if (MULTI.includes(key)) {
        const cur = prev[key]
        return { ...prev, [key]: cur.includes(opt) ? cur.filter((x) => x !== opt) : [...cur, opt] }
      }
      return { ...prev, [key]: prev[key] === opt ? null : opt }  // 단일: 재클릭 시 해제
    })
  }
  function handleReset() {
    setSel({ ...EMPTY })
    onReset()
  }

  return (
    <div className="adv-search">
      {GROUPS.map((g) => (
        <div className="adv-row" key={g.key}>
          <div className="adv-label">
            {g.label}
            {g.note && (
              <span className="adv-hint" ref={g.key === 'region' ? hintRef : null}>
                <button type="button" className="adv-hint-btn"
                  onClick={() => setHintOpen((v) => !v)} aria-label="지역 안내">?</button>
                {hintOpen && <span className="adv-hint-pop">{g.note}</span>}
              </span>
            )}
          </div>
          <div className="adv-opts">
            {g.options.map((opt) => (
              <button type="button" key={opt}
                className={`adv-chip ${isOn(g.key, opt) ? 'on' : ''}`}
                onClick={() => toggle(g.key, opt)}>{opt}</button>
            ))}
          </div>
        </div>
      ))}
      <div className="adv-actions">
        <button type="button" className="adv-apply" onClick={() => onApply(sel)}>반영하여 검색</button>
        <button type="button" className="adv-reset" onClick={handleReset}>초기화</button>
      </div>
    </div>
  )
}
```

- [ ] **Step 2: CSS 작성**

`web/src/components/AdvancedSearch.css`:
```css
.adv-search {
  max-width: 660px; margin: 12px auto 0; display: flex; flex-direction: column; gap: 10px;
}
.adv-row { display: grid; grid-template-columns: 64px 1fr; gap: 10px; align-items: start; }
.adv-label { font-size: 13px; font-weight: 600; color: var(--text-sub); padding-top: 6px; display: flex; align-items: center; gap: 4px; position: relative; }
.adv-opts { display: flex; flex-wrap: wrap; gap: 6px; }
.adv-chip {
  background: transparent; border: 1px solid var(--primary); color: var(--primary-dark);
  padding: 5px 12px; border-radius: 16px; font-size: 13px; cursor: pointer; font-family: inherit;
  transition: background 0.12s, color 0.12s;
}
.adv-chip:hover { background: var(--primary-light); }
.adv-chip.on { background: var(--primary); border-color: var(--primary); color: white; }
.adv-chip.on:hover { filter: brightness(1.05); background: var(--primary); }

/* 지역 (?) 말풍선 */
.adv-hint { position: relative; display: inline-flex; }
.adv-hint-btn {
  width: 16px; height: 16px; border-radius: 50%; border: 1px solid var(--border-strong);
  background: white; color: var(--text-muted); font-size: 11px; line-height: 1; cursor: pointer;
  display: inline-flex; align-items: center; justify-content: center; padding: 0; font-family: inherit;
}
.adv-hint-pop {
  position: absolute; top: 22px; left: 0; z-index: 30; width: 160px;
  background: var(--text); color: white; font-size: 12px; font-weight: 400;
  padding: 8px 10px; border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,0.18);
}

.adv-actions { display: flex; justify-content: center; gap: 10px; margin-top: 6px; }
.adv-apply {
  background: var(--primary); border: 1px solid var(--primary); color: white;
  padding: 8px 20px; border-radius: 8px; font-size: 14px; font-weight: 600; cursor: pointer; font-family: inherit;
}
.adv-apply:hover { filter: brightness(1.05); }
.adv-reset {
  background: transparent; border: 1px solid var(--border-strong); color: var(--text-sub);
  padding: 8px 20px; border-radius: 8px; font-size: 14px; cursor: pointer; font-family: inherit;
}
.adv-reset:hover { background: var(--surface); }

@media (max-width: 768px) {
  .adv-row { grid-template-columns: 1fr; gap: 4px; }
}
```

- [ ] **Step 3: lint**

Run: `cd web && npx eslint src/components/AdvancedSearch.jsx`
Expected: 에러 없음.

- [ ] **Step 4: 커밋**

```bash
git add web/src/components/AdvancedSearch.jsx web/src/components/AdvancedSearch.css
git commit -m "feat: AdvancedSearch 필터 패널 컴포넌트(7그룹 칩 토글 + 반영/초기화 + 지역 안내)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Search.jsx 통합 — 토글·적용필터·배지·결합

**Files:**
- Modify: `web/src/pages/Search.jsx`

**Interfaces:**
- Consumes: `AdvancedSearch`(Task 4), `buildSearchFilters`(Task 1), `searchWorksiteCards`(Task 3).
- Produces: 없음(화면).

- [ ] **Step 1: import 추가**

[Search.jsx](../../../web/src/pages/Search.jsx) 상단에 추가(기존 import 블록 안):
```jsx
import AdvancedSearch from '../components/AdvancedSearch'
import { buildSearchFilters } from '../lib/searchFilters'
```

- [ ] **Step 2: 상태 + 핸들러 추가**

`Search()` 안, `const [page, setPage] = useState(1)` 아래에 추가:
```jsx
  const [showAdvanced, setShowAdvanced] = useState(false)
  const EMPTY_FILTER = { type: [], location: [], region: [], duration: null, track: [], degree: null, status: null }
  const [appliedFilters, setAppliedFilters] = useState(EMPTY_FILTER)

  // 적용된 필터 개수(버튼 총합)
  const filterCount =
    appliedFilters.type.length + appliedFilters.location.length + appliedFilters.region.length +
    appliedFilters.track.length + (appliedFilters.duration ? 1 : 0) +
    (appliedFilters.degree ? 1 : 0) + (appliedFilters.status ? 1 : 0)
```

- [ ] **Step 3: 카드 fetch effect에 필터 결합**

`searchWorksiteCards({ ... })` 호출을 아래로 교체하고, effect deps 배열에 `appliedFilters` 추가:
```jsx
        const { cards: rows, total: t } = await searchWorksiteCards({
          query: submittedQuery,
          sort: sortKeyToParam(effectiveSort),
          page,
          perPage,
          filters: buildSearchFilters(appliedFilters),
        })
```
deps 교체:
```jsx
  }, [authUser, submittedQuery, effectiveSort, page, perPage, appliedFilters])
```

- [ ] **Step 4: 적용/초기화 핸들러 + 토글 버튼 + 패널 렌더**

`runSearch` 함수 아래에 추가:
```jsx
  function applyFilters(selection) {
    setAppliedFilters(selection)
    setPage(1)
  }
  function resetAll() {
    setAppliedFilters(EMPTY_FILTER)
    setQuery('')
    setSubmittedQuery('')
    setPage(1)
  }
```
그리고 기존 고급검색 토글 버튼 줄을 교체:
```jsx
        <div className="filter-toggle-btn">
          <button type="button" onClick={() => setShowAdvanced((v) => !v)}>
            고급검색{filterCount ? ` (${filterCount})` : ''} {showAdvanced ? '▴' : '▾'}
          </button>
        </div>
        {showAdvanced && (
          <AdvancedSearch initial={appliedFilters} onApply={applyFilters} onReset={resetAll} />
        )}
```
> 위 토글+패널은 `.search-head` div **안**, 기존 `<div className="filter-toggle-btn">…</div>` 자리에 들어간다.

- [ ] **Step 5: lint + 빌드 + 테스트**

Run: `cd web && npx eslint src/pages/Search.jsx && npx vitest run && npm run build`
Expected: eslint 에러 없음(미사용 import 없음), 테스트 PASS, build 성공.

- [ ] **Step 6: 수동 검증 (dev, DB push 후)**

Run: `cd web && npm run dev` → `/search`(로그인).
확인:
1. 고급검색 토글 → 패널 펼침/접힘, `▾`/`▴`.
2. 다중 그룹(유형/교내외/지역/우대) 여러 개 on, 단일(기간/학위/학적) 하나만 on(재클릭 해제).
3. "반영하여 검색" → 결과가 필터대로 줄고 토글에 `(n)` 배지.
4. 검색어 + 필터 동시(AND) 동작.
5. "초기화" → 필터·검색어 비우고 전체 결과.
6. 지역 (?) → 말풍선, 바깥클릭 닫힘.
7. 잠금 계정서도 필터 동작(점수만 더미).

- [ ] **Step 7: 커밋**

```bash
git add web/src/pages/Search.jsx
git commit -m "Search: 고급검색 패널 통합(토글·배지·적용필터 AND 결합·초기화)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: 문서 갱신 + 최종 검증

**Files:**
- Modify: `web/src/components/README.md`, `web/src/pages/README.md`

**Interfaces:**
- Consumes: 없음. Produces: 없음.

- [ ] **Step 1: components/README에 AdvancedSearch 추가**

`web/src/components/README.md`의 컴포넌트 목록에 한 줄 추가(기존 표/목록 형식에 맞춰):
```
| `AdvancedSearch.jsx` / `.css` | 근장찾기 고급검색 필터 패널. 7그룹(유형·교내외·지역·기간·우대·학위·학적) 칩 토글 + 반영/초기화 + 지역 안내 말풍선. 옵션은 `lib/profileOptions`(REGIONS·PREFFEREDTRACK). props: initial/onApply/onReset. |
```

- [ ] **Step 2: pages/README의 Search 행에 고급검색 반영**

`web/src/pages/README.md`의 Search 행에서 "고급검색(필터바)은 토글 버튼만 — 미구현" 문구를 아래로 교체:
```
고급검색 패널(`components/AdvancedSearch`): 유형·교내외·지역·기간·우대·학위·학적 필터를 "반영하여 검색"으로 적용(검색어와 AND), 초기화로 전체 리셋. 필터는 대표공고 기준, 학위/학적은 지원가능 의미.
```

- [ ] **Step 3: 전체 lint(내 파일) + 테스트 + 빌드**

Run: `cd web && npx eslint src/lib/searchFilters.js src/components/AdvancedSearch.jsx src/pages/Search.jsx src/data/worksiteQueries.js && npx vitest run && npm run build`
Expected: 내 파일 eslint 에러 없음, 테스트 PASS, build 성공.
> 참고: `npx eslint .` 전체는 기존 파일(WorksiteDetail/Home/Notice 등)의 `react-hooks/set-state-in-effect` 부채가 남아 있을 수 있음 — 이번 작업 범위 밖.

- [ ] **Step 4: 커밋**

```bash
git add web/src/components/README.md web/src/pages/README.md
git commit -m "docs: 고급검색 패널 반영(components/pages README)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review (작성자 확인 완료)

**Spec coverage:**
- 7그룹 다중/단일 + 빈그룹 무필터 → Task 1(buildSearchFilters), Task 4(MULTI/단일 토글). ✓
- 대표공고 기준 필터 → Task 2(`r` CTE 기준 where). ✓
- 학위/학적 지원가능 확장 → Task 1(DEGREE_MAP/STATUS_MAP [0,2,3]/[1,2,3]). ✓
- 지역=region in(...), 학교근장 자동한정 + 검증노트 → Task 2 Step4. ✓
- (?) 말풍선 → Task 4(adv-hint-pop). ✓
- 검색어 AND 결합 → Task 5 Step3. ✓
- 반영(패널 열어둠)·초기화(필터+검색어 리셋) → Task 5 Step4. ✓
- 배지 n=버튼 총개수 → Task 5 Step2(filterCount). ✓
- 패널 pending=적용필터 초기화 → Task 4(useEffect [initial]). ✓
- 옵션 profileOptions 재사용 → Task 4 import. ✓
- on/off 버튼 톤 → Task 4 CSS(.adv-chip / .on). ✓
- RPC DROP+재생성 → Task 2 Step2. ✓
- 순수함수+테스트 → Task 1. ✓

**Type consistency:** `buildSearchFilters(selection)→{p_*}`, `searchWorksiteCards({...,filters})`, `AdvancedSearch{initial,onApply,onReset}`, selection shape 7키 — Task 1·3·4·5 동일. `filterCount`는 selection의 배열 length + 단일 1/0. ✓

**Placeholder scan:** 마이그레이션 `담당 <이름>`만 작업자 기입. `PREFFEREDTRACK`의 `추가예정`은 의도된 데이터 placeholder(작업자 소관). 코드·테스트·명령 전부 실내용. ✓
