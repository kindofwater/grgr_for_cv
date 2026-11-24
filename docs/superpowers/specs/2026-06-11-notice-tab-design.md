# 공지사항(Notice) 탭 설계 (page-only)

작성일: 2026-06-11 · 담당: 배경록 (도유진이 위임)

## 1. 목적 / 범위

지금까지 "껍데기만" 있던 공지사항을 **실제로 동작하는 탭**으로 만든다.
현재 상태: Navbar·모바일 하단탭의 "공지사항" 링크는 로그인 사용자에겐 **죽은 링크**,
Home 사이드바 `notice-box`는 **하드코딩된 가짜 공지 3개**, 라우트·페이지·data 계층은 **전무**.

**범위 = page-only(읽기 전용).** 기존 `notices` 테이블에서 **SELECT만** 한다.
- ✅ 목록 페이지 + 상세 페이지 + 라우트 + data 계층 + 죽은 링크 연결 + Home 사이드바 실데이터화
- ✅ **DB 변경 0** — 스키마·시드·마이그레이션 손대지 않음. 순수 프론트 작업(push·디스코드 공유 불필요).
- ❌ **범위 밖**: 작성/수정/삭제 UI, 관리자(`is_admin`) 권한·RLS, 검색·페이지네이션, 색 정책 확정, **샘플/시드 데이터** (전부 후속)

> **RLS 미적용 근거:** 이 앱의 public 테이블은 현재 RLS 없이 anon 키로 읽힌다(메모리의 `password_hash` 노출 이슈가 그 증거). 쓰기 UI를 안 만드는 한 SELECT는 그대로 동작하므로 RLS는 후속 과제. 단 이는 기존 보안부채를 따르는 것이며 이 탭이 새로 만드는 문제는 아니다.

## 2. 결정사항 (브레인스토밍)

- **데이터 소스: Supabase `notices` 테이블(정식).** 하드코딩 아님. (테이블은 baseline에 이미 존재 — 새로 만들 필요 없음)
- **구조: 목록 + 상세(별도 라우트).** 목업(`#screen-notice`)은 "내용까지 한 번에 보이는 평타 목록"이지만, **의식적으로 목록+상세를 택함**(본문이 길어도 목록이 깔끔, 확장성). → 목업과 의도적으로 다름.
- **배지: `is_pinned` 기반.** `is_pinned=true` → "공지" 배지 + 목록 상단 고정, `false` → "안내" 배지. (목업의 공지/안내 2종 배지를 스키마의 `is_pinned`에 매핑) **색은 하드코딩 금지 → CSS 토큰으로, 색 정책은 후속 결정.**
- **스키마 변경 없음.** 컬럼 추가(category 등) 안 함. 전부 기존 컬럼으로.
- **로그인 가드 없음.** 공지는 공개성 콘텐츠라 `/notice` 직접 접근 시에도 표시(민감정보 없음). 게스트는 Navbar에서 로그인 유도로 도달이 막혀 있음(기존 패턴 유지).
- **샘플/시드 데이터 없음.** 처음엔 빈 상태(empty state)로 노출하고, 실제 공지는 후속(도유진/관리자)이 추가. (이 프로젝트는 throwaway 시드를 `seed.sql`에 두는 컨벤션이 있으나, 팀이 Docker 미사용이라 `seed.sql`이 로컬에서 안 돌고, 마이그레이션 시드는 prod 정본을 오염시켜 둘 다 안 씀 → 빈 상태로 시작.)

## 3. 라우트 / 네비

- `App.jsx`에 추가:
  ```jsx
  <Route path="/notice" element={<Notice />} />
  <Route path="/notice/:id" element={<NoticeDetail />} />
  ```
- **Navbar 죽은 링크 살리기** (`components/Navbar.jsx`):
  - 데스크톱 `nav-links`의 "공지사항" `<a>` → `go('/notice')` (근장찾기·교환센터와 동일 패턴: 게스트는 `onGuestClick`, 로그인은 navigate).
  - 모바일 `bottom-nav`의 "공지사항" `<a>` → `go('/notice')` + `pathname.startsWith('/notice')`일 때 `nav-active`.
