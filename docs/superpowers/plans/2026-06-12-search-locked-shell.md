# 근장찾기(Search) 잠금 셸 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `/search` 페이지에 전체 근장 목록을 렌더하고, 열람권 유무에 따라 점수를 블러/표시한다(잠금 셸).

**Architecture:** `Home` 패턴을 따른다 — `Search.jsx` 페이지 + 파일 내 로컬 컴포넌트 + 병치 `Search.css`. 데이터는 `data/worksiteQueries.js`의 새 함수 2개 + 새 RPC `get_worksite_score_cards`(서버 집계)로 가져온다. 열람권 판정은 `lib/passes.js`의 순수함수 `isPassActive`로 단일화한다.

**Tech Stack:** React 19 + Vite, react-router-dom 7, Supabase JS, Vitest.

**참고:** 설계 = `docs/superpowers/specs/2026-06-12-search-locked-shell-design.md`. mockup = `honeyjang/mockups/근로고래 mockup.html` (L.1399 블러 채택).

**Git:** 현재 브랜치 `signup-login`(작업 트리에 내 것이 아닌 미커밋 변경 존재). 새 브랜치 `feat/search-locked-shell`를 파서 작업하고, 각 커밋은 **내가 만든 파일만 명시적으로 `git add`** 한다(기존 미커밋 변경은 건드리지 않음). 푸시는 하지 않는다.

---

## File Structure

| 파일 | 동작 | 책임 |
|------|------|------|
| `web/src/index.css` | Modify | `--warn` 토큰 추가(노란 막대용; 현재 미정의) |
| `web/src/lib/passes.js` | Modify | `isPassActive(expiresAt, now)` 순수함수 추가 |
| `web/src/lib/passes.test.js` | Modify | `isPassActive` 테스트 |
| `web/src/lib/scores.js` | Modify | `ratingBarColor(value)` 순수함수 추가 |
| `web/src/lib/scores.test.js` | Modify | `ratingBarColor` 테스트 |
| `web/supabase/migrations/20260612130000_worksite_score_cards.sql` | Create | 새 RPC `get_worksite_score_cards` |
| `web/src/data/worksiteQueries.js` | Modify | `fetchSearchPostings()` + `getWorksiteScoreCards()` |
| `web/src/pages/Search.css` | Create | 검색 페이지 스타일(mockup 포팅) |
| `web/src/pages/Search.jsx` | Rewrite | 페이지 본체 + `ResultCard`/`RatingBar` 로컬 컴포넌트 |
| `web/src/pages/WorksiteDetail.jsx` | Modify | 인라인 `hasPass` → `isPassActive`로 교체 |
| `web/src/pages/README.md` | Modify | Search 행 갱신(구현됨 + css) |
| `web/src/data/README.md` | Modify | 새 함수 2개 기재 |

테스트: 컴포넌트/페이지 단위 테스트 인프라는 코드베이스에 없음(현재 `lib`만 vitest). 신규 순수함수만 단위 테스트하고, 페이지는 §Task 10 수동 검증으로 확인(코드베이스 관행 유지, YAGNI).

---

## Task 1: `--warn` 토큰 추가

**Files:**
- Modify: `web/src/index.css` (`--good`/`--danger` 정의 부근, 38~40행 근처)

- [ ] **Step 1: `--warn` 추가**

`web/src/index.css`의 `--good: #3CA171;` 줄 바로 아래에 추가:

```css
  --warn:          #E89A1F;
```

(mockup `:root`의 `--warn` 값과 동일. `.fill-yellow { background: var(--warn); }`가 이걸 참조.)

- [ ] **Step 2: 커밋**

```bash
git add web/src/index.css
git commit -m "style: add --warn token for rating bar yellow"
```

---

## Task 2: `isPassActive` 순수함수 (TDD)

**Files:**
- Modify: `web/src/lib/passes.js`
- Test: `web/src/lib/passes.test.js`

- [ ] **Step 1: 실패하는 테스트 작성**

`web/src/lib/passes.test.js` 상단 import에 `isPassActive`를 추가하고(기존 import 줄에 합치기), 파일 끝에 추가:

