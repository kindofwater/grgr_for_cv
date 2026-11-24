# 공지사항(Notice) 탭 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 기존 `notices` 테이블에서 읽기만 하는 공지사항 목록(`/notice`)·상세(`/notice/:id`) 페이지를 만들고, 죽어 있던 Navbar·모바일탭·Home 사이드바 링크를 살린다.

**Architecture:** DB 변경 0(순수 프론트). `data/noticeQueries.js`의 SELECT 2개로 조회, `lib/dates.js` 순수 헬퍼로 날짜 포맷, 두 페이지가 단일 `Notice.css`를 공유. 배지 색은 `index.css` 토큰으로(정책 후속). RLS·작성 UI·관리자 권한은 범위 밖.

**Tech Stack:** React 19 + react-router-dom 7, Supabase JS(`.from().select()`), Vitest(순수 함수), Vite.

**Spec:** `docs/superpowers/specs/2026-06-11-notice-tab-design.md`
**Branch:** `feat/notice-tab` (이미 생성됨)

> 모든 커밋 메시지 끝에 한 줄 추가: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
> 폴더를 만지기 전 그 폴더 `README.md`를 읽고, 파일 추가 시 "현재 파일" 표를 갱신한다(CLAUDE.md §5).
> 명령은 `web/`에서 실행(`cd web`). 작업 디렉터리는 `c:\새 폴더`.

---

## File Structure

- Create: `web/src/lib/dates.js` (+ `dates.test.js`) — `formatDate(ts)` 순수 헬퍼
- Create: `web/src/data/noticeQueries.js` — `fetchNotices`, `fetchNoticeById`
- Create: `web/src/pages/Notice.jsx` — 목록 화면
- Create: `web/src/pages/Notice.css` — 공지 목록·상세 **공용** 스타일(두 페이지가 import)
- Create: `web/src/pages/NoticeDetail.jsx` — 상세 화면 (css는 `Notice.css` 공유)
- Modify: `web/src/index.css` — 배지 색 토큰 4개
- Modify: `web/src/App.jsx` — `/notice`, `/notice/:id` 라우트
- Modify: `web/src/components/Navbar.jsx` — 공지사항 링크(데스크톱+모바일) 연결 + 모바일 active
- Modify: `web/src/pages/Home.jsx` — 사이드바 실데이터 + 더보기 연결(게스트 게이트 가드)
- Modify: `web/src/lib/README.md` · `data/README.md` · `pages/README.md` — 현재 파일 표

> **spec과의 차이(의도적):** spec §12는 `NoticeDetail.css`를 별도로 적었으나, 배지·상태·wrap 클래스를 두 페이지가 공유하므로 단일 `Notice.css`로 합치고 양쪽에서 import한다(DRY).

---

## Task 1: 날짜 포맷 헬퍼 `lib/dates.js` (TDD)

**Files:**
- Create: `web/src/lib/dates.js`
- Test: `web/src/lib/dates.test.js`

- [ ] **Step 1: 실패 테스트 작성** — `web/src/lib/dates.test.js`

```js
import { describe, it, expect } from 'vitest'
import { formatDate } from './dates'

describe('formatDate (timestamp → "YYYY.MM.DD")', () => {
  it('ISO 날짜+시간 문자열은 날짜부만 점 표기', () => {
    expect(formatDate('2026-06-11T09:30:00')).toBe('2026.06.11')
  })
  it('공백 구분 timestamp도 처리', () => {
    expect(formatDate('2026-01-05 14:00:00')).toBe('2026.01.05')
  })
  it('null/undefined/빈값은 빈 문자열', () => {
    expect(formatDate(null)).toBe('')
    expect(formatDate(undefined)).toBe('')
    expect(formatDate('')).toBe('')
  })
})
```

- [ ] **Step 2: 실패 확인**

Run: `cd web && npx vitest run src/lib/dates.test.js`
Expected: FAIL — `Failed to resolve import './dates'` (모듈 없음)

- [ ] **Step 3: 최소 구현** — `web/src/lib/dates.js`