- **Home 사이드바** "더보기 ›" → `navigate('/notice')` (§7).

## 4. 데이터 계층 — `data/noticeQueries.js` (신규)

기존 `worksiteQueries` 패턴(`../supabase`만 의존, `if (error) throw error`) 그대로.

```js
import { supabase } from '../supabase'

// 목록: 본문 제외(가벼움). 고정 우선 + 최신순.
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

// 상세: 본문 포함.
export async function fetchNoticeById(id) {
  const { data, error } = await supabase
    .from('notices')
    .select('id, title, content, is_pinned, created_at, updated_at')
    .eq('id', id)
    .maybeSingle()      // 없는 id → null (throw 아님), 페이지에서 "없음" 분기
  if (error) throw error
  return data
}
```

- `fetchNotices()` → 목록 페이지, `fetchNotices({ limit: 3 })` → Home 사이드바(§7) 공용.
- `data/README.md` "현재 파일" 표에 `noticeQueries.js` 한 줄 추가.

## 5. 목록 페이지 — `pages/Notice.jsx` (+ `Notice.css`)

```
nav (기존 <Navbar /> 재사용)
notice-wrap (max-width ~760px, 중앙)
└── 제목 "공지사항"
└── 로딩 / 에러 / 빈 상태 / 목록
    └── notice-row × N  (클릭 → navigate(`/notice/${id}`))
        ├── badge (is_pinned ? "공지" : "안내")
        ├── title
        └── date  (formatDate(created_at))
```

- 마운트 시 `fetchNotices()`. `useState`로 `loading / error / list`.
- **로딩**: 간단 텍스트("불러오는 중…") 또는 스켈레톤(기존 패턴 가벼우면 텍스트로 충분).
- **에러**: "공지를 불러오지 못했어요." + "다시 시도" 버튼(재호출).
- **빈 상태**: "등록된 공지가 없습니다."
- 행 클릭 → 상세로 이동. 키보드 접근은 후속(YAGNI).

## 6. 상세 페이지 — `pages/NoticeDetail.jsx` (+ `NoticeDetail.css`)

```
nav (<Navbar />)
notice-detail-wrap (max-width ~760px, 중앙)
├── "← 목록" (navigate('/notice'))
├── badge + date
├── title
└── content  ({content}, white-space: pre-wrap)
```

- `useParams()`로 `id` → `fetchNoticeById(id)`.
- `loading / notFound / notice` 분기.
- **없음(null)**: "존재하지 않는 공지입니다." + "목록으로" 버튼.
- 본문 줄바꿈은 CSS `white-space: pre-wrap` (§10 보안).

## 7. Home 사이드바 실데이터화 (2-b) — `pages/Home.jsx`

- 기존 데이터 로딩 흐름에 `fetchNotices({ limit: 3 })` 합류(Promise 묶음 또는 별도 `useState`; 공지는 실패해도 화면 치명적이지 않으므로 **개별 try/catch로 격리** 권장 — 공지 못 불러와도 홈 본문은 정상).
- `notice-box` 안 **하드코딩 `notice-item` 3개 → 실제 최신 3개 map**.
  - 각 항목 `<p>{title}</p><span>{formatDate(created_at)}</span>`.
  - **공지 0개면 "등록된 공지가 없습니다." 한 줄** (샘플 없으므로 초기 기본 상태).
- ⚠️ **게스트 게이트 우회 방지(중요):** 더보기·각 항목 클릭 핸들러는 **로그인 시에만** `navigate(...)`를 달고, **게스트는 핸들러를 달지 않아** `notice-box` 전체의 기존 `onClick={onLockedClick}`(로그인 유도)에 맡긴다. 무조건 `navigate`를 달면 게스트가 로그인 게이트를 우회해 `/notice`로 가버림.
  - 로그인 시: 더보기 → `navigate('/notice')`, 항목 → `navigate(`/notice/${id}`)`.