```js
import { isPassActive } from './passes'

describe('isPassActive', () => {
  const now = new Date('2026-06-12T00:00:00Z')
  it('만료가 미래면 true', () => {
    expect(isPassActive('2026-06-20T00:00:00Z', now)).toBe(true)
  })
  it('만료가 과거면 false', () => {
    expect(isPassActive('2026-06-01T00:00:00Z', now)).toBe(false)
  })
  it('정확히 now면 false (strictly greater)', () => {
    expect(isPassActive('2026-06-12T00:00:00Z', now)).toBe(false)
  })
  it('null/undefined면 false', () => {
    expect(isPassActive(null, now)).toBe(false)
    expect(isPassActive(undefined, now)).toBe(false)
  })
})
```

> `passes.test.js`에 이미 `import { ... } from './passes'`가 있으면 거기에 `isPassActive`만 추가하고, `describe`/`it`/`expect`가 전역(vitest globals)인지 확인 — 기존 테스트 형식을 그대로 따른다.

- [ ] **Step 2: 실패 확인**

Run: `cd web && npx vitest run src/lib/passes.test.js`
Expected: FAIL — `isPassActive is not a function` / not exported.

- [ ] **Step 3: 구현**

`web/src/lib/passes.js` 끝에 추가:

```js
// 열람권 활성 여부 — 만료시각이 현재보다 미래면 true. (WorksiteDetail·Search 공용 단일 진실)
export function isPassActive(expiresAt, now = new Date()) {
  return !!(expiresAt && new Date(expiresAt) > now)
}
```

- [ ] **Step 4: 통과 확인**

Run: `cd web && npx vitest run src/lib/passes.test.js`
Expected: PASS

- [ ] **Step 5: 커밋**

```bash
git add web/src/lib/passes.js web/src/lib/passes.test.js
git commit -m "feat(lib): add isPassActive pure helper"
```

---

## Task 3: `ratingBarColor` 순수함수 (TDD)

**Files:**
- Modify: `web/src/lib/scores.js`
- Test: `web/src/lib/scores.test.js`

임계값은 기본(열람권 있음) mockup `screen-search-default`의 실제 색 기준: `>=4.5` 파랑, `>=4.0` 초록, `>=3.0` 노랑, 그 외 빨강.

- [ ] **Step 1: 실패하는 테스트 작성**

`web/src/lib/scores.test.js`에 추가(파일 상단 import에 `ratingBarColor` 합치기):

```js
import { ratingBarColor } from './scores'

describe('ratingBarColor', () => {
  it('>=4.5 → fill-blue', () => {
    expect(ratingBarColor(4.5)).toBe('fill-blue')
    expect(ratingBarColor(5.0)).toBe('fill-blue')
  })
  it('4.0~4.4 → fill-green', () => {
    expect(ratingBarColor(4.0)).toBe('fill-green')
    expect(ratingBarColor(4.4)).toBe('fill-green')
  })
  it('3.0~3.9 → fill-yellow', () => {
    expect(ratingBarColor(3.0)).toBe('fill-yellow')
    expect(ratingBarColor(3.9)).toBe('fill-yellow')
  })
  it('<3.0 → fill-red', () => {
    expect(ratingBarColor(2.5)).toBe('fill-red')
    expect(ratingBarColor(0.5)).toBe('fill-red')
  })
  it('null → 빈 문자열', () => {
    expect(ratingBarColor(null)).toBe('')
  })
})
```

- [ ] **Step 2: 실패 확인**

Run: `cd web && npx vitest run src/lib/scores.test.js`
Expected: FAIL — `ratingBarColor is not a function`.

- [ ] **Step 3: 구현**

`web/src/lib/scores.js` 끝에 추가:

```js
// 평점 값(0.5~5.0)에 따른 막대 색 클래스. 기준: 기본 mockup(search-default)의 실제 색.
export function ratingBarColor(value) {
  if (value == null) return ''
  if (value >= 4.5) return 'fill-blue'
  if (value >= 4.0) return 'fill-green'
  if (value >= 3.0) return 'fill-yellow'
  return 'fill-red'
}
```

