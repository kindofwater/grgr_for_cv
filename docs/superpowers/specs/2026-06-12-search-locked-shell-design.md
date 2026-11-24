# 근장찾기(Search) — 잠금 셸 설계

- 날짜: 2026-06-12
- 대상 파일: `web/src/pages/Search.jsx` (현재 빈 placeholder) → 실제 화면 구현
- 참고 mockup: `honeyjang/mockups/근로고래 mockup.html`
  - L.1302 `screen-search-lock` (로그인 + 열람권 없음 — 대시)
  - L.1399 `screen-search-lock-blur` (열람권 없음 — **블러, 채택**)
  - L.1495 `screen-search-default` (기본/열람권 있음)

## 1. 목표

`/search` 라우트에 전체 근장 목록 화면을 만든다. 핵심은 **열람권(viewing pass) 유무에 따른 잠금 상태**를 올바르게 렌더하는 것:
- 열람권 **없음** → 상단 lock-banner, 카드 점수 **블러**, 정렬 select `disabled`, 교환 CTA.
- 열람권 **있음** → 점수 정상 표시.

기존 `WorksiteDetail`의 잠금 패턴(CSS 블러 + `SECURITY-DEBT(auth)` 주석)과 `Home`의 데이터 패턴을 그대로 따른다.

## 2. 범위

### 이번 세션 (잠금 셸)
- 전체 근장 목록 데이터 fetch + worksite 단위 그룹화.
- 카드 렌더 (org/name, 태그, 항목별 평점 바, 추천%, 추천점수, 리뷰쓰기 버튼, 모집중/완료 상태).
- 열람권 상태 분기: 블러 / lock-banner / 정렬 disabled / 교환 CTA.
- 비로그인 → `/login` 리다이렉트.
- `전체 근장 N개` 카운트 = 매칭 근장 수.

### 다음 세션 (deferred — UI는 그리되 동작 X)
- 검색어 필터링.
- 고급필터 동작 (근로유형 스코프, 지역, 선호 계열/단대/학과 캐스케이드, 선호학년, 기간, 학위/학적, 모집중만, 최근리뷰만).
- 정렬 동작 (추천순/리뷰많은순/조회순/항목별순).
- **페이지네이션 동작** (per-page 개수 변경 + 페이지 이동). mockup의 per-page select 방식을 채택하며 **무한스크롤은 만들지 않는다**(페이지네이션과 중복).
- 필터 적용 시 카운트를 DB count로 전환.

## 3. 결정 로그

| 항목 | 결정 | 근거 |
|------|------|------|
| 범위 | 잠금 셸 먼저 | 사용자: "먼저 열람권 없음 구현" |
| 무열람권 표시 | **블러** (L.1399) | 기존 `WorksiteDetail`(ScoreSummary/ReviewList)과 일치, 데이터 존재감으로 교환 유도 |
| 카드 단위 | **근장(worksite)** | 카운트가 "매칭 근장 수" 기준 |
| 카드 데이터 | **새 RPC** (서버 집계) | 날 리뷰 클라이언트 미전송(앱 원칙). 사용자: 새 RPC OK, 디코공유·`db push`는 사용자가 |
| 열람권 판정 | `authUser.pass_expires_at > now` | `WorksiteDetail`과 동일 단일 진실원(AuthContext) |
| 비로그인 | `/login` 리다이렉트 | `WorksiteDetail` 선례 |
| 목록 분량 | **페이지네이션**(per-page) | 사용자: "페이지네이션 있으면 무한스크롤 안 만드는 게 좋음" |

## 4. 데이터 계층

### 4.1 새 RPC `get_worksite_score_cards`

`get_review_stats`(avg_score + review_count만 반환, Home 의존)는 **건드리지 않는다**. 카드가 항목별 평점·추천%를 보이므로 별도 RPC를 신설한다.

