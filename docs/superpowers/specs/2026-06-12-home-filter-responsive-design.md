# 홈 필터 반응형 (데스크톱 pill / 모바일 드롭다운) 설계

작성일: 2026-06-12 · 담당: 배경록

## 1. 목적 / 범위

홈(`/home`) 근장 목록 필터를 **화면 너비에 따라 다르게** 보여준다.
- **≥480px (데스크톱)**: 지금 그대로 — pill 4개 + 우측 범례. *현상유지.*
- **<480px (모바일)**: 좁은 폭에서 pill+범례가 어수선해지므로 **커스텀 드롭다운 2개**로.

> 배경: 모바일 드롭다운 컴포넌트는 보류 브랜치 `feat/home-filter-mobile-select`(main −28커밋, 미푸시)에 이미 `FilterDropdown`으로 구현돼 있음. 그 브랜치는 너무 뒤처져 살리지 않고, **현재 main에서 새 브랜치**를 파서 `FilterDropdown` 컴포넌트만 포팅한다.

- ✅ 범위: `Home.jsx`/`Home.css`만. 필터 UI의 반응형 분기 + 모집상태 3지화.
- ❌ 범위 밖: 다른 페이지, 새 데이터/쿼리, 정렬·검색 기능.

## 2. 결정사항 (브레인스토밍)

- **데스크톱 2지 / 모바일 3지** — 모집상태 필터를 데스크톱은 `모집중만`(2지)로 *현상유지*, 모바일은 `전체/모집중/모집완료`(3지)로.
- **상태는 3지 `statusFilter` 하나** — 데스크톱은 그중 2지(open/all)만 노출. (상태 1개라 동기화 문제 없음)
- **엣지 리셋 포함** — `<480 → ≥480` 전환 시 `statusFilter==='closed'`면 `'all'`로 리셋(데스크톱이 closed를 표현 못 하므로).
- **전환은 CSS @media** + 엣지용 `matchMedia` 리스너(작은 JS).
- 기존 보류 브랜치는 안 살리고 컴포넌트만 포팅, 새 브랜치에서 작업.

## 3. 상태 모델 — `Home.jsx`

`openOnly`(bool)를 **`statusFilter`('all' | 'open' | 'closed')** 로 교체.

```js
const [typeFilter, setTypeFilter] = useState('all')      // 그대로
const [statusFilter, setStatusFilter] = useState('all')  // openOnly 대체
```

필터링(`baseFiltered` useMemo): `[postings, typeFilter, statusFilter]` 의존.
```js
if (typeFilter !== 'all' && p.worksite?.type !== typeFilter) return false
if (statusFilter === 'open' && !p.is_active) return false
if (statusFilter === 'closed' && p.is_active) return false
return true
```

## 4. ≥480px (데스크톱) — *현상유지*

기존 `.filter-bar-wrap` > `.home-filter-bar`(pill 4개) + `.status-legend`(범례) **그대로**. 단 `모집중만` pill만 `statusFilter`를 2지로 다루게 바꿈(시각·동작은 동일):
```jsx
<button
  className={`home-filter-pill ${statusFilter === 'open' ? 'active' : ''}`}
  onClick={() => setStatusFilter(s => (s === 'open' ? 'all' : 'open'))}
>모집중만</button>
```
유형 pill 3개(`전체/국가근장/학교근장`)와 범례는 변경 없음.

## 5. <480px (모바일) — `FilterDropdown` 2개

보류 브랜치의 `FilterDropdown` 컴포넌트를 `Home.jsx` 모듈 스코프로 포팅(접근성·바깥클릭·ESC 닫기 포함). props: `label`, `value`, `onChange`, `options:[{value,label,dotClass?}]`, `ariaLabel`.

```jsx
<div className="home-filter-mobile">
  <FilterDropdown label="유형" value={typeFilter} onChange={setTypeFilter} ariaLabel="근장 종류 필터"
    options={[
      { value: 'all', label: '전체' },
      { value: 'national', label: '국가근장' },
      { value: 'school', label: '학교근장' },
    ]} />
  <FilterDropdown label="모집상태" value={statusFilter} onChange={setStatusFilter} ariaLabel="모집 상태 필터"
    options={[
      { value: 'all', label: '전체' },
      { value: 'open', label: '모집중', dotClass: 'dot-green' },
      { value: 'closed', label: '모집완료', dotClass: 'dot-red' },
    ]} />
</div>
```
- 유형 → `typeFilter`, 모집상태(3지) → `statusFilter` 직접 매핑.
- `dotClass`로 옵션 옆 색 동그라미(`legend-dot dot-green/dot-red`) — 범례 겸.

## 6. 전환 + 엣지 리셋

**표시 전환 (CSS @media, 480px 기준):**
- 기본: `.home-filter-mobile { display: none }` (데스크톱 기본 숨김).
- `@media (max-width: 479.98px)`: `.home-filter-bar, .status-legend { display: none }` + `.home-filter-mobile { display: flex }`.

**엣지 리셋 (JS, `Home` 컴포넌트):**
```js
useEffect(() => {
  const mq = window.matchMedia('(min-width: 480px)')
  const onChange = (e) => { if (e.matches) setStatusFilter(s => (s === 'closed' ? 'all' : s)) }
  mq.addEventListener('change', onChange)
  return () => mq.removeEventListener('change', onChange)
}, [])
```
- `≥480`로 전환되는 순간 `closed`였으면 `all`로. (set 함수형 업데이트라 effect 의존성 불필요 → lint 안전, `setStatusFilter`만 사용)

## 7. CSS — `Home.css`

- `FilterDropdown` 스타일 포팅: `.home-filter-mobile`(flex, gap 8px), `.filter-dd`, `.filter-dd-btn`, `.filter-dd-current/-label(::after ':')/-value/-caret`, `.filter-dd-list`, `.filter-dd-option(.selected/:hover)`. **단 `.filter-dd`는 모바일 전용이라 `flex: 1 1 0; min-width: 0`**(브랜치의 고정 190px 대신 — 좌우 반반, 좁은 폰 대응).
- 미디어쿼리(§6) 추가. `.legend-dot.dot-green/.dot-red`는 기존 정의 재사용.
- `var(--…)` 토큰만, `:root` 재정의 금지.

## 8. 변경 파일

- **수정**: `web/src/pages/Home.jsx` (`FilterDropdown` 컴포넌트 추가 · `openOnly`→`statusFilter` · `모집중만` pill 로직 · `.home-filter-mobile` 렌더 · `matchMedia` 엣지 리셋), `web/src/pages/Home.css` (`.filter-dd*` + 미디어쿼리)
- **신규/README**: 없음(`FilterDropdown`은 Home.jsx 모듈 스코프 헬퍼라 컴포넌트 README 항목 불필요)
- **DB 변경 없음.**

## 9. 범위 밖 (YAGNI)

`FilterDropdown`을 `components/`로 분리(지금은 홈 전용이라 Home.jsx에 둠), 데스크톱도 드롭다운화, 정렬/검색, 모바일에서 유형도 3지 외 추가 옵션, 480px 외 추가 브레이크포인트.