```js
// timestamp(타임존 없음) 문자열 → "YYYY.MM.DD".
// new Date() 파싱은 로컬 타임존 보정이 끼어 날짜가 하루 밀릴 수 있어,
// 문자열 날짜부("YYYY-MM-DD")만 잘라 점으로 바꾼다(순수·결정적, lib 규칙: 외부상태/시간 의존 0).
export function formatDate(ts) {
  if (!ts) return ''
  return String(ts).slice(0, 10).replaceAll('-', '.')
}
```

- [ ] **Step 4: 통과 확인**

Run: `cd web && npx vitest run src/lib/dates.test.js`
Expected: PASS (3 tests)

- [ ] **Step 5: lib README 갱신** — `web/src/lib/README.md` "현재 파일" 표 끝에 2줄 추가

```markdown
| `dates.js` | timestamp → "YYYY.MM.DD" 포맷(`formatDate`) |
| `dates.test.js` | `dates.js` 단위테스트 |
```

- [ ] **Step 6: 커밋**

```bash
git add web/src/lib/dates.js web/src/lib/dates.test.js web/src/lib/README.md
git commit -m "feat(notice): 날짜 포맷 헬퍼 lib/dates.js 추가 (TDD)"
```

---

## Task 2: 데이터 계층 `data/noticeQueries.js`

**Files:**
- Create: `web/src/data/noticeQueries.js`
- Modify: `web/src/data/README.md`

- [ ] **Step 1: 쿼리 파일 작성** — `web/src/data/noticeQueries.js`

```js
import { supabase } from '../supabase'

// 목록: 본문 제외(가벼움). 고정(is_pinned) 우선 + 최신순.
export async function fetchNotices({ limit } = {}) {
  let q = supabase
    .from('notices')
    .select('id, title, is_pinned, created_at')
    .order('is_pinned', { ascending: false })
    .order('created_at', { ascending: false })
  if (limit) q = q.limit(limit)
  const { data, error } = await q
  if (error) throw error
  return data ?? []
}

// 상세: 본문 포함. 없는 id면 null 반환(throw 아님) → 페이지에서 "없음" 분기.
export async function fetchNoticeById(id) {
  const { data, error } = await supabase
    .from('notices')
    .select('id, title, content, is_pinned, created_at, updated_at')
    .eq('id', id)
    .maybeSingle()
  if (error) throw error
  return data
}
```

- [ ] **Step 2: data README 갱신** — `web/src/data/README.md` "현재 파일" 표 끝에 1줄 추가

```markdown
| `noticeQueries.js` | 공지사항 조회. `fetchNotices`(목록·고정우선/최신순), `fetchNoticeById`(상세) |
```

- [ ] **Step 3: lint 확인**

Run: `cd web && npm run lint`
Expected: PASS (새 파일 관련 에러 없음)

- [ ] **Step 4: 커밋**

```bash
git add web/src/data/noticeQueries.js web/src/data/README.md
git commit -m "feat(notice): data 계층 noticeQueries.js (fetchNotices/fetchNoticeById)"
```

---

## Task 3: 배지 색 토큰 `index.css`

**Files:**
- Modify: `web/src/index.css`

- [ ] **Step 1: 토큰 추가** — `web/src/index.css`의 `:root` 안, `--progress: #22C55E;` 줄 **바로 아래**에 삽입

찾을 기준 줄:
```css
  /* 회원가입 진행 바 초록 (원색 유지) — 추후 --good 등으로 정리 검토 (담당: kindofwater) */
  --progress:     #22C55E;
```

그 아래에 추가:
```css

  /* 공지 배지 — 색 정책 미정(추후 결정). 일단 기존 토큰 별칭. */
  --notice-pin-bg:    var(--primary-light);
  --notice-pin-fg:    var(--primary-dark);
  --notice-badge-bg:  var(--surface);
  --notice-badge-fg:  var(--text-sub);
```

- [ ] **Step 2: 커밋**

```bash
git add web/src/index.css
git commit -m "feat(notice): 공지 배지 색 토큰 추가 (정책은 후속)"
```

---

## Task 4: 목록 페이지 `pages/Notice.jsx` + `Notice.css` + 라우트

**Files:**
- Create: `web/src/pages/Notice.jsx`
- Create: `web/src/pages/Notice.css`
- Modify: `web/src/App.jsx`
- Modify: `web/src/pages/README.md`

- [ ] **Step 1: 목록 페이지 작성** — `web/src/pages/Notice.jsx`

