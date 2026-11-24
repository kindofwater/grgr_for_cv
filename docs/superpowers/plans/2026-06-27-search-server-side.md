# 근장찾기 서버측 검색·페이지네이션 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 근장찾기 검색·정렬·페이징·dedup을 전부 Supabase RPC로 내려, 프론트는 서버가 준 페이지·순서를 재정렬 없이 렌더한다.

**Architecture:** DB 함수 2개(`search_worksite_cards`=필터+정렬+페이징+총개수, `search_worksite_suggestions`=드롭다운 제안)를 신설한다. 순수 변환·검증 로직은 `lib/searchCards.js`로 빼서 단위 테스트하고, `data/worksiteQueries.js`가 RPC를 호출해 카드 모양으로 변환, `Search.jsx`는 입력→제안 드롭다운 / Enter→카드 검색으로 재작성한다.

**Tech Stack:** React 19 + Vite, react-router-dom 7, Supabase(@supabase/supabase-js 2), Vitest 4, Supabase CLI 마이그레이션.

## Global Constraints

- DB 통신은 `web/src/data/`에서만. 페이지·컴포넌트는 data 함수만 호출. (CLAUDE.md §2)
- DB 변경은 `web/supabase/migrations/` 마이그레이션으로만. SQL 에디터 수동편집 금지. 파일 맨 위 헤더 2줄 필수: `-- 목적:` / `-- 날짜: YYYY-MM-DD · 담당:`. (CLAUDE.md §3)
- 신규 함수라 `DROP FUNCTION` 불필요. `grant execute ... to authenticated`.
- 의존성 방향: `pages → components / data / lib`. 역방향 import 금지.
- 정렬 라벨 정본(드롭다운): `'추천순'`, `'리뷰 많은 순'` (공백 포함, 기존 문자열 그대로).
- 모든 명령은 `web/`에서 실행 (CLI·vitest가 web의 devDependency).
- 커밋 메시지 끝에: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`
- 현재 작업 브랜치: `detail_choi_2`.

---

## File Structure

- `web/src/lib/searchCards.js` (신규) — 순수 헬퍼: `escapeLike`, `sortKeyToParam`, `toCard`, `suggestionAddress`.
- `web/src/lib/searchCards.test.js` (신규) — 위 함수 단위 테스트.
- `web/supabase/migrations/<ts>_search_worksite_rpc.sql` (신규) — RPC 2개.
- `web/src/data/worksiteQueries.js` (수정) — `searchWorksiteCards`·`searchWorksiteSuggestions` 추가, `fetchSearchPostings` 제거.
- `web/src/pages/Search.jsx` (수정) — 서버 검색·정렬·페이징·드롭다운으로 재작성. `ResultCard`/`RatingBar`/`barColor`는 유지.
- `web/src/pages/Search.css` (수정) — 제안 드롭다운 스타일 추가.

---

## Task 1: lib/searchCards.js — 순수 헬퍼 (TDD)

**Files:**
- Create: `web/src/lib/searchCards.js`
- Test: `web/src/lib/searchCards.test.js`

**Interfaces:**
- Consumes: 없음 (순수 함수).
- Produces:
  - `escapeLike(text: string|null|undefined): string` — LIKE 와일드카드(`\ % _`) 이스케이프.
  - `sortKeyToParam(label: string): 'recommend' | 'reviews'`
  - `toCard(row: object): { is_active, worksite, posting, stats|null }`
  - `suggestionAddress(s: {address?, region?}): string`

- [ ] **Step 1: 실패하는 테스트 작성**

`web/src/lib/searchCards.test.js`:
```js
// web/src/lib/searchCards.test.js
import { describe, it, expect } from 'vitest'
import { escapeLike, sortKeyToParam, toCard, suggestionAddress } from './searchCards'

describe('escapeLike', () => {
  it('%, _, 백슬래시를 이스케이프한다', () => {
    expect(escapeLike('a%b_c\\d')).toBe('a\\%b\\_c\\\\d')
  })
  it('null/undefined는 빈 문자열', () => {
    expect(escapeLike(null)).toBe('')
    expect(escapeLike(undefined)).toBe('')
  })
})

