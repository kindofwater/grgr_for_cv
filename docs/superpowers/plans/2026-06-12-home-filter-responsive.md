# 홈 필터 반응형 (데스크톱 pill / 모바일 드롭다운) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 홈 근장 목록 필터를 `≥480px`는 기존 pill+범례(현상유지), `<480px`는 커스텀 드롭다운 2개로 보여준다.

**Architecture:** 모집상태를 3지 `statusFilter`('all'|'open'|'closed') 하나로 두고, 데스크톱 `모집중만` pill은 그중 2지(open/all)만 노출, 모바일은 3지 드롭다운 전부. 표시 전환은 CSS `@media 480px`, `<480→≥480` 전환 시 `closed→all` 리셋은 `matchMedia` 리스너. 보류 브랜치의 `FilterDropdown` 컴포넌트를 Home.jsx로 포팅.

**Tech Stack:** React 19, Vite. (page 컴포넌트라 단위테스트 없음 — lint+build+수동 QA)

**Spec:** `docs/superpowers/specs/2026-06-12-home-filter-responsive-design.md`
**Branch:** `feat/home-filter-responsive` (이미 생성됨)

> 모든 커밋 메시지 끝에: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
> 명령은 `web/`에서 실행. 작업 디렉터리 `c:\새 폴더`. git hygiene: 무관한 `.gitignore`는 스테이징 금지(각 태스크 `git add` 경로만). DB 변경 없음.

---

## File Structure

- Modify: `web/src/pages/Home.jsx` — `FilterDropdown` 모듈스코프 컴포넌트 추가 · `openOnly`→`statusFilter` · `모집중만` pill 로직 · `.home-filter-mobile` 렌더 · `matchMedia` 엣지 리셋
- Modify: `web/src/pages/Home.css` — `.filter-dd*`/`.home-filter-mobile` 스타일 + `@media(max-width:479.98px)` 전환

> `useState`/`useRef`/`useEffect`/`useMemo`는 Home.jsx에 이미 import됨(파일 1행). 새 import 불필요.
> 중간 커밋도 항상 동작하도록 순서 유지: 컴포넌트 추가(미사용) → 상태 전환 → 모바일 렌더+미디어쿼리.

---

## Task 1: FilterDropdown 컴포넌트 + 드롭다운 스타일 (미사용 추가)

**Files:** Modify `web/src/pages/Home.jsx`, `web/src/pages/Home.css`

- [ ] **Step 1: FilterDropdown 컴포넌트 추가** — `web/src/pages/Home.jsx`

`function CardSection(...) { ... }` 정의가 끝나는 곳 바로 다음, `function Home() {` 바로 위에 추가. (현재 `function Home()` 직전 `}` 다음 줄)

찾기:
```jsx
function Home() {
  const navigate = useNavigate()
```
바꾸기:
```jsx
// 모바일(<480px) 필터용 커스텀 드롭다운.
// 네이티브 <select>는 옵션에 색 동그라미를 못 넣어서 직접 구현.
// options: [{ value, label, dotClass? }] — dotClass 있으면 legend-dot 색 동그라미 표시.
function FilterDropdown({ label, value, onChange, options, ariaLabel }) {
  const [open, setOpen] = useState(false)
  const ref = useRef(null)
  const selected = options.find(o => o.value === value) ?? options[0]

  // 열렸을 때만 바깥 클릭 / ESC로 닫기 (리스너 콜백 안에서만 setState → set-state-in-effect 안전)
  useEffect(() => {
    if (!open) return
    function onDocClick(e) {
      if (ref.current && !ref.current.contains(e.target)) setOpen(false)
    }
    function onKey(e) {
      if (e.key === 'Escape') setOpen(false)
    }
    document.addEventListener('mousedown', onDocClick)
    document.addEventListener('keydown', onKey)
    return () => {
      document.removeEventListener('mousedown', onDocClick)
      document.removeEventListener('keydown', onKey)
    }
  }, [open])

  return (
    <div className="filter-dd" ref={ref}>
      <button
        type="button"
        className="filter-dd-btn"
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-label={ariaLabel}
        onClick={() => setOpen(o => !o)}
      >
        <span className="filter-dd-current">
          <span className="filter-dd-label">{label}</span>
          <span className="filter-dd-value">
            {selected.dotClass && <span className={`legend-dot ${selected.dotClass}`}></span>}
            {selected.label}
          </span>
        </span>
        <svg className="filter-dd-caret" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M6 9l6 6 6-6" /></svg>
      </button>
      {open && (
        <ul className="filter-dd-list" role="listbox" aria-label={ariaLabel}>
          {options.map(o => (
            <li
              key={o.value}
              role="option"
              aria-selected={o.value === value}
              className={`filter-dd-option ${o.value === value ? 'selected' : ''}`}
              onClick={() => { onChange(o.value); setOpen(false) }}
            >
              {o.dotClass && <span className={`legend-dot ${o.dotClass}`}></span>}
              {o.label}
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}

function Home() {
  const navigate = useNavigate()
```

