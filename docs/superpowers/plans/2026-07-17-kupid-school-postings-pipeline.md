# 교내근로(KUPID) 공고 적재 파이프라인 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** KUPID 크롤 공고를 `recruit_until`(날짜 기반 모집 판정)과 함께 카탈로그에 적재하는 파이프라인(파싱 보강 → Excel 검수 → SQL 생성 → 마이그레이션)과, 프론트의 날짜 기반 "모집중" 판정을 구현한다.

**Architecture:** 파이프라인은 `crawling_scripts/`의 순수 함수 모듈(캐스케이드·SQL 생성)로 나눠 pytest로 검증하고, DB는 `web/supabase/migrations/` 단일 경로로만 변경한다. 프론트는 `lib/recruit.js`의 순수 함수 `effectiveActive`가 `recruit_until`(NULL이면 `is_active` 폴백)로 판정하고, 검색 RPC는 `recruit_until`을 반환 컬럼에 추가한다(롤업·필터는 여전히 `is_active` — 스펙 스코프 밖).

**Tech Stack:** Python 3(openpyxl·pytest·anthropic), React+Vite(vitest), Supabase CLI 마이그레이션.

**Spec:** `docs/superpowers/specs/2026-07-17-kupid-school-postings-design.md`

## Global Constraints

- DB 변경은 **`web/supabase/migrations/`로만**. 파일 맨 위 헤더 2줄 필수: `-- 목적:` / `-- 날짜: YYYY-MM-DD · 담당: 배경록`. SQL 에디터 수동 편집 금지. (CLAUDE.md §3)
- 함수 **시그니처(인자·리턴 타입) 변경 시 `DROP FUNCTION IF EXISTS` 먼저**, DROP 후 grant 재부여(authenticated·anon).
- `search_worksite_cards` 본문을 고칠 땐 **최신본(`20260716180000_oncampus_national_seed.sql`)에서 복사** — 옛 파일에서 뜨면 limit/offset 상한·지역 조건이 롤백된다.
- **prod 반영 순서: DB(`db push`) 먼저 → 프론트 prod 배포.** 프론트가 `recruit_until` 컬럼을 select하므로 컬럼 없는 prod에 프론트가 먼저 나가면 홈/상세가 깨진다. push 전 디스코드 공유 + `npx supabase migration list`로 대기분 확인.
- `web/src/lib/`는 **순수·결정적** — 현재 시각은 `now` 파라미터로 주입(기본값만 `new Date()`), 테스트 코로케이션(`*.test.js`).
- DB 통신은 `web/src/data/`에서만. 의존성 방향 `pages → components/data/lib` 유지.
- region 계약: **교내 = NULL / 교외 = REGIONS 17개 짧은 형태 필수**(DB CHECK `worksites_region_normalized`가 위반 시 push를 실패시킨다).
- worksites `organization_name = '고려대학교(본교)'`(국가근로 시드의 `'고려대학교(본교) 학부'`와 다름 — 교내근로는 대학원생 공고도 있어 '학부'를 뺀다).
- 국가근장 `recruit_until`은 **추측 금지** — 캐스케이드는 학교근장 전용. 국가근장은 기간 확정 시 일괄 UPDATE(Task 8 뼈대).
- **연락처는 DB 미적재**: `postings.contact_phone`/`contact_email`은 개인정보 최소수집으로 **drop됨**(`20260619000000`, 회의 결정 #15). 파싱된 이메일·전화번호·이메일제목형식은 Excel에만 남긴다(검수 참고용). ⚠️ 스펙 §3의 "contact_* 그대로" 매핑은 낡은 스키마 기준 — 이 계획이 정정한다.
- **postings는 컬럼 화이트리스트 GRANT**(`20260713144538`, 보안점검 H1): 새 컬럼은 grant에 추가하지 않으면 프론트 직접 select가 permission denied. `recruit_until`을 Task 1에서 grant에 추가한다. `raw_text`는 화이트리스트 밖(연락처 포함 가능) — 적재는 하되 클라이언트에 노출되지 않는 게 정상.
- 각 태스크 완료 시 커밋(푸시는 하지 않는다).
- Python 테스트 실행 위치: `cd crawling_scripts && python -m pytest <파일> -v` (기존 관례). 웹 테스트: `cd web && npx vitest run`.

---

### Task 1: `postings.recruit_until` 스키마 마이그레이션 + 문서 갱신

**Files:**
- Create: `web/supabase/migrations/<타임스탬프>_postings_recruit_until.sql` (`npx supabase migration new`가 생성)
- Modify: `docs/db-schema.md` (postings 스키마 — `is_placeholder` 항목 근처, 378행 부근)

**Interfaces:**
- Produces: `postings.recruit_until date`(NULL=판정 불가·레거시), `postings.recruit_until_estimated boolean not null default false`. Task 4의 생성 SQL과 Task 7의 RPC가 이 컬럼을 참조한다.

- [ ] **Step 1: 마이그레이션 파일 생성**

```powershell
cd web; npx supabase migration new postings_recruit_until
```

Expected: `web/supabase/migrations/<YYYYMMDDHHMMSS>_postings_recruit_until.sql` 빈 파일 생성.

- [ ] **Step 2: SQL 작성**

```sql
-- 목적: 모집 상태를 날짜로 판정하기 위한 postings.recruit_until / recruit_until_estimated 추가 (정적 is_active의 낡음 해소)
-- 날짜: 2026-07-17 · 담당: 배경록
-- 비고: spec docs/superpowers/specs/2026-07-17-kupid-school-postings-design.md §2
--       학교근장=파이프라인 캐스케이드 추정 / 국가근장=학기·방학 기간 확정 시 일괄 UPDATE(추측 금지).
--       NULL=판정 불가(레거시 포함) → 프론트 effectiveActive가 is_active로 폴백한다.

alter table postings add column if not exists recruit_until date;
alter table postings add column if not exists recruit_until_estimated boolean not null default false;

comment on column postings.recruit_until is
  '이 날짜까지 접수 가능(추정 포함). NULL=판정 불가(레거시) — 프론트는 is_active 폴백.';
comment on column postings.recruit_until_estimated is
  'true면 recruit_until이 추정값(명시 마감일 없음 — 근무시작 전날 또는 등록일+30일).';

-- ⚠️ postings는 컬럼 화이트리스트 GRANT(20260713144538, H1) — 새 컬럼은 grant에 넣어야
--    프론트 직접 조회(HOME_POSTING_COLS·fetchRepresentativePosting)가 select할 수 있다.
grant select (recruit_until, recruit_until_estimated)
  on table public.postings to anon, authenticated;
```

- [ ] **Step 3: `docs/db-schema.md` 갱신**

postings 스키마 블록(`is_placeholder` 항목이 있는 곳)에 두 컬럼을 추가:

```
  recruit_until     DATE                      -- 이 날짜까지 접수 가능(추정 포함). NULL=판정 불가(레거시) → 프론트 is_active 폴백
  recruit_until_estimated BOOLEAN NOT NULL DEFAULT FALSE  -- true면 추정값(명시 마감일 없음)
  -- 학교근장: 파이프라인 캐스케이드(명시 마감일 → 근무시작 전날 → 등록일+30일)로 채움 (crawling_scripts/recruit_until.py)
  -- 국가근장: 추측 금지 — 학기·방학 모집기간 확정 시 일괄 UPDATE (web/supabase/README.md 뼈대 참고)
```

- [ ] **Step 4: 마이그레이션이 대기 목록에 잡히는지 확인**

Run: `cd web; npx supabase migration list`
Expected: 새 파일이 Local에만 있고 Remote에 없는 상태로 표시(적용은 Task 9에서 일괄).

- [ ] **Step 5: Commit**

```powershell
git add web/supabase/migrations docs/db-schema.md
git commit -m "feat(db): postings.recruit_until/_estimated 컬럼 — 날짜 기반 모집 판정"
```

---

### Task 2: recruit_until 캐스케이드 순수 모듈 (`crawling_scripts/recruit_until.py`)

**Files:**
- Create: `crawling_scripts/recruit_until.py`
- Test: `crawling_scripts/test_recruit_until.py`

**Interfaces:**
- Produces:
  - `parse_date_like(text, base_year=None, pick='last', floor=None) -> datetime.date | None`
  - `compute_recruit_until(recruitment_end, work_start_text, registered_date) -> tuple[datetime.date | None, bool]` — `(recruit_until, estimated)`. `registered_date`는 `'YYYY-MM-DD'` 문자열.
- Consumes: 없음(표준 라이브러리만 — anthropic 등 무거운 의존 없이 pytest 가능해야 한다).

- [ ] **Step 1: 실패하는 테스트 작성** (`crawling_scripts/test_recruit_until.py`)

```python
"""recruit_until 캐스케이드 단위테스트. 실행: cd crawling_scripts && python -m pytest test_recruit_until.py -v"""
from datetime import date

from recruit_until import parse_date_like, compute_recruit_until


class TestParseDateLike:
    def test_iso(self):
        assert parse_date_like('2026-07-24') == date(2026, 7, 24)

    def test_dotted_korean_slash(self):
        assert parse_date_like('2026. 7. 24.(금) 18:00까지') == date(2026, 7, 24)
        assert parse_date_like('2026년 7월 24일') == date(2026, 7, 24)
        assert parse_date_like('2026/7/24') == date(2026, 7, 24)

    def test_md_needs_base_year(self):
        assert parse_date_like('7월 24일') is None
        assert parse_date_like('7월 24일', base_year=2026) == date(2026, 7, 24)
        assert parse_date_like('7. 24 (금)', base_year=2026) == date(2026, 7, 24)

    def test_range_pick_last_vs_first(self):
        s = '2026. 7. 15 (수) ~ 7. 24 (금)'
        assert parse_date_like(s, base_year=2026, pick='last') == date(2026, 7, 24)
        assert parse_date_like(s, base_year=2026, pick='first') == date(2026, 7, 15)

    def test_md_year_rollover_with_floor(self):
        # 12월 등록 공고의 "1월 5일" 마감 → 이듬해로 보정
        assert parse_date_like('1월 5일', base_year=2026, floor=date(2026, 12, 20)) == date(2027, 1, 5)
        # floor보다 뒤면 그대로
        assert parse_date_like('7월 24일', base_year=2026, floor=date(2026, 7, 1)) == date(2026, 7, 24)

    def test_invalid_and_noise(self):
        assert parse_date_like(None) is None
        assert parse_date_like('') is None
        assert parse_date_like('선발 시까지') is None
        assert parse_date_like('2026-13-45') is None          # 불가능한 날짜
        assert parse_date_like('18:00', base_year=2026) is None  # 시각은 날짜 아님


class TestComputeRecruitUntil:
    def test_1_explicit_deadline(self):
        d, est = compute_recruit_until('2026-07-24', '2026-08-03', '2026-07-14')
        assert (d, est) == (date(2026, 7, 24), False)

    def test_2_work_start_minus_1(self):
        d, est = compute_recruit_until(None, '2026. 8. 3.(월)부터', '2026-07-14')
        assert (d, est) == (date(2026, 8, 2), True)

    def test_2_ignores_unparseable_start(self):
        # "8월 중"처럼 일(day)이 없으면 3단계로 폴백
        d, est = compute_recruit_until('선발 시까지', '8월 중', '2026-07-14')
        assert (d, est) == (date(2026, 8, 13), True)

    def test_3_registered_plus_30(self):
        d, est = compute_recruit_until(None, None, '2026-07-14')
        assert (d, est) == (date(2026, 8, 13), True)

    def test_no_inputs(self):
        assert compute_recruit_until(None, None, None) == (None, False)

    def test_deadline_range_picks_end(self):
        d, est = compute_recruit_until('2026. 7. 15 ~ 7. 24', None, '2026-07-14')
        assert (d, est) == (date(2026, 7, 24), False)
```

- [ ] **Step 2: 실패 확인**

Run: `cd crawling_scripts; python -m pytest test_recruit_until.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'recruit_until'`

- [ ] **Step 3: 구현** (`crawling_scripts/recruit_until.py`)

```python
"""recruit_until 캐스케이드 — 순수 함수(표준 라이브러리만). parse_kupid.py·테스트가 사용.

정책(spec §2, 학교근장 전용 — 국가근장은 추측 금지):
  1. 명시 마감일(recruitment_end) → (그 날짜, estimated=False)
  2. 근무시작일(work_start_text) 전날 → (전날, estimated=True)
     ("선발 시까지"여도 근무 시작 후엔 모집 종료가 확실하다)
  3. 등록일 + 30일 → (그 날짜, estimated=True)

⚠️ 짧은 필드 값(지원마감일·근무시작일 원문)에만 쓸 것 — 공고 본문 전체에 돌리면
   "1. 2026년…" 같은 목차 번호가 M.D 패턴에 오탐된다.
"""

import re
from datetime import date, timedelta

# 연도 포함: 2026-07-24 / 2026.7.24 / 2026. 7. 24. / 2026년 7월 24일 / 2026/7/24
_FULL = re.compile(r'(20\d{2})\s*[.\-년/]\s*(\d{1,2})\s*[.\-월/]\s*(\d{1,2})')
# 월일만: 7월 24일 / 7. 24 / 7/24  (전후에 숫자·점이 붙어 있으면 제외 — 소수·전화번호 방지)
_MD = re.compile(r'(?<![\d.])(\d{1,2})\s*(?:월\s*(\d{1,2})\s*일|[./]\s*(\d{1,2}))(?![\d.])')


def parse_date_like(text, base_year=None, pick='last', floor=None):
    """문자열에서 날짜 추출. 연도 없는 월일은 base_year로 보정하고, floor(등록일)보다
    앞이면 이듬해로 넘긴다(12월 등록 → 1월 마감). pick='last'(마감) / 'first'(근무시작).
    날짜를 못 찾으면 None."""
    if not text:
        return None
    s = str(text)
    found = []   # (위치, date)
    spans = []   # 연도 포함 매치 범위 — 월일 패턴과의 중복 방지
    for m in _FULL.finditer(s):
        try:
            found.append((m.start(), date(int(m[1]), int(m[2]), int(m[3]))))
            spans.append((m.start(), m.end()))
        except ValueError:
            pass
    if base_year is not None:
        for m in _MD.finditer(s):
            if any(a <= m.start() < b for a, b in spans):
                continue
            day = m[2] or m[3]
            try:
                d = date(base_year, int(m[1]), int(day))
            except ValueError:
                continue
            if floor is not None and d < floor:
                try:
                    d = d.replace(year=d.year + 1)
                except ValueError:   # 2/29
                    continue
            found.append((m.start(), d))
    if not found:
        return None
    found.sort(key=lambda t: t[0])
    return found[-1][1] if pick == 'last' else found[0][1]


def compute_recruit_until(recruitment_end, work_start_text, registered_date):
    """(recruit_until, estimated) 반환. 셋 다 실패하면 (None, False)."""
    reg = None
    if registered_date:
        try:
            reg = date.fromisoformat(str(registered_date)[:10])
        except ValueError:
            pass
    base_year = reg.year if reg else None

    d = parse_date_like(recruitment_end, base_year, pick='last', floor=reg)
    if d:
        return d, False
    d = parse_date_like(work_start_text, base_year, pick='first', floor=reg)
    if d:
        return d - timedelta(days=1), True
    if reg:
        return reg + timedelta(days=30), True
    return None, False
```

- [ ] **Step 4: 통과 확인**

Run: `cd crawling_scripts; python -m pytest test_recruit_until.py -v`
Expected: 전부 PASS. 기존 테스트 회귀도 확인: `python -m pytest test_kupid_portal_crawler.py -v` → PASS.

- [ ] **Step 5: Commit**

```powershell
git add crawling_scripts/recruit_until.py crawling_scripts/test_recruit_until.py
git commit -m "feat(crawl): recruit_until 캐스케이드 순수 모듈 + pytest"
```

---

### Task 3: `parse_kupid.py`에 캐스케이드·검수 컬럼 통합

**Files:**
- Modify: `crawling_scripts/parse_kupid.py` (HEADERS 227-237행, values 270-298행, col_widths 306-311행, main 루프 344-368행, import 11-18행)

**Interfaces:**
- Consumes: Task 2의 `compute_recruit_until`.
- Produces: Excel `data/kupid_parsed_result.xlsx`에 새 컬럼 4개 — `지역(교외만)`(검수자 수기), `모집마감일(계산)`(ISO 문자열), `마감추정`(O/X), `출처URL`. Task 4의 생성기가 **헤더 이름으로** 읽는다.

- [ ] **Step 1: import 추가**

`import openpyxl` 아래에:

```python
from recruit_until import compute_recruit_until
```

- [ ] **Step 2: HEADERS 교체** (227-237행)

```python
HEADERS = [
    # 자동 채움 (파란색)
    "출처", "마감여부", "제목", "부서명", "등록일", "게시기한", "시급",
    # AI 파싱 (초록색) — "지역(교외만)"·"모집마감일(계산)"·"마감추정"은 자동 계산+검수(노란색)
    "모집인원", "학부생가능", "대학원생가능", "재학생가능", "휴학생가능",
    "직무내용", "근무장소", "교외여부", "지역(교외만)", "근무시작일", "근무기간", "근무시간",
    "지원마감일", "모집마감일(계산)", "마감추정", "이메일", "전화번호", "이메일제목형식",
    "우대조건", "단기여부", "기타특이사항",
    # 원본
    "출처URL", "본문(원본)",
]

# 검수자 확인이 특히 필요한 컬럼(노란색): 교외면 지역 필수(REGIONS 17개 짧은 형태 — 예: '서울'),
# 모집마감일(계산)은 캐스케이드 추정이라 오독 가능.
REVIEW_HEADERS = {"지역(교외만)", "모집마감일(계산)", "마감추정"}
```

- [ ] **Step 3: 헤더 채색에 노란색 추가** (BLUE_FILL 정의부 근처와 write_excel 헤더 루프)

```python
YELLOW_FILL = PatternFill("solid", fgColor="FFF2CC")
```

write_excel 헤더 루프의 fill 결정을:

```python
        fill = BLUE_FILL if col <= 7 else GREEN_FILL
        if h in REVIEW_HEADERS:
            fill = YELLOW_FILL
        if h in ("본문(원본)", "출처URL"):
            fill = PatternFill("solid", fgColor="F2F2F2")
```

- [ ] **Step 4: main 루프에서 캐스케이드 계산** (354행 `post_process` 호출 뒤, `notice["_body"] = body` 앞)

```python
        ru, ru_est = compute_recruit_until(
            ai_result.get("recruitment_end"),
            ai_result.get("work_start_text"),
            notice.get("registered_date"),
        )
        notice["_recruit_until"] = ru.isoformat() if ru else ""
        notice["_recruit_until_estimated"] = ru_est
```

파싱 실패(`ai_result = {}`) 경로에서도 위 코드는 그대로 동작한다(3단계 등록일+30일로 폴백) — 실패 분기 밖(공통 경로)에 둔다.

- [ ] **Step 5: values 리스트를 새 HEADERS 순서에 맞게 교체** (270-298행)

```python
        values = [
            row["_source"],
            "마감" if closed else "모집중",
            row.get("title", ""),
            row.get("department", ""),
            row.get("registered_date", ""),
            row.get("due_date", ""),
            row["_wage"] if row["_wage"] else "",
            # AI
            ai.get("recruit_count", ""),
            bool_to_str(ai.get("undergrad_ok")),
            bool_to_str(ai.get("grad_ok")),
            bool_to_str(ai.get("enrolled_ok")),
            bool_to_str(ai.get("leave_ok")),
            ai.get("job_description", ""),
            ai.get("work_location", ""),
            bool_to_str(ai.get("is_offcampus")),
            "",                                   # 지역(교외만) — 검수자 수기
            ai.get("work_start_text", ""),
            ai.get("work_period_text", ""),
            ai.get("work_time_text", ""),
            ai.get("recruitment_end", ""),
            row.get("_recruit_until", ""),
            "O" if row.get("_recruit_until_estimated") else "X",
            ai.get("contact_email", ""),
            ai.get("contact_phone", ""),
            ai.get("email_subject_format", ""),
            ai.get("preference_notes", ""),
            bool_to_str(ai.get("is_short_term")),
            ai.get("extra_notes", ""),
            row.get("detail_url", ""),
            row["_body"],
        ]
```

- [ ] **Step 6: col_widths를 새 컬럼 수(30개)에 맞게 교체** (306-311행)

```python
    col_widths = [15, 8, 40, 20, 12, 12, 8,
                  8, 8, 8, 8, 8,
                  40, 30, 8, 10, 20, 20, 30,
                  14, 12, 8, 30, 15, 35,
                  30, 8, 50,
                  40, 60]
```

`assert len(col_widths) == len(HEADERS)`를 write_excel 서두에 추가(개수 어긋남을 즉시 잡는다).

- [ ] **Step 7: 검증 — 문법·테스트·(가능하면) 스모크**

Run: `cd crawling_scripts; python -m py_compile parse_kupid.py; python -m pytest -v`
Expected: 컴파일 에러 없음, 테스트 전부 PASS.
`ANTHROPIC_API_KEY`가 설정돼 있으면 스모크(기존 3건 JSON): `parse_kupid.py`의 `TEST_MODE = True`로 잠깐 바꿔 `python parse_kupid.py` 실행 → Excel에 새 컬럼 4개·모집마감일 값 확인 → `TEST_MODE = False` 원복. 키가 없으면 이 스모크는 Task 9(실데이터)에서 수행.

- [ ] **Step 8: Commit**

```powershell
git add crawling_scripts/parse_kupid.py
git commit -m "feat(crawl): parse_kupid에 recruit_until 캐스케이드 + 검수 컬럼(지역·마감계산·출처URL)"
```

---

### Task 4: Excel → 마이그레이션 SQL 생성기 (`generate_school_migration.py`)

**Files:**
- Create: `crawling_scripts/generate_school_migration.py`
- Test: `crawling_scripts/test_generate_school_migration.py`
- Modify: `crawling_scripts/README.md` (스크립트 목록에 한 줄 추가)

**Interfaces:**
- Consumes: Task 3의 Excel 헤더 이름(문자열 키 dict로 로드).
- Produces:
  - `build_migration_sql(rows: list[dict], today: datetime.date) -> str` — 완성된 마이그레이션 SQL(검증 실패 시 `ValueError`에 행 번호 목록).
  - CLI 실행 시 `web/supabase/migrations/<YYYYMMDDHHMMSS>_school_postings_reload.sql` 생성.

- [ ] **Step 1: 실패하는 테스트 작성** (`crawling_scripts/test_generate_school_migration.py`)

```python
"""SQL 생성기 단위테스트. 실행: cd crawling_scripts && python -m pytest test_generate_school_migration.py -v"""
from datetime import date

import pytest

from generate_school_migration import build_migration_sql, eligible_pair, q

TODAY = date(2026, 7, 20)


def row(**over):
    """검수 완료 Excel 한 행(헤더 이름 키). over로 덮어쓴다."""
    base = {
        "출처": "kupid-current", "마감여부": "모집중", "제목": "[공지] 근로장학생 모집",
        "부서명": "도서관 학술정보서비스팀", "등록일": "2026-07-14", "게시기한": "", "시급": 10400,
        "모집인원": "1명", "학부생가능": "O", "대학원생가능": "X", "재학생가능": "O", "휴학생가능": "O",
        "직무내용": "자료 정리", "근무장소": "중앙도서관", "교외여부": "X", "지역(교외만)": "",
        "근무시작일": "2026-08-03", "근무기간": "2026-08-03 ~ 2027-01-31", "근무시간": "주중 9-17시",
        "지원마감일": "2026-07-24", "모집마감일(계산)": "2026-07-24", "마감추정": "X",
        "이메일": "lib@korea.ac.kr", "전화번호": "02-1234-5678", "이메일제목형식": "[근로] 학번_이름",
        "우대조건": "", "단기여부": "X", "기타특이사항": "성실한 분",
        "출처URL": "https://portal.korea.ac.kr/p/BO06?encQS=abc",
        "본문(원본)": "본문 'ㅇ'표시 포함",
    }
    base.update(over)
    return base


class TestHelpers:
    def test_q_escapes_quotes(self):
        assert q("d'or") == "'d''or'"
        assert q(None) == "null"
        assert q("") == "null"

    def test_eligible_pair(self):
        assert eligible_pair("O", "O") == 2   # 둘 다
        assert eligible_pair("O", "X") == 0   # 앞쪽만
        assert eligible_pair("X", "O") == 1   # 뒤쪽만
        assert eligible_pair("", "") == 3     # 미정
        assert eligible_pair("O", "") == 3    # 한쪽 미상 → 미정(필터에서 배제하지 않음)


class TestBuildSql:
    def test_wipe_then_insert(self):
        sql = build_migration_sql([row()], TODAY)
        assert "-- 목적:" in sql and "-- 날짜: 2026-07-20 · 담당:" in sql
        assert "delete from worksites where type = 'school';" in sql
        assert "'고려대학교(본교)'" in sql
        assert "'도서관 학술정보서비스팀'" in sql
        assert sql.index("delete from worksites") < sql.index("insert into worksites")
        assert sql.index("insert into worksites") < sql.index("insert into postings")

    def test_posting_values(self):
        sql = build_migration_sql([row()], TODAY)
        assert "'2026-07-24', false, true" in sql       # recruit_until, estimated, is_active(미래=true)
        assert "'성실한 분'" in sql                       # extra_notes 그대로
        assert "본문 ''ㅇ''표시 포함" in sql               # raw_text 이스케이프

    def test_contact_info_not_loaded(self):
        # 개인정보 최소수집(20260619 drop, 회의 #15) — 이메일·전화·제목형식은 Excel에만
        sql = build_migration_sql([row()], TODAY)
        assert "lib@korea.ac.kr" not in sql
        assert "02-1234-5678" not in sql
        assert "[근로] 학번_이름" not in sql

    def test_is_active_snapshot_false_when_past(self):
        sql = build_migration_sql([row(**{"모집마감일(계산)": "2026-07-01", "마감추정": "O"})], TODAY)
        assert "'2026-07-01', true, false" in sql

    def test_worksite_dedup_two_postings(self):
        rows = [row(), row(**{"제목": "두 번째 공고", "등록일": "2026-06-01"})]
        sql = build_migration_sql(rows, TODAY)
        assert sql.count("insert into worksites") == 1
        assert sql.count("insert into postings") == 2

    def test_offcampus_requires_region(self):
        with pytest.raises(ValueError, match="지역"):
            build_migration_sql([row(**{"교외여부": "O", "지역(교외만)": ""})], TODAY)
        with pytest.raises(ValueError, match="지역"):  # 긴 행정구역명도 거부(REGIONS 밖)
            build_migration_sql([row(**{"교외여부": "O", "지역(교외만)": "서울특별시"})], TODAY)
        sql = build_migration_sql([row(**{"교외여부": "O", "지역(교외만)": "서울"})], TODAY)
        assert "'off_campus'" in sql and "'서울'" in sql

    def test_missing_department_fails(self):
        with pytest.raises(ValueError, match="부서명"):
            build_migration_sql([row(**{"부서명": ""})], TODAY)

    def test_conflicting_offcampus_fails(self):
        rows = [row(), row(**{"교외여부": "O", "지역(교외만)": "서울"})]
        with pytest.raises(ValueError, match="교외여부"):
            build_migration_sql(rows, TODAY)

    def test_recruit_count_truncated_to_20(self):
        # varchar(20) 안전 — 21자 입력이 20자로 잘린다
        sql = build_migration_sql([row(**{"모집인원": "가나다라마바사아자차카타파하가나다라마바사"})], TODAY)
        assert "'가나다라마바사아자차카타파하가나다라마바'" in sql
        assert "가나다라마바사아자차카타파하가나다라마바사" not in sql
```

- [ ] **Step 2: 실패 확인**

Run: `cd crawling_scripts; python -m pytest test_generate_school_migration.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'generate_school_migration'`

- [ ] **Step 3: 구현** (`crawling_scripts/generate_school_migration.py`)

```python
"""검수 완료 Excel(kupid_parsed_result.xlsx) → school 재적재 마이그레이션 SQL 생성 (spec §1·§3·§4).

사용법(저장소 루트에서):
  python crawling_scripts/generate_school_migration.py
  python crawling_scripts/generate_school_migration.py --excel data/kupid_parsed_result.xlsx

Excel이 정본 — 생성된 SQL을 손으로 고치지 말고 Excel을 고쳐 재생성한다.
출력: web/supabase/migrations/<YYYYMMDDHHMMSS>_school_postings_reload.sql
"""

import argparse
from datetime import date, datetime
from pathlib import Path

import openpyxl

ROOT_DIR = Path(__file__).resolve().parent.parent
DEFAULT_EXCEL = ROOT_DIR / "data" / "kupid_parsed_result.xlsx"
MIGRATIONS_DIR = ROOT_DIR / "web" / "supabase" / "migrations"

# DB CHECK(worksites_region_normalized, 20260716190000)·web/src/lib/profileOptions.js REGIONS와
# 일치해야 한다 — 셋 중 하나를 바꾸면 셋 다 같이 바꿀 것.
REGIONS = ['서울', '경기', '부산', '경남', '인천', '경북', '대구', '충남', '전남',
           '전북', '충북', '강원', '대전', '광주', '울산', '제주', '세종']

HEADER = """-- 목적: 교내근로(KUPID) 공고 재적재 — school 근무지 wipe 후 검수 완료 Excel 적재
-- 날짜: {today} · 담당: 배경록
-- 생성: crawling_scripts/generate_school_migration.py — SQL 수동 편집 금지, Excel 수정 후 재생성.
-- 비고: spec docs/superpowers/specs/2026-07-17-kupid-school-postings-design.md
--       리뷰가 붙은 school 근무지가 있으면 reviews.worksite_id의 on delete restrict로
--       아래 delete가 실패한다(의도된 가드) — 그때는 해당 근무지 유지로 전환 판단(spec §4)."""


def q(val):
    """SQL 문자열 리터럴(작은따옴표 이스케이프). None/공백 → null."""
    if val is None or str(val).strip() == "":
        return "null"
    return "'" + str(val).strip().replace("'", "''") + "'"


def _flag(v):
    """Excel 'O'/'X'/공백 → True/False/None."""
    s = str(v or "").strip().upper()
    return True if s == "O" else False if s == "X" else None


def eligible_pair(a_ok, b_ok):
    """스펙 §3 매핑 — 둘 다=2, 앞쪽만=0, 뒤쪽만=1, 그 외(미상 포함)=3.
    (a=학부/재학, b=대학원/휴학. 미상은 3 — 필터에서 아무도 배제하지 않는 안전값.)"""
    a, b = _flag(a_ok), _flag(b_ok)
    if a and b:
        return 2
    if a and b is False:
        return 0
    if b and a is False:
        return 1
    return 3


def _to_date(v):
    if isinstance(v, datetime):
        return v.date()
    if isinstance(v, date):
        return v
    return date.fromisoformat(str(v).strip()[:10])


def validate_rows(rows):
    errors = []
    for i, row in enumerate(rows, start=2):   # Excel 행 번호(1행=헤더)
        if not str(row.get("부서명") or "").strip():
            errors.append(f"{i}행: 부서명 없음(worksite 키)")
        if _flag(row.get("교외여부")):
            region = str(row.get("지역(교외만)") or "").strip()
            if region not in REGIONS:
                errors.append(f"{i}행: 교외인데 지역이 비었거나 REGIONS 밖: '{region}'"
                              " — DB CHECK로 push가 실패한다. 짧은 형태(예: '서울')로 기입")
        ru = row.get("모집마감일(계산)")
        if ru not in (None, ""):
            try:
                _to_date(ru)
            except ValueError:
                errors.append(f"{i}행: 모집마감일(계산) 형식 오류: {ru!r} (YYYY-MM-DD)")
    return errors


def build_migration_sql(rows, today):
    errors = validate_rows(rows)
    if errors:
        raise ValueError("검수 필요:\n" + "\n".join(errors))

    # 부서 단위 dedup — 최신 등록일 행이 worksite 대표(주소·교외 판정). 스펙 §3.
    ws_by_name = {}
    for row in rows:
        name = str(row["부서명"]).strip()
        prev = ws_by_name.get(name)
        if prev is None or str(row.get("등록일") or "") > str(prev.get("등록일") or ""):
            ws_by_name[name] = row
    for name in ws_by_name:
        offs = {bool(_flag(r.get("교외여부"))) for r in rows if str(r["부서명"]).strip() == name}
        if len(offs) > 1:
            raise ValueError(f"부서 '{name}': 행마다 교외여부가 다름 — Excel에서 통일 후 재생성")

    lines = [HEADER.format(today=today.isoformat()), "", "begin;", "",
             "delete from worksites where type = 'school';", ""]

    for name in sorted(ws_by_name):
        rep = ws_by_name[name]
        off = bool(_flag(rep.get("교외여부")))
        loc = "off_campus" if off else "on_campus"
        region = q(rep.get("지역(교외만)")) if off else "null"
        lines.append(
            "insert into worksites (university_id, type, location_type, organization_name,"
            " workplace_name, region, address)\n"
            f"values (1, 'school', '{loc}', '고려대학교(본교)', {q(name)}, {region},"
            f" {q(rep.get('근무장소'))});"
        )
    lines.append("")

    for row in rows:
        name = str(row["부서명"]).strip()
        ru = _to_date(row["모집마감일(계산)"]) if row.get("모집마감일(계산)") not in (None, "") else None
        est = bool(_flag(row.get("마감추정")))
        active = ru is not None and ru >= today   # is_active 스냅숏(스펙 §2 — 검색 RPC 롤업용)
        short = _flag(row.get("단기여부"))
        duration = "short" if short else "long" if short is False else "unknown"
        # ⚠️ 이메일·전화번호·이메일제목형식은 DB 미적재 — contact 컬럼은 개인정보 최소수집으로
        #    drop됨(20260619, 회의 #15). Excel에만 남긴다(검수 참고용).
        recruit_count = str(row.get("모집인원") or "").strip()[:20]   # varchar(20)
        wage = row.get("시급")
        wage_sql = str(int(wage)) if isinstance(wage, (int, float)) else "null"
        lines.append(f"""insert into postings (worksite_id, source_url, recruit_count, eligible_degree, eligible_status,
  job_description, preference_notes, extra_notes, hourly_wage, work_period_text, work_duration_type,
  work_time_text, recruitment_period_text, raw_text,
  recruit_until, recruit_until_estimated, is_active, is_placeholder, created_at)
select w.id, {q(row.get('출처URL'))}, {q(recruit_count)}, {eligible_pair(row.get('학부생가능'), row.get('대학원생가능'))}, {eligible_pair(row.get('재학생가능'), row.get('휴학생가능'))},
  {q(row.get('직무내용'))}, {q(row.get('우대조건'))}, {q(row.get('기타특이사항'))}, {wage_sql}, {q(row.get('근무기간'))}, '{duration}',
  {q(row.get('근무시간'))}, {q(row.get('지원마감일'))}, {q(row.get('본문(원본)'))},
  {q(ru.isoformat()) if ru else 'null'}, {'true' if est else 'false'}, {'true' if active else 'false'}, false,
  coalesce({q(str(row.get('등록일') or ''))}::timestamp, now())
from worksites w
where w.type = 'school' and w.workplace_name = {q(name)} and w.deleted_at is null;""")
        lines.append("")

    lines.append("commit;")
    return "\n".join(lines)


def load_rows(xlsx_path):
    wb = openpyxl.load_workbook(xlsx_path, data_only=True)
    ws = wb["파싱결과"]
    headers = [c.value for c in ws[1]]
    rows = []
    for r in ws.iter_rows(min_row=2, values_only=True):
        if any(v not in (None, "") for v in r):
            rows.append(dict(zip(headers, r)))
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--excel", default=str(DEFAULT_EXCEL))
    ap.add_argument("--today", default=None, help="YYYY-MM-DD (기본: 오늘) — is_active 스냅숏 기준일")
    args = ap.parse_args()

    today = date.fromisoformat(args.today) if args.today else date.today()
    rows = load_rows(args.excel)
    print(f"Excel {len(rows)}행 로드: {args.excel}")
    sql = build_migration_sql(rows, today)

    out = MIGRATIONS_DIR / f"{datetime.now():%Y%m%d%H%M%S}_school_postings_reload.sql"
    out.write_text(sql, encoding="utf-8")
    print(f"생성 완료: {out}")
    print("다음: 검증(db reset 또는 sandbox push) → 디스코드 공유 → npx supabase db push")


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: 통과 확인**

Run: `cd crawling_scripts; python -m pytest test_generate_school_migration.py -v`
Expected: 전부 PASS.

- [ ] **Step 5: `crawling_scripts/README.md` 스크립트 목록에 추가**

`parse_kupid.py` 항목 아래:

```markdown
- `generate_school_migration.py` — 검수 완료 Excel → `web/supabase/migrations/*_school_postings_reload.sql` 생성(wipe+재적재). SQL 수동 편집 금지 — Excel 고쳐서 재생성.
- `recruit_until.py` — 마감일 캐스케이드 순수 모듈(명시 마감일 → 근무시작 전날 → 등록일+30일). 학교근장 전용.
```

`import_to_supabase.py` 항목을 레거시로 표시: `(레거시) 적재는 generate_school_migration.py + db push로 대체(RLS 컷오버로 anon INSERT 불가).`

- [ ] **Step 6: Commit**

```powershell
git add crawling_scripts/generate_school_migration.py crawling_scripts/test_generate_school_migration.py crawling_scripts/README.md
git commit -m "feat(crawl): Excel→school 재적재 마이그레이션 SQL 생성기 + pytest"
```

---

### Task 5: 프론트 순수 함수 `effectiveActive` (`web/src/lib/recruit.js`)

**Files:**
- Create: `web/src/lib/recruit.js`
- Test: `web/src/lib/recruit.test.js`

**Interfaces:**
- Produces:
  - `effectiveActive(posting, now = new Date()) -> boolean` — `posting.recruit_until`('YYYY-MM-DD' 문자열|null)과 `posting.is_active`를 읽는다. flat RPC 행도 같은 키라 그대로 넘겨도 된다.
  - `kstToday(now = new Date()) -> 'YYYY-MM-DD'`
- Consumes: 없음(순수).

- [ ] **Step 1: 실패하는 테스트 작성** (`web/src/lib/recruit.test.js`)

```js
import { describe, it, expect } from 'vitest'
import { effectiveActive, kstToday } from './recruit'

const NOW = new Date('2026-07-17T03:00:00+09:00')  // KST 2026-07-17 새벽

describe('kstToday', () => {
  it('KST 달력일 YYYY-MM-DD', () => {
    expect(kstToday(NOW)).toBe('2026-07-17')
    // UTC로는 전날 18시여도 KST 기준 오늘
    expect(kstToday(new Date('2026-07-16T18:00:00Z'))).toBe('2026-07-17')
  })
})

describe('effectiveActive (recruit_until 우선, NULL이면 is_active 폴백)', () => {
  it('마감일 당일까지 모집중(경계 포함)', () => {
    expect(effectiveActive({ recruit_until: '2026-07-17', is_active: false }, NOW)).toBe(true)
  })
  it('마감일 지나면 is_active=true여도 모집완료(낡은 스냅숏 무시)', () => {
    expect(effectiveActive({ recruit_until: '2026-07-16', is_active: true }, NOW)).toBe(false)
  })
  it('recruit_until NULL이면 is_active 폴백 — 레거시 교외 6,647건이 뒤집히면 안 된다', () => {
    expect(effectiveActive({ recruit_until: null, is_active: true }, NOW)).toBe(true)
    expect(effectiveActive({ recruit_until: null, is_active: false }, NOW)).toBe(false)
    expect(effectiveActive({ is_active: true }, NOW)).toBe(true)  // 키 자체가 없어도(구 RPC 행) 폴백
  })
  it('posting이 없으면 false', () => {
    expect(effectiveActive(null, NOW)).toBe(false)
    expect(effectiveActive(undefined, NOW)).toBe(false)
  })
})
```

- [ ] **Step 2: 실패 확인**

Run: `cd web; npx vitest run src/lib/recruit.test.js`
Expected: FAIL — 모듈 없음.

- [ ] **Step 3: 구현** (`web/src/lib/recruit.js`)

```js
// 모집 상태 판정 — recruit_until('YYYY-MM-DD' date 컬럼) 우선, NULL이면 is_active 폴백.
// lib 규칙: 순수·결정적(now 주입). 날짜 비교는 KST 달력일 문자열 사전순(포맷 고정이라 안전).
const KST = 'Asia/Seoul'

// 오늘 날짜 'YYYY-MM-DD' (KST 달력일)
export function kstToday(now = new Date()) {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: KST, year: 'numeric', month: '2-digit', day: '2-digit',
  }).format(now)
}

