# 비로그인 공개(soft-wall) + AdSense 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 비로그인 방문자/크롤러에게 근무지 정보 + 리뷰 개수·추천율까지 공개하여 AdSense 승인·SEO를 확보하되, 세부 별점·리뷰 본문은 로그인/열람권 뒤에 유지한다.

**Architecture:** 프론트 피처 플래그(`PUBLIC_BROWSE`)로 로그인 리다이렉트를 우회하고, 비로그인 경로는 **anon 화이트리스트 RPC**(`get_worksite_public_detail` 신설 + 기존 `get_worksite_score_cards`·`search_worksite_cards`)만 호출한다. 리뷰 본문 RPC(`list_worksite_reviews`)는 authenticated 전용 그대로 → 비로그인은 리뷰를 원천적으로 못 받는다. 테이블 anon SELECT는 열지 않는다.

**Tech Stack:** React 19 + Vite, react-router-dom 7, Supabase(Postgres, security-definer RPC), vitest(순수함수 테스트만).

## Global Constraints

- **anon에 테이블 SELECT 금지** — 비로그인 데이터는 화이트리스트 RPC로만. 반환 필드에 `contact_name`·내부 관리 컬럼·리뷰 본문 절대 포함 금지.
- **단일 토글:** 모든 비로그인 접근은 `PUBLIC_BROWSE` 하나로 여닫힌다.
- **리뷰 본문 RPC(`list_worksite_reviews`) 변경 금지** (authenticated 전용 유지).
- **DB 변경 규칙(CLAUDE.md §3):** 마이그레이션 파일 맨 위 헤더 2줄(`-- 목적:` / `-- 날짜: YYYY-MM-DD · 담당:`), 시그니처 변경 시 `DROP FUNCTION` 선행, 로컬 db reset 검증 후 `db push`(배경록 직접).
- **AdSense 퍼블리셔:** `ca-pub-2107047521899823`.
- **커밋:** 한국어 conventional commit, 태스크 단위로 자주.
- **테스트 현실:** 컴포넌트 테스트 하네스 없음 → 프론트는 `npm run dev`로 로그아웃 상태 행위 검증, RPC는 SQL 쿼리 검증.

---

### Task 1: 피처 플래그 설정

**Files:**
- Create: `web/src/config.js`

**Interfaces:**
- Produces: `export const PUBLIC_BROWSE: boolean` — 비로그인 공개 on/off. Task 5·6이 소비.

- [ ] **Step 1: config.js 생성**

```js
// 앱 전역 피처 플래그.
// PUBLIC_BROWSE: 비로그인에게 근무지 정보 + 리뷰 개수·추천율 공개(soft-wall). AdSense/SEO용.
//   다학교 확장 시 false + anon RPC 권한 회수(닫기 런북, spec §5)로 함께 닫는다.
export const PUBLIC_BROWSE = true
```

- [ ] **Step 2: import 확인**

Run: `cd web && node -e "import('./src/config.js').then(m=>console.log('PUBLIC_BROWSE=', m.PUBLIC_BROWSE))"`
Expected: `PUBLIC_BROWSE= true`

- [ ] **Step 3: 커밋**

```bash
git add web/src/config.js
git commit -m "feat(config): 비로그인 공개 피처 플래그 PUBLIC_BROWSE 추가"
```

---

### Task 2: 백엔드 — get_worksite_public_detail RPC + anon 권한 (마이그레이션)

**Files:**
- Create: `web/supabase/migrations/20260716120000_public_browse_rpc.sql`

**Interfaces:**
- Produces: RPC `get_worksite_public_detail(p_worksite_id int) returns table(worksite jsonb, posting jsonb)` — anon/authenticated 실행 가능. `search_worksite_cards`에 anon 실행 권한 추가. Task 3이 소비.

- [ ] **Step 1: 마이그레이션 SQL 작성**