describe('sortKeyToParam', () => {
  it('리뷰 많은 순 → reviews', () => {
    expect(sortKeyToParam('리뷰 많은 순')).toBe('reviews')
  })
  it('그 외(추천순 포함) → recommend', () => {
    expect(sortKeyToParam('추천순')).toBe('recommend')
    expect(sortKeyToParam('아무거나')).toBe('recommend')
  })
})

describe('toCard', () => {
  const baseRow = {
    worksite_id: 7, organization_name: '고려대', workplace_name: '도서관',
    region: '서울', address: '안암로 1', type: 'school', location_type: 'on_campus',
    view_count: 12, is_active: true,
    preferred_track: '이공계열', eligible_degree: 0, eligible_status: 2, work_duration_type: 'short',
    review_count: 3, avg_recommend: 4.2, avg_work: 4.0, avg_growth: 3.5, avg_vibe: 4.1, avg_flex: 3.9,
    recommend_rate: 67, total_count: 50,
  }
  it('flat 행을 {worksite,posting,stats,is_active}로 변환한다', () => {
    const c = toCard(baseRow)
    expect(c.is_active).toBe(true)
    expect(c.worksite).toEqual({
      id: 7, organization_name: '고려대', workplace_name: '도서관', region: '서울',
      address: '안암로 1', type: 'school', location_type: 'on_campus', view_count: 12,
    })
    expect(c.posting).toEqual({
      preferred_track: '이공계열', eligible_degree: 0, eligible_status: 2, work_duration_type: 'short',
    })
    expect(c.stats.review_count).toBe(3)
    expect(c.stats.avg_recommend).toBe(4.2)
    expect(c.stats.recommend_rate).toBe(67)
  })
  it('리뷰 0개면 stats는 null', () => {
    const c = toCard({ ...baseRow, review_count: 0, avg_recommend: null })
    expect(c.stats).toBeNull()
  })
})

describe('suggestionAddress', () => {
  it('address 있으면 address', () => {
    expect(suggestionAddress({ address: '안암로 1', region: '서울' })).toBe('안암로 1')
  })
  it('address 비면 region 폴백', () => {
    expect(suggestionAddress({ address: '', region: '서울' })).toBe('서울')
    expect(suggestionAddress({ address: null, region: '충남' })).toBe('충남')
  })
  it('둘 다 없으면 빈 문자열', () => {
    expect(suggestionAddress({})).toBe('')
  })
})
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd web && npx vitest run src/lib/searchCards.test.js`
Expected: FAIL — `searchCards.js`가 없어 import 에러.

- [ ] **Step 3: 최소 구현 작성**

`web/src/lib/searchCards.js`:
```js
// 근장찾기(서버 검색) 순수 헬퍼. data/worksiteQueries가 사용. UI/DB 의존 없음.

// LIKE 와일드카드(%, _, \) 이스케이프 — RPC ilike '%q%'에서 의도치 않은 패턴/매칭 방지.
// (Postgres ilike 기본 escape는 백슬래시. 인젝션은 파라미터 바인딩이라 별개로 안전.)
export function escapeLike(text) {
  return String(text ?? '').replace(/[\\%_]/g, (ch) => '\\' + ch)
}

// 정렬 드롭다운 라벨 → RPC p_sort 값.
export function sortKeyToParam(label) {
  return label === '리뷰 많은 순' ? 'reviews' : 'recommend'
}

// search_worksite_cards의 flat 행 → ResultCard가 쓰는 {worksite, posting, stats, is_active} 모양.
export function toCard(row) {
  const hasReview = Number(row.review_count) > 0
  return {
    is_active: row.is_active,
    worksite: {
      id: row.worksite_id,
      organization_name: row.organization_name,
      workplace_name: row.workplace_name,
      region: row.region,
      address: row.address,
      type: row.type,
      location_type: row.location_type,
      view_count: row.view_count,
    },
    posting: {
      preferred_track: row.preferred_track,
      eligible_degree: row.eligible_degree,
      eligible_status: row.eligible_status,
      work_duration_type: row.work_duration_type,
    },
    stats: hasReview ? {
      worksite_id: row.worksite_id,
      review_count: Number(row.review_count),
      avg_recommend: row.avg_recommend,
      avg_work: row.avg_work,
      avg_growth: row.avg_growth,
      avg_vibe: row.avg_vibe,
      avg_flex: row.avg_flex,
      recommend_rate: row.recommend_rate,
    } : null,
  }
}