- [ ] **Step 4: 통과 확인**

Run: `cd web && npx vitest run src/lib/scores.test.js`
Expected: PASS

- [ ] **Step 5: 커밋**

```bash
git add web/src/lib/scores.js web/src/lib/scores.test.js
git commit -m "feat(lib): add ratingBarColor pure helper"
```

---

## Task 4: 새 RPC 마이그레이션

**Files:**
- Create: `web/supabase/migrations/20260612130000_worksite_score_cards.sql`

- [ ] **Step 1: 마이그레이션 파일 작성**

```sql
-- 목적: 근장찾기 카드용 항목별 평점·추천율 집계 RPC (get_review_stats는 Home 의존이라 미변경)
-- 날짜: 2026-06-12 · 담당: <작성자>

create or replace function get_worksite_score_cards(worksite_ids int[])
returns table(
  worksite_id    int,
  review_count   bigint,
  avg_recommend  numeric,
  avg_work       numeric,
  avg_growth     numeric,
  avg_vibe       numeric,
  avg_flex       numeric,
  recommend_rate int
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

> `<작성자>`를 실제 담당자명으로 교체. 새 함수라 `DROP FUNCTION` 불필요.

- [ ] **Step 2: (사용자) 로컬 검증 + 배포**

`cd web && npx supabase db reset` 로 맨바닥 재구축이 안 깨지는지 확인. **`db push`·디스코드 공유는 사용자가 직접**(CLAUDE.md §3). Claude는 push하지 않음. 로컬 supabase가 없으면 이 스텝은 사용자 환경에서 수행.

- [ ] **Step 3: 커밋**

```bash
git add web/supabase/migrations/20260612130000_worksite_score_cards.sql
git commit -m "feat(db): add get_worksite_score_cards RPC for search cards"
```

---

## Task 5: 데이터 함수 추가

**Files:**
- Modify: `web/src/data/worksiteQueries.js` (`fetchHomePostings` 아래, `HOME_POSTING_COLS` 재사용)

- [ ] **Step 1: 함수 2개 추가**

`fetchHomePostings` 함수 정의 바로 아래에 추가:

```js
// 근장찾기 목록: 매칭 공고 전부 fetch (대표공고 사전 선정 없음 — 그룹화·대표선정은 호출부).
// 이번 세션은 필터 없음 → limit 없이 전부. (다음 세션에서 필터/페이징 추가)
export async function fetchSearchPostings() {
  const { data, error } = await supabase
    .from('postings').select(HOME_POSTING_COLS)
    .not('worksite', 'is', null)
    .order('is_active', { ascending: false })
  if (error) throw error
  return data ?? []
}

// 근장찾기 카드 점수 집계 RPC 래퍼. 반환: [{ worksite_id, review_count, avg_recommend,
//   avg_work, avg_growth, avg_vibe, avg_flex, recommend_rate }]
export async function getWorksiteScoreCards(worksiteIds) {
  const { data, error } = await supabase
    .rpc('get_worksite_score_cards', { worksite_ids: worksiteIds })
  if (error) throw error
  return data ?? []
}
```

- [ ] **Step 2: 빌드 확인(import 깨짐 없음)**

Run: `cd web && npx vitest run` (전체 테스트 그대로 통과 — 데이터 함수는 테스트 없음, 회귀만 확인)
Expected: PASS (기존 + Task 2,3 테스트)

- [ ] **Step 3: 커밋**

```bash
git add web/src/data/worksiteQueries.js
git commit -m "feat(data): add fetchSearchPostings + getWorksiteScoreCards"
```

---

## Task 6: `Search.css` 작성

**Files:**
- Create: `web/src/pages/Search.css`

태그 색(`.tag-national` 등)·범례(`.status-legend`/`.legend-dot`)는 `Home.css` 전역 클래스 재사용(App.jsx가 Home을 eager import하므로 항상 주입됨). 토큰은 `index.css`. 여기선 카드/막대/배너/검색헤더만 포팅한다.

- [ ] **Step 1: 파일 작성**

```css
/* 근장찾기(Search) 전용 스타일. 토큰=index.css, 태그·범례=Home.css 전역 재사용. */
.search-page { min-height: 100vh; background: var(--bg); }
.search-loading, .search-error, .search-empty {
  max-width: 760px; margin: 0 auto; padding: 80px 20px; text-align: center; color: var(--text-muted);
}