```jsx
import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import Navbar from '../components/Navbar'
import { fetchNotices } from '../data/noticeQueries'
import { formatDate } from '../lib/dates'
import './Notice.css'

export default function Notice() {
  const navigate = useNavigate()
  const [list, setList] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  async function load() {
    setLoading(true)
    setError(null)
    try {
      setList(await fetchNotices())
    } catch (err) {
      setError(err.message)
    }
    setLoading(false)
  }

  useEffect(() => { load() }, [])

  return (
    <div className="notice-wrap">
      <Navbar />
      <div className="notice-page">
        <h1 className="notice-title">공지사항</h1>

        {loading && <p className="notice-state">불러오는 중…</p>}

        {!loading && error && (
          <div className="notice-state">
            <p>공지를 불러오지 못했어요.</p>
            <button className="notice-retry" onClick={load}>다시 시도</button>
          </div>
        )}

        {!loading && !error && list.length === 0 && (
          <p className="notice-state">등록된 공지가 없습니다.</p>
        )}

        {!loading && !error && list.length > 0 && (
          <ul className="notice-list">
            {list.map((n) => (
              <li
                key={n.id}
                className="notice-card"
                onClick={() => navigate(`/notice/${n.id}`)}
              >
                <div className="notice-card-top">
                  <span className={`notice-badge ${n.is_pinned ? 'notice-badge--pin' : ''}`}>
                    {n.is_pinned ? '공지' : '안내'}
                  </span>
                  <span className="notice-date">{formatDate(n.created_at)}</span>
                </div>
                <div className="notice-card-title">{n.title}</div>
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  )
}
```

- [ ] **Step 2: 공용 스타일 작성** — `web/src/pages/Notice.css` (목록 + 상세 공용. 토큰만 참조, hex 금지)

```css
/* 공지 목록·상세 공용 (Notice.jsx, NoticeDetail.jsx 양쪽 import) */
.notice-wrap { min-height: 100vh; background: var(--bg); }

.notice-page { max-width: 760px; margin: 0 auto; padding: 40px 20px 80px; }
.notice-title { font-size: 22px; font-weight: 700; color: var(--text-h); margin-bottom: 20px; }

.notice-state { color: var(--text-sub); font-size: 14px; padding: 32px 0; text-align: center; }
.notice-retry {
  margin-top: 12px; padding: 8px 16px; border: 1px solid var(--border);
  border-radius: 8px; background: var(--card); color: var(--text); cursor: pointer;
}
.notice-retry:hover { border-color: var(--border-strong); }

.notice-list { display: flex; flex-direction: column; gap: 12px; list-style: none; padding: 0; margin: 0; }
.notice-card {
  background: var(--card); border: 1px solid var(--border); border-radius: 12px;
  padding: 18px 22px; cursor: pointer; transition: border-color .15s, box-shadow .15s;
}
.notice-card:hover { border-color: var(--border-strong); box-shadow: var(--shadow-sm); }
.notice-card-top { display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px; }
.notice-date { font-size: 12px; color: var(--text-muted); }
.notice-card-title { font-size: 15px; font-weight: 600; color: var(--text); }

.notice-badge {
  font-size: 11px; font-weight: 700; padding: 3px 8px; border-radius: 4px;
  background: var(--notice-badge-bg); color: var(--notice-badge-fg);
}
.notice-badge--pin { background: var(--notice-pin-bg); color: var(--notice-pin-fg); }

/* ── 상세 (NoticeDetail.jsx) ── */
.notice-detail { max-width: 760px; margin: 0 auto; padding: 32px 20px 80px; }
.notice-back {
  background: none; border: none; color: var(--text-sub); font-size: 14px;
  cursor: pointer; padding: 4px 0; margin-bottom: 20px;
}
.notice-back:hover { color: var(--text); }
.notice-article {
  background: var(--card); border: 1px solid var(--border); border-radius: 12px; padding: 28px 28px 36px;
}
.notice-article-title {
  font-size: 20px; font-weight: 700; color: var(--text-h);
  margin: 10px 0 18px; line-height: 1.4; word-break: break-word;
}
.notice-article-body {
  font-size: 14px; color: var(--text-sub); line-height: 1.7;
  white-space: pre-wrap; word-break: break-word;
}
```

- [ ] **Step 3: 라우트 등록** — `web/src/App.jsx`