```sql
create or replace function get_worksite_score_cards(worksite_ids int[])
returns table(
  worksite_id    int,
  review_count   bigint,
  avg_recommend  numeric,  -- 추천 점수(big-num) = avg(score_recommend)
  avg_work       numeric,
  avg_growth     numeric,
  avg_vibe       numeric,
  avg_flex       numeric,
  recommend_rate int       -- score_recommend >= 4.0 비율(%) — computeScoreSummary와 동일
)
language sql
security definer
as $$
  select
    worksite_id,
    count(*)                                 as review_count,
    round(avg(score_recommend)::numeric, 1)  as avg_recommend,
    round(avg(score_work)::numeric, 1)       as avg_work,
    round(avg(score_growth)::numeric, 1)     as avg_growth,
    round(avg(score_vibe)::numeric, 1)       as avg_vibe,
    round(avg(score_flex)::numeric, 1)       as avg_flex,
    round(100.0 * count(*) filter (where score_recommend >= 4.0) / count(*))::int as recommend_rate
  from reviews
  where worksite_id = any(worksite_ids)
    and deleted_at is null
  group by worksite_id;
$$;

grant execute on function get_worksite_score_cards(int[]) to anon, authenticated;
```

- 마이그레이션 파일: `web/supabase/migrations/<timestamp>_worksite_score_cards.sql`.
- 헤더 2줄 필수: `-- 목적: 근장찾기 카드용 항목별 평점·추천율 집계 RPC` / `-- 날짜: 2026-06-12 · 담당: <작성자>`.
- 새 함수라 `DROP FUNCTION` 불필요(기존 시그니처 변경 아님).
- **검증**: 로컬 `supabase db reset`로 맨바닥 재구축 확인.
- **prod 반영(`db push`)·디스코드 공유는 사용자가 직접** (CLAUDE.md §3). Claude는 push하지 않음.

### 4.2 `data/worksiteQueries.js` 추가 함수

```js
// 근장찾기 목록: 매칭 공고 전부 fetch (대표공고 사전 선정 없음). 그룹화·대표선정은 호출부.
export async function fetchSearchPostings() {
  const { data, error } = await supabase.from('postings').select(HOME_POSTING_COLS)
    .not('worksite', 'is', null)
    .order('is_active', { ascending: false })
  if (error) throw error
  return data ?? []
}

// 카드 점수 집계 RPC 래퍼
export async function getWorksiteScoreCards(worksiteIds) {
  const { data, error } = await supabase
    .rpc('get_worksite_score_cards', { worksite_ids: worksiteIds })
  if (error) throw error
  return data ?? []
}
```

- `HOME_POSTING_COLS` 재사용(worksite 조인 + 카드 태그용 posting 컬럼 포함).
- 이번 세션은 필터 없음 → `limit` 없이 전부. 다음 세션에서 필터/페이징을 이 함수에 추가.

## 5. 페이지 흐름 (`Search.jsx`)

1. `useAuth()`로 `authUser`. **비로그인 → `navigate('/login')`** (mount effect, `WorksiteDetail`과 동일).
2. mount:
   - `fetchSearchPostings()` → 공고 전체.
   - **worksite 단위 그룹화** (Home 로직 재사용): `wsActiveMap`(한 공고라도 active면 모집중) + `byWorksite`(active-우선 대표공고 = 카드 태그 표시용) + worksite 단위 `is_active` 롤업.
   - `ids = 그룹화된 worksite id 배열` → `getWorksiteScoreCards(ids)` → `statsMap` 병합.
3. `hasPass = isPassActive(authUser?.pass_expires_at)` (§8 신규 순수함수).
4. 기본 정렬: `avg_recommend` desc (null 뒤). 정렬 드롭다운은 UI만(동작 X).
5. 카운트: `전체 근장 {그룹화된 worksite 수}개`.

> **가정(리뷰 때 확인)**: 한 근장에 매칭 공고가 여럿일 때, 카드의 posting-유래 태그(기간/학위/학적/선호)는 active-우선 대표공고 1개에서 가져온다. "대표공고 선정 안 함"은 fetch/필터 단계 규칙으로만 적용(모든 공고를 가져와 필터한 뒤 근장 추출). 표시용 대표선정은 별개.