/* search-head */
.search-head { background: white; border-bottom: 1px solid var(--border); padding: 24px clamp(16px, calc(8.63vw - 42.9px), 40px); }
.search-bar-md { max-width: 620px; margin: 0 auto; position: relative; }
.search-bar-md input { width: 100%; padding: 11px 44px 11px 18px; border: 2px solid var(--border); border-radius: 50px; font-size: 14px; outline: none; font-family: inherit; }
.search-bar-md input:focus { border-color: var(--primary-dark); }
.search-bar-md button { position: absolute; right: 5px; top: 50%; transform: translateY(-50%); background: var(--primary); border: none; color: white; width: 32px; height: 32px; border-radius: 50%; cursor: pointer; display: flex; align-items: center; justify-content: center; user-select: none; }
.search-bar-md button svg { width: 15px; height: 15px; }
.filter-toggle-btn { text-align: center; margin-top: 10px; }
.filter-toggle-btn button { background: transparent; border: 1px solid var(--border); color: var(--text-sub); padding: 5px 16px; border-radius: 20px; font-size: 13px; cursor: pointer; font-family: inherit; }

/* lock-banner */
.lock-banner { background: linear-gradient(180deg, rgba(255,251,235,0.7), rgba(255,251,235,1)); border-bottom: 1px solid var(--accent-mid); padding: 12px 40px; display: flex; align-items: center; justify-content: center; gap: 18px; flex-wrap: wrap; }
.lock-banner-text { font-size: 13px; color: var(--accent-deep); font-weight: 500; display: inline-flex; align-items: center; gap: 8px; }
.lock-banner-icon { display: inline-flex; align-items: center; }
.lock-banner-icon svg { display: block; }
.lock-banner-cta { background: var(--accent); color: white; border: none; padding: 7px 14px; border-radius: 8px; font-size: 12px; font-weight: 700; cursor: pointer; font-family: inherit; white-space: nowrap; box-shadow: 0 1px 2px rgba(250, 169, 22, 0.32); transition: filter 0.15s, transform 0.15s; }
.lock-banner-cta:hover { filter: brightness(1.05); transform: translateY(-1px); }

/* results-bar */
.results-bar { max-width: 960px; margin: 0 auto; padding: 16px clamp(16px, calc(8.63vw - 42.9px), 40px) 10px; display: flex; justify-content: space-between; align-items: center; }
.results-bar span { font-size: 14px; color: var(--text-sub); }
.results-bar strong { color: var(--text); }
.per-page-select { padding: 6px 10px; border: 1px solid var(--border); border-radius: 6px; font-size: 13px; font-family: inherit; width: 90px; }
.sort-select { padding: 6px 10px; border: 1px solid var(--border); border-radius: 6px; font-size: 13px; font-family: inherit; width: 110px; }
.sort-select:disabled { color: var(--text-muted); background: var(--bg); cursor: not-allowed; }