- [ ] **Step 2: 드롭다운 스타일 추가** — `web/src/pages/Home.css`

찾기 (기존 한 줄):
```css
.legend-dot.dot-red   { background: var(--border-strong); }
```
바꾸기 (그 줄 + 아래 블록):
```css
.legend-dot.dot-red   { background: var(--border-strong); }

/* ── 모바일(<480px) 필터 드롭다운 (FilterDropdown) ── 데스크톱은 기존 pill 유지.
   기본 숨김; 480px 미디어쿼리에서 표시(Task 3). */
.home-filter-mobile { display: none; gap: 8px; width: 100%; }
.filter-dd { position: relative; flex: 1 1 0; min-width: 0; }
/* .home-wrap button 전역 규칙(0,1,1)을 이기려고 선택자 특이도 ↑ */
.home-filter-mobile .filter-dd-btn {
  width: 100%; display: flex; align-items: center; justify-content: space-between; gap: 6px;
  padding: 8px 10px 8px 12px; border-radius: 8px; border: 1.5px solid var(--border);
  background: white; color: var(--text-sub); font-size: 13px; font-weight: 600; font-family: inherit; cursor: pointer;
}
.filter-dd-current { display: inline-flex; align-items: center; gap: 6px; min-width: 0; overflow: hidden; }
.filter-dd-label { flex-shrink: 0; color: var(--text-muted); }
.filter-dd-label::after { content: ':'; }
.filter-dd-value { display: inline-flex; align-items: center; gap: 6px; min-width: 0; overflow: hidden; white-space: nowrap; text-overflow: ellipsis; }
.filter-dd .legend-dot { flex-shrink: 0; }
.filter-dd-caret { width: 14px; height: 14px; flex-shrink: 0; color: var(--text-muted); }
.filter-dd-list {
  position: absolute; top: calc(100% + 4px); left: 0; right: 0; z-index: 5;
  margin: 0; padding: 4px; list-style: none; background: white;
  border: 1px solid var(--border); border-radius: 8px; box-shadow: 0 6px 20px rgba(0, 0, 0, 0.12);
}
.filter-dd-option { display: flex; align-items: center; gap: 8px; padding: 8px 10px; border-radius: 6px; font-size: 13px; font-weight: 600; color: var(--text-sub); cursor: pointer; }
.filter-dd-option:hover { background: var(--surface); }
.filter-dd-option.selected { background: var(--primary-light); color: var(--primary-dark); }
```

- [ ] **Step 3: lint + build**

Run: `cd web && npm run lint && npm run build`
Expected: 빌드 성공. 기존 2개 경고(Home.jsx useMemo·WorksiteDetail.jsx) 외 새 에러 없음. `FilterDropdown`이 "정의됐지만 미사용"이어도 eslint는 컴포넌트 함수엔 no-unused 에러를 내지 않음(곧 Task 3에서 사용). 새 에러가 나오면 STOP 후 보고.

- [ ] **Step 4: 커밋**

```bash
git add web/src/pages/Home.jsx web/src/pages/Home.css
git commit -m "feat(home-filter): FilterDropdown 컴포넌트 + 드롭다운 스타일 추가(미사용)"
```

---

## Task 2: 모집상태 상태값 3지화 (openOnly → statusFilter)

**Files:** Modify `web/src/pages/Home.jsx`

> 이 태스크는 상태·필터·데스크톱 pill을 한 번에 바꿔 *항상 동작하는* 상태를 유지한다. (데스크톱 동작·외형은 동일)

- [ ] **Step 1: 상태 선언 교체** — `web/src/pages/Home.jsx`

찾기:
```jsx
  const [openOnly, setOpenOnly] = useState(false)
```
바꾸기:
```jsx
  const [statusFilter, setStatusFilter] = useState('all') // all | open | closed
```

- [ ] **Step 2: baseFiltered 필터 로직** — 같은 파일