// ⚠️ NULL 폴백 필수: 레거시(교외 6,647건 등)는 recruit_until이 NULL —
//    폴백 없으면 전부 '모집완료'로 뒤집힌다(spec §2).
export function effectiveActive(posting, now = new Date()) {
  if (!posting) return false
  if (posting.recruit_until == null) return !!posting.is_active
  return String(posting.recruit_until) >= kstToday(now)
}
```

- [ ] **Step 4: 통과 확인**

Run: `cd web; npx vitest run`
Expected: 새 테스트 포함 전부 PASS.

- [ ] **Step 5: Commit**

```powershell
git add web/src/lib/recruit.js web/src/lib/recruit.test.js
git commit -m "feat(lib): effectiveActive — recruit_until 날짜 기반 모집 판정(레거시 is_active 폴백)"
```

---

### Task 6: 프론트 적용 — 홈·상세가 `effectiveActive`를 쓰도록

**Files:**
- Modify: `web/src/data/worksiteQueries.js` (14-24행 `fetchRepresentativePosting`, 184-205행 `HOME_POSTING_COLS`)
- Modify: `web/src/pages/Home.jsx` (import부, 335-352행)
- Modify: `web/src/components/InfoCard.jsx` (1-11행)

**Interfaces:**
- Consumes: Task 5의 `effectiveActive`. Task 1의 `postings.recruit_until` 컬럼(⚠️ prod엔 Task 9의 db push 후에 존재 — 그 전까지 이 변경은 prod에 배포하지 말 것. main/preview는 무방하나 preview도 같은 DB를 보므로 push 전엔 select 에러가 난다 — 로컬 확인은 push 후로 미룬다).
- Produces: 홈 카드·상세 InfoCard의 "모집중/모집완료"가 날짜 기반으로 판정됨. `Home.jsx`의 하류(필터·정렬·렌더)는 계속 `p.is_active`를 읽지만 그 값은 이미 effective 값으로 덮어써져 있음(기존 355-358행 로직 재활용 — 하류 변경 없음).

- [ ] **Step 1: `worksiteQueries.js` 셀렉트에 `recruit_until` 추가**

`fetchRepresentativePosting`의 cols(18행)를:

```js
    recruitment_period_text, contact_name, is_active, recruit_until, created_at`
```

