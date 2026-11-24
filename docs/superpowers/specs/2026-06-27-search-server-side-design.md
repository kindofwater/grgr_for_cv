# 근장찾기 서버측 검색·페이지네이션 설계 (#4 + #6)

- 날짜: 2026-06-27
- 담당: (작업자)
- 대상 화면: `web/src/pages/Search.jsx` (근장찾기)
- 관련: CLAUDE.md §2·§3 (data 계층·마이그레이션 규칙)

---

## 0. 배경 / 문제

현재 [Search.jsx](../../../web/src/pages/Search.jsx)는:

1. `fetchSearchPostings()`로 **공고를 전부** 받아온다 (limit 없음).
2. 클라이언트에서 worksite 단위로 **그룹화(dedup)** + 대표공고 선정.
3. 클라이언트에서 검색어 **필터 → 정렬 → slice 페이징**.

문제(부채 A·D):
- 데이터가 커지면 전부 받아 느리다.
- 페이징이 가짜다(이미 다 받아놓고 자르기만).
- 정렬이 클라에서 일어난다("받아온 뒤 재정렬").
- 검색 버튼이 장식이다(`onChange` 실시간 필터).

## 1. 목표 (이번 spec 범위)

검색·정렬·페이징·dedup을 **전부 서버(Supabase)로** 내린다. 프론트는 **재정렬하지 않고** 서버가 준 순서·페이지를 그대로 렌더한다.

포함:
- worksite 단위 결과(대표공고 선정 = active 우선 → 최신).
- 이름 부분일치 검색 (기관명 + 근무지명).
- 정렬 2종: **추천순 / 리뷰많은순** (드롭다운 유지).
- 서버 페이지네이션 (limit/offset) + 총개수.
- 검색창 입력 시 **제안 드롭다운**(이름 부분일치, 이름+주소 표시) — 항목 클릭 시 해당 근무지 상세로 이동.
- **Enter / 검색버튼** 누를 때만 카드 결과 갱신.

명시적 비범위(이번에 안 함):
- **고급검색(debt-C)**: 버튼은 no-op 유지. 서버 필터 파라미터는 이번엔 안 넣고, 추후 별도 마이그레이션에서 RPC에 추가(§7 참고).
- **점수 서버 게이팅(debt-B)**: 잠금 사용자에게도 RPC는 실점수를 반환한다(네트워크엔 옴). 클라가 더미+블러로 가리는 현 동작 유지(2단계서 적용 완료). 진짜 서버 차단은 별도 작업.
- **초성 검색 / 예측 자동완성**: 영구 폐기. 검색은 `ilike` 부분일치만.

## 2. 아키텍처 개요

```
[Search.jsx]
  ├─(입력 중, debounce)→ searchWorksiteSuggestions(q)  → 드롭다운(이름+주소)
  │                                                       └ 클릭 → /worksite/:id
  └─(Enter/버튼/정렬/페이지 변경)→ searchWorksiteCards({q, sort, page, perPage})
                                      → { rows, total } → 카드 렌더 + 페이지네이션
```

DB 함수 2개 신설(둘 다 신규 → `DROP` 불필요):

1. `search_worksite_cards(p_query, p_sort, p_limit, p_offset)` — 카드 결과 + 총개수.
2. `search_worksite_suggestions(p_query, p_limit)` — 드롭다운 제안(가벼움).

data 계층(`web/src/data/worksiteQueries.js`)에 래퍼 2개 추가, `fetchSearchPostings`는 Search에서 더 안 쓰이면 제거.

## 3. DB 설계 (마이그레이션)

마이그레이션 파일 1개: `npx supabase migration new search_worksite_rpc`.
헤더 2줄 필수. 둘 다 `security definer`(reviews 집계를 행 노출 없이 읽기 위해), `grant execute ... to authenticated`(검색은 로그인 뒤 화면).

### 3.1 `search_worksite_cards`

반환 컬럼(카드 1장 = worksite 1행):

| 그룹 | 컬럼 |
|------|------|
| worksite | `worksite_id, organization_name, workplace_name, region, address, type, location_type, view_count, is_active` |
| 대표공고 | `preferred_track, eligible_degree, eligible_status, work_duration_type` |
| 점수집계 | `review_count, avg_recommend, avg_work, avg_growth, avg_vibe, avg_flex, recommend_rate` |
| 페이징 | `total_count` (필터된 전체 행수, 매 행에 동일값) |