/* result-list / result-card */
.result-list { max-width: 960px; margin: 0 auto; padding: 0 clamp(16px, calc(8.63vw - 42.9px), 40px) 40px; display: flex; flex-direction: column; gap: 14px; }
.result-card { background: white; border: 1px solid var(--border); border-radius: 12px; padding: 20px clamp(3px, calc(6.25vw - 36px), 24px); cursor: pointer; display: grid; grid-template-columns: 200px 1fr 90px; gap: 16px clamp(3px, calc(4.68vw - 28.9px), 16px); transition: box-shadow 0.15s; align-items: center; }
.result-card:hover { box-shadow: 0 4px 12px rgba(0,0,0,0.08); }
.result-card.status-open { border-left: 3px solid var(--primary); }
.result-card.status-closed { border-left: 3px solid var(--border-strong); }
.status-closed .rc-org, .status-closed .rc-name { color: var(--text-muted); }
.rc-org { font-size: 12px; font-weight: 500; color: var(--text-sub); margin-bottom: 2px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.rc-name { font-size: 18px; font-weight: 700; margin-bottom: 4px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.tag-rows { margin-top: 6px; display: flex; flex-direction: column; gap: 4px; }
.tag-row { display: flex; gap: 5px; flex-wrap: wrap; }
.rc-mid { display: flex; flex-direction: column; justify-content: center; gap: 8px; }
.rating-bars { display: flex; gap: clamp(3px, 1.8vw, 18px); }
.rb-item { flex: 1; min-width: 70px; }
.rb-label { font-size: clamp(8pt, 1.56vw, 14px); color: var(--text-muted); display: flex; justify-content: space-between; margin-bottom: 4px; }
.rb-label span { font-weight: 700; color: var(--text); }
.rb-track { height: 12px; background: var(--surface); border-radius: 5px; overflow: hidden; }
.rb-fill { height: 100%; border-radius: 3px; }
.fill-blue { background: var(--primary); }
.fill-green { background: var(--good); }
.fill-yellow { background: var(--warn); }
.fill-red { background: var(--danger); }
.status-closed .rb-fill { background: var(--border-strong) !important; }
.rec-text { font-size: 12px; color: var(--text-muted); }
.rec-text strong { color: var(--primary-dark); }
.rc-right { display: flex; flex-direction: column; align-items: center; justify-content: center; }
.big-num { font-size: clamp(28px, 4.11vw, 33px); font-weight: 800; color: var(--primary-dark); line-height: 1; }
.big-label { font-size: clamp(11px, 1.61vw, 13px); color: var(--text-muted); margin-top: 4px; text-align: center; }
.btn-review-write { margin-top: 8px; padding: 4px 10px; font-size: clamp(9.5px, 1.39vw, 11px); font-weight: 600; color: var(--primary-dark); background: white; border: 1.5px solid var(--primary); border-radius: 6px; cursor: pointer; font-family: inherit; white-space: nowrap; }
.btn-review-write:hover { background: var(--primary-light); }
.score-blur { filter: blur(12px) grayscale(1); user-select: none; pointer-events: none; }

@media (max-width: 768px) {
  .lock-banner { padding: 10px 16px; gap: 10px; }
  .lock-banner-text { font-size: 12px; }
  .result-card { grid-template-columns: 1fr auto; gap: 12px; padding: 16px; }
  .rc-mid { display: none; }
  .rc-name { white-space: normal; }
}
```

- [ ] **Step 2: 커밋** (Search.jsx와 함께 묶어도 됨)

```bash
git add web/src/pages/Search.css
git commit -m "style(search): add Search.css ported from mockup"
```

---

## Task 7: `Search.jsx` 본체

**Files:**
- Rewrite: `web/src/pages/Search.jsx`

- [ ] **Step 1: 파일 전체 작성**

```jsx
import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { fetchSearchPostings, getWorksiteScoreCards } from '../data/worksiteQueries'
import { isPassActive } from '../lib/passes'
import { ratingBarColor } from '../lib/scores'
import { useAuth } from '../auth/AuthContext'
import Navbar from '../components/Navbar'
import './Search.css'

function RatingBar({ label, value }) {
  const pct = value != null ? (value / 5) * 100 : 0
  return (
    <div className="rb-item">
      <div className="rb-label">{label} <span>{value != null ? value.toFixed(1) : '-'}</span></div>
      <div className="rb-track"><div className={`rb-fill ${ratingBarColor(value)}`} style={{ width: `${pct}%` }} /></div>
    </div>
  )
}

// SECURITY-DEBT(auth): 블러는 CSS 마스킹일 뿐 실 점수가 DOM에 존재. Auth 후 서버 게이팅. (debt #3)
function ResultCard({ card, locked, onOpen, onWrite }) {
  const ws = card.worksite
  const p = card.posting
  const s = card.stats
  const has = !!(s && s.review_count > 0)

  const typeTag = ws.type === 'national' ? '국가근장' : '학교근장'
  const locTag = ws.location_type === 'on_campus' ? '교내' : '교외'
  const durTag = p?.work_duration_type === 'short' ? '단기' : p?.work_duration_type === 'long' ? '장기' : null
  const degreeTag = { 0: '학부생 가능', 1: '대학원생 가능', 2: '학부생/대학원생 가능' }[p?.eligible_degree]
  const statusTag = { 0: '재학생 가능', 1: '휴학생 가능', 2: '재학생/휴학생 가능' }[p?.eligible_status]

  const bars = (
    <div className="rating-bars">
      <RatingBar label="업무" value={has ? Number(s.avg_work) : null} />
      <RatingBar label="자기계발" value={has ? Number(s.avg_growth) : null} />
      <RatingBar label="분위기" value={has ? Number(s.avg_vibe) : null} />
      <RatingBar label="시간 유연성" value={has ? Number(s.avg_flex) : null} />
    </div>
  )
  const bigNum = has ? Number(s.avg_recommend).toFixed(1) : '-'
  const blurScores = has && locked

  return (
    <div
      className={`result-card ${card.is_active ? 'status-open' : 'status-closed'}`}
      onClick={() => onOpen(ws.id)}
    >
      <div>
        <div className="rc-org" title={ws.organization_name}>{ws.organization_name}</div>
        <div className="rc-name" title={ws.workplace_name}>{ws.workplace_name}</div>
        <div className="tag-rows">
          <div className="tag-row">
            <span className={`tag tag-${ws.type === 'national' ? 'national' : 'school'}`}>{typeTag}</span>
            <span className="tag tag-loc">{locTag}</span>
            {ws.type === 'national' && ws.region && <span className="tag tag-region">{ws.region}</span>}
            {durTag && <span className="tag tag-dur">{durTag}</span>}
          </div>
          <div className="tag-row">
            {degreeTag && <span className="tag tag-gray">{degreeTag}</span>}
            {statusTag && <span className="tag tag-gray">{statusTag}</span>}
          </div>
        </div>
      </div>

      <div className="rc-mid">
        {blurScores ? <div className="score-blur">{bars}</div> : bars}
        <div className="rec-text">
          {has
            ? <>리뷰 {s.review_count}개 · <strong>{s.recommend_rate}%</strong>가 이 근무지를 추천합니다</>
            : '아직 리뷰가 없어요'}
        </div>
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6 }}>
        <div className={`rc-right${blurScores ? ' score-blur' : ''}`}>
          <div className="big-num">{bigNum}</div>
          <div className="big-label">추천 점수</div>
        </div>
        <button className="btn-review-write" onClick={(e) => { e.stopPropagation(); onWrite(ws.id) }}>리뷰 쓰기</button>
      </div>
    </div>
  )
}