`HOME_POSTING_COLS`(186행 `is_active,` 아래)에 한 줄 추가:

```js
  is_active,
  recruit_until,
```

- [ ] **Step 2: `Home.jsx` — 근무지 활성 판정을 `effectiveActive`로**

import부에 추가(다른 lib import들 옆):

```js
import { effectiveActive } from '../lib/recruit'
```

335-352행의 두 곳을 교체:

```js
        // 근무지별 활성 공고 존재 여부 (한 개라도 active면 모집중) — recruit_until 우선, 레거시는 is_active
        const wsActiveMap = {}
        for (const p of allRaw) {
          const wid = p.worksite?.id
          if (!wid) continue
          wsActiveMap[wid] = wsActiveMap[wid] || effectiveActive(p)
        }

        // 근무지당 대표 공고 1개만 (활성 공고 우선)
        const byWorksite = new Map()
        for (const p of allRaw) {
          const wid = p.worksite?.id
          if (!wid) continue
          const existing = byWorksite.get(wid)
          if (!existing || (!effectiveActive(existing) && effectiveActive(p))) {
            byWorksite.set(wid, p)
          }
        }
```

(그 아래 `unique = ... is_active: wsActiveMap[p.worksite.id]` 덮어쓰기는 그대로 — 하류가 전부 이 값을 읽는다.)