찾기:
```jsx
  // 공통 필터: type + openOnly
  const baseFiltered = useMemo(() => {
    return postings.filter(p => {
      if (typeFilter !== 'all' && p.worksite?.type !== typeFilter) return false
      if (openOnly && !p.is_active) return false
      return true
    })
  }, [postings, typeFilter, openOnly])
```
바꾸기:
```jsx
  // 공통 필터: type + status(전체/모집중/모집완료)
  const baseFiltered = useMemo(() => {
    return postings.filter(p => {
      if (typeFilter !== 'all' && p.worksite?.type !== typeFilter) return false
      if (statusFilter === 'open' && !p.is_active) return false
      if (statusFilter === 'closed' && p.is_active) return false
      return true
    })
  }, [postings, typeFilter, statusFilter])
```

- [ ] **Step 3: 데스크톱 '모집중만' pill 로직** — 같은 파일

찾기:
```jsx
                <button className={`home-filter-pill ${openOnly ? 'active' : ''}`} onClick={() => setOpenOnly(o => !o)}>모집중만</button>
```
바꾸기:
```jsx
                <button className={`home-filter-pill ${statusFilter === 'open' ? 'active' : ''}`} onClick={() => setStatusFilter(s => (s === 'open' ? 'all' : 'open'))}>모집중만</button>
```

> `setOpenOnly`/`openOnly` 잔재가 더 없는지 확인: `grep -n "openOnly" web/src/pages/Home.jsx` → 0건이어야 함.

- [ ] **Step 4: lint + build + 수동 확인**

Run: `cd web && npm run lint && npm run build`
Expected: 빌드 성공, 새 에러 없음.
수동: `npm run dev` → 데스크톱 폭에서 `모집중만` pill 토글이 예전과 동일하게 동작(켜면 모집중만, 끄면 전체).

- [ ] **Step 5: 커밋**

```bash
git add web/src/pages/Home.jsx
git commit -m "feat(home-filter): 모집상태 openOnly → statusFilter(3지) 전환 (데스크톱 동작 동일)"
```

---

## Task 3: 모바일 드롭다운 렌더 + 480px 전환 + 엣지 리셋

**Files:** Modify `web/src/pages/Home.jsx`, `web/src/pages/Home.css`

- [ ] **Step 1: 모바일 드롭다운 렌더** — `web/src/pages/Home.jsx`

찾기 (필터바의 status-legend 닫힘 ~ filter-bar-wrap 닫힘):
```jsx
              <div className="status-legend">
                <span className="legend-item"><span className="legend-dot dot-green"></span>모집중</span>
                <span className="legend-item"><span className="legend-dot dot-red"></span>모집완료</span>
              </div>
            </div>
```
바꾸기 (status-legend 뒤에 `.home-filter-mobile` 추가):
```jsx
              <div className="status-legend">
                <span className="legend-item"><span className="legend-dot dot-green"></span>모집중</span>
                <span className="legend-item"><span className="legend-dot dot-red"></span>모집완료</span>
              </div>
              <div className="home-filter-mobile">
                <FilterDropdown
                  label="유형"
                  value={typeFilter}
                  onChange={setTypeFilter}
                  ariaLabel="근장 종류 필터"
                  options={[
                    { value: 'all', label: '전체' },
                    { value: 'national', label: '국가근장' },
                    { value: 'school', label: '학교근장' },
                  ]}
                />
                <FilterDropdown
                  label="모집상태"
                  value={statusFilter}
                  onChange={setStatusFilter}
                  ariaLabel="모집 상태 필터"
                  options={[
                    { value: 'all', label: '전체' },
                    { value: 'open', label: '모집중', dotClass: 'dot-green' },
                    { value: 'closed', label: '모집완료', dotClass: 'dot-red' },
                  ]}
                />
              </div>
            </div>
```

- [ ] **Step 2: 엣지 리셋 useEffect** — 같은 파일, `fetchData` 효과 바로 다음에 추가

찾기:
```jsx
    fetchData()
  }, [authUser])
```
바꾸기:
```jsx
    fetchData()
  }, [authUser])

  // 480px 이상으로 넘어가면(데스크톱 전환) 데스크톱이 표현 못 하는 'closed'를 'all'로 리셋.
  // 리스너 콜백 안에서만 setState → set-state-in-effect 안전.
  useEffect(() => {
    const mq = window.matchMedia('(min-width: 480px)')
    const onChange = (e) => { if (e.matches) setStatusFilter(s => (s === 'closed' ? 'all' : s)) }
    mq.addEventListener('change', onChange)
    return () => mq.removeEventListener('change', onChange)
  }, [])
```