export default function Search() {
  const navigate = useNavigate()
  const { user: authUser } = useAuth()
  const [cards, setCards] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  useEffect(() => {
    if (!authUser) { navigate('/login'); return }
    let alive = true
    ;(async () => {
      try {
        const postings = await fetchSearchPostings()

        // worksite 단위 그룹화 (Home 로직): active 롤업 + active-우선 대표공고(태그 표시용)
        const wsActiveMap = {}
        for (const p of postings) {
          const wid = p.worksite?.id
          if (!wid) continue
          wsActiveMap[wid] = wsActiveMap[wid] || p.is_active
        }
        const byWorksite = new Map()
        for (const p of postings) {
          const wid = p.worksite?.id
          if (!wid) continue
          const ex = byWorksite.get(wid)
          if (!ex || (!ex.is_active && p.is_active)) byWorksite.set(wid, p)
        }
        const grouped = [...byWorksite.values()].map((p) => ({
          worksite: p.worksite,
          posting: p,
          is_active: wsActiveMap[p.worksite.id],
        }))

        const ids = grouped.map((g) => g.worksite.id)
        let statsRows = []
        try {
          statsRows = await getWorksiteScoreCards(ids)
        } catch (e) {
          console.warn('get_worksite_score_cards RPC 없음 — 점수 생략:', e.message)
        }
        const statsMap = {}
        for (const s of statsRows ?? []) statsMap[s.worksite_id] = s

        const enriched = grouped.map((g) => ({ ...g, stats: statsMap[g.worksite.id] ?? null }))
        // 기본 정렬: 추천 점수(avg_recommend) 내림차순, 없으면 뒤로
        enriched.sort((a, b) => (Number(b.stats?.avg_recommend) || 0) - (Number(a.stats?.avg_recommend) || 0))

        if (alive) { setCards(enriched); setLoading(false) }
      } catch (e) {
        if (alive) { setError(e.message); setLoading(false) }
      }
    })()
    return () => { alive = false }
  }, [authUser, navigate])

  const locked = !isPassActive(authUser?.pass_expires_at)

  if (loading) return <div className="search-page"><Navbar /><div className="search-loading">불러오는 중…</div></div>
  if (error) return <div className="search-page"><Navbar /><div className="search-error">에러: {error}</div></div>

  return (
    <div className="search-page">
      <Navbar />

      <div className="search-head">
        <div className="search-bar-md">
          <input type="text" placeholder="근장 이름, 위치로 검색하세요" readOnly />
          <button aria-label="검색">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 28 28" fill="none" stroke="white" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
              <circle cx="11" cy="11" r="8" /><line x1="24" y1="24" x2="16.66" y2="16.66" />
            </svg>
          </button>
        </div>
        <div className="filter-toggle-btn"><button type="button">고급검색 ▾</button></div>
      </div>

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
          <select className="per-page-select" defaultValue="20" aria-label="페이지당 개수">
            <option value="10">10개씩</option>
            <option value="20">20개씩</option>
            <option value="30">30개씩</option>
            <option value="50">50개씩</option>
          </select>
          <span>전체 근장 <strong>{cards.length}개</strong></span>
        </div>
        <div className="status-legend">
          <span className="legend-item"><span className="legend-dot dot-green"></span>모집중</span>
          <span className="legend-item"><span className="legend-dot dot-red"></span>모집완료</span>
        </div>
        <select className="sort-select" defaultValue="추천순" disabled={locked}
          title={locked ? '열람권이 없을 때는 정렬을 변경할 수 없어요' : undefined} aria-label="정렬">
          <option>추천순</option>
        </select>
      </div>

      <div className="result-list">
        {cards.length === 0 ? (
          <div className="search-empty">표시할 근장이 없어요.</div>
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
    </div>
  )
}
```

- [ ] **Step 2: 린트 확인**

Run: `cd web && npx eslint src/pages/Search.jsx`
Expected: 에러 없음(경고 0). hook 의존성(`authUser`, `navigate`) 포함됨.

- [ ] **Step 3: 커밋**

```bash
git add web/src/pages/Search.jsx web/src/pages/Search.css
git commit -m "feat(search): implement locked-shell search page with blur"
```

---

## Task 8: `WorksiteDetail`의 `hasPass`를 `isPassActive`로 교체

**Files:**
- Modify: `web/src/pages/WorksiteDetail.jsx:117-119`

- [ ] **Step 1: import 추가**

`WorksiteDetail.jsx`의 import 블록(`computeScoreSummary` 근처)에 추가:

```js
import { isPassActive } from '../lib/passes'
```

- [ ] **Step 2: 인라인 계산 교체**

다음 줄(117~119행 근처):

```js
  // 열람권 활성 여부 = 실제 만료시각(pass_expires_at) 기준. AuthContext 유저가 단일 진실 공급원.
  const hasPass = !!(authUser?.pass_expires_at && new Date(authUser.pass_expires_at) > new Date())
  const locked = !hasPass
```

을 다음으로 교체:

```js
  // 열람권 활성 여부 = 실제 만료시각(pass_expires_at) 기준. AuthContext 유저가 단일 진실 공급원.
  const locked = !isPassActive(authUser?.pass_expires_at)
```

- [ ] **Step 3: 회귀 확인**

Run: `cd web && npx vitest run && npx eslint src/pages/WorksiteDetail.jsx`
Expected: 테스트 PASS, 린트 에러 없음.

- [ ] **Step 4: 커밋**

```bash
git add web/src/pages/WorksiteDetail.jsx
git commit -m "refactor: use isPassActive in WorksiteDetail (dedup pass check)"
```

---

## Task 9: 문서 갱신

**Files:**
- Modify: `web/src/pages/README.md` (Search 행)
- Modify: `web/src/data/README.md` (worksiteQueries 함수 목록)

- [ ] **Step 1: pages/README.md Search 행 수정**

기존:
```
| `Search.jsx` | `/search` | 근장찾기 전용 화면. 현재 빈 placeholder(추후 검색 결과 구현). css 없음(inline) |
```
→
```
| `Search.jsx` / `.css` | `/search` | 근장찾기 목록. 열람권 없으면 점수 블러+잠금 배너+정렬 disabled. DB는 `data/worksiteQueries`(`fetchSearchPostings`·`getWorksiteScoreCards`). 검색·고급필터·정렬·페이지네이션은 UI만(동작 미구현) |
```

- [ ] **Step 2: data/README.md에 새 함수 기재**

`worksiteQueries.js` 설명에 `fetchSearchPostings`(근장찾기 목록용 공고 전체)와 `getWorksiteScoreCards`(근장찾기 카드 점수 집계 RPC 래퍼) 한 줄씩 추가(기존 함수 목록 형식에 맞춰).

- [ ] **Step 3: 커밋**

```bash
git add web/src/pages/README.md web/src/data/README.md
git commit -m "docs: update READMEs for search page + new data fns"
```

---

## Task 10: 수동 검증

**Files:** 없음(실행 확인)

- [ ] **Step 1: 전체 테스트 + 린트**

Run: `cd web && npm test && npx eslint .`
Expected: 전부 PASS / 에러 없음.

- [ ] **Step 2: 개발 서버 띄우고 확인**

Run: `cd web && npm run dev` → `/search` 접속.
- 비로그인: `/login`으로 튕기는지.
- 로그인 + 열람권 없음: lock-banner 노출, 카드 점수 **블러**, 정렬 select disabled, "전체 근장 N개"가 실제 근장 수, 카드 클릭 → 상세, 리뷰쓰기 → 리뷰 폼(카드 클릭과 분리).
- 열람권 있음(ExchangeCenter의 devToggle 또는 활성화): 블러 해제, 점수·색 막대 정상, 정렬 select 활성(동작은 아직 X).
- 리뷰 0개 근장: 점수 `-`, "아직 리뷰가 없어요".

> RPC 미배포 상태면 점수가 전부 `-`로 나오고 `console.warn`만 뜸(graceful) — RPC `db push` 후 정상 표시.

- [ ] **Step 2 결과 사용자 확인 후 마무리.**

---

## Self-Review (작성자 체크 완료)

- **Spec 커버리지:** §4 데이터(Task 4,5) · §5 흐름(Task 7) · §6 컴포넌트(Task 7) · §7 엣지(Task 7) · §8 테스트(Task 2,3,8) · §9 CSS(Task 6) · §10 보안주석(Task 7 ResultCard 주석). deferred 항목은 의도적으로 미구현(UI만).
- **Placeholder:** 마이그레이션 `<작성자>`만 의도적 — 사용자 교체. 그 외 전부 실코드.
- **타입 일관성:** `card = { worksite, posting, is_active, stats }` 형태를 Task 7 전체에서 일관 사용. `stats` 키(`review_count/avg_recommend/avg_work/avg_growth/avg_vibe/avg_flex/recommend_rate`)는 Task 4 RPC 반환과 정확히 일치. `ratingBarColor`/`isPassActive` 시그니처는 Task 2,3 정의와 Task 7 사용처 일치.