> `is_active` = 그 worksite에 **active 공고가 하나라도** 있으면 true(롤업). 카드 모집중/완료 색·정렬과 무관.

SQL 골격(CTE로 dedup → 필터 → 정렬 → 페이징 → window 총개수):

```sql
create or replace function search_worksite_cards(
  p_query  text  default null,
  p_sort   text  default 'recommend',   -- 'recommend' | 'reviews'
  p_limit  int   default 20,
  p_offset int   default 0
)
returns table( /* 위 표의 컬럼들 + total_count bigint */ )
language sql
security definer
as $$
  with rep as (                       -- 대표공고 1개/worksite
    select distinct on (p.worksite_id)
      p.worksite_id, p.preferred_track, p.eligible_degree,
      p.eligible_status, p.work_duration_type
    from postings p
    where p.deleted_at is null
    order by p.worksite_id, p.is_active desc, p.created_at desc
  ),
  ws_active as (                       -- active 롤업
    select worksite_id, bool_or(is_active) as is_active
    from postings where deleted_at is null group by worksite_id
  ),
  stats as (                          -- 점수 집계(get_worksite_score_cards와 동일 규칙)
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
    join rep r       on r.worksite_id = w.id      -- 공고 있는 worksite만
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
    worksite_id                       -- tie-breaker: 페이지 경계 안정
  limit p_limit offset p_offset;
$$;
```