```sql
-- 목적: 비로그인 공개용 근무지 상세 RPC(InfoCard 필드만 화이트리스트, contact_name·내부컬럼·리뷰 제외) + 검색 RPC anon 권한
-- 날짜: 2026-07-16 · 담당: 배경록

-- 근무지 정보 화이트리스트 RPC (대표 공고 1개: 활성 우선 → 최신)
drop function if exists get_worksite_public_detail(int);
create or replace function get_worksite_public_detail(p_worksite_id int)
returns table (worksite jsonb, posting jsonb)
language sql security definer set search_path = public as $$
  with rep as (
    select p.*
    from postings p
    where p.worksite_id = p_worksite_id and p.deleted_at is null
    order by p.is_active desc, p.created_at desc
    limit 1
  )
  select
    jsonb_build_object(
      'organization_name', w.organization_name,
      'workplace_name',    w.workplace_name,
      'type',              w.type,
      'location_type',     w.location_type,
      'address',           w.address,
      'region',            w.region
    ) as worksite,
    case when rep.id is null then null else
      jsonb_build_object(
        'is_active',               rep.is_active,
        'preferred_track',         rep.preferred_track,
        'min_grade',               rep.min_grade,
        'eligible_degree',         rep.eligible_degree,
        'eligible_status',         rep.eligible_status,
        'recruitment_period_text', rep.recruitment_period_text,
        'recruit_count',           rep.recruit_count,
        'hourly_wage',             rep.hourly_wage,
        'work_period_text',        rep.work_period_text,
        'work_time_text',          rep.work_time_text,
        'job_description',         rep.job_description,
        'preference_notes',        rep.preference_notes,
        'extra_notes',             rep.extra_notes,
        'source_url',              rep.source_url
      )
    end as posting
  from worksites w
  left join rep on true
  where w.id = p_worksite_id and w.deleted_at is null;
$$;

revoke execute on function get_worksite_public_detail(int) from public;
grant  execute on function get_worksite_public_detail(int) to anon, authenticated;

-- 검색 RPC: 이미 화이트리스트(필드 제한). 비로그인 검색 위해 anon 실행 권한만 부여.
grant execute on function search_worksite_cards(text,text,int,int,text[],text[],text[],text[],text[],int[],int[],boolean[]) to anon;

-- 참고: get_worksite_score_cards·get_review_stats 는 이미 anon 허용(20260708 마이그레이션). 변경 없음.
-- 참고: list_worksite_reviews 는 authenticated 전용 유지(리뷰 본문 보호). 변경 없음.
```

- [ ] **Step 2: 로컬 db reset 검증 (가능 시)**

Run: `cd web && npx supabase db reset`
Expected: 에러 없이 맨바닥 재구축 성공. (Docker 불가 환경이면 이 스텝 스킵하고 Step 3의 원격 검증으로 대체 — spec/CLAUDE.md 규칙)

- [ ] **Step 3: db push 후 anon 반환 필드 검증**

`db push`(배경록) 후, Supabase SQL 에디터 또는 anon 키로 다음 확인:
```sql
select worksite, posting from get_worksite_public_detail(<존재하는_worksite_id>);
```
Expected: `worksite`에 organization_name/workplace_name/type/location_type/address/region만, `posting`에 위 화이트리스트 필드만. **`contact_name`·리뷰 관련 필드가 없어야 함.**

- [ ] **Step 4: 커밋**

```bash
git add web/supabase/migrations/20260716120000_public_browse_rpc.sql
git commit -m "feat(rpc): 비로그인 공개용 get_worksite_public_detail 화이트리스트 RPC + 검색 anon 권한"
```

---

### Task 3: 데이터 레이어 — 공개 상세·점수 조회 함수

**Files:**
- Modify: `web/src/data/worksiteQueries.js` (파일 상단, `fetchReviews` 근처에 추가)

**Interfaces:**
- Consumes: `get_worksite_public_detail`, `get_worksite_score_cards` (Task 2 / 기존).
- Produces:
  - `fetchWorksitePublicDetail(id): Promise<{worksite, posting}>` — InfoCard가 쓰는 shape.
  - `fetchWorksiteScoreCard(id): Promise<{review_count:int, recommend_rate:int}>` (기타 avg 필드도 오지만 소비 안 함).
  - Task 5가 소비.

- [ ] **Step 1: 두 함수 추가**

```js
// 비로그인 공개용 근무지 상세 — 화이트리스트 RPC(contact_name·리뷰 제외). InfoCard shape 반환.
export async function fetchWorksitePublicDetail(id) {
  const { data, error } = await supabase
    .rpc('get_worksite_public_detail', { p_worksite_id: Number(id) })
  if (error) throw error
  const row = data?.[0]
  if (!row) throw new Error('근무지를 찾을 수 없어요.')
  return { worksite: row.worksite, posting: row.posting }
}

// 비로그인 공개용 점수 집계 — 개수·추천율만 사용(본문 경유 없음).
export async function fetchWorksiteScoreCard(id) {
  const { data, error } = await supabase
    .rpc('get_worksite_score_cards', { worksite_ids: [Number(id)] })
  if (error) throw error
  return data?.[0] ?? { review_count: 0, recommend_rate: 0 }
}
```

- [ ] **Step 2: 문법·export 확인**