## 6. 컴포넌트 (파일 내 로컬 — Home 패턴)

- `Search` (페이지 기본 export):
  - `Navbar`
  - `search-head`: 검색창(`search-bar-md`) + 고급검색 토글 버튼 — **정적**.
  - `filter-bar filter-advanced is-collapsed` — **정적**(mockup 마크업 그대로, onchange 핸들러 없음).
  - `lock-banner` — `!hasPass`일 때만. "열람권이 있으면 점수와 리뷰 내용을 확인할 수 있어요" + "열람권 교환하러 가기 →" → `/exchange`.
  - `results-bar`: per-page select(정적) · `전체 근장 N개` · 모집중/완료 legend · 정렬 select(`disabled` if `!hasPass`).
  - `result-list`: 카드 map.
- `ResultCard({ p, stats, locked, onOpen, onWrite })`:
  - 좌: `rc-org`(organization_name) · `rc-name`(workplace_name) · 태그(`tag-national/school`, `tag-loc`, `tag-region`, `tag-dur`, `tag-gray` 학위/학적).
  - 중: 평점 바 4개(업무/자기계발/분위기/시간유연성) — `locked`면 `score-blur` 래핑. `rec-text`: `리뷰 {review_count}개 · {recommend_rate}%가 이 근무지를 추천합니다`.
  - 우: `big-num`(avg_recommend) + `추천 점수` — `locked`면 `score-blur`. `btn-review-write` 리뷰쓰기.
  - 카드 className: `status-open`(is_active) / `status-closed`.
- 평점 바 색(`fill-green/yellow/red/blue`)은 값 임계로 결정하는 순수 헬퍼.

## 7. 상태 / 엣지

- 카드 클릭 → `onOpen` → `/worksite/:id` (상세에서도 블러됨 — 일관).
- 리뷰쓰기 → `onWrite` → `/worksite/:id/review`, `event.stopPropagation()`로 카드 클릭과 분리.
- 리뷰 0개 근장: `avg_*`·바 = `-`/빈값, `recommend_rate` 미표시 또는 0, `리뷰 없음`.
- loading: 간단 스켈레톤/placeholder. error: 메시지(Home 패턴).
- `getWorksiteScoreCards` 실패: `console.warn` 후 점수 생략(Home의 `get_review_stats` 실패 처리와 동일하게 graceful).

## 8. 테스트 (TDD)

- `lib/passes.js`에 순수함수 추가:
  ```js
  export function isPassActive(expiresAt, now = new Date()) {
    return !!(expiresAt && new Date(expiresAt) > now)
  }
  ```
- `lib/passes.test.js` 케이스: 만료 전(true) / 만료 후(false) / null(false) / 경계.
- `WorksiteDetail`의 인라인 `hasPass` 계산을 `isPassActive`로 교체(같은 로직, 중복 제거).
- 평점 바 색 헬퍼도 순수함수면 간단 테스트 추가.

## 9. CSS (`Search.css` 신규, 페이지 병치)

- `index.css`의 토큰(`--primary-dark` 등)·태그 클래스(`tag-national` 등) 재사용 — 재정의 금지.
- mockup `<style>`에서 포팅: `search-head · search-bar-md · filter-toggle-btn · filter-bar/filter-advanced · lock-banner · results-bar · per-page-select · sort-select · result-list · result-card · rc-org/rc-name · tag-rows · rc-mid · rating-bars · rb-item/rb-label/rb-track/rb-fill(+fill-*) · rec-text · rc-right · big-num/big-label · score-blur · btn-review-write · status-open/closed`.

## 10. 보안 노트

- 블러는 CSS 마스킹일 뿐 실 점수가 DOM에 존재 → 기존 앱이 받아들인 `SECURITY-DEBT(auth) #3`와 동일. 카드에도 동일 주석 표기. 추후 Auth+RLS로 서버 게이팅 시 RPC가 잠금 유저에 점수 미반환하도록 전환.
- RPC는 `security definer` + 집계만 반환(개별 리뷰 본문·작성자 미노출).