- [ ] **Step 3: `InfoCard.jsx` — 상세 판정 교체**

```js
import { effectiveActive } from '../lib/recruit'
```

11행을:

```js
  const isOpen = effectiveActive(posting)
```

(비로그인 공개 RPC가 아직 `recruit_until`을 안 주는 동안은 키가 없어 `is_active` 폴백 — Task 7에서 채워진다.)

- [ ] **Step 4: 테스트·린트 확인**

Run: `cd web; npx vitest run`
Expected: 전부 PASS(이 태스크는 순수 함수 소비만 — 기존 테스트 회귀 없어야 함).

- [ ] **Step 5: Commit**

```powershell
git add web/src/data/worksiteQueries.js web/src/pages/Home.jsx web/src/components/InfoCard.jsx
git commit -m "feat(home,detail): 모집 판정을 effectiveActive(recruit_until)로 전환"
```

---

### Task 7: 검색·공개상세 RPC가 `recruit_until`을 반환 + 검색 카드 적용

**Files:**
- Create: `web/supabase/migrations/<타임스탬프>_search_cards_recruit_until.sql` (`npx supabase migration new search_cards_recruit_until`)
- Modify: `web/src/lib/searchCards.js` (14-46행 `toCard`)
- Modify: `web/src/lib/searchCards.test.js`
- Modify: `web/src/data/worksiteQueries.js` (249행 `rows.map(toCard)`)
- Modify: `docs/db-schema.md` (RPC 목록에 반환 컬럼 변경 기록)