Run: `cd web && npm run lint`
Expected: 새 함수 관련 에러 없음.

- [ ] **Step 3: 커밋**

```bash
git add web/src/data/worksiteQueries.js
git commit -m "feat(data): 비로그인 공개 상세·점수 조회 함수 추가"
```

---

### Task 4: ScoreSummary — public 변형(개수·추천율만)

**Files:**
- Modify: `web/src/components/ScoreSummary.jsx`

**Interfaces:**
- Consumes: `summary: {count:int, recommendRate:int}` (Task 5가 공개 집계로 구성).
- Produces: `<ScoreSummary summary={...} publicOnly />` — "리뷰 N개 · X% 추천"만 렌더(세부 별점 없음). Task 5가 사용.

- [ ] **Step 1: publicOnly 분기 추가**

`export default function ScoreSummary({ summary, locked })` → `({ summary, locked, publicOnly })`로 바꾸고, `summary.count === 0` 처리 **다음에** 아래 블록 추가:

```jsx
  if (publicOnly) {
    return (
      <div className="summary-card locked-summary">
        <div className="public-rec">리뷰 {summary.count}개 · <strong>{summary.recommendRate}%</strong>가 이 근무지를 추천합니다</div>
      </div>
    )
  }
```

(세부 별점·score-mask 없음. 기존 `locked`/일반 분기는 그대로 둔다.)

- [ ] **Step 2: 렌더 확인 (Task 5 완료 후 통합 검증) — 여기선 lint만**

Run: `cd web && npm run lint`
Expected: 에러 없음.

- [ ] **Step 3: 커밋**

```bash
git add web/src/components/ScoreSummary.jsx
git commit -m "feat(score): ScoreSummary public 변형(개수·추천율만) 추가"
```

---

### Task 5: WorksiteDetail — 비로그인 공개 경로

**Files:**
- Modify: `web/src/pages/WorksiteDetail.jsx`

**Interfaces:**
- Consumes: `PUBLIC_BROWSE`(T1), `fetchWorksitePublicDetail`·`fetchWorksiteScoreCard`(T3), `ScoreSummary publicOnly`(T4).

- [ ] **Step 1: import 추가**

상단 import에 추가:
```js
import { PUBLIC_BROWSE } from '../config'
```
그리고 `../data/worksiteQueries` import 목록에 `fetchWorksitePublicDetail, fetchWorksiteScoreCard` 추가.

- [ ] **Step 2: useEffect — 리다이렉트 우회 + 비로그인 분기**

`useEffect` 안의 `if (!authUser) { navigate('/login', { replace: true }); return }`(현 33행)을 아래로 교체:

```js
    if (!authUser && !PUBLIC_BROWSE) { navigate('/login', { replace: true }); return }
    let alive = true
    setState({ error: null })
    setHelpfulIds(new Set())

    // 비로그인 공개 경로: 화이트리스트 RPC + 집계만(리뷰 본문 안 가져옴)
    if (!authUser) {
      Promise.all([fetchWorksitePublicDetail(id), fetchWorksiteScoreCard(id)])
        .then(([detail, card]) => {
          if (!alive) return
          setState((s) => ({
            ...s,
            worksite: detail.worksite,
            posting: detail.posting,
            publicSummary: { count: card.review_count, recommendRate: card.recommend_rate },
          }))
        })
        .catch((e) => { if (alive) setState((s) => ({ ...s, error: e.message })) })
      return () => { alive = false }
    }
```

이 블록을 기존 `Promise.all([fetchWorksite... ` (그룹 A) **앞**에 두어, 비로그인이면 기존 로그인 경로(그룹 A/B·incrementViewCount)를 타지 않게 한다. 기존 로그인 경로 코드는 그대로 둔다.

- [ ] **Step 3: 렌더 — 비로그인 분기**

렌더부의 준비 플래그와 JSX를 아래처럼 조정한다. `locked`/`infoReady`/`reviewsReady` 정의 근처:

```js
  const isAnon = !authUser
  const locked = !isPassActive(authUser?.pass_expires_at)
  const infoReady = isAnon ? !!state.worksite : (state.worksite && state.posting)
  const reviewsReady = !isAnon && infoReady && state.reviews
```

InfoCard 아래 점수/리뷰 렌더 블록을 교체:

```jsx
        {infoReady && <InfoCard worksite={state.worksite} posting={state.posting} />}
        {isAnon ? (
          state.publicSummary && (
            <>
              <ScoreSummary summary={state.publicSummary} publicOnly />
              <div className="review-login-prompt">
                <p>리뷰는 로그인하고 볼 수 있어요.</p>
                <button className="btn-unlock" onClick={() => navigate('/login')}>로그인하고 리뷰 보기</button>
              </div>
            </>
          )
        ) : (
          <>
            {reviewsReady && <ScoreSummary summary={summary} locked={locked} />}
          </>
        )}
```