import 블록 끝(`import MyPage from './pages/MyPage'` 아래)에 추가:
```jsx
import Notice from './pages/Notice'
```

`<Route path="/mypage" element={<MyPage />} />` 아래에 추가:
```jsx
<Route path="/notice" element={<Notice />} />
```

- [ ] **Step 4: pages README 갱신** — `web/src/pages/README.md` "현재 파일" 표 끝에 1줄 추가

```markdown
| `Notice.jsx` / `Notice.css` | `/notice` | 공지 목록. `data/noticeQueries.fetchNotices` 조회. css는 상세와 공용 |
```

- [ ] **Step 5: lint + 빌드 확인**

Run: `cd web && npm run lint && npm run build`
Expected: PASS (빌드 성공)

- [ ] **Step 6: 커밋**

```bash
git add web/src/pages/Notice.jsx web/src/pages/Notice.css web/src/App.jsx web/src/pages/README.md
git commit -m "feat(notice): 공지 목록 페이지 /notice + 공용 css"
```

---

## Task 5: 상세 페이지 `pages/NoticeDetail.jsx` + 라우트

**Files:**
- Create: `web/src/pages/NoticeDetail.jsx`
- Modify: `web/src/App.jsx`
- Modify: `web/src/pages/README.md`

- [ ] **Step 1: 상세 페이지 작성** — `web/src/pages/NoticeDetail.jsx` (css는 공용 `Notice.css` 재사용)

```jsx
import { useEffect, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import Navbar from '../components/Navbar'
import { fetchNoticeById } from '../data/noticeQueries'
import { formatDate } from '../lib/dates'
import './Notice.css'

export default function NoticeDetail() {
  const { id } = useParams()
  const navigate = useNavigate()
  const [notice, setNotice] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  useEffect(() => {
    async function load() {
      setLoading(true)
      setError(null)
      try {
        setNotice(await fetchNoticeById(id))
      } catch (err) {
        setError(err.message)
      }
      setLoading(false)
    }
    load()
  }, [id])

  return (
    <div className="notice-wrap">
      <Navbar />
      <div className="notice-detail">
        <button className="notice-back" onClick={() => navigate('/notice')}>← 목록</button>

        {loading && <p className="notice-state">불러오는 중…</p>}
        {!loading && error && <p className="notice-state">공지를 불러오지 못했어요.</p>}

        {!loading && !error && !notice && (
          <div className="notice-state">
            <p>존재하지 않는 공지입니다.</p>
            <button className="notice-retry" onClick={() => navigate('/notice')}>목록으로</button>
          </div>
        )}

        {!loading && !error && notice && (
          <article className="notice-article">
            <div className="notice-card-top">
              <span className={`notice-badge ${notice.is_pinned ? 'notice-badge--pin' : ''}`}>
                {notice.is_pinned ? '공지' : '안내'}
              </span>
              <span className="notice-date">{formatDate(notice.created_at)}</span>
            </div>
            <h1 className="notice-article-title">{notice.title}</h1>
            <div className="notice-article-body">{notice.content}</div>
          </article>
        )}
      </div>
    </div>
  )
}
```

> 보안(CLAUDE §4): `{notice.title}`·`{notice.content}`는 React가 자동 escape → XSS 안전. `dangerouslySetInnerHTML` 절대 쓰지 않는다. 줄바꿈은 css `white-space: pre-wrap`.

- [ ] **Step 2: 라우트 등록** — `web/src/App.jsx`

`import Notice from './pages/Notice'` 아래에 추가:
```jsx
import NoticeDetail from './pages/NoticeDetail'
```

`<Route path="/notice" element={<Notice />} />` 아래에 추가:
```jsx
<Route path="/notice/:id" element={<NoticeDetail />} />
```

- [ ] **Step 3: pages README 갱신** — `web/src/pages/README.md` "현재 파일" 표 끝에 1줄 추가

```markdown
| `NoticeDetail.jsx` | `/notice/:id` | 공지 상세. `fetchNoticeById`. css는 `Notice.css` 공유 |
```

- [ ] **Step 4: lint + 빌드 확인**

Run: `cd web && npm run lint && npm run build`
Expected: PASS

- [ ] **Step 5: 커밋**