- 마크업 클래스(`notice-box/head/more/item`)는 기존 CSS 재사용 — 시각 변화 없음.

## 8. 배지 / 색 토큰 — `index.css`

색 정책 미정이므로 **의미 토큰**을 새로 추가하고 일단 기존 토큰에 별칭(추후 한 곳만 바꾸면 정책 반영):

```css
/* 공지 배지 — 색 정책 미정(추후 결정). 일단 기존 토큰 별칭. */
--notice-pin-bg:    var(--primary-light);
--notice-pin-fg:    var(--primary-dark);
--notice-badge-bg:  var(--surface);
--notice-badge-fg:  var(--text-sub);
```

- `Notice.css` / `NoticeDetail.css`의 배지는 위 토큰만 `var()`로 참조. **hex 직접 사용 금지**(최근 `--progress` 토큰화 커밋과 동일 원칙).
- 배지 라벨: `is_pinned ? '공지' : '안내'`.

## 9. 날짜 헬퍼 / 테스트 — `lib/dates.js` (+ `dates.test.js`)

```js
// timestamp(타임존 없음) 문자열을 "YYYY.MM.DD"로. TZ 드리프트 방지 위해
// Date 파싱 대신 문자열 날짜부만 사용.
export function formatDate(ts) {
  if (!ts) return ''
  return String(ts).slice(0, 10).replaceAll('-', '.')   // "2026-06-11..." → "2026.06.11"
}
```

- 순수 함수. 목록·상세·Home 공용.
- `dates.test.js`(vitest): 정상값, `null`/`undefined`, 시간 포함 문자열.
- `lib/README.md` 표에 `dates.js` 추가.
- (목업은 "2026.03.10 09:00"처럼 시간도 표기하지만, 이번엔 날짜만. 시간 표기는 후속 — 헬퍼만 추가하면 쉬움.)

## 10. 보안 (CLAUDE.md 4번)

- `title`·`content`는 **일반 텍스트** → JSX `{content}`로 렌더(React 자동 escape). **`dangerouslySetInnerHTML` 절대 금지** → XSS 안전.
- 본문 줄바꿈은 HTML 주입이 아니라 CSS `white-space: pre-wrap`로 처리.
- 사용자 입력을 다루지 않음(읽기 전용) → 인젝션 표면 없음.

## 11. 변경 파일 요약

**DB 변경 없음 — 순수 프론트.** (마이그레이션·시드·스키마 손대지 않음)

- **신규**:
  - `web/src/pages/Notice.jsx` (+`Notice.css`)
  - `web/src/pages/NoticeDetail.jsx` (+`NoticeDetail.css`)
  - `web/src/data/noticeQueries.js`
  - `web/src/lib/dates.js` (+`dates.test.js`)
- **수정**:
  - `web/src/App.jsx` (라우트 2개)
  - `web/src/components/Navbar.jsx` (공지사항 링크 데스크톱+모바일 연결, 모바일 active)
  - `web/src/pages/Home.jsx` (사이드바 실데이터 + 더보기 연결, 게스트 게이트 가드)
  - `web/src/index.css` (배지 토큰 4개)
- **README 갱신**: `web/src/pages/README.md`, `web/src/data/README.md`, `web/src/lib/README.md`
- **문서**: 이 spec. (스키마 변경 없음 → `docs/db-schema.md`·`web/supabase/README.md` 갱신 불필요)

## 12. 범위 밖 (YAGNI)

작성/수정/삭제 UI, 관리자(`is_admin`) 권한·쓰기 RLS, 공지 카테고리 컬럼, 검색·페이지네이션, 날짜+시간 표기, 색 정책 확정, 첨부파일·이미지, 읽음 표시, 샘플/시드 데이터.