그리고 기존 `{reviewsReady && (<ReviewList .../>)}` 블록은 그대로 둔다(비로그인이면 `reviewsReady`가 false라 안 뜸). → **비로그인은 ReviewList가 아예 렌더 안 되므로 리뷰 쓰기·도움돼요·신고 액션이 노출되지 않는다**(액션 가드 자동 충족). 리뷰 진입은 위 "로그인하고 리뷰 보기" 버튼으로만.

- [ ] **Step 4: `.review-login-prompt` 스타일 추가**

`web/src/pages/WorksiteDetail.css` 하단에:
```css
.review-login-prompt { text-align: center; padding: 32px 20px; color: var(--text-sub); }
.review-login-prompt p { margin: 0 0 12px; font-size: 14px; }
```

- [ ] **Step 5: 행위 검증 (개발 서버, 로그아웃 상태)**

Run: `cd web && npm run dev` → 브라우저에서 **로그아웃 상태**로 `/worksite/<id>` 진입.
Expected: `/login`으로 안 튕기고, 근무지 정보 + "리뷰 N개 · X% 추천" + "로그인하고 리뷰 보기" 버튼이 보임. 세부 별점·리뷰 본문 없음. 콘솔 에러 없음. (Network 탭: `get_worksite_public_detail`·`get_worksite_score_cards`만 호출, `list_worksite_reviews` 없음.)

- [ ] **Step 6: 회귀 검증 (로그인 상태)**

로그인(무열람권/열람권 각각)으로 `/worksite/<id>` 진입 → 기존과 동일 동작(무열람권=블러 티저/마스킹, 열람권=전체). 

- [ ] **Step 7: 커밋**

```bash
git add web/src/pages/WorksiteDetail.jsx web/src/pages/WorksiteDetail.css
git commit -m "feat(worksite): 비로그인 공개 경로(정보+개수·추천율, 리뷰 잠금)"
```

---

### Task 6: Search — 비로그인 접근

**Files:**
- Modify: `web/src/pages/Search.jsx`

**Interfaces:**
- Consumes: `PUBLIC_BROWSE`(T1), `search_worksite_cards` anon 권한(T2).

- [ ] **Step 1: import + 리다이렉트 우회**

상단에 `import { PUBLIC_BROWSE } from '../config'` 추가. 현 164행 `if (!authUser) navigate('/login', { replace: true })`을 `if (!authUser && !PUBLIC_BROWSE) navigate('/login', { replace: true })`로. 같은 이펙트 내 이어지는 `if (!authUser) return`(현 169행)은 — 비로그인도 검색 결과를 받아야 하므로 — `if (!authUser && !PUBLIC_BROWSE) return`로 바꾼다.

- [ ] **Step 2: 로그인 회귀 확인**

로그인 상태로 `/search` 진입 → 기존 동작(정렬·필터·카드) 유지. (카드 점수 노출 일관성은 Task 9에서 홈과 함께 일괄 처리.)

- [ ] **Step 3: 행위 검증 (로그아웃 상태)**

Run: `npm run dev` → 로그아웃 상태로 `/search` 및 `/search?q=...` 진입.
Expected: 로그인 안 튕기고 검색 결과 카드(근무지 정보 + 개수/추천율) 표시, 콘솔 에러 없음. (`search_worksite_cards` 401/권한 에러 없어야 — T2 grant 적용 후.)

- [ ] **Step 4: 커밋**

```bash
git add web/src/pages/Search.jsx
git commit -m "feat(search): 비로그인 검색 허용(PUBLIC_BROWSE)"
```

---

### Task 7: AdSense 사이트 연결

**Files:**
- Modify: `web/index.html`
- Create: `web/public/ads.txt`

- [ ] **Step 1: index.html `<head>`에 AdSense 스니펫**

`</head>` 바로 위에 추가:
```html
    <script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=ca-pub-2107047521899823" crossorigin="anonymous"></script>
    <meta name="google-adsense-account" content="ca-pub-2107047521899823" />
```

- [ ] **Step 2: ads.txt 생성**

`web/public/ads.txt`:
```
google.com, pub-2107047521899823, DIRECT, f08c47fec0942fa0
```

- [ ] **Step 3: 빌드 산출 확인**

