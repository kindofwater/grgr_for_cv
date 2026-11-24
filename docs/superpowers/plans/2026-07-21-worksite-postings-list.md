# 근무지 상세 공고 목록 노출 (A안) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 학교근로 근무지 상세에서 대표 공고 1개만이 아니라 그 근무지의 여러 공고를 목록으로 보여, 한 부서가 올린 성격 다른 일들을 사용자가 구분할 수 있게 한다.

**Architecture:** 데이터 모델(`worksites`:`postings` 1:N, 리뷰는 근무지 단위)은 그대로. 상세 페이지가 공고 배열을 받아 **클라이언트에서** 대표/목록을 선별(Fable #3 단일 정본)한다. 대표는 현행 `InfoCard`로, 나머지는 새 `PostingList`(펼침 미니카드)로 렌더. 공고 상세 필드 렌더는 `PostingFields`로 추출해 둘이 공유.

**Tech Stack:** React 19 + Vite, vitest, Supabase(Postgres, RLS, security-definer RPC).

## Global Constraints

- 웹 코드는 `web/` 안만 참조. 외부 폴더 import 금지. 의존성 방향 `pages → components/data/lib`.
- DB 통신은 `web/src/data/`에서만. 페이지·컴포넌트는 data 함수만 호출.
- **DB/RPC 변경은 마이그레이션 + 수동 `supabase db push`로만**(SQL 에디터 수동편집 금지). 시그니처 변경 시 `DROP FUNCTION IF EXISTS` 먼저. push는 담당자가 직접, 디스코드 공유 후. (CLAUDE.md §3)
- 순수 로직은 `web/src/lib/`에 두고 vitest로 테스트. JSX 컴포넌트는 이 저장소에 단위테스트 관례가 없음 → **앱 실행 육안 검증**.
- 테스트 러너 TZ=UTC 고정(`vite.config.js`). 날짜 로직은 `now` 주입.
- **배포 순서 무관 설계:** 프론트는 구/신 RPC 반환을 모두 수용(tolerant). 그래서 프론트 배포와 `db push` 순서에 관계없이 안 깨지고, 목록 기능은 db push 시점에 켜진다.

---

## 파일 구조

| 파일 | 책임 |
|------|------|
| `web/src/lib/postings.js` (신규) | 순수: `selectPostings`(대표/목록 선별 단일 정본), `summarizeJob`(직무 요약) |
| `web/src/lib/postings.test.js` (신규) | 위 두 함수 vitest |
| `web/src/components/InfoCard.jsx` (수정) | 공고 상세 필드+신청버튼을 `PostingFields`로 추출·export. 대표 카드 겉모습 불변 |
| `web/src/components/PostingList.jsx` (신규) | 다른 공고 목록(접힘/펼침 미니카드). 목록 비면 null |
| `web/src/components/PostingList.css` (신규) | 위 스타일(기존 토큰·`.tag` 재사용) |
| `web/src/data/worksiteQueries.js` (수정) | `fetchRepresentativePosting`→`fetchPostings`(배열·limit30), `fetchWorksitePublicDetail` tolerant 배열화 |
| `web/src/pages/WorksiteDetail.jsx` (수정) | 3개 fetch 경로 배열 통일, 대표+목록 렌더 |
| `web/supabase/migrations/<ts>_worksite_detail_postings.sql` (신규) | `get_worksite_public_detail` 반환 `posting`→`postings`(배열, 30캡) |
| `docs/db-schema.md` · `web/supabase/README.md` (수정) | RPC 변경 반영 |

**작업 순서 근거:** 로그인 경로는 테이블 쿼리(`fetchPostings`)라 **db push 전에도 전체 목록이 동작** → 프론트(Task 1~5)를 먼저 만들고 로그인 경로로 검증. 마이그레이션(Task 6)은 비로그인 경로까지 켜는 스위치.

---

### Task 1: 선별·요약 순수 로직 (`lib/postings.js`)

**Files:**
- Create: `web/src/lib/postings.js`
- Test: `web/src/lib/postings.test.js`

**Interfaces:**
- Produces:
  - `selectPostings(postings: object[]): { representative: object|null, others: object[] }`
  - `summarizeJob(posting: object, max?: number): string`

- [ ] **Step 1: 실패하는 테스트 작성** — `web/src/lib/postings.test.js`

```js
import { describe, it, expect } from 'vitest'
import { selectPostings, summarizeJob } from './postings'

describe('selectPostings (Fable #3 단일 정본)', () => {
  it('비-placeholder 중 첫째가 대표, 나머지가 목록', () => {
    const ps = [{ id: 1, is_placeholder: false }, { id: 2, is_placeholder: false }, { id: 3, is_placeholder: false }]
    const { representative, others } = selectPostings(ps)
    expect(representative.id).toBe(1)
    expect(others.map((p) => p.id)).toEqual([2, 3])
  })
  it('placeholder는 대표·목록에서 제외', () => {
    const ps = [{ id: 1, is_placeholder: false }, { id: 2, is_placeholder: true }]
    const { representative, others } = selectPostings(ps)
    expect(representative.id).toBe(1)
    expect(others).toEqual([])
  })
  it('전부 placeholder(국가근로)면 대표는 폴백, 목록은 빔', () => {
    const { representative, others } = selectPostings([{ id: 9, is_placeholder: true }])
    expect(representative.id).toBe(9)
    expect(others).toEqual([])
  })
  it('빈·널 입력이면 대표 null·목록 빔', () => {
    expect(selectPostings([])).toEqual({ representative: null, others: [] })
    expect(selectPostings(null)).toEqual({ representative: null, others: [] })
    expect(selectPostings(undefined)).toEqual({ representative: null, others: [] })
  })
})

describe('summarizeJob', () => {
  it('40자 이하는 그대로', () => {
    expect(summarizeJob({ job_description: '행정 보조' })).toBe('행정 보조')
  })
  it('40자 초과는 잘리고 … 붙음', () => {
    const out = summarizeJob({ job_description: '가'.repeat(50) })
    expect(out.length).toBe(41)
    expect(out.endsWith('…')).toBe(true)
  })
  it('개행·연속 공백은 한 칸으로 축약', () => {
    expect(summarizeJob({ job_description: '실험실\n\n  조교' })).toBe('실험실 조교')
  })
  it('비면 (직무 미상)', () => {
    expect(summarizeJob({ job_description: '' })).toBe('(직무 미상)')
    expect(summarizeJob({})).toBe('(직무 미상)')
    expect(summarizeJob(null)).toBe('(직무 미상)')
  })
})
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd web && npx vitest run src/lib/postings.test.js`
Expected: FAIL — `Failed to resolve import './postings'` (또는 함수 미정의)

- [ ] **Step 3: 최소 구현** — `web/src/lib/postings.js`

```js
// 근무지 상세: 공고 배열에서 대표/목록 선별 + 직무 요약. 순수·결정적.
// Fable #3: 대표/목록 규칙은 여기 한 곳(서버는 폴백 분기 없이 배열만 준다).

// 대표 = 비-placeholder 첫째(활성→최신 순은 호출자가 정렬해 넘김).
// 비-placeholder가 하나도 없으면(국가근로 껍데기만) 배열 첫 원소를 대표로 폴백, 목록은 빔.
export function selectPostings(postings) {
  const list = Array.isArray(postings) ? postings : []
  const nonPh = list.filter((p) => p && !p.is_placeholder)
  if (nonPh.length > 0) return { representative: nonPh[0], others: nonPh.slice(1) }
  return { representative: list[0] ?? null, others: [] }
}

const DEFAULT_MAX = 40
// 접힌 줄 라벨. 제목 컬럼이 없어 job_description을 요약(공고명 title은 SSC 크롤러 후속).
export function summarizeJob(posting, max = DEFAULT_MAX) {
  const raw = posting?.job_description
  const text = typeof raw === 'string' ? raw.replace(/\s+/g, ' ').trim() : ''
  if (!text) return '(직무 미상)'
  return text.length > max ? text.slice(0, max) + '…' : text
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd web && npx vitest run src/lib/postings.test.js`
Expected: PASS (8 tests)

- [ ] **Step 5: 커밋**

```bash
git add web/src/lib/postings.js web/src/lib/postings.test.js
git commit -m "feat(worksite): 공고 대표/목록 선별·직무 요약 순수 로직 + 테스트"
```

---

### Task 2: `InfoCard`에서 `PostingFields` 추출

**Files:**
- Modify: `web/src/components/InfoCard.jsx`

**Interfaces:**
- Produces: `export function PostingFields({ posting, isNational })` — 공고 상세 행들(직무·시간·자격·우대·기타)+신청 버튼을 렌더하는 fragment.
- Consumes: (없음)

**목표:** 대표 카드(InfoCard) 겉모습·동작은 **완전히 그대로**. 공고별 필드+버튼만 재사용 가능한 컴포넌트로 뽑아낸다. `Row`·헬퍼는 같은 파일이라 그대로 사용.

- [ ] **Step 1: `PostingFields` 추가 + InfoCard 본문 치환** — `web/src/components/InfoCard.jsx` 전체를 아래로 교체

```jsx
import { dash, formatWage, eligibleDegreeLabel, eligibleStatusLabel, formatMinGrade } from '../lib/scores'
import { effectiveActive } from '../lib/recruit'

function Row({ label, value }) {
  return (
    <div className="info-row"><span className="info-lbl">{label}</span><span>{dash(value)}</span></div>
  )
}

// 공고 1건의 상세 필드 + 신청 버튼. InfoCard 본문과 PostingList 펼침이 공유(중복 제거).
export function PostingFields({ posting, isNational }) {
  const isOpen = effectiveActive(posting)
  const degreeLabel = eligibleDegreeLabel(posting?.eligible_degree)
  const statusLabel = eligibleStatusLabel(posting?.eligible_status)
  return (
    <>
      {isNational ? (
        <>
          <Row label="선호계열" value={posting?.preferred_track || '상관없음'} />
          <Row label="선호학년" value={formatMinGrade(posting?.min_grade)} />
        </>
      ) : (
        <>
          {degreeLabel && <Row label="학위 과정" value={degreeLabel} />}
          {statusLabel && <Row label="학적 상태" value={statusLabel} />}
          <Row label="모집 기간" value={posting?.recruitment_period_text} />
        </>
      )}
      <Row label="모집 인원" value={posting?.recruit_count} />
      <Row label="시급" value={formatWage(posting?.hourly_wage)} />
      <Row label="근로기간" value={posting?.work_period_text} />
      <Row label="근로시간" value={posting?.work_time_text} />
      <Row label="직무 내용" value={posting?.job_description} />
      {!isNational && <Row label="우대조건" value={posting?.preference_notes} />}
      <Row label="기타" value={posting?.extra_notes} />

      {isOpen ? (
        <button className="btn-apply" onClick={() => posting?.source_url && window.open(posting.source_url, '_blank')}>
          {isNational ? '국가근장 장학 시스템에서 신청하기 ↗' : '근장 사이트에서 신청하기 ↗'}
        </button>
      ) : (
        <button className="btn-apply" disabled>모집완료</button>
      )}
    </>
  )
}

export default function InfoCard({ worksite, posting }) {
  const isNational = worksite.type === 'national'
  const isOpen = effectiveActive(posting)
  const typeLabel = isNational ? '국가근장' : '학교근장'
  const locLabel = worksite.type === 'school' ? null : (worksite.location_type === 'off_campus' ? '교외' : '교내')

  return (
    <div className={`info-card ${isOpen ? 'status-open' : 'status-closed'}`}>
      <div className="det-head">
        <div className="det-titles">
          <div className="det-org">{dash(worksite.organization_name)}</div>
          <div className="det-name">{dash(worksite.workplace_name)}</div>
        </div>
        <span className={`det-status-badge ${isOpen ? 'badge-open' : 'badge-closed'}`}>
          <span className="badge-dot" />{isOpen ? '모집중' : '모집완료'}
        </span>
      </div>

      <div className="tag-rows">
        <div className="tag-row">
          <span className={`tag ${isNational ? 'tag-national' : 'tag-school'}`}>{typeLabel}</span>
          {locLabel && <span className="tag tag-loc">{locLabel}</span>}
        </div>
      </div>

      <Row label="주소" value={worksite.address} />
      <Row label="근로유형" value={typeLabel} />
      <PostingFields posting={posting} isNational={isNational} />
    </div>
  )
}
```

- [ ] **Step 2: 회귀 없음 확인(빌드·기존 테스트)**

Run: `cd web && npx vitest run && npm run build`
Expected: 테스트 그대로 통과, 빌드 성공(에러 0)

- [ ] **Step 3: 육안 회귀 확인**

Run: `cd web && npm run dev` → 임의 근무지 상세 열기.
Expected: InfoCard가 이전과 **픽셀 동일**(제목·태그·주소·근로유형·공고필드·신청버튼 순서·모양 그대로).

- [ ] **Step 4: 커밋**

```bash
git add web/src/components/InfoCard.jsx
git commit -m "refactor(worksite): InfoCard 공고 필드를 PostingFields로 추출(겉모습 불변)"
```

---

### Task 3: `PostingList` 컴포넌트 + CSS

**Files:**
- Create: `web/src/components/PostingList.jsx`
- Create: `web/src/components/PostingList.css`

**Interfaces:**
- Consumes: `PostingFields`(Task 2), `selectPostings`/`summarizeJob`(Task 1), `effectiveActive`(`lib/recruit`).
- Produces: `export default function PostingList({ postings, worksite })` — `postings`(=대표 제외 목록)가 비면 `null`.

- [ ] **Step 1: 컴포넌트 작성** — `web/src/components/PostingList.jsx`

```jsx
import { useState } from 'react'
import { effectiveActive } from '../lib/recruit'
import { summarizeJob } from '../lib/postings'
import { PostingFields } from './InfoCard'
import './PostingList.css'

function PostingRow({ posting, isNational }) {
  const [open, setOpen] = useState(false)
  const isOpen = effectiveActive(posting)
  return (
    <div className={`posting-item ${isOpen ? 'status-open' : 'status-closed'}`}>
      <button className="posting-row" onClick={() => setOpen((v) => !v)} aria-expanded={open}>
        <span className="posting-summary">{summarizeJob(posting)}</span>
        <span className="posting-tags">
          <span className={`tag ${isOpen ? 'tag-status-open' : 'tag-status-closed'}`}>{isOpen ? '모집중' : '모집완료'}</span>
          {posting?.recruitment_period_text && (
            <span className="tag tag-period">{posting.recruitment_period_text}</span>
          )}
        </span>
        <span className="posting-caret" aria-hidden>{open ? '▲' : '▼'}</span>
      </button>
      {open && (
        <div className="posting-body">
          <PostingFields posting={posting} isNational={isNational} />
        </div>
      )}
    </div>
  )
}

// 근무지의 '다른 공고' 목록. 목록이 비면(국가근로·공고 1개뿐) 아무것도 렌더 안 함.
export default function PostingList({ postings, worksite }) {
  if (!postings || postings.length === 0) return null
  const isNational = worksite?.type === 'national'
  return (
    <div className="posting-list">
      <h3 className="posting-list-head">이 근무지의 다른 공고 {postings.length}개</h3>
      {postings.map((p) => (
        <PostingRow key={p.id} posting={p} isNational={isNational} />
      ))}
    </div>
  )
}
```

- [ ] **Step 2: CSS 작성** — `web/src/components/PostingList.css` (기존 토큰·`.tag`·`.status-open/closed` 재사용)

```css
.posting-list { margin-bottom: 16px; }
.posting-list-head { font-size: 15px; font-weight: 700; margin: 4px 0 10px; }

.posting-item { background: white; border: 1px solid var(--border); border-radius: var(--card-radius); margin-bottom: 8px; overflow: hidden; }
.posting-row { display: flex; align-items: center; gap: 10px; width: 100%; background: transparent; border: none; padding: 12px 16px; cursor: pointer; font-family: inherit; text-align: left; }
.posting-row:hover { background: var(--surface); }
.posting-summary { flex: 1; min-width: 0; font-size: 14px; font-weight: 600; color: var(--text); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.posting-tags { display: flex; gap: 4px; flex-wrap: wrap; flex-shrink: 0; }
.posting-tags .tag { margin: 0; }
.tag-period { background: var(--surface); color: var(--text-sub); }
.posting-caret { color: var(--text-muted); font-size: 10px; flex-shrink: 0; }
.posting-body { padding: 0 16px 16px; }

@media (max-width: 480px) {
  .posting-summary { white-space: normal; }
}
```

- [ ] **Step 3: 빌드 확인**

Run: `cd web && npm run build`
Expected: 성공(에러 0). (렌더 검증은 Task 5에서 배선 후.)

- [ ] **Step 4: 커밋**

```bash
git add web/src/components/PostingList.jsx web/src/components/PostingList.css
git commit -m "feat(worksite): PostingList — 다른 공고 접힘/펼침 목록"
```

---

### Task 4: 데이터 계층 — `fetchPostings` + tolerant 공개 상세

**Files:**
- Modify: `web/src/data/worksiteQueries.js`

**Interfaces:**
- Produces:
  - `fetchPostings(worksiteId): Promise<object[]>` — 근무지 공고 배열(활성→최신, ≤30, `is_placeholder`·`recruit_until` 포함).
  - `fetchWorksitePublicDetail(id): Promise<{ worksite: object, postings: object[] }>`.
- 제거: `fetchRepresentativePosting`.

- [ ] **Step 1: 다른 소비처 없음 확인**

Run: `cd web && grep -rn "fetchRepresentativePosting" src`
Expected: `WorksiteDetail.jsx`의 import·사용 2곳만(Task 5에서 교체). 그 외 없음.

- [ ] **Step 2: `fetchRepresentativePosting` → `fetchPostings` 교체** — `web/src/data/worksiteQueries.js`

기존(대표 공고, limit 1):
```js
// 대표 공고: 활성 우선, 그다음 최신
export async function fetchRepresentativePosting(worksiteId) {
  const cols = `id, source_url, job_category, preferred_track, preferred_college, preferred_dept,
    recruit_count, min_grade, eligible_degree, eligible_status, job_description, preference_notes,
    extra_notes, hourly_wage, work_period_text, work_duration_type, work_time_text,
    recruitment_period_text, contact_name, is_active, recruit_until, created_at`
  const { data, error } = await supabase
    .from('postings').select(cols).eq('worksite_id', worksiteId)
    .order('is_active', { ascending: false }).order('created_at', { ascending: false }).limit(1)
  if (error) throw error
  return data?.[0] ?? null
}
```

교체(공고 배열, limit 30, `is_placeholder` 포함):
```js
// 근무지 공고 목록: 활성 우선 → 최신, 최근 30개(SSC 이력 대비 캡). 대표/목록 선별은 lib/postings.selectPostings.
export async function fetchPostings(worksiteId) {
  const cols = `id, source_url, job_category, preferred_track, preferred_college, preferred_dept,
    recruit_count, min_grade, eligible_degree, eligible_status, job_description, preference_notes,
    extra_notes, hourly_wage, work_period_text, work_duration_type, work_time_text,
    recruitment_period_text, contact_name, is_active, is_placeholder, recruit_until, created_at`
  const { data, error } = await supabase
    .from('postings').select(cols).eq('worksite_id', worksiteId)
    .order('is_active', { ascending: false }).order('created_at', { ascending: false }).limit(30)
  if (error) throw error
  return data ?? []
}
```

- [ ] **Step 3: `fetchWorksitePublicDetail` tolerant 배열화** — 같은 파일

기존:
```js
export async function fetchWorksitePublicDetail(id) {
  const { data, error } = await supabase
    .rpc('get_worksite_public_detail', { p_worksite_id: Number(id) })
  if (error) throw error
  const row = data?.[0]
  if (!row) throw new Error('근무지를 찾을 수 없어요.')
  return { worksite: row.worksite, posting: row.posting }
}
```

교체:
```js
export async function fetchWorksitePublicDetail(id) {
  const { data, error } = await supabase
    .rpc('get_worksite_public_detail', { p_worksite_id: Number(id) })
  if (error) throw error
  const row = data?.[0]
  if (!row) throw new Error('근무지를 찾을 수 없어요.')
  // 신 RPC는 postings(배열), 구 RPC는 posting(단수) — 둘 다 수용해 배포 순서와 무관하게 동작.
  // db push 전: posting 하나만 → 대표만 보이고 목록은 빈다(현행과 동일). push 후: 목록까지 켜짐.
  const postings = row.postings ?? (row.posting ? [row.posting] : [])
  return { worksite: row.worksite, postings }
}
```

- [ ] **Step 4: 빌드·기존 테스트 확인**

Run: `cd web && npx vitest run && npm run build`
Expected: 통과·성공. (배선 전이라 `fetchPostings` 미사용 경고 없음 — export라 OK.)

- [ ] **Step 5: 커밋**

```bash
git add web/src/data/worksiteQueries.js
git commit -m "feat(data): fetchPostings(배열·30캡) + 공개 상세 tolerant 배열화"
```

---

### Task 5: `WorksiteDetail` 배선 — 대표 + 목록 렌더

**Files:**
- Modify: `web/src/pages/WorksiteDetail.jsx`

**Interfaces:**
- Consumes: `fetchPostings`·`fetchWorksitePublicDetail`(Task 4), `selectPostings`(Task 1), `PostingList`(Task 3), `InfoCard`(Task 2).

- [ ] **Step 1: import 교체** — `web/src/pages/WorksiteDetail.jsx` 상단

기존:
```js
import {
  fetchWorksite, fetchRepresentativePosting,
  fetchReviews, fetchMyReviewIds, incrementViewCount, deleteReview,
  fetchMyHelpfulIds, toggleHelpful, reportReview,
  fetchWorksitePublicDetail, fetchWorksiteScoreCard, fetchReviewTeaser,
} from '../data/worksiteQueries'
```
교체(‘fetchRepresentativePosting’→‘fetchPostings’):
```js
import {
  fetchWorksite, fetchPostings,
  fetchReviews, fetchMyReviewIds, incrementViewCount, deleteReview,
  fetchMyHelpfulIds, toggleHelpful, reportReview,
  fetchWorksitePublicDetail, fetchWorksiteScoreCard, fetchReviewTeaser,
} from '../data/worksiteQueries'
```
그리고 컴포넌트/유틸 import 추가(기존 `import InfoCard ...` 아래, `import ScoreSummary ...` 위 등 적당한 위치):
```js
import { selectPostings } from '../lib/postings'
import PostingList from '../components/PostingList'
```

- [ ] **Step 2: 3개 fetch 경로를 배열로 통일**

(a) 잠금 경로 정보카드 그룹 A — 기존:
```js
      const infoP = !authUser
        ? fetchWorksitePublicDetail(id)
        : Promise.all([fetchWorksite(id), fetchRepresentativePosting(id)])
            .then(([worksite, posting]) => { incrementViewCount(id); return { worksite, posting } })
      infoP
        .then((info) => { if (alive) setState((s) => ({ ...s, worksite: info.worksite, posting: info.posting })) })
        .catch(onInfoError)
```
교체:
```js
      const infoP = !authUser
        ? fetchWorksitePublicDetail(id)
        : Promise.all([fetchWorksite(id), fetchPostings(id)])
            .then(([worksite, postings]) => { incrementViewCount(id); return { worksite, postings } })
      infoP
        .then((info) => { if (alive) setState((s) => ({ ...s, worksite: info.worksite, postings: info.postings })) })
        .catch(onInfoError)
```

(b) 열람권 보유자 경로 정보카드 그룹 A — 기존:
```js
    Promise.all([fetchWorksite(id), fetchRepresentativePosting(id)])
      .then(([worksite, posting]) => {
        if (!alive) return
        incrementViewCount(id)  // fire-and-forget (조회수 +1은 auth.uid() 기반 RPC)
        setState((s) => ({ ...s, worksite, posting }))
      })
      .catch(onInfoError)
```
교체:
```js
    Promise.all([fetchWorksite(id), fetchPostings(id)])
      .then(([worksite, postings]) => {
        if (!alive) return
        incrementViewCount(id)  // fire-and-forget (조회수 +1은 auth.uid() 기반 RPC)
        setState((s) => ({ ...s, worksite, postings }))
      })
      .catch(onInfoError)
```

- [ ] **Step 3: 대표/목록 파생 + infoReady + 렌더 교체**

`sortedReviews` useMemo 아래에 파생 추가:
```js
  // 대표/목록 선별(단일 정본 — lib/postings). state.postings 없으면 대표 null·목록 빈 배열.
  const { representative, others } = useMemo(() => selectPostings(state.postings), [state.postings])
```

`infoReady` 기존:
```js
  const infoReady = isAnon ? !!state.worksite : (state.worksite && state.posting)
```
교체(`posting`→`postings`):
```js
  const infoReady = isAnon ? !!state.worksite : (state.worksite && state.postings)
```

렌더 — 기존:
```jsx
          {infoReady && <InfoCard worksite={state.worksite} posting={state.posting} />}
```
교체(대표 카드 + 목록):
```jsx
          {infoReady && representative && <InfoCard worksite={state.worksite} posting={representative} />}
          {infoReady && <PostingList postings={others} worksite={state.worksite} />}
```

- [ ] **Step 4: 빌드·테스트**

Run: `cd web && npx vitest run && npm run build`
Expected: 통과·성공. (`useMemo`는 이미 import됨 — 파일 상단 `import { useEffect, useMemo, useState }` 확인.)

- [ ] **Step 5: 육안 검증(로그인 경로는 db push 전에도 전체 동작)**

Run: `cd web && npm run dev` (로그인·열람권 보유 계정)
확인:
1. **학교근로(공고 여러 개)** 근무지 → 대표 카드 아래 "이 근무지의 다른 공고 N개" 섹션, 각 줄에 직무요약 + `[모집중/완료]` `[모집기간]` 태그. 줄 클릭 시 펼쳐져 상세 필드·신청버튼 표시.
2. **국가근로** 근무지 → "다른 공고" 섹션 **없음**(placeholder뿐), 대표 카드는 현행대로.
3. **공고 1개뿐** 학교근로 → 섹션 없음.
4. `job_description` 없는 공고 → 접힌 줄 `(직무 미상)`.
5. 좁은 폭(≤480px)에서 줄·태그 깨짐 없음.

- [ ] **Step 6: 커밋**

```bash
git add web/src/pages/WorksiteDetail.jsx
git commit -m "feat(worksite): 상세에 대표 공고 + 다른 공고 목록 배선"
```

---

### Task 6: 마이그레이션 — `get_worksite_public_detail` 배열 반환

**Files:**
- Create: `web/supabase/migrations/<ts>_worksite_detail_postings.sql`

**⚠️ 이 태스크는 공유 prod DB를 바꾼다.** 착수 전 디스코드 공유. 베이스는 **최신 정의 `20260720015012_search_cards_recruit_until.sql`**(`recruit_until` 키 포함) — 옛 20260716 버전을 베끼면 `recruit_until`이 증발해 배지 오판(Fable #1). 시그니처 변경(`posting`→`postings`)이라 `DROP FUNCTION` 먼저 + grant 재부여.

- [ ] **Step 1: 마이그레이션 파일 생성**

Run: `cd web && npx supabase migration new worksite_detail_postings`
Expected: `web/supabase/migrations/<ts>_worksite_detail_postings.sql` 생성.

- [ ] **Step 2: SQL 작성** — 생성된 파일에 아래 전체 기입

```sql
-- 목적: 근무지 상세가 대표 공고 1개(posting) 대신 공고 목록(postings 배열)을 반환 — 학교근로 다중 공고 노출(A안)
-- 날짜: 2026-07-21 · 담당: 배경록

-- 반환 시그니처 변경(posting jsonb → postings jsonb) → DROP 먼저(안 그러면 옛 함수 잔존해 RPC 꼬임)
drop function if exists get_worksite_public_detail(int);

create function get_worksite_public_detail(p_worksite_id int)
returns table (worksite jsonb, postings jsonb)
language sql security definer set search_path = public as $$
  with ps as (
    select p.*
    from postings p
    where p.worksite_id = p_worksite_id and p.deleted_at is null
    order by p.is_active desc, p.created_at desc
    limit 30                                   -- SSC 이력 대비 캡(응답 비대 방지, Fable #2)
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
    coalesce(
      (select jsonb_agg(
         jsonb_build_object(
           'id',                      ps.id,
           'is_active',               ps.is_active,
           'is_placeholder',          ps.is_placeholder,   -- 대표/목록 선별용
           'recruit_until',           ps.recruit_until,     -- 배지 판정(Fable #1)
           'preferred_track',         ps.preferred_track,
           'min_grade',               ps.min_grade,
           'eligible_degree',         ps.eligible_degree,
           'eligible_status',         ps.eligible_status,
           'recruitment_period_text', ps.recruitment_period_text,
           'recruit_count',           ps.recruit_count,
           'hourly_wage',             ps.hourly_wage,
           'work_period_text',        ps.work_period_text,
           'work_time_text',          ps.work_time_text,
           'job_description',         ps.job_description,
           'preference_notes',        ps.preference_notes,
           'extra_notes',             ps.extra_notes,
           'source_url',              ps.source_url
         )
         order by ps.is_active desc, ps.created_at desc     -- 배열 순서 = 활성→최신(대표=첫 원소)
       ) from ps),
      '[]'::jsonb
    ) as postings
  from worksites w
  where w.id = p_worksite_id and w.deleted_at is null;
$$;

-- 개인정보(contact_name 등)는 화이트리스트에서 계속 제외.
revoke execute on function get_worksite_public_detail(int) from public;
grant  execute on function get_worksite_public_detail(int) to anon, authenticated;
```

- [ ] **Step 3: 로컬 검증(Docker 있으면)**

Docker 사용 가능 시:
Run: `cd web && npx supabase db reset`
Expected: 맨바닥 재구축 성공(에러 0). 이후 `select jsonb_array_length(postings) from get_worksite_public_detail(<school_id>);` 로 배열 확인.

Docker 없으면(이 저장소 관례): SQL 문법·컬럼명을 [db-schema.md](../../db-schema.md) `postings` 정의와 대조 검토하고 Step 4로.

- [ ] **Step 4: prod 반영(담당자, 디스코드 공유 후)**

Run: `cd web && npx supabase db push`
검증(Supabase SQL 에디터 또는 psql):
```sql
-- 학교근로(공고 여러 개) 근무지: 배열 길이 >1
select jsonb_array_length(postings) from get_worksite_public_detail(<school_worksite_id>);
-- 국가근로: 길이 1(placeholder)
select jsonb_array_length(postings) from get_worksite_public_detail(<national_worksite_id>);
-- 각 원소에 is_placeholder·recruit_until 키 존재
select postings->0 from get_worksite_public_detail(<school_worksite_id>);
```
Expected: 학교>1, 국가=1, 원소에 `is_placeholder`·`recruit_until` 포함.

- [ ] **Step 5: 비로그인 경로 육안 검증**

`npm run dev`에서 로그아웃(PUBLIC_BROWSE) 상태로 학교근로 상세 → 대표 카드 + "다른 공고" 목록 표시(로그인 경로와 동일).

- [ ] **Step 6: 커밋**

```bash
git add web/supabase/migrations
git commit -m "feat(db): get_worksite_public_detail 공고 배열 반환(30캡·is_placeholder·recruit_until)"
```

---

### Task 7: 문서 갱신

**Files:**
- Modify: `docs/db-schema.md`
- Modify: `web/supabase/README.md`

- [ ] **Step 1: `docs/db-schema.md`** — `get_worksite_public_detail` 언급부에 시그니처 변경 한 줄 추가

`get_worksite_public_detail` 관련 서술 근처에 추가:
```markdown
- **`get_worksite_public_detail`**: 반환이 `posting jsonb`(대표 1개) → **`postings jsonb`(공고 배열, 활성→최신, 최근 30개)** 로 변경(20260721). 각 원소에 `is_placeholder`·`recruit_until` 포함. 대표/목록 선별은 클라(`web/src/lib/postings.js selectPostings`). 시그니처 변경이라 `DROP FUNCTION` 먼저 + grant 재부여.
```

- [ ] **Step 2: `web/supabase/README.md`** — 최근 변경/마이그레이션 목록에 한 줄 추가

```markdown
- `<ts>_worksite_detail_postings.sql` — `get_worksite_public_detail` 공고 배열 반환(A안: 근무지 상세 다중 공고 노출). 시그니처 변경(DROP 먼저).
```

- [ ] **Step 3: 커밋**

```bash
git add docs/db-schema.md web/supabase/README.md
git commit -m "docs: get_worksite_public_detail 배열 반환 반영"
```

---

## Self-Review

**1. Spec coverage:**
- §2 A안(근무지 유지+목록) → Task 3·5. §3 비목표(리뷰/근무지 분리·title 없음) → 데이터 모델 무변경(준수). §5 UI(대표+목록·접힘줄·시급 제외·공통태그 대표만) → Task 3. §5 선별 단일정본 → Task 1 `selectPostings`. §6 파일변경 표 전부 → Task 1~7 매핑. §7 엣지(공고1개·국가근로 placeholder·직무미상·정렬·배지·30캡) → Task 1 테스트 + Task 5 육안 + Task 6 SQL. §8 순서 → Task 순서(단, 프론트 먼저·마이그 나중으로 조정, tolerant라 안전). ✅ 갭 없음.
- 추가 반영: 배포 순서 함정 → Task 4 tolerant 읽기 + Global Constraints.

**2. Placeholder scan:** "TBD/TODO/적절히" 없음. 모든 코드 스텝에 실제 코드. ✅

**3. Type consistency:**
- `selectPostings(postings) → {representative, others}` — Task 1 정의, Task 5 소비 일치.
- `summarizeJob(posting)` — Task 1 정의, Task 3 소비 일치.
- `PostingFields({posting, isNational})` — Task 2 export, Task 3 소비 일치.
- `fetchPostings(worksiteId) → object[]` — Task 4 정의, Task 5 소비 일치.
- `fetchWorksitePublicDetail → {worksite, postings}` — Task 4, Task 5 `info.postings` 일치.
- RPC `postings` 키 ↔ Task 4 `row.postings` 일치. 각 원소 `id`(React key)·`is_placeholder`·`recruit_until` ↔ Task 1·3 사용 일치. ✅