**Interfaces:**
- Consumes: Task 1의 컬럼(마이그레이션 타임스탬프가 Task 1보다 뒤여야 함 — `migration new`가 보장), Task 5의 `effectiveActive`.
- Produces: `search_worksite_cards` 반환 테이블에 `recruit_until date` 추가(근무지별 `max(recruit_until)`), `get_worksite_public_detail`의 posting jsonb에 `recruit_until` 키 추가. `toCard(row, now?)`의 `is_active`가 effective 값이 됨.
- ⚠️ 리턴 타입 변경 = 시그니처 변경 → **`DROP FUNCTION IF EXISTS` 먼저 + grant 재부여**(authenticated·anon — anon은 비로그인 공개용, `20260716120000` 참고).
- 스코프 확인: RPC **내부의** active 롤업 필터(`p_actives`)·정렬은 여전히 `is_active`(스펙 스코프 밖 — 적재 시 is_active 스냅숏이 지탱). 여기서는 **반환 컬럼만** 추가한다.

- [ ] **Step 1: 마이그레이션 파일 생성**

```powershell
cd web; npx supabase migration new search_cards_recruit_until
```

- [ ] **Step 2: SQL 작성** — 본문은 최신본(`20260716180000`) 복사 + `recruit_until` 3곳 추가