```bash
git add web/src/pages/NoticeDetail.jsx web/src/App.jsx web/src/pages/README.md
git commit -m "feat(notice): 공지 상세 페이지 /notice/:id"
```

---

## Task 6: Navbar 죽은 링크 살리기

**Files:**
- Modify: `web/src/components/Navbar.jsx`

- [ ] **Step 1: 데스크톱 링크 연결** — `web/src/components/Navbar.jsx`

찾기:
```jsx
        <a style={{ cursor: 'pointer' }} onClick={guest ? onGuestClick : undefined}>공지사항</a>
```
바꾸기:
```jsx
        <a style={{ cursor: 'pointer' }} onClick={go('/notice')}>공지사항</a>
```

- [ ] **Step 2: 모바일 하단탭 링크 연결 + active** — 같은 파일

찾기 (모바일 `bottom-nav`의 공지사항 항목):
```jsx
      <a onClick={guest ? onGuestClick : undefined}>
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9" /><path d="M13.73 21a2 2 0 0 1-3.46 0" /></svg>
        공지사항
      </a>
```
바꾸기 (className active만 추가, onClick을 `go('/notice')`로):
```jsx
      <a className={pathname.startsWith('/notice') ? 'nav-active' : ''} onClick={go('/notice')}>
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9" /><path d="M13.73 21a2 2 0 0 1-3.46 0" /></svg>
        공지사항
      </a>
```

> `go`·`pathname`·`guest`는 이미 이 컴포넌트에 정의돼 있음(`go = (path) => guest ? onGuestClick : () => navigate(path)`). 게스트(Home)면 로그인 유도, 로그인 사용자면 이동 — 기존 근장찾기/교환센터와 동일 패턴.

- [ ] **Step 3: lint + 빌드 확인**

Run: `cd web && npm run lint && npm run build`
Expected: PASS

- [ ] **Step 4: 커밋**

```bash
git add web/src/components/Navbar.jsx
git commit -m "feat(notice): Navbar·모바일탭 공지사항 링크 /notice 연결 + 모바일 active"
```

---

## Task 7: Home 사이드바 실데이터 + 더보기 (게스트 게이트 가드)

**Files:**
- Modify: `web/src/pages/Home.jsx`

- [ ] **Step 1: import 추가** — `web/src/pages/Home.jsx` 상단 import 블록

`import SkeletonHome from '../components/SkeletonHome'` 아래(또는 import 블록 적당한 곳)에 추가:
```jsx
import { fetchNotices } from '../data/noticeQueries'
import { formatDate } from '../lib/dates'
```

- [ ] **Step 2: notices 상태 추가** — Home 컴포넌트 내부

찾기:
```jsx
  const [showLoginModal, setShowLoginModal] = useState(false)
```
그 아래에 추가:
```jsx
  const [notices, setNotices] = useState([])
```

- [ ] **Step 3: 공지 로딩(격리)** — 같은 파일 `fetchData` 안, 메인 try/catch 끝과 `setLoading(false)` 사이

찾기 (effect 안의 이 구간):
```jsx
      } catch (err) {
        setError(err.message)
      }
      setLoading(false)
    }
    fetchData()
  }, [authUser])
```
바꾸기 (공지 로딩을 별도 try/catch로 격리 — 실패해도 홈 본문 정상):
```jsx
      } catch (err) {
        setError(err.message)
      }

      try {
        setNotices(await fetchNotices({ limit: 3 }))
      } catch { /* 공지 못 불러와도 홈은 정상 */ }

      setLoading(false)
    }
    fetchData()
  }, [authUser])
```

- [ ] **Step 4: 사이드바 notice-box 실데이터화 + 게스트 가드** — 같은 파일