// 드롭다운 주소 표시: address 있으면 address, 없으면 region 폴백.
export function suggestionAddress(s) {
  return (s.address && String(s.address).trim()) ? s.address : (s.region ?? '')
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd web && npx vitest run src/lib/searchCards.test.js`
Expected: PASS (모든 it 통과).

- [ ] **Step 5: 커밋**

```bash
git add web/src/lib/searchCards.js web/src/lib/searchCards.test.js
git commit -m "검색 lib 순수헬퍼(escapeLike/sortKeyToParam/toCard/suggestionAddress) + 테스트

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: DB 마이그레이션 — RPC 2개

**Files:**
- Create: `web/supabase/migrations/<생성된 타임스탬프>_search_worksite_rpc.sql`

**Interfaces:**
- Consumes: 기존 테이블 `worksites`, `postings`, `reviews` (db-schema.md).
- Produces:
  - `search_worksite_cards(p_query text, p_sort text, p_limit int, p_offset int)` → 카드 행 + `total_count`.
  - `search_worksite_suggestions(p_query text, p_limit int)` → `worksite_id, organization_name, workplace_name, address, region`.

- [ ] **Step 1: 마이그레이션 파일 생성**

Run: `cd web && npx supabase migration new search_worksite_rpc`
Expected: `web/supabase/migrations/<ts>_search_worksite_rpc.sql` 빈 파일 생성. 출력에 경로 표시.

- [ ] **Step 2: SQL 작성**

생성된 파일에 아래 전체를 붙여넣는다(헤더 2줄 포함, `담당`은 실제 작업자명으로):
```sql
-- 목적: 근장찾기 서버측 검색·정렬·페이징 RPC (worksite 단위 dedup + 점수집계 + 총개수). 드롭다운 제안 RPC 동봉.
-- 날짜: 2026-06-27 · 담당: <이름>
-- 비고: 신규 함수 → DROP 불필요. recommend_rate는 score_recommend>=4.0 비율(get_worksite_score_cards와 동일 규칙).

create or replace function search_worksite_cards(
  p_query  text default null,
  p_sort   text default 'recommend',   -- 'recommend' | 'reviews'
  p_limit  int  default 20,
  p_offset int  default 0
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
  with rep as (                       -- 대표공고 1개/worksite (active 우선 → 최신)
    select distinct on (p.worksite_id)
      p.worksite_id, p.preferred_track, p.eligible_degree,
      p.eligible_status, p.work_duration_type
    from postings p
    where p.deleted_at is null
    order by p.worksite_id, p.is_active desc, p.created_at desc
  ),
  ws_active as (                       -- active 롤업(공고 하나라도 active면 true)
    select worksite_id, bool_or(is_active) as is_active
    from postings where deleted_at is null group by worksite_id
  ),
  stats as (                          -- 점수 집계
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
    join rep r           on r.worksite_id = w.id   -- 공고 있는 worksite만
    left join ws_active a on a.worksite_id = w.id
    left join stats s    on s.worksite_id = w.id
    where w.deleted_at is null
      and ( p_query is null or p_query = '' or
            w.organization_name ilike '%'||p_query||'%' or
            w.workplace_name    ilike '%'||p_query||'%' )
  )
  select *, count(*) over() as total_count
  from joined
  order by
    case when p_sort='reviews'   then review_count end desc nulls last,
    case when p_sort='recommend' then avg_recommend end desc nulls last,
    worksite_id                       -- tie-breaker: offset 페이징 경계 안정(행 중복/누락 방지)
  limit p_limit offset p_offset;
$$;

create or replace function search_worksite_suggestions(
  p_query text, p_limit int default 8
)
returns table(
  worksite_id int, organization_name varchar, workplace_name varchar,
  address text, region varchar
)
language sql
security definer
as $$
  select w.id, w.organization_name, w.workplace_name, w.address, w.region
  from worksites w
  where w.deleted_at is null
    and exists (select 1 from postings p
                where p.worksite_id = w.id and p.deleted_at is null)
    and ( w.organization_name ilike '%'||p_query||'%' or
          w.workplace_name    ilike '%'||p_query||'%' )
  order by w.organization_name, w.workplace_name
  limit p_limit;
$$;

grant execute on function search_worksite_cards(text, text, int, int) to authenticated;
grant execute on function search_worksite_suggestions(text, int) to authenticated;
```

> ⚠️ 반환 컬럼 타입은 실제 컬럼 타입과 일치해야 한다. `worksites.organization_name`/`workplace_name`/`region`은 `varchar`, `worksites.address`는 `text`, `postings.preferred_track`은 `varchar`다(db-schema.md). 타입 불일치 시 `structure of query does not match function result type` 에러가 난다 — 이 에러가 나면 해당 컬럼 타입을 맞춘다.

- [ ] **Step 3: 검증 (sandbox 또는 Docker)**

디스코드에 변경 공유 후:
- Docker 있으면: `cd web && npx supabase db reset` (맨바닥 재구축이 안 깨지는지).
- Docker 없으면(현 방식): sandbox 프로젝트에 `npx supabase db push`.

그 다음 RPC 동작 확인(Supabase SQL 에디터/psql에서, **읽기 전용 select라 안전**):
```sql
select worksite_id, organization_name, review_count, avg_recommend, total_count
from search_worksite_cards(null, 'recommend', 5, 0);
```
Expected: 최대 5행. 각 행 `total_count`는 전체 매칭 worksite 수로 동일. `avg_recommend` 내림차순(리뷰 없는 곳은 뒤).

```sql
select * from search_worksite_suggestions('고', 8);
```
Expected: 이름에 '고' 들어가는 worksite 최대 8행(이름순).

- [ ] **Step 4: prod 반영 + 커밋**

push 전 디스코드 한 마디 → `cd web && npx supabase db push` (변경한 사람이 직접).
```bash
git add web/supabase/migrations/
git commit -m "검색 RPC 추가: search_worksite_cards / search_worksite_suggestions

worksite 단위 dedup + 이름 부분일치 + 추천순/리뷰순 정렬 + limit/offset + window 총개수.
드롭다운 제안용 경량 RPC 동봉. 신규 함수(DROP 불필요), authenticated grant.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: data 계층 래퍼

**Files:**
- Modify: `web/src/data/worksiteQueries.js`

**Interfaces:**
- Consumes: `escapeLike`, `toCard` (Task 1); RPC `search_worksite_cards`·`search_worksite_suggestions` (Task 2).
- Produces:
  - `searchWorksiteCards({ query, sort, page, perPage }): Promise<{ cards: Card[], total: number }>` — `sort`는 이미 `'recommend'|'reviews'`. `query`는 raw(여기서 escape).
  - `searchWorksiteSuggestions(query: string, limit=8): Promise<Row[]>` — Row = `{worksite_id, organization_name, workplace_name, address, region}`.

- [ ] **Step 1: import 추가**

`web/src/data/worksiteQueries.js` 맨 위 `import { supabase } from '../supabase'` 아래에 추가:
```js
import { escapeLike, toCard } from '../lib/searchCards'
```

- [ ] **Step 2: 기존 근장찾기 함수 교체**

[worksiteQueries.js](../../../web/src/data/worksiteQueries.js)의 `fetchSearchPostings` 함수(주석 `// ── 근장찾기(검색 목록) 전용 ──` 아래 블록)를 아래로 **교체**한다. `getWorksiteScoreCards`는 그대로 둔다(다른 사용처 확인은 Task 5).
```js
// ── 근장찾기(검색 목록) 전용 ──

// 카드 결과 + 총개수. 서버가 dedup·필터·정렬·페이징을 모두 수행(프론트 재정렬 없음).
// flat RPC 행을 ResultCard가 쓰는 {worksite,posting,stats,is_active} 모양으로 변환해 반환.
export async function searchWorksiteCards({ query, sort, page, perPage }) {
  const { data, error } = await supabase.rpc('search_worksite_cards', {
    p_query: escapeLike(query ?? ''),
    p_sort: sort,                         // 'recommend' | 'reviews'
    p_limit: perPage,
    p_offset: (page - 1) * perPage,
  })
  if (error) throw error
  const rows = data ?? []
  const total = rows.length ? Number(rows[0].total_count) : 0
  return { cards: rows.map(toCard), total }
}

// 검색창 입력 중 드롭다운 제안(이름 부분일치, 경량). 점수·집계 없음.
export async function searchWorksiteSuggestions(query, limit = 8) {
  const { data, error } = await supabase.rpc('search_worksite_suggestions', {
    p_query: escapeLike(query),
    p_limit: limit,
  })
  if (error) throw error
  return data ?? []
}
```

- [ ] **Step 3: lib 테스트가 여전히 통과하는지 + lint**

Run: `cd web && npx vitest run && npx eslint src/data/worksiteQueries.js`
Expected: 테스트 PASS, eslint 에러 없음. (이 파일 자체 단위 테스트는 없음 — 프로젝트 규칙상 data 계층은 순수 로직을 lib로 빼서 테스트하고, 얇은 래퍼는 다음 태스크의 수동 검증으로 확인.)

- [ ] **Step 4: 커밋**

```bash
git add web/src/data/worksiteQueries.js
git commit -m "data: searchWorksiteCards/searchWorksiteSuggestions 추가, fetchSearchPostings 교체

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Search.jsx + Search.css — 서버 검색·드롭다운·페이징 재작성

**Files:**
- Modify: `web/src/pages/Search.jsx`
- Modify: `web/src/pages/Search.css`

**Interfaces:**
- Consumes: `searchWorksiteCards`, `searchWorksiteSuggestions` (Task 3); `sortKeyToParam`, `suggestionAddress` (Task 1); 기존 `isPassActive`, `useAuth`, `SkeletonSearch`, `Pagination`, `Dropdown`.
- Produces: 없음 (라우트 화면).

- [ ] **Step 1: import 교체**

[Search.jsx](../../../web/src/pages/Search.jsx) 상단 import 블록(1~9행)을 아래로 교체:
```jsx
import { useEffect, useRef, useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { searchWorksiteCards, searchWorksiteSuggestions } from '../data/worksiteQueries'
import { sortKeyToParam, suggestionAddress } from '../lib/searchCards'
import { isPassActive } from '../lib/passes'
import { useAuth } from '../components/AuthContext'
import SkeletonSearch from '../components/SkeletonSearch'
import Pagination from '../components/Pagination'
import Dropdown from '../components/Dropdown'
import './Search.css'
```

- [ ] **Step 2: Search() 컴포넌트 본문 교체**

`export default function Search() { ... }` 전체(현재 110행부터 끝까지)를 아래로 교체한다. `ResultCard`/`RatingBar`/`barColor`(그 위 함수들)는 **그대로 둔다** — 잠금 더미·블러 로직 유지.
```jsx
export default function Search() {
  const navigate = useNavigate()
  const { user: authUser } = useAuth()
  const [searchParams] = useSearchParams()

  const initialQ = searchParams.get('q') ?? ''
  const [query, setQuery] = useState(initialQ)              // 검색창 입력값
  const [submittedQuery, setSubmittedQuery] = useState(initialQ) // 실제 검색에 쓰는 확정 검색어
  const [sortKey, setSortKey] = useState('추천순')
  const [perPage, setPerPage] = useState(20)
  const [page, setPage] = useState(1)

  const [cards, setCards] = useState([])
  const [total, setTotal] = useState(0)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  const [suggestions, setSuggestions] = useState([])
  const [showDropdown, setShowDropdown] = useState(false)
  const debounceRef = useRef(null)
  const boxRef = useRef(null)

  const locked = !isPassActive(authUser?.pass_expires_at)
  // 잠금 상태면 점수가 가려져 점수 정렬이 무의미 → 추천순 고정
  const effectiveSort = locked ? '추천순' : sortKey

  // 로그인 가드
  useEffect(() => {
    if (!authUser) navigate('/login')
  }, [authUser, navigate])

  // 카드 결과: 검색어/정렬/페이지/perPage 변하면 서버 호출 (프론트 재정렬·필터 없음)
  useEffect(() => {
    if (!authUser) return
    let alive = true
    setLoading(true)
    ;(async () => {
      try {
        const { cards: rows, total: t } = await searchWorksiteCards({
          query: submittedQuery,
          sort: sortKeyToParam(effectiveSort),
          page,
          perPage,
        })
        if (!alive) return
        // 빈 페이지인데 page>1 → 데이터 축소 등으로 범위 초과. 1페이지로 재요청.
        if (rows.length === 0 && page > 1) { setPage(1); return }
        setCards(rows); setTotal(t); setLoading(false)
      } catch (e) {
        if (alive) { setError(e.message); setLoading(false) }
      }
    })()
    return () => { alive = false }
  }, [authUser, submittedQuery, effectiveSort, page, perPage])

  // 입력 중 제안 드롭다운(debounce 200ms). 카드·정렬은 건드리지 않음.
  useEffect(() => {
    const q = query.trim()
    if (q.length < 1) { setSuggestions([]); setShowDropdown(false); return }
    if (debounceRef.current) clearTimeout(debounceRef.current)
    debounceRef.current = setTimeout(async () => {
      try {
        const rows = await searchWorksiteSuggestions(q)
        setSuggestions(rows); setShowDropdown(true)
      } catch { /* 제안 실패는 무시 */ }
    }, 200)
    return () => { if (debounceRef.current) clearTimeout(debounceRef.current) }
  }, [query])

  // 바깥 클릭 시 드롭다운 닫기
  useEffect(() => {
    function onDoc(e) {
      if (boxRef.current && !boxRef.current.contains(e.target)) setShowDropdown(false)
    }
    document.addEventListener('mousedown', onDoc)
    return () => document.removeEventListener('mousedown', onDoc)
  }, [])

  // Enter/검색버튼: 입력값을 검색어로 확정하고 1페이지부터
  function runSearch() {
    setSubmittedQuery(query.trim())
    setPage(1)
    setShowDropdown(false)
  }

  const totalPages = Math.max(1, Math.ceil(total / perPage))
  const safePage = Math.min(page, totalPages)

  return (
    <div className="search-page">
      <div className="search-head">
        <div className="search-bar-md" ref={boxRef}>
          <input
            type="text"
            placeholder="근장 이름, 위치로 검색하세요"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter') runSearch() }}
            onFocus={() => { if (suggestions.length) setShowDropdown(true) }}
          />
          <button aria-label="검색" type="button" onClick={runSearch}>
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 28 28" fill="none" stroke="white" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
              <circle cx="11" cy="11" r="8" /><line x1="24" y1="24" x2="16.66" y2="16.66" />
            </svg>
          </button>
          {showDropdown && suggestions.length > 0 && (
            <ul className="search-suggest">
              {suggestions.map((s) => (
                <li key={s.worksite_id} onClick={() => navigate(`/worksite/${s.worksite_id}`)}>
                  <span className="ss-name">{s.organization_name} - {s.workplace_name}</span>
                  <span className="ss-addr">{suggestionAddress(s)}</span>
                </li>
              ))}
            </ul>
          )}
        </div>
        <div className="filter-toggle-btn"><button type="button">고급검색 ▾</button></div>
      </div>

      {error ? (
        <div className="search-error">에러: {error}</div>
      ) : loading ? (
        <SkeletonSearch />
      ) : (
      <>
      {locked && (
        <div className="lock-banner">
          <span className="lock-banner-text">
            <span className="lock-banner-icon">
              <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                <rect x="5" y="11" width="14" height="9" rx="2" /><path d="M8.5 11V8a3.5 3.5 0 0 1 7 0v3" />
              </svg>
            </span>
            열람권이 있으면 점수와 리뷰 내용을 확인할 수 있어요
          </span>
          <button onClick={() => navigate('/exchange')} className="lock-banner-cta">열람권 교환하러 가기 →</button>
        </div>
      )}

      <div className="results-bar">
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <div style={{ width: 100 }}>
            <Dropdown size="sm" value={String(perPage)} ariaLabel="페이지당 개수"
              onChange={(v) => { setPerPage(Number(v)); setPage(1) }}
              options={[
                { value: '10', label: '10개씩' },
                { value: '20', label: '20개씩' },
                { value: '30', label: '30개씩' },
                { value: '50', label: '50개씩' },
              ]} />
          </div>
          <span>전체 근장 <strong>{total}개</strong></span>
        </div>
        <div className="status-legend">
          <span className="legend-item"><span className="legend-dot dot-green"></span>모집중</span>
          <span className="legend-item"><span className="legend-dot dot-red"></span>모집완료</span>
        </div>
        <div style={{ width: 135, marginLeft: 20 }}>
          <Dropdown size="sm" value={effectiveSort} disabled={locked} ariaLabel="정렬"
            onChange={(v) => { setSortKey(v); setPage(1) }}
            options={locked ? ['추천순'] : ['추천순', '리뷰 많은 순']} />
        </div>
      </div>

      <div className="result-list">
        {cards.length === 0 ? (
          <div className="search-empty">{submittedQuery ? '검색 결과가 없어요.' : '표시할 근장이 없어요.'}</div>
        ) : (
          cards.map((card) => (
            <ResultCard
              key={card.worksite.id}
              card={card}
              locked={locked}
              onOpen={(id) => navigate(`/worksite/${id}`)}
              onWrite={(id) => navigate(`/worksite/${id}/review`)}
            />
          ))
        )}
      </div>

      {cards.length > 0 && totalPages > 1 && (
        <Pagination page={safePage} totalPages={totalPages} onPage={setPage} />
      )}
      </>
      )}
    </div>
  )
}
```

- [ ] **Step 3: 제안 드롭다운 CSS 추가**

[Search.css](../../../web/src/pages/Search.css)의 `.filter-toggle-btn button { ... }` 줄 바로 아래에 추가:
```css
/* 검색 제안 드롭다운 */
.search-suggest {
  position: absolute; top: calc(100% + 6px); left: 0; right: 0; z-index: 20;
  background: white; border: 1px solid var(--border); border-radius: 12px;
  box-shadow: 0 8px 24px rgba(0,0,0,0.12);
  list-style: none; margin: 0; padding: 6px; max-height: 320px; overflow-y: auto;
}
.search-suggest li {
  display: flex; flex-direction: column; gap: 2px;
  padding: 8px 12px; border-radius: 8px; cursor: pointer;
}
.search-suggest li:hover { background: var(--surface); }
.ss-name { font-size: 14px; font-weight: 600; color: var(--text); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.ss-addr { font-size: 12px; color: var(--text-muted); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
```
> `.search-bar-md`는 이미 `position: relative`라 드롭다운이 검색창에 정렬된다.

- [ ] **Step 4: lint + 빌드 + 테스트**

Run: `cd web && npx eslint src/pages/Search.jsx && npx vitest run && npm run build`
Expected: eslint 에러 없음(사용 안 하는 import 없음 — `useMemo`·`getWorksiteScoreCards`·`fetchSearchPostings` 제거 확인), vitest PASS, build 성공.

- [ ] **Step 5: 수동 검증 (dev 서버)**

Run: `cd web && npm run dev` → 브라우저에서 `/search`(로그인 상태).
확인:
1. 입력 시 드롭다운에 `기관명 - 근무지명` + 주소(없으면 지역) 표시.
2. 드롭다운 항목 클릭 → 해당 근무지 상세로 이동.
3. Enter(또는 검색버튼) → 카드 결과 갱신, "전체 근장 N개"가 서버 총개수.
4. 정렬 추천순/리뷰많은순 전환 시 순서 바뀜(서버 정렬), 1페이지로.
5. 페이지 이동·perPage 변경 동작. 페이지마다 새로 서버 호출.
6. 잠금 계정: 더미+블러 유지, 정렬은 추천순 1개만, 배너 표시.
7. 검색 결과 0 → "검색 결과가 없어요."

- [ ] **Step 6: 커밋**

```bash
git add web/src/pages/Search.jsx web/src/pages/Search.css
git commit -m "Search: 서버측 검색·정렬·페이징 + 제안 드롭다운으로 재작성

클라 group/filter/sort/slice 제거, RPC 결과를 그대로 렌더. 입력→드롭다운(이름+주소,
클릭 시 상세), Enter→카드 검색. 정렬 추천순/리뷰많은순 서버 처리.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: 정리 — 미사용 코드 제거 + 최종 검증

**Files:**
- Modify: `web/src/data/worksiteQueries.js` (해당 시)

**Interfaces:**
- Consumes: 없음.
- Produces: 없음.

- [ ] **Step 1: getWorksiteScoreCards 사용처 확인**

Run: `cd web && grep -rn "getWorksiteScoreCards" src`
Expected: 정의(`worksiteQueries.js`) 외 호출이 없으면 미사용. (Search에서 제거됐으므로.)

- [ ] **Step 2: 미사용이면 제거**

위 grep 결과가 정의 1곳뿐이면 `getWorksiteScoreCards` 함수와 그 위 주석(`// 근장찾기 카드 점수 집계 RPC 래퍼 ...`)을 삭제한다. **다른 곳에서 쓰면 그대로 둔다.**

- [ ] **Step 3: 전체 lint + 테스트 + 빌드**

Run: `cd web && npx eslint . && npx vitest run && npm run build`
Expected: 전부 통과(에러·미사용 import 없음).

- [ ] **Step 4: 커밋**

```bash
git add web/src/data/worksiteQueries.js
git commit -m "정리: 미사용 getWorksiteScoreCards 제거(검색 서버 RPC로 대체)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```
> Step 2에서 제거할 게 없었으면 이 커밋은 생략.

---

## Self-Review (작성자 확인 완료)

**Spec coverage:**
- 서버 dedup+정렬+페이징+총개수 → Task 2 RPC + Task 4 렌더. ✓
- 이름 부분일치(기관명+근무지명) → Task 2 `ilike`. ✓
- 정렬 2종(추천순/리뷰많은순), 드롭다운 유지 → Task 4 options + `sortKeyToParam`. ✓
- 제안 드롭다운(이름+주소), 클릭→상세 → Task 2 suggestions + Task 4 UI. ✓
- Enter/버튼으로만 카드 검색(부채 D) → Task 4 `runSearch`. ✓
- ResultCard 모양 유지 → Task 1 `toCard`. ✓
- 순수함수 lib + 테스트 → Task 1. ✓
- escapeLike 와일드카드 → Task 1 + Task 3. ✓
- 페이지 범위초과 단일 규칙, 드롭다운 발동(≥1자·200ms) → Task 4. ✓
- 비범위(고급검색 버튼 no-op 유지, 점수 게이팅 미적용, 초성 없음) → 고급검색 버튼 그대로 둠(Task 4), 게이팅·초성 미포함. ✓

**Type consistency:** `searchWorksiteCards({query,sort,page,perPage})→{cards,total}`, `toCard(row)→{worksite,posting,stats,is_active}`, `sortKeyToParam(label)→'recommend'|'reviews'`, `suggestionAddress(s)→string` — Task 1·3·4에서 동일하게 사용. ✓

**Placeholder scan:** `담당 <이름>`(마이그레이션 헤더)만 작업자가 채울 칸. 코드/테스트/명령은 모두 실내용. ✓