```sql
-- 목적: 검색·공개상세 RPC가 recruit_until을 반환 — 카드/상세의 "모집중"을 날짜 기반(effectiveActive)으로 판정 가능하게
-- 날짜: 2026-07-17 · 담당: 배경록
-- 비고: 리턴 타입 변경이므로 DROP 먼저 + grant(authenticated·anon) 재부여.
--       본문은 최신본 20260716180000에서 복사(옛 파일에서 뜨면 limit/offset 상한·지역 조건 롤백 주의).
--       변경 3곳: ①returns table에 recruit_until ②ws_active CTE에 max(recruit_until) ③joined select.
--       active 롤업 필터(p_actives)·정렬은 여전히 is_active — recruit_until 기반 전환은 스코프 밖(spec).

drop function if exists search_worksite_cards(text,text,int,int,text[],text[],text[],text[],text[],int[],int[],boolean[]);

create function search_worksite_cards(
  p_query  text default null,
  p_sort   text default 'recommend',
  p_limit  int  default 20,
  p_offset int  default 0,
  p_types     text[] default null,
  p_locations text[] default null,
  p_regions   text[] default null,
  p_durations text[] default null,
  p_tracks    text[] default null,
  p_degrees   int[]  default null,
  p_statuses  int[]  default null,
  p_actives   boolean[] default null
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
  recruit_until      date,
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
  with rep as (
    select distinct on (p.worksite_id)
      p.worksite_id, p.preferred_track, p.eligible_degree,
      p.eligible_status, p.work_duration_type
    from postings p
    where p.deleted_at is null
    order by p.worksite_id, p.is_active desc, p.created_at desc
  ),
  ws_active as (
    select worksite_id, bool_or(is_active) as is_active, max(recruit_until) as recruit_until
    from postings where deleted_at is null group by worksite_id
  ),
  stats as (
    select worksite_id,
           count(*) as review_count,
           round(avg(score_recommend)::numeric,1) as avg_recommend,
           round(avg(score_work)::numeric,1)      as avg_work,
           round(avg(score_growth)::numeric,1)    as avg_growth,
           round(avg(score_vibe)::numeric,1)      as avg_vibe,
           round(avg(score_flex)::numeric,1)      as avg_flex,
           round(100.0*count(*) filter (where score_recommend>=4.0)/count(*))::int as recommend_rate
    from reviews where deleted_at is null and not is_blinded group by worksite_id
  ),
  joined as (
    select w.id as worksite_id, w.organization_name, w.workplace_name,
           w.region, w.address, w.type, w.location_type, w.view_count,
           coalesce(a.is_active,false) as is_active,
           a.recruit_until,
           r.preferred_track, r.eligible_degree, r.eligible_status, r.work_duration_type,
           coalesce(s.review_count,0) as review_count,
           s.avg_recommend, s.avg_work, s.avg_growth, s.avg_vibe, s.avg_flex, s.recommend_rate
    from worksites w
    join rep r           on r.worksite_id = w.id
    left join ws_active a on a.worksite_id = w.id
    left join stats s    on s.worksite_id = w.id
    where w.deleted_at is null
      and ( p_query is null or p_query = '' or
            w.organization_name ilike '%'||p_query||'%' or
            w.workplace_name    ilike '%'||p_query||'%' )
      and (p_actives   is null or coalesce(a.is_active,false) = any(p_actives))
      and (p_types     is null or w.type          = any(p_types::worksite_type_e[]))
      and (p_locations is null or w.location_type = any(p_locations::location_type_e[]))
      and (p_regions   is null or w.location_type = 'on_campus' or w.region = any(p_regions))
      and (p_durations is null or r.work_duration_type = any(p_durations::duration_type_e[]))
      and (p_tracks    is null or r.preferred_track     = any(p_tracks))
      and (p_degrees   is null or r.eligible_degree::int = any(p_degrees))
      and (p_statuses  is null or r.eligible_status::int = any(p_statuses))
  )
  select *, count(*) over() as total_count
  from joined
  order by
    case when p_sort='reviews'   then review_count end desc nulls last,
    case when p_sort='recommend' then avg_recommend end desc nulls last,
    worksite_id
  limit  least(greatest(coalesce(p_limit, 20), 0), 50)
  offset least(greatest(coalesce(p_offset, 0), 0), 10000);
$$;

-- DROP으로 grant가 소멸 — 재부여 (authenticated=로그인 검색, anon=비로그인 공개 검색: 20260716120000)
grant execute on function search_worksite_cards(text,text,int,int,text[],text[],text[],text[],text[],int[],int[],boolean[]) to authenticated, anon;

-- 공개 상세: posting jsonb에 recruit_until 추가 (jsonb 반환이라 시그니처 불변 → create or replace)
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
        'recruit_until',           rep.recruit_until,
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
```