찾기 (하드코딩 3개):
```jsx
          <div className="notice-box" onClick={!isLoggedIn ? onLockedClick : undefined} style={!isLoggedIn ? { cursor: 'pointer' } : undefined}>
            <div className="notice-head">
              <span>공지사항</span>
              <span className="notice-more">더보기 ›</span>
            </div>
            <div className="notice-item">
              <p>서비스 오픈 안내</p>
              <span>2026.06.01</span>
            </div>
            <div className="notice-item">
              <p>리뷰 작성 시 포인트 지급</p>
              <span>2026.05.28</span>
            </div>
            <div className="notice-item">
              <p>크롤링 데이터 업데이트</p>
              <span>2026.05.25</span>
            </div>
          </div>
```
바꾸기:
```jsx
          <div className="notice-box" onClick={!isLoggedIn ? onLockedClick : undefined} style={!isLoggedIn ? { cursor: 'pointer' } : undefined}>
            <div className="notice-head">
              <span>공지사항</span>
              <span
                className="notice-more"
                onClick={isLoggedIn ? () => navigate('/notice') : undefined}
                style={isLoggedIn ? { cursor: 'pointer' } : undefined}
              >더보기 ›</span>
            </div>
            {notices.length === 0 ? (
              <div className="notice-item"><p style={{ color: 'var(--text-muted)' }}>등록된 공지가 없습니다.</p></div>
            ) : (
              notices.map((n) => (
                <div
                  key={n.id}
                  className="notice-item"
                  onClick={isLoggedIn ? () => navigate(`/notice/${n.id}`) : undefined}
                  style={isLoggedIn ? { cursor: 'pointer' } : undefined}
                >
                  <p>{n.title}</p>
                  <span>{formatDate(n.created_at)}</span>
                </div>
              ))
            )}
          </div>
```

> **게스트 가드:** 로그인 안 됐을 때 더보기·항목의 `onClick`은 `undefined` → 클릭이 `notice-box` 전체의 `onLockedClick`으로 버블링(로그인 유도). 로그인 시에만 `navigate`. 게이트 우회 없음. (로그인 사용자는 box onClick이 `undefined`라 이중 호출 없음.)

- [ ] **Step 5: lint + 빌드 확인**

Run: `cd web && npm run lint && npm run build`
Expected: PASS

- [ ] **Step 6: 커밋**

```bash
git add web/src/pages/Home.jsx
git commit -m "feat(notice): Home 사이드바 실제 공지 최신 3개 + 더보기 연결(게스트 가드)"
```

---

## Task 8: 전체 검증 (테스트·lint·빌드·수동 QA)

**Files:** 없음(검증만)

- [ ] **Step 1: 단위테스트 전체**

Run: `cd web && npm run test`
Expected: PASS (`dates.test.js` 포함 모든 기존 테스트 통과)

- [ ] **Step 2: lint + 빌드**

Run: `cd web && npm run lint && npm run build`
Expected: PASS (에러 0)

- [ ] **Step 3: 수동 QA** — `cd web && npm run dev` 후 브라우저에서:
  - 로그인 상태로 상단 "공지사항" 클릭 → `/notice` 이동, **"등록된 공지가 없습니다."** 표시(데이터 없음 = 정상).
  - 모바일 폭(≤768px)에서 하단탭 "공지사항" 활성(active) 표시 + 이동 확인.
  - Home 사이드바: 로그인 시 빈 상태 한 줄 + "더보기" 클릭 → `/notice`. **비로그인** 시 사이드바/더보기 클릭 → 로그인 모달(게이트 우회 없음) 확인.
  - (선택) Supabase **대시보드에서 임시 행 1개** insert(throwaway) → 목록 카드·배지·날짜 렌더 + 클릭 시 `/notice/:id` 상세(본문 `pre-wrap`) 확인 → 확인 후 행 삭제.

- [ ] **Step 4: (해당 시) 마무리 커밋** — 검증 중 고친 게 있으면 커밋. 없으면 생략.

---

## Self-Review (작성자 점검 결과)

- **Spec 커버리지:** §3 라우트/네비→T4·T5·T6, §4 데이터→T2, §5 목록→T4, §6 상세→T5, §7 Home→T7, §8 배지토큰→T3, §9 날짜헬퍼→T1, §10 보안→T5(주석), §11 변경파일→전체. 누락 없음. (§범위의 "DB 변경 0" = seed/마이그레이션 태스크 없음 — 의도적.)
- **Placeholder:** 없음(모든 코드 전문 기재).
- **타입/이름 일관성:** `fetchNotices`/`fetchNoticeById`, `formatDate`, 토큰 `--notice-pin-bg/-fg`·`--notice-badge-bg/-fg`, 클래스 `notice-badge(--pin)`·`notice-card-top`·`notice-state` — 정의(T1~T4)와 사용(T4·T5·T7) 일치.