설계 근거 / 재검토에서 잡은 포인트:
- **정렬은 RPC 내부 `ORDER BY`** — 점수·리뷰수 집계를 기준으로 DB가 정렬. 프론트 재정렬 0.
- **tie-breaker `worksite_id`** 필수: 동점이 많으면(특히 리뷰 0인 worksite 다수) offset 페이징에서 행 중복/누락이 생긴다. 안정 정렬로 막는다.
- **`nulls last`**: 리뷰 없는 worksite(avg null)는 뒤로 — 현 클라 동작과 동일.
- **`count(*) over()`**: 페이지 행과 함께 총개수 1회 반환. (별도 count 쿼리 불필요.)
- **`ilike` 와일드카드**: `p_query`에 `%`·`_`가 들어오면 의도치 않은 매칭이 된다. 래퍼/ RPC에서 `replace`로 이스케이프(`\`,`%`,`_`)한다. 인젝션은 파라미터라 안전.
- 표시에 안 쓰는 공고 컬럼(min_grade·hourly_wage·job_category 등)은 반환 안 함(YAGNI).

### 3.2 `search_worksite_suggestions`

```sql
create or replace function search_worksite_suggestions(
  p_query text, p_limit int default 8
)
returns table(worksite_id int, organization_name text, workplace_name text,
              address text, region text)
language sql
security definer
as $$
  select w.id, w.organization_name, w.workplace_name, w.address, w.region
  from worksites w
  where w.deleted_at is null
    and exists (select 1 from postings p
                where p.worksite_id=w.id and p.deleted_at is null)
    and ( w.organization_name ilike '%'||p_query||'%' or
          w.workplace_name    ilike '%'||p_query||'%' )
  order by w.organization_name, w.workplace_name
  limit p_limit;
$$;
```

- 점수·집계 없음 → 가볍다.
- `exists(postings)`로 결과에 안 뜨는 worksite는 제안에서도 제외(일관성).
- 정렬: 이름순(단순). 빈 쿼리는 프론트가 호출 안 함.

## 4. data 계층 (`worksiteQueries.js`)

```js
// 카드 결과 + 총개수. flat RPC 행 → ResultCard가 쓰는 {worksite,posting,stats,is_active} 모양으로 변환.
export async function searchWorksiteCards({ query, sort, page, perPage }) {
  const { data, error } = await supabase.rpc('search_worksite_cards', {
    p_query: escapeLike(query ?? ''),
    p_sort:  sort,                       // 'recommend' | 'reviews'
    p_limit: perPage,
    p_offset: (page - 1) * perPage,
  })
  if (error) throw error
  const rows = data ?? []
  const total = rows.length ? Number(rows[0].total_count) : 0
  return { cards: rows.map(toCard), total }
}

export async function searchWorksiteSuggestions(query, limit = 8) {
  const { data, error } = await supabase.rpc('search_worksite_suggestions', {
    p_query: escapeLike(query), p_limit: limit,
  })
  if (error) throw error
  return data ?? []
}
```

- `escapeLike` / `toCard` (flat→nested 변환)는 **순수 함수** → `web/src/lib/searchCards.js`로 빼고 테스트 작성(프로젝트 규칙: 순수함수+테스트는 lib).
- `toCard`로 모양을 맞추면 **ResultCard는 거의 안 고쳐도 된다**(현 `{worksite,posting,stats}` 구조 유지).
- `fetchSearchPostings`·(Search 한정)`getWorksiteScoreCards` 호출 제거. 함수 자체는 다른 사용처 없으면 삭제.

## 5. 프론트 (`Search.jsx`) 변경

상태:
- `query`(입력값) / `submittedQuery`(실제 검색어, Enter 시 확정) / `sort` / `perPage` / `page`
- `cards` / `total` / `loading` / `error`
- `suggestions` / `showDropdown`

흐름:
- **입력 변경**: `query` 갱신 → trim 후 길이 ≥ 1이면 debounce(~200ms) 후 `searchWorksiteSuggestions` → 드롭다운 표시. 빈 입력이면 드롭다운 닫고 호출 안 함. (정렬·카드 건드리지 않음 — 부채 D 해소)
- **Enter / 검색버튼**: `submittedQuery=query`, `page=1`, 드롭다운 닫기.
- **`useEffect([submittedQuery, sort, perPage, page, authUser])`**: `searchWorksiteCards` 호출 → `cards`·`total` 세팅.
- 기존 `filtered`/`sorted`/`grouped` `useMemo` **전부 제거**.
- **드롭다운 항목 클릭** → `navigate('/worksite/'+id)`.
- 페이지수 `totalPages = max(1, ceil(total/perPage))` (직전 성공 응답의 total 사용). **페이지 범위 초과 처리**: 새 검색·정렬·perPage 변경 시 `page=1`로 리셋한다. 그래도 빈 페이지(rows=[])가 오고 `page>1`이면(다른 사용자가 데이터를 줄인 드문 경우) `page=1`로 재요청한다. → "또는" 없이 단일 규칙.
- 정렬 키 매핑: `추천순→recommend`, `리뷰많은순→reviews`. 잠금 시 `추천순` 고정 유지(옵션 1개).

드롭다운 UI: Search 내 소형 컴포넌트(또는 인라인). 각 줄 = `기관명 - 근무지명` + 주소(`address` 있으면 address, 없으면 `region` 폴백). 바깥 클릭·ESC로 닫힘.

ResultCard: `toCard` 덕에 props 모양 동일 → 변경 최소. 잠금 더미·블러(2단계) 그대로.

## 6. 에러 / 엣지

- RPC 에러 → 기존 `error` 분기로 표시.
- 결과 0 → `total=0`, 빈 상태 문구(`검색 결과가 없어요` / `표시할 근장이 없어요`).
- `page>totalPages` → 보정 후 재요청(§5).
- 빈 검색어 → cards는 전체 목록(페이징), 드롭다운은 호출 안 함.
- `ilike` 와일드카드 → `escapeLike`로 막음.

## 7. 추후 확장(이번 비범위, 경로만)

- **고급검색(debt-C)**: `search_worksite_cards`에 선택 필터 파라미터(`p_type, p_location, p_region, p_track, p_degree, p_status, p_duration ...`) 추가. 시그니처 변경이므로 그때 `DROP FUNCTION IF EXISTS ...` 먼저(CLAUDE.md §3-4) 후 재생성하는 마이그레이션.
- **점수 게이팅(debt-B)**: 잠금 시 RPC가 점수 컬럼을 NULL로 반환(`auth.uid()`로 pass 확인). 그러면 클라 더미도 불필요해질 수 있음.

## 8. 테스트 / 검증

- `lib/searchCards.test.js`: `escapeLike`(특수문자), `toCard`(flat→nested, null 점수 처리), 정렬키 매핑.
- DB: Docker 없으므로 sandbox 프로젝트에 `db push` 후 RPC 동작 확인(또는 Docker 있으면 `db reset`).
- 수동: 검색어 입력 시 드롭다운, 클릭 이동, Enter 카드 갱신, 정렬 2종, 페이지 이동, perPage 변경, 잠금 계정 더미·블러 유지.

## 9. 마이그레이션 운영 (CLAUDE.md §3)

1. 변경 전 디스코드 공유.
2. `migration new` → SQL(헤더 2줄) → sandbox `db push`(또는 `db reset`) 검증.
3. 본인이 `db push`. push 전 디스코드 한 마디.
4. 신규 함수라 `DROP` 불필요. `grant execute ... to authenticated`.