Run: `cd web && npm run build`
Expected: 빌드 성공. `web/dist/ads.txt` 존재(내용 동일), `web/dist/index.html` `<head>`에 adsbygoogle 스크립트 포함.

- [ ] **Step 4: 커밋**

```bash
git add web/index.html web/public/ads.txt
git commit -m "feat(adsense): 사이트 연결 스크립트/meta + ads.txt"
```

---

### Task 8: SEO 기본 — robots.txt + sitemap.xml

**Files:**
- Create: `web/public/robots.txt`
- Create: `web/public/sitemap.xml`

> canonical·per-page 동적 meta는 SPA head 동적 관리가 필요해 spec §8 후속(per-page meta)과 함께 처리한다. 이 태스크는 정적 파일만.

- [ ] **Step 1: robots.txt**

`web/public/robots.txt`:
```
User-agent: *
Allow: /
Sitemap: https://grgr.kr/sitemap.xml
```

- [ ] **Step 2: sitemap.xml (주요 라우트)**

`web/public/sitemap.xml`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>https://grgr.kr/home</loc></url>
  <url><loc>https://grgr.kr/search</loc></url>
  <url><loc>https://grgr.kr/notice</loc></url>
</urlset>
```
> 근무지별 URL(`/worksite/<id>`) 자동 생성 sitemap은 빌드 스크립트로 별도(후속). 우선 주요 라우트만.

- [ ] **Step 3: 접근 확인**

Run: `cd web && npm run build`
Expected: `web/dist/robots.txt`·`web/dist/sitemap.xml` 존재.

- [ ] **Step 4: 커밋**

```bash
git add web/public/robots.txt web/public/sitemap.xml
git commit -m "feat(seo): robots.txt + 주요 라우트 sitemap.xml"
```

---

### Task 9: 카드 점수 일관성 확인 (Home/Search)

**Files:**
- Modify(조건부): `web/src/pages/Home.jsx`, `web/src/pages/Search.jsx`

- [ ] **Step 1: 카드 점수 렌더 위치 찾기**

Run: `cd web && npx vitest related --run 2>/dev/null; grep -nE "avg_work|avg_growth|avg_vibe|avg_flex|score-|recommend_rate|avg_recommend" src/pages/Home.jsx src/pages/Search.jsx`
목적: 카드가 **항목별 세부 별점(avg_work/growth/vibe/flex 또는 항목별 막대)** 을 그리는지 확인. 로그아웃 상태 `/home`·`/search`도 눈으로 확인.

- [ ] **Step 2: 규칙 적용**

- **허용(변경 없음):** 개수, 추천율(recommend_rate), **단일 평균(avg_recommend)** 표시 → 비로그인에 그대로 노출 OK(공개 정책 부합).
- **감쌈:** 카드가 **항목별 세부 별점(avg_work/growth/vibe/flex, 4개 막대)** 을 비로그인에 그리면 그 JSX만 `{isLoggedIn && ( … )}`로 감싼다. (대부분 카드는 단일 평균+추천율이라 변경 없을 가능성 높음.)

- [ ] **Step 3: 커밋(변경 있을 때만)**

```bash
git add web/src/pages/Home.jsx web/src/pages/Search.jsx
git commit -m "fix(cards): 비로그인 카드 점수 노출을 공개 정책과 일치"
```

---

## 실행 후 통합 검증 (전 태스크 후)

1. `db push`(배경록) 완료 확인 → 배포.
2. **grgr.kr 로그아웃 상태**: `/home`·`/search`·`/worksite/<id>` 모두 로그인 안 튕기고 정보+개수/추천율 보임, 리뷰 본문·세부 별점 미노출, 콘솔 에러 없음.
3. Network: `get_worksite_public_detail`·`get_worksite_score_cards`·`search_worksite_cards`만, `list_worksite_reviews` 없음. `get_worksite_public_detail` 응답에 `contact_name` 없음.
4. 로그인(무열람권/열람권) 기존 동작 유지.
5. AdSense: `grgr.kr/ads.txt` 접근 가능, head에 스크립트 존재 → AdSense 콘솔에서 사이트 검토 요청.
6. **닫기 리허설(선택):** `PUBLIC_BROWSE=false` + anon RPC revoke → 로그인 벽 원복 확인 후 되돌림.

## 후속 (범위 밖 — spec §8)
- debt#3 서버 게이팅(무열람권 로그인 리뷰 본문 유출) — 별도 이슈 `project-debt3-review-body-gating`.
- per-page 동적 title/meta/canonical.
- 근무지별 URL sitemap 빌드 스크립트.
- thin content 시 빈약 근무지 noindex.