- [ ] **Step 3: `toCard` 테스트 보강** (`web/src/lib/searchCards.test.js`)

기존 `toCard` describe에 케이스 추가(기존 fixture 행에 `recruit_until` 없음 → 폴백 검증도 겸함):

```js
  it('recruit_until 지난 행은 is_active=true여도 카드가 모집완료', () => {
    const NOW = new Date('2026-07-17T12:00:00+09:00')
    const c = toCard({ ...row, is_active: true, recruit_until: '2026-07-10' }, NOW)
    expect(c.is_active).toBe(false)
  })
  it('recruit_until 없으면(구 RPC/레거시) is_active 폴백', () => {
    const NOW = new Date('2026-07-17T12:00:00+09:00')
    expect(toCard({ ...row, is_active: true }, NOW).is_active).toBe(true)
  })
```

(기존 fixture 변수명이 `row`가 아니면 그 파일의 실제 이름에 맞춘다 — 29행 부근의 flat 행 객체.)

- [ ] **Step 4: 실패 확인 → `toCard` 구현 수정** (`web/src/lib/searchCards.js`)

Run: `cd web; npx vitest run src/lib/searchCards.test.js` → 새 케이스 FAIL 확인 후:

```js
import { effectiveActive } from './recruit'
```

```js
// search_worksite_cards의 flat 행 → ResultCard가 쓰는 {worksite, posting, stats, is_active} 모양.
// is_active는 effectiveActive 결과(recruit_until 우선) — now는 테스트용 주입.
export function toCard(row, now = new Date()) {
  const hasReview = Number(row.review_count) > 0
  return {
    is_active: effectiveActive(row, now),
    ...
```

(나머지 필드는 기존 그대로.)

- [ ] **Step 5: `worksiteQueries.js`의 map 호출 수정** — ⚠️ 필수

249행 `rows.map(toCard)`는 `map`이 두 번째 인자로 **index**를 넘겨 `now` 자리에 숫자가 들어간다. 반드시 화살표로 감싼다:

```js
  return { cards: rows.map((r) => toCard(r)), total }
```

- [ ] **Step 6: 통과 확인**

Run: `cd web; npx vitest run`
Expected: 전부 PASS.

- [ ] **Step 7: `docs/db-schema.md` RPC 기록 갱신**

`search_worksite_cards`·`get_worksite_public_detail` 설명이 있는 곳에 "반환에 `recruit_until` 추가(20260717 마이그레이션) — 카드 모집 판정은 프론트 `effectiveActive`" 한 줄씩 추가.

- [ ] **Step 8: Commit**

```powershell
git add web/supabase/migrations web/src/lib/searchCards.js web/src/lib/searchCards.test.js web/src/data/worksiteQueries.js docs/db-schema.md
git commit -m "feat(search): RPC가 recruit_until 반환 — 검색 카드·공개 상세도 날짜 기반 모집 판정"
```

---

### Task 8: 국가근장 학기 일괄 UPDATE 뼈대 문서화