- [ ] **Step 3: 480px 전환 미디어쿼리** — `web/src/pages/Home.css`

찾기 (Task 1에서 추가한 마지막 드롭다운 규칙):
```css
.filter-dd-option.selected { background: var(--primary-light); color: var(--primary-dark); }
```
바꾸기 (그 줄 + 미디어쿼리):
```css
.filter-dd-option.selected { background: var(--primary-light); color: var(--primary-dark); }

/* <480px: 데스크톱 pill·범례 숨기고 모바일 드롭다운 표시.
   (.status-legend는 .filter-bar-wrap 안의 것만 — CardSection의 범례는 유지) */
@media (max-width: 479.98px) {
  .home-filter-bar,
  .filter-bar-wrap .status-legend { display: none; }
  .home-filter-mobile { display: flex; }
}
```

- [ ] **Step 4: lint + build**

Run: `cd web && npm run lint && npm run build`
Expected: 빌드 성공. 기존 2개 경고 외 새 에러/경고 없음(특히 `react-hooks/set-state-in-effect` 미발생 — matchMedia·드롭다운 효과 모두 리스너 콜백에서만 setState). 새 에러면 STOP 후 보고(eslint-disable 금지).

- [ ] **Step 5: 수동 QA** — `cd web && npm run dev`, 로그인 상태로 `/home`:
  - **≥480px**: pill 4개 + 우측 범례 그대로. `모집중만` 토글 동작.
  - **<480px**(개발자도구 반응형 또는 창 줄이기): pill·범례 사라지고 **드롭다운 2개**(유형·모집상태) 표시, 좌우 반반. 유형 선택 → 목록 필터, 모집상태 3지(전체/모집중/모집완료) 선택 → 목록 필터. 옵션 색 동그라미 표시. 바깥클릭/ESC로 닫힘.
  - **엣지**: <480에서 `모집완료` 선택 → 창을 480 넘게 늘림 → 데스크톱 pill `모집중만` 꺼짐 + 목록 전체로 리셋(closed→all) 확인.
  - **게스트(비로그인) 모바일**: 필터바 자체가 안 뜨고(로그인 전용), CardSection 범례는 그대로 보이는지(필터바 범례만 숨겼으므로) 확인.

- [ ] **Step 6: 커밋**

```bash
git add web/src/pages/Home.jsx web/src/pages/Home.css
git commit -m "feat(home-filter): <480px 모바일 드롭다운 2개 + 480px 전환 + closed→all 엣지 리셋"
```

---

## Task 4: 전체 검증

**Files:** 없음(검증만)

- [ ] **Step 1: 테스트·lint·빌드** — Run: `cd web && npm run test && npm run lint && npm run build`
Expected: 테스트 26 그린(변동 없음), lint 0 errors(기존 2 경고만), 빌드 성공.

- [ ] **Step 2: 수동 QA 매트릭스** — Task 3 Step 5의 ≥480 / <480 / 엣지 / 게스트 4가지 재확인.

- [ ] **Step 3: (해당 시) 마무리 커밋** — 고친 게 있으면 커밋, 없으면 생략.

---

## Self-Review (작성자 점검)

- **Spec 커버리지:** §3 상태모델→T2, §4 데스크톱 pill→T2-Step3, §5 모바일 FilterDropdown→T1+T3-Step1, §6 전환→T3-Step3 / 엣지리셋→T3-Step2, §7 CSS→T1+T3, §8 변경파일→Home.jsx/css. 누락 없음.
- **Placeholder:** 없음(전 코드 기재).
- **이름 일관성:** `statusFilter`/`setStatusFilter`(값 'all'|'open'|'closed'), `typeFilter`, `FilterDropdown`(props label/value/onChange/options/ariaLabel), CSS `.home-filter-mobile`·`.filter-dd*` — 정의(T1·T2)와 사용(T3) 일치. baseFiltered open/closed 분기 = 드롭다운 옵션 value('open'/'closed')와 일치.
- **중간 상태 안전:** T1(컴포넌트 미사용·CSS는 display:none이라 무영향) → T2(상태 전환, 데스크톱 동작 동일) → T3(렌더+미디어쿼리). 각 단계 빌드 가능.
- **lint 주의:** 두 useEffect 모두 리스너만 등록(동기 setState 없음) → set-state-in-effect 미발생.