**Files:**
- Modify: `web/supabase/README.md` (「## DB 바꿀 때 (워크플로우)」 섹션 뒤에 새 섹션)

**Interfaces:**
- Produces: 국가근장 모집기간 확정 시 복붙해 쓰는 운영 템플릿(스펙 §5-5 — 기간 미확정이라 마이그레이션 파일은 아직 안 만든다).

- [ ] **Step 1: README에 섹션 추가**

```markdown
## 국가근장 모집기간 반영(정기 운영 — 학기·방학마다)

국가근장은 KOSAF 일괄 모집이라 근무지별 마감 추측이 성립하지 않는다(**추측 금지**).
학기·방학 집중근로 **모집기간 공지가 확정될 때마다** 아래 템플릿으로 마이그레이션을 만들어 push한다.
이 UPDATE가 교외 6,647건의 낡은 `is_active`도 겸사겸사 해소한다(별도 백필 불필요 — spec 2026-07-17 §2).

```sql
-- 목적: 국가근로 <2026-2학기|2026-동계방학> 모집기간 반영 — recruit_until 일괄 입력(확정값)
-- 날짜: YYYY-MM-DD · 담당: <이름>
update postings p
   set recruit_until = '<접수 마감일 YYYY-MM-DD>',
       recruit_until_estimated = false,
       is_active = ('<접수 마감일 YYYY-MM-DD>'::date >= current_date),  -- 검색 RPC 롤업이 아직 is_active를 봄
       updated_at = now()
  from worksites w
 where w.id = p.worksite_id and w.type = 'national' and p.deleted_at is null;
```
```

- [ ] **Step 2: Commit**

```powershell
git add web/supabase/README.md
git commit -m "docs(supabase): 국가근장 모집기간 일괄 UPDATE 운영 템플릿"
```

---

### Task 9: 실데이터 실행 런북 (⚠️ 사용자 개입 필요 — KUPID 로그인·API 키·검수·db push)

**Files:** 코드 변경 없음(생성기가 만드는 마이그레이션 1개 + Excel 산출물).

**Interfaces:**
- Consumes: Task 1~8 전부. 사용자: KUPID 로그인(크롤), `ANTHROPIC_API_KEY`(파싱), Excel 검수, 디스코드 공유, `db push` 승인.

- [ ] **Step 1: 크롤 full 실행** (사용자 로그인 필요)

```powershell
python crawling_scripts/kupid_portal_crawler.py --full
```

Edge 창에서 KUPID 로그인 → 일반공지 목록 보이면 콘솔 Enter. Expected: `data/kupid_workstudy_notices.json`에 근로장학 공고 전량(검색 기준 ~2,296건 중 매칭분).

- [ ] **Step 2: 파싱** (API 키 필요 · 건당 ~1.5초 대기 → 수백 건이면 수십 분~수 시간)

```powershell
$env:ANTHROPIC_API_KEY = "sk-ant-..."
python crawling_scripts/parse_kupid.py
```

Expected: `data/kupid_parsed_result.xlsx` 생성, `모집마감일(계산)`·`마감추정`·`출처URL` 채워짐.

- [ ] **Step 3: 사람 검수** (Excel — 노란 컬럼 중심)

체크리스트(스펙 §1): ①자격 4종(학부/대학원/재학/휴학) 오판 ②마감일 추출 누락·오독(`모집마감일(계산)` — 특히 `마감추정=O` 행) ③부서명 이상치(worksite 키) ④`교외여부`와 `지역(교외만)` — **교외면 지역 필수, REGIONS 짧은 형태**(예: '서울'). KUPID 밖 공고(SSC 등)는 이 단계에서 행 수동 추가.

- [ ] **Step 4: SQL 생성**

```powershell
python crawling_scripts/generate_school_migration.py
```

Expected: `web/supabase/migrations/<ts>_school_postings_reload.sql` 생성. 검증 에러가 나오면 Excel 고치고 재실행(이전 생성 파일은 삭제 후 재생성 — 중복 마이그레이션 방지).

- [ ] **Step 5: 검증** — Docker 있으면 `cd web; npx supabase db reset`(맨바닥 재구축), 없으면 sandbox 프로젝트에 `db push`(README 방식). school 카운트·recruit_until 분포 눈검사.

- [ ] **Step 6: prod 반영** (사용자 확인 후)

디스코드에 공유 → `cd web; npx supabase migration list`로 대기분 확인(⚠️ push는 남의 미적용분도 함께 나간다 — 20260716170000 교훈) → `npx supabase db push`.
push 대상: Task 1(컬럼) + Task 7(RPC) + Step 4(재적재) 3개.

- [ ] **Step 7: push 후 회귀 확인**

- 검색: 지역 필터 17종 total_count가 push 전과 동일(교외 재적재분 반영 감안), 교내 school 카드가 지역 필터에서도 노출.
- 홈/상세/검색 카드에서 마감 지난 공고가 "모집완료"로 보이는지(레거시 교외 카드가 뒤집히지 **않았는지** — is_active 폴백).
- 비로그인(시크릿 창) grgr.kr 상세·검색 정상.
- ⚠️ **프론트 prod 배포는 이 push가 끝난 뒤에**(main → prod 머지). 순서 역전 시 홈/상세 select 에러.

- [ ] **Step 8: Commit** (생성된 마이그레이션 + 크롤/파싱 산출물 중 커밋 대상만)

```powershell
git add web/supabase/migrations
git commit -m "feat(db): 교내근로(KUPID) 공고 재적재 — school wipe 후 검수 완료 데이터 적재"
```

(`data/*.json`·`*.xlsx` 산출물의 커밋 여부는 기존 repo 관례를 따른다 — `data/kupid_workstudy_notices.json`은 현재 추적 중이므로 함께 커밋.)

---

## 후속 과제 (구현 중 발견 — 이 계획 밖, 별건으로)

- **`fetchRepresentativePosting`의 대표 공고 선정이 아직 레거시 `is_active` 정렬**
  (`web/src/data/worksiteQueries.js:20-21`). Task 6 리뷰에서 발견.
  상세 페이지의 *배지*는 날짜 기반(`effectiveActive`)이 됐지만, *어느 공고를 보여줄지*는
  여전히 `.order('is_active', desc).limit(1)`이 고른다. 한 근무지에
  A(`is_active=true`·마감 지남)와 B(`is_active=false`·마감 미래)가 공존하면
  홈은 "모집중"(근무지 단위 OR 롤업), 상세는 A를 골라 "모집완료" — 서로 모순된다.
  지금은 school만 recruit_until을 갖고, 적재 시 `is_active` 스냅숏이 recruit_until과
  일치해 실현되기 어렵다. 다만 **Task 8의 국가근장 일괄 UPDATE가 이 전제를 깬다**
  (recruit_until만 갱신하고 is_active는 안 건드리는 변형을 쓸 경우) — 그때 재검토.
  ⚠️ 근본 해결은 "검색 RPC의 롤업·정렬을 recruit_until 기반으로 전환"(아래 스코프 밖 항목)과
  한 묶음 — 따로 고치면 프론트/RPC 판정이 또 갈린다.

- **검색 RPC `ws_active`의 `max(recruit_until)`가 활성 레거시 형제 공고를 가릴 수 있음**
  (`search_worksite_cards`, 20260717095637). Task 7 리뷰에서 발견. `max`는 NULL을 무시하므로,
  한 근무지가 [마감 지난 dated 공고]+[레거시 NULL·is_active=true 공고]를 함께 가지면
  롤업이 `recruit_until=<지난 날짜>`·`is_active=true`가 되고, `effectiveActive`는 non-NULL
  날짜를 우선해 **"모집완료"로 오판**(실제로는 레거시 공고가 모집 중). 위 대표공고 항목과
  같은 뿌리(롤업이 is_active를 봄)라 **같은 전환으로 함께 해소**한다. 현재는 근무지가
  school 아니면 national 한 종류라 dated+NULL 혼재가 잘 안 생겨(national은 Task 8이
  is_active도 함께 갱신) 좁은 과도기 엣지 — Task 9 데이터 눈검사 때 확인.

## 스코프 밖 (스펙 그대로)

- SSC 크롤러(MVP 배포 이후)
- 검색 RPC의 active 롤업·필터·정렬을 recruit_until 기반으로 전환
- 서울대/타대학(현수 담당)
- "~M/D 접수" 등 마감일 라벨 세부 문구(구현 중 별도 확정 — 이 계획은 모집중/모집완료 판정까지만)
