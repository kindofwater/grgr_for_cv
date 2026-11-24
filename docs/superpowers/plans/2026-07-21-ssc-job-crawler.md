# SSC 근로장학 크롤·파싱·적재 파이프라인 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 고려대 SSC(job.korea.ac.kr) 근로장학 공고를 매일 무인으로 크롤→Opus 파싱→멱등 UPSERT 적재하는 파이프라인을 만든다.

**Architecture:** 순수 함수(정규화·id·기간 파싱)와 파서를 fixture 기반 TDD로 먼저 굳히고, KUPID 크롤러(`kupid_portal_crawler.py`) 패턴을 미러링해 세션·크롤 루프를 얹는다. 적재는 마이그레이션이 아니라 service_role 클라이언트로 `unique(source, external_id)`·`unique(normalized_name)` 키에 무삭제 UPSERT한다. KUPID 파싱 산출도 같은 로더로 흡수한다.

**Tech Stack:** Python 3.13, requests, beautifulsoup4+lxml, playwright(msedge), anthropic(Opus), openpyxl, supabase-py, Supabase(Postgres), Windows 작업 스케줄러.

**Spec:** `docs/superpowers/specs/2026-07-21-ssc-job-crawler-design.md` (v3.1)

## Global Constraints

- school worksite 고정값: `university_id=1`, `type='school'`, `location_type='on_campus'`, `organization_name='고려대학교(본교)'`, `region=null`. (SSC `구분=교외`·`지역`은 DB에 반영하지 않음 — raw JSON 참고용.)
- `postings.source` 값: `'ssc'` | `'kupid'`. 
- `external_id`: SSC = `str(board_no)`; KUPID = `sha256("제목|부서명|등록일")` 앞 16자.
- `recruit_until` = 모집기간 끝 날짜, `recruit_until_estimated=false`(SSC는 명시 마감일).
- 크롤 컷오프 기본 `2023-01-01`(모집기간 시작일 기준), `--all-history`로 해제.
- 파이썬 모듈은 `from __future__ import annotations`로 시작(기존 스크립트 관행).
- 신규 의존성 `supabase`(supabase-py)는 `crawling_scripts/requirements.txt`에 명시.
- **절대 커밋 금지:** `crawling_scripts/creds.py`, service_role 키, `data/ssc_*.json`. fixture HTML은 담당자 연락처·이름 **마스킹 후** 커밋.
- DB 스키마 변경(Task 7)만 `web/supabase/migrations/` + 수동 `db push`(CLAUDE.md §3). 나머지 데이터 적재는 로더 스크립트.
- 테스트 실행 위치: 저장소 루트. `python -m pytest crawling_scripts/<file>::<test> -v`.

---

### Task 1: 근무지 이름 정규화 순수 함수

**Files:**
- Create: `crawling_scripts/worksite_norm.py`
- Test: `crawling_scripts/test_worksite_norm.py`

**Interfaces:**
- Produces: `normalize_worksite_name(name: str) -> str` — 접두어·대괄호 태그·공백·대소문자 정리한 정규화 키. Task 9(로더)·Task 10(백필)이 소비.

- [ ] **Step 1: 실패하는 테스트 작성** — `crawling_scripts/test_worksite_norm.py`

```python
from worksite_norm import normalize_worksite_name


def test_strips_university_prefix():
    assert normalize_worksite_name("고려대학교 물리학과") == "물리학과"
    assert normalize_worksite_name("고려대 물리학과") == "물리학과"

def test_strips_bracket_tags():
    assert normalize_worksite_name("[Student Success Center] 근로") == "근로"

def test_strips_bonkyo_and_collapses_space():
    assert normalize_worksite_name("고려대학교(본교)  중앙도서관") == "중앙도서관"

def test_case_and_trim():
    assert normalize_worksite_name("  학생처 Student Success Center ") == \
        normalize_worksite_name("학생처 student success center")

def test_same_dept_two_sources_match():
    assert normalize_worksite_name("고려대학교 물리학과") == normalize_worksite_name("물리학과")

def test_empty_and_none_safe():
    assert normalize_worksite_name("") == ""
    assert normalize_worksite_name(None) == ""
```

- [ ] **Step 2: 실패 확인**

Run: `python -m pytest crawling_scripts/test_worksite_norm.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'worksite_norm'`

> pytest는 테스트 파일이 있는 `crawling_scripts/`를 sys.path에 넣으므로 `import worksite_norm`이 동작한다(기존 `test_kupid_portal_crawler.py`와 동일 관행).

- [ ] **Step 3: 최소 구현** — `crawling_scripts/worksite_norm.py`

```python
from __future__ import annotations

import re

# 근무지명 앞에 붙는 대학 접두어(표기 흔들림 흡수). 긴 것부터 매칭.
_PREFIXES = ("고려대학교(본교)", "고려대학교", "고려대")


def normalize_worksite_name(name: str | None) -> str:
    """근무지명을 소스 간 매칭용 정규화 키로 변환.

    - '[태그]' 제거, 대학 접두어 제거, 공백 1칸 축약, 소문자, 양끝 트림.
    - SSC '고려대학교 물리학과'와 KUPID '물리학과'가 같은 키가 되게 한다.
    """
    if not name:
        return ""
    s = str(name)
    s = re.sub(r"\[[^\]]*\]", " ", s)          # [Student Success Center] 등 태그 제거
    s = s.replace("\xa0", " ")
    s = re.sub(r"\s+", " ", s).strip()
    for p in _PREFIXES:
        if s.startswith(p):
            s = s[len(p):].strip()
            break
    s = re.sub(r"\s+", " ", s).strip().lower()
    return s
```

- [ ] **Step 4: 통과 확인**

Run: `python -m pytest crawling_scripts/test_worksite_norm.py -v`
Expected: PASS (6 passed)

- [ ] **Step 5: 커밋**

```bash
git add crawling_scripts/worksite_norm.py crawling_scripts/test_worksite_norm.py
git commit -m "feat(ssc): 근무지 이름 정규화 순수 함수 + 테스트"
```

---

### Task 2: SSC external_id · 모집기간 파싱 순수 함수

**Files:**
- Create: `crawling_scripts/ssc_job_crawler.py` (이 태스크에서 순수 함수만 먼저)
- Test: `crawling_scripts/test_ssc_job_crawler.py`

**Interfaces:**
- Produces:
  - `ssc_external_id(row: dict) -> str` — `str(row["board_no"])`. Task 5·9가 소비.
  - `parse_period(period_text: str) -> tuple[str, str]` — `("YYYY-MM-DD","YYYY-MM-DD")` (시작, 끝). 파싱 불가 시 `("","")`. Task 3·5가 소비.

- [ ] **Step 1: 실패하는 테스트 작성** — `crawling_scripts/test_ssc_job_crawler.py`

```python
from ssc_job_crawler import ssc_external_id, parse_period


def test_ssc_external_id_is_board_no_string():
    assert ssc_external_id({"board_no": 71}) == "71"
    assert ssc_external_id({"board_no": "70"}) == "70"

def test_parse_period_range():
    assert parse_period("2026.07.20 00:00~2026.07.24 12:00") == ("2026-07-20", "2026-07-24")

def test_parse_period_dates_only():
    assert parse_period("2026.06.22~2026.06.30") == ("2026-06-22", "2026-06-30")

def test_parse_period_garbage_returns_empty():
    assert parse_period("상시모집") == ("", "")
    assert parse_period("") == ("", "")
```

- [ ] **Step 2: 실패 확인**

Run: `python -m pytest crawling_scripts/test_ssc_job_crawler.py -v`
Expected: FAIL — `ImportError: cannot import name 'ssc_external_id'`

- [ ] **Step 3: 최소 구현** — `crawling_scripts/ssc_job_crawler.py` (파일 상단 생성)

```python
"""고려대 SSC(job.korea.ac.kr) 아르바이트 게시판 근로장학 공고 크롤러.

kupid_portal_crawler.py 패턴 미러링: Playwright SSO 로그인 → requests 세션 크롤.
목록 표 + 각 공고 상세 본문 수집 → data/ssc_workstudy_raw.json.
"""
from __future__ import annotations

import re

_DATE_RE = re.compile(r"(\d{4})[.\-/](\d{2})[.\-/](\d{2})")


def ssc_external_id(row: dict) -> str:
    """SSC 공고 자연키 = 게시판 번호(안정적·유니크). unique(source, external_id)의 external_id."""
    return str(row["board_no"]).strip()


def parse_period(period_text: str) -> tuple[str, str]:
    """'2026.07.20 00:00~2026.07.24 12:00' → ('2026-07-20','2026-07-24').

    시작/끝 각각에서 첫 날짜를 뽑는다. 못 뽑으면 빈 문자열.
    """
    text = period_text or ""
    halves = text.split("~", 1)
    out = []
    for part in (halves[0], halves[1] if len(halves) > 1 else ""):
        m = _DATE_RE.search(part)
        out.append(f"{m.group(1)}-{m.group(2)}-{m.group(3)}" if m else "")
    return out[0], out[1]
```

- [ ] **Step 4: 통과 확인**

Run: `python -m pytest crawling_scripts/test_ssc_job_crawler.py -v`
Expected: PASS (4 passed)

- [ ] **Step 5: 커밋**

```bash
git add crawling_scripts/ssc_job_crawler.py crawling_scripts/test_ssc_job_crawler.py
git commit -m "feat(ssc): external_id·모집기간 파싱 순수 함수 + 테스트"
```

---

### Task 3: 목록 표 파서 `parse_list_page`

**Files:**
- Modify: `crawling_scripts/ssc_job_crawler.py`
- Test: `crawling_scripts/test_ssc_job_crawler.py`

**Interfaces:**
- Consumes: `parse_period` (Task 2)
- Produces: `parse_list_page(html: str) -> list[dict]` — 각 dict 키: `board_no:int, category, region_raw, company_name, title, period_text, period_start, recruit_until, views, detail_url, source="ssc"`. Task 5가 소비.

> **주의:** 아래 테스트는 스크린샷에서 확인한 컬럼 순서(번호·구분·지역·회사명·공고명·모집기간·조회수)를 재현한 최소 표 HTML로 셀 인덱스 파싱을 검증한다. **실제 로그인 후 저장한 fixture(`fixtures/ssc_list_page1.html`, Task 6)로 재확인**하고, 열 순서/구조가 다르면 인덱스를 조정한다. 클래스명이 아닌 셀 위치로 파싱해 클래스 변경에 강하다.

- [ ] **Step 1: 실패하는 테스트 추가** — `test_ssc_job_crawler.py`에 append

```python
from ssc_job_crawler import parse_list_page

_MIN_LIST_HTML = """
<table class="board"><thead><tr>
<th>번호</th><th>구분</th><th>지역</th><th>회사명</th><th>공고명</th><th>모집기간</th><th>조회수</th>
</tr></thead><tbody>
<tr>
  <td>71</td><td>교내</td><td>서울</td><td>학생처 Student Success Center</td>
  <td><a href="/ptfol/ncEm/job/rcrt/arb/view.do?seq=1234">[Student Success Center] 근로장학생 모집</a></td>
  <td>2026.07.20 00:00~2026.07.24 12:00</td><td>41</td>
</tr>
<tr>
  <td>70</td><td>교내</td><td>서울</td><td>4단계 BK21 컴퓨터학교육연구단</td>
  <td><a href="/ptfol/ncEm/job/rcrt/arb/view.do?seq=1233">[4단계 BK21 컴퓨터학교육연구단] 근로장학생 모집</a></td>
  <td>2026.07.16 00:00~2026.07.22 00:00</td><td>35</td>
</tr>
</tbody></table>
"""


def test_parse_list_page_extracts_rows():
    rows = parse_list_page(_MIN_LIST_HTML)
    assert len(rows) == 2
    r = rows[0]
    assert r["board_no"] == 71
    assert r["category"] == "교내"
    assert r["region_raw"] == "서울"
    assert r["company_name"] == "학생처 Student Success Center"
    assert r["title"] == "[Student Success Center] 근로장학생 모집"
    assert r["period_start"] == "2026-07-20"
    assert r["recruit_until"] == "2026-07-24"
    assert r["detail_url"].endswith("seq=1234")
    assert r["source"] == "ssc"

def test_parse_list_page_empty_table():
    assert parse_list_page("<table><tbody></tbody></table>") == []
```

- [ ] **Step 2: 실패 확인**

Run: `python -m pytest crawling_scripts/test_ssc_job_crawler.py -k list_page -v`
Expected: FAIL — `ImportError: cannot import name 'parse_list_page'`

- [ ] **Step 3: 구현 추가** — `ssc_job_crawler.py` (import 보강 + 함수)

파일 상단 import에 추가:
```python
from bs4 import BeautifulSoup
```

함수 추가:
```python
def _cell_text(td) -> str:
    return td.get_text(" ", strip=True) if td else ""


def parse_list_page(html_text: str) -> list[dict]:
    """SSC 아르바이트 목록 표 → 행 리스트. 셀 인덱스 기반(클래스명 비의존).

    열 순서: 0 번호 · 1 구분 · 2 지역 · 3 회사명 · 4 공고명(링크) · 5 모집기간 · 6 조회수.
    """
    soup = BeautifulSoup(html_text, "lxml")
    rows: list[dict] = []
    for tr in soup.select("table tbody tr"):
        tds = tr.find_all("td")
        if len(tds) < 7:
            continue
        board_raw = _cell_text(tds[0])
        if not board_raw.isdigit():
            continue                      # 헤더/구분행 등 스킵
        link = tds[4].find("a")
        period_text = _cell_text(tds[5])
        start, until = parse_period(period_text)
        rows.append({
            "board_no": int(board_raw),
            "category": _cell_text(tds[1]),
            "region_raw": _cell_text(tds[2]),
            "company_name": _cell_text(tds[3]),
            "title": (link.get_text(strip=True) if link else _cell_text(tds[4])),
            "period_text": period_text,
            "period_start": start,
            "recruit_until": until,
            "views": _cell_text(tds[6]),
            "detail_url": (link.get("href", "") if link else ""),
            "source": "ssc",
        })
    return rows
```

- [ ] **Step 4: 통과 확인**

Run: `python -m pytest crawling_scripts/test_ssc_job_crawler.py -v`
Expected: PASS (전체)

- [ ] **Step 5: 커밋**

```bash
git add crawling_scripts/ssc_job_crawler.py crawling_scripts/test_ssc_job_crawler.py
git commit -m "feat(ssc): 목록 표 파서 parse_list_page(셀 인덱스 기반) + 테스트"
```

---

### Task 4: 상세 본문 파서 `parse_detail`

**Files:**
- Modify: `crawling_scripts/ssc_job_crawler.py`
- Test: `crawling_scripts/test_ssc_job_crawler.py`

**Interfaces:**
- Produces: `parse_detail(html: str) -> dict` — `{"body": str, "posted_at": str}` (상세 본문 텍스트 + 게시일자 YYYY-MM-DD, 없으면 ""). Task 5·8이 소비.

> **게시일자(2026-07-21 추가):** SSC 목록 표엔 게시일 컬럼이 없어 상세 페이지에서 뽑는다. '게시일/작성일/등록일' 라벨 뒤 날짜를 방어적 정규식으로 추출(실물 fixture로 라벨 확정). 로더(Task 9)가 `postings.created_at`으로 적재 → 공고의 실제 게시일 보존(KUPID 관행과 동일).

> **주의:** SSC 상세 HTML 실물은 Task 6 로그인 후 저장한 `fixtures/ssc_detail_sample.html`로 확정한다. 아래 구현은 본문 컨테이너 후보를 순차 탐색하는 방어적 방식이며, 실제 컨테이너 셀렉터를 fixture로 확인해 `_DETAIL_SELECTORS` 맨 앞에 추가한다.

- [ ] **Step 1: 실패하는 테스트 추가** — `test_ssc_job_crawler.py`에 append

```python
from ssc_job_crawler import parse_detail

_MIN_DETAIL_HTML = """
<html><body>
<div class="view_cont">
  근무내용: 도서 정리 및 대출 보조
  시급: 9,860원   근무시간: 주 15시간   지원자격: 학부 재학생
</div>
</body></html>
"""


def test_parse_detail_extracts_body():
    d = parse_detail(_MIN_DETAIL_HTML)
    assert "도서 정리" in d["body"]
    assert "9,860" in d["body"]

def test_parse_detail_missing_container_returns_empty():
    d = parse_detail("<html><body></body></html>")
    assert d["body"] == ""
```

- [ ] **Step 2: 실패 확인**

Run: `python -m pytest crawling_scripts/test_ssc_job_crawler.py -k detail -v`
Expected: FAIL — `ImportError: cannot import name 'parse_detail'`

- [ ] **Step 3: 구현 추가** — `ssc_job_crawler.py`

```python
# 상세 본문 컨테이너 후보(실물 fixture 확인 후 맨 앞에 실제 셀렉터 추가).
_DETAIL_SELECTORS = ("div.view_cont", "div.board_view", "div.view_area", "div.cont", "article")


def _clean_text(value: str) -> str:
    value = (value or "").replace("\xa0", " ")
    value = re.sub(r"[ \t]+", " ", value)
    value = re.sub(r"\n[ \t]+", "\n", value)
    value = re.sub(r"\n{3,}", "\n\n", value)
    return value.strip()


def parse_detail(html_text: str) -> dict:
    """상세 페이지 → {"body": 본문텍스트}. 컨테이너 후보를 순차 탐색."""
    soup = BeautifulSoup(html_text, "lxml")
    node = None
    for sel in _DETAIL_SELECTORS:
        node = soup.select_one(sel)
        if node:
            break
    body = _clean_text(node.get_text("\n", strip=True)) if node else ""
    return {"body": body}
```

- [ ] **Step 4: 통과 확인**

Run: `python -m pytest crawling_scripts/test_ssc_job_crawler.py -v`
Expected: PASS

- [ ] **Step 5: 커밋**

```bash
git add crawling_scripts/ssc_job_crawler.py crawling_scripts/test_ssc_job_crawler.py
git commit -m "feat(ssc): 상세 본문 파서 parse_detail(방어적 컨테이너 탐색) + 테스트"
```

---

### Task 5: 크롤 루프 `crawl` (페이지네이션·컷오프·중복)

**Files:**
- Modify: `crawling_scripts/ssc_job_crawler.py`
- Test: `crawling_scripts/test_ssc_job_crawler.py`

**Interfaces:**
- Consumes: `parse_list_page`, `parse_detail`, `ssc_external_id`
- Produces: `crawl(fetch, oldest_date=None, limit=None, skip_ids=None, results=None, max_pages=300) -> list[dict]` — 각 레코드는 목록 행 + `detail_text`. `fetch(url)->html`을 주입받아(테스트는 fake) 순수하게 순회. Task 6이 실제 session fetch로 호출.

- [ ] **Step 1: 실패하는 테스트 추가** — `test_ssc_job_crawler.py`에 append

```python
from ssc_job_crawler import crawl, build_list_url


def _fake_fetch_factory(pages: dict[int, str], detail_html: str):
    """currentPageNo→목록HTML 매핑. 상세 URL은 전부 detail_html 반환."""
    def fetch(url: str) -> str:
        if "view.do" in url:
            return detail_html
        m = re.search(r"currentPageNo=(\d+)", url)
        page = int(m.group(1)) if m else 1
        return pages.get(page, "<table><tbody></tbody></table>")
    return fetch


def test_crawl_paginates_and_attaches_detail():
    pages = {1: _MIN_LIST_HTML, 2: "<table><tbody></tbody></table>"}
    fetch = _fake_fetch_factory(pages, _MIN_DETAIL_HTML)
    rows = crawl(fetch)
    assert len(rows) == 2
    assert "도서 정리" in rows[0]["detail_text"]

def test_crawl_stops_at_oldest_date():
    # period_start 2026-07-20, 2026-07-16 — oldest 2026-07-18이면 첫 행만 남고 둘째서 중단
    fetch = _fake_fetch_factory({1: _MIN_LIST_HTML}, _MIN_DETAIL_HTML)
    rows = crawl(fetch, oldest_date="2026-07-18")
    assert [r["board_no"] for r in rows] == [71]

def test_crawl_skips_known_ids():
    fetch = _fake_fetch_factory({1: _MIN_LIST_HTML, 2: "<table><tbody></tbody></table>"}, _MIN_DETAIL_HTML)
    rows = crawl(fetch, skip_ids={"71"})
    assert [r["board_no"] for r in rows] == [70]

def test_crawl_limit():
    fetch = _fake_fetch_factory({1: _MIN_LIST_HTML}, _MIN_DETAIL_HTML)
    rows = crawl(fetch, limit=1)
    assert len(rows) == 1
```

- [ ] **Step 2: 실패 확인**

Run: `python -m pytest crawling_scripts/test_ssc_job_crawler.py -k crawl -v`
Expected: FAIL — `ImportError: cannot import name 'crawl'`

- [ ] **Step 3: 구현 추가** — `ssc_job_crawler.py`

파일 상단 상수(import 아래)에 추가:
```python
from urllib.parse import quote

BASE_URL = "https://job.korea.ac.kr"
LIST_PATH = "/ptfol/ncEm/job/rcrt/arb/index.do"
SEARCH_KEYWORD = "근로장학"
DEFAULT_OLDEST_DATE = "2023-01-01"
```

함수 추가:
```python
def build_list_url(page_no: int, keyword: str = SEARCH_KEYWORD) -> str:
    return (f"{BASE_URL}{LIST_PATH}?tabType=tot&currentPageNo={page_no}"
            f"&placeSh=0000&searchType=1&frDtSh=&toDtSh=&searchValue={quote(keyword)}")


def _abs_url(path_or_url: str) -> str:
    return path_or_url if path_or_url.startswith("http") else BASE_URL + path_or_url


def crawl(fetch, oldest_date=None, limit=None, skip_ids=None,
          results=None, on_progress=None, max_pages=300):
    """목록을 최신순으로 순회하며 각 공고 상세를 붙여 수집.

    - oldest_date: period_start가 이보다 과거인 행을 만나면 즉시 중단(최신순 가정).
    - skip_ids: 이미 가진 external_id 집합(증분/이어받기).
    - fetch(url)->html 주입(테스트는 fake, 운영은 세션 fetch).
    """
    if results is None:
        results = []
    if skip_ids is None:
        skip_ids = set()
    seen: set[str] = set()
    page_no = 1
    while page_no <= max_pages:
        list_html = fetch(build_list_url(page_no))
        rows = parse_list_page(list_html)
        if not rows:
            break
        for row in rows:
            if oldest_date and row["period_start"] and row["period_start"] < oldest_date:
                return results
            ext = ssc_external_id(row)
            if ext in seen:
                continue
            seen.add(ext)
            if ext in skip_ids:
                continue
            detail_html = fetch(_abs_url(row["detail_url"]))
            detail = parse_detail(detail_html)
            record = dict(row)
            record["external_id"] = ext
            record["detail_url"] = _abs_url(row["detail_url"])
            record["detail_text"] = detail["body"]
            record["posted_at"] = detail["posted_at"]   # 게시일자(상세에서 추출, 없으면 "")
            results.append(record)
            if on_progress:
                on_progress(len(results), record)
            if limit is not None and len(results) >= limit:
                return results
        page_no += 1
    return results
```

- [ ] **Step 4: 통과 확인**

Run: `python -m pytest crawling_scripts/test_ssc_job_crawler.py -v`
Expected: PASS (전체)

- [ ] **Step 5: 커밋**

```bash
git add crawling_scripts/ssc_job_crawler.py crawling_scripts/test_ssc_job_crawler.py
git commit -m "feat(ssc): 크롤 루프 crawl(페이지네이션·컷오프·중복·limit) + 테스트"
```

---

### Task 6: 세션 캡처(수동/자동로그인)·JSON 병합·CLI main

**Files:**
- Modify: `crawling_scripts/ssc_job_crawler.py`
- Create: `crawling_scripts/fixtures/ssc_list_page1.html`, `crawling_scripts/fixtures/ssc_detail_sample.html` (로그인 후 저장, PII 마스킹)

**Interfaces:**
- Consumes: `crawl`, `ssc_external_id`
- Produces: `main()` CLI (`--full`/`--incremental`/`--limit N`/`--all-history`), 출력 `data/ssc_workstudy_raw.json`, 상태 `data/ssc_last_crawl.json`.

> 이 태스크는 SSO·Playwright·파일 IO라 순수 단위테스트가 어렵다. `merge_into_json`·`load_skip_ids`만 소형 테스트하고, 세션/자동로그인은 스모크(`--limit 3`)로 검증한다. `kupid_portal_crawler.py`의 `session_from_cookies`·`make_session_fetch`·`merge_into_json`·`is_login_redirect`를 **미러링**한다.

- [ ] **Step 1: merge/state 테스트 추가** — `test_ssc_job_crawler.py`에 append

```python
from ssc_job_crawler import merge_into_json


def test_merge_dedups_by_external_id():
    existing = [{"external_id": "71", "views": "10"}]
    new = [{"external_id": "71", "views": "41"}, {"external_id": "70", "views": "35"}]
    merged = merge_into_json(existing, new)
    by = {r["external_id"]: r for r in merged}
    assert set(by) == {"70", "71"}
    assert by["71"]["views"] == "41"   # 새 값이 이김
```

- [ ] **Step 2: 실패 확인**

Run: `python -m pytest crawling_scripts/test_ssc_job_crawler.py -k merge -v`
Expected: FAIL — `ImportError: cannot import name 'merge_into_json'`

- [ ] **Step 3: 구현 추가** — `ssc_job_crawler.py` (상단에 경로 상수·import)

```python
import argparse
import datetime
import json
import sys
import time
from pathlib import Path

import requests

ROOT_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = ROOT_DIR / "data"
OUTPUT_FILE = DATA_DIR / "ssc_workstudy_raw.json"
STATE_FILE = DATA_DIR / "ssc_last_crawl.json"
PROFILE_DIR = ROOT_DIR / ".ssc_playwright_profile"
REQUEST_DELAY_SEC = 0.4
USER_AGENT = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
              "(KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36 Edg/148.0.0.0")
```

함수 추가:
```python
def merge_into_json(existing: list[dict], new: list[dict]) -> list[dict]:
    by_key = {r.get("external_id"): r for r in existing}
    for r in new:
        by_key[r.get("external_id")] = r
    return list(by_key.values())


def load_skip_ids(path: Path) -> set[str]:
    if not path.exists():
        return set()
    return {r.get("external_id") for r in json.loads(path.read_text(encoding="utf-8"))}


def save_rows(out_path: Path, rows: list[dict]) -> list[dict]:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    existing = json.loads(out_path.read_text(encoding="utf-8")) if out_path.exists() else []
    merged = merge_into_json(existing, rows)
    out_path.write_text(json.dumps(merged, ensure_ascii=False, indent=2), encoding="utf-8")
    ids = [int(r["external_id"]) for r in merged if str(r.get("external_id", "")).isdigit()]
    if ids:
        STATE_FILE.write_text(json.dumps({"last_max_board_no": max(ids)}, ensure_ascii=False),
                              encoding="utf-8")
    return merged


def is_login_redirect(resp) -> bool:
    url = getattr(resp, "url", "")
    if "sso.korea.ac.kr" in url or "login" in url.lower():
        return True
    text = getattr(resp, "text", "") or ""
    return ("아이디를 입력" in text) and ("<table" not in text)


def session_from_cookies(cookies: list[dict]) -> requests.Session:
    session = requests.Session()
    session.headers.update({"User-Agent": USER_AGENT, "Referer": BASE_URL + LIST_PATH})
    for c in cookies:
        domain = (c.get("domain") or "").lstrip(".")
        if "korea.ac.kr" in domain:
            session.cookies.set(c["name"], c["value"], domain=domain, path=c.get("path", "/"))
    return session


def make_session_fetch(session, max_retries: int = 3):
    def fetch(url: str) -> str:
        for attempt in range(1, max_retries + 1):
            try:
                resp = session.get(url, timeout=20)
                resp.raise_for_status()
            except requests.RequestException as exc:
                if attempt < max_retries:
                    time.sleep(2 * attempt)
                    continue
                raise RuntimeError(f"요청 실패({url[:60]}): {exc}") from exc
            resp.encoding = "utf-8"
            if is_login_redirect(resp):
                raise RuntimeError("세션 만료(로그인 필요). 다시 실행해 로그인하세요.")
            time.sleep(REQUEST_DELAY_SEC)
            return resp.text
    return fetch


def capture_session(auto: bool = False) -> requests.Session:
    """Playwright(Edge)로 SSO 로그인 후 쿠키를 requests 세션에 주입.

    auto=False: 사람이 창에서 로그인 후 Enter(수동).
    auto=True : creds.py의 SSC_ID/SSC_PW로 SSO 폼 자동입력(무인, 2FA 없음 전제).
    """
    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        try:
            context = p.chromium.launch_persistent_context(
                user_data_dir=str(PROFILE_DIR), channel="msedge",
                headless=auto, viewport={"width": 1400, "height": 900})
        except Exception:
            context = p.chromium.launch_persistent_context(
                user_data_dir=str(PROFILE_DIR), headless=auto,
                viewport={"width": 1400, "height": 900})
        page = context.pages[0] if context.pages else context.new_page()
        page.goto(BASE_URL + LIST_PATH, wait_until="domcontentloaded")
        if auto:
            _auto_login(page)
        else:
            print("\n[로그인] 열린 Edge 창에서 SSC에 로그인 후, 목록이 보이면 Enter.")
            input("> ")
        cookies = context.cookies()
        context.close()
    return session_from_cookies(cookies)


def _auto_login(page) -> None:
    """SSO 폼 자동입력. 셀렉터는 실제 로그인 페이지로 확인 후 조정(§10)."""
    import creds  # gitignore: SSC_ID / SSC_PW
    if "sso.korea.ac.kr" not in page.url and "login" not in page.url.lower():
        page.goto(BASE_URL + LIST_PATH, wait_until="domcontentloaded")
    try:
        page.fill("input[name='id'], input#id, input[type='text']", creds.SSC_ID, timeout=10000)
        page.fill("input[name='pw'], input#pw, input[type='password']", creds.SSC_PW)
        page.press("input[type='password']", "Enter")
        page.wait_for_load_state("networkidle", timeout=20000)
    except Exception as exc:
        raise RuntimeError(f"자동 로그인 실패(셀렉터/2FA 확인 필요): {exc}") from exc
```

main 추가:
```python
def main() -> int:
    ap = argparse.ArgumentParser(description="SSC 근로장학 공고 크롤러")
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--full", action="store_true", help="전량(기본, 2023년까지)")
    mode.add_argument("--incremental", action="store_true", help="마지막 번호 이후 신규만")
    ap.add_argument("--limit", type=int, default=None, help="상세 N건만(스모크)")
    ap.add_argument("--all-history", action="store_true", help="컷오프 해제")
    ap.add_argument("--auto", action="store_true", help="자동 로그인(무인)")
    args = ap.parse_args()

    oldest = None if args.all_history else DEFAULT_OLDEST_DATE
    skip_ids = load_skip_ids(OUTPUT_FILE) if args.incremental else set()

    try:
        session = capture_session(auto=args.auto)
    except KeyboardInterrupt:
        print("\n[stopped] 로그인 전 중단.")
        return 130
    fetch = make_session_fetch(session)

    def progress(n, rec):
        print(f"  [{n}] no.{rec['board_no']} {rec['period_start']} {rec['title'][:40]}")

    rows: list[dict] = []
    try:
        crawl(fetch, oldest_date=oldest, limit=args.limit, skip_ids=skip_ids,
              results=rows, on_progress=progress)
    except (KeyboardInterrupt, RuntimeError) as exc:
        merged = save_rows(OUTPUT_FILE, rows)
        print(f"\n[saved partial] {len(rows)} collected, {len(merged)} total -> {OUTPUT_FILE}")
        print(f"[stopped] {exc}")
        return 1
    merged = save_rows(OUTPUT_FILE, rows)
    print(f"\n[done] collected {len(rows)}, total {len(merged)} -> {OUTPUT_FILE}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: merge 테스트 통과 확인**

Run: `python -m pytest crawling_scripts/test_ssc_job_crawler.py -v`
Expected: PASS (전체)

- [ ] **Step 5: 실물 스모크 + fixture 저장 (수동)**

로그인해 3건만 긁고, 실제 목록/상세 HTML을 fixture로 저장(PII 마스킹):
```bash
python crawling_scripts/ssc_job_crawler.py --limit 3
```
Expected: `data/ssc_workstudy_raw.json`에 3건, 각 `detail_text` 채워짐. 목록/상세 HTML을 브라우저에서 저장해 `fixtures/ssc_list_page1.html`·`ssc_detail_sample.html`로 두고, Task 3·4 테스트가 실물에서도 통과하는지 재확인(열 순서·컨테이너 셀렉터 다르면 조정).

- [ ] **Step 6: 커밋**

```bash
git add crawling_scripts/ssc_job_crawler.py crawling_scripts/test_ssc_job_crawler.py crawling_scripts/fixtures/ssc_list_page1.html crawling_scripts/fixtures/ssc_detail_sample.html
git commit -m "feat(ssc): 세션 캡처(수동/자동로그인)·JSON 병합·CLI + fixture"
```

---

### Task 7: 스키마 보강 마이그레이션 (§4.5)

**Files:**
- Create: `web/supabase/migrations/<ts>_ssc_posting_keys.sql` (CLI가 타임스탬프 생성)
- Modify: `docs/db-schema.md` (postings/worksites 신규 컬럼·유니크 반영)

**Interfaces:**
- Produces: `postings.source`, `postings.external_id`, `postings.manual_override`, `worksites.normalized_name` + 부분 유니크 인덱스 2개. Task 9·10이 소비.

> 데이터 무관·additive. `normalized_name` 백필은 Python 정규화가 정본이므로 여기서 안 하고 Task 10에서. 컷오버 후 서비스에 신규 컬럼은 기존 RPC/프론트에 무영향(SELECT * 아님).

- [ ] **Step 1: 마이그레이션 파일 생성**

```bash
cd web && npx supabase migration new ssc_posting_keys
```
Expected: `web/supabase/migrations/<타임스탬프>_ssc_posting_keys.sql` 생성(빈 파일).

- [ ] **Step 2: SQL 작성** — 생성된 파일에 기록

```sql
-- 목적: SSC/KUPID 공고 멱등 UPSERT용 외부키·정규화키·수동수정 플래그 추가
-- 날짜: 2026-07-21 · 담당: 배경록
-- 비고: spec docs/superpowers/specs/2026-07-21-ssc-job-crawler-design.md §4.5
--       additive(기존 데이터 무영향). normalized_name 백필은 로더가 수행(Python 정규화 정본).

begin;

-- postings: 공고 외부키 + 수동수정 보호 플래그
alter table postings add column if not exists source          varchar(20);
alter table postings add column if not exists external_id     varchar(100);
alter table postings add column if not exists manual_override boolean not null default false;

-- 같은 외부 공고 재적재 시 갱신(중복 방지). NULL(레거시/수동 행)은 유니크에서 제외.
create unique index if not exists postings_source_extid_uq
  on postings (source, external_id)
  where source is not null and external_id is not null;

-- worksites: 소스 간 매칭용 정규화 이름키. 소프트삭제 행은 키를 반납(deleted_at is null).
alter table worksites add column if not exists normalized_name varchar(200);

create unique index if not exists worksites_norm_uq
  on worksites (university_id, type, normalized_name)
  where normalized_name is not null and deleted_at is null;

commit;
```

- [ ] **Step 3: 로컬 검증**

Docker 로컬 DB가 있으면 `cd web && npx supabase db reset`로 맨바닥 재구축이 안 깨지는지 확인. 없으면 SQL을 눈으로 재검토(구문·additive 여부).
Expected: 재구축 성공 또는 구문 오류 없음.

- [ ] **Step 4: prod 반영 (수동, 디스코드 공유 후)**

```bash
cd web && npx supabase db push
```
Expected: `<ts>_ssc_posting_keys` 적용. `postings`·`worksites`에 신규 컬럼·인덱스 생성.

- [ ] **Step 5: db-schema.md 갱신 + 커밋**

`docs/db-schema.md`의 postings에 `source`·`external_id`·`manual_override`, worksites에 `normalized_name`과 유니크 인덱스 2개를 주석과 함께 추가.

```bash
git add web/supabase/migrations/*_ssc_posting_keys.sql docs/db-schema.md
git commit -m "feat(db): SSC/KUPID 공고 외부키·정규화키·manual_override 컬럼 추가"
```

---

### Task 8: Opus 파서 `parse_ssc.py`

**Files:**
- Create: `crawling_scripts/parse_ssc.py`
- Create: `crawling_scripts/test_parse_ssc.py`

**Interfaces:**
- Consumes: `data/ssc_workstudy_raw.json` (Task 6 산출)
- Produces:
  - `build_parse_messages(record: dict) -> list[dict]` — Opus 메시지(프롬프트). 순수·TDD.
  - `parse_response_json(text: str) -> dict` — Opus 응답 텍스트 → 필드 dict. 순수·TDD.
  - `to_canonical(record: dict, parsed: dict) -> dict` — 목록 확정 필드 + 파싱 필드 병합(목록 우선). 순수·TDD.
  - `main()` — raw JSON 전체를 Opus로 파싱해 `data/ssc_parsed.json` 저장.
- Canonical 레코드 키(로더 계약, Task 9와 일치): `source, external_id, company_name(원문), normalized_key 아님, worksite_name=company_name, title, recruit_until, period_text, source_url, recruit_count, hourly_wage, eligible_degree, eligible_status, job_description, preference_notes, extra_notes, work_period_text, work_duration_type, work_time_text, raw_text`.

- [ ] **Step 1: 실패하는 테스트 작성** — `crawling_scripts/test_parse_ssc.py`

```python
import json
from parse_ssc import parse_response_json, to_canonical


def test_parse_response_strips_codefence_and_loads():
    text = '```json\n{"hourly_wage": 9860, "recruit_count": "2"}\n```'
    d = parse_response_json(text)
    assert d["hourly_wage"] == 9860
    assert d["recruit_count"] == "2"

def test_parse_response_unknown_is_none():
    d = parse_response_json('{"hourly_wage": null, "eligible_degree": 3}')
    assert d["hourly_wage"] is None
    assert d["eligible_degree"] == 3

def test_to_canonical_list_fields_win_over_parse():
    record = {"external_id": "71", "company_name": "고려대학교 물리학과",
              "title": "[물리학과] 근로", "recruit_until": "2026-07-24",
              "period_text": "2026.07.20~2026.07.24",
              "detail_url": "https://job.korea.ac.kr/x", "detail_text": "본문"}
    parsed = {"hourly_wage": 9860, "recruit_until": "2099-01-01",  # 파싱이 틀린 마감일
              "recruit_count": "2", "job_description": "도서정리"}
    c = to_canonical(record, parsed)
    assert c["source"] == "ssc"
    assert c["external_id"] == "71"
    assert c["worksite_name"] == "고려대학교 물리학과"
    assert c["recruit_until"] == "2026-07-24"   # 목록 확정값 우선(파싱 무시)
    assert c["hourly_wage"] == 9860             # 파싱 필드는 채택
    assert c["source_url"] == "https://job.korea.ac.kr/x"
    assert c["raw_text"] == "본문"
```

- [ ] **Step 2: 실패 확인**

Run: `python -m pytest crawling_scripts/test_parse_ssc.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'parse_ssc'`

- [ ] **Step 3: 구현** — `crawling_scripts/parse_ssc.py`

```python
"""SSC 상세 본문 → Opus 구조화 파싱 → data/ssc_parsed.json (로더 입력).

실행: $env:ANTHROPIC_API_KEY="sk-ant-..."; python crawling_scripts/parse_ssc.py
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = ROOT_DIR / "data"
RAW_FILE = DATA_DIR / "ssc_workstudy_raw.json"
OUT_FILE = DATA_DIR / "ssc_parsed.json"
MODEL = "claude-opus-4-8"

# Opus가 뽑을 필드(목록에서 확정되는 recruit_until 등은 요청하지 않음).
_SYSTEM = (
    "너는 대학 근로장학 공고 본문에서 구조화 정보를 뽑는 파서다. "
    "반드시 JSON 하나만 출력한다(설명·코드펜스 금지). "
    "모르면 null. 숫자 필드는 숫자로. 다음 키만 채운다:\n"
    "hourly_wage(정수 원, 정액/미상 null), recruit_count(문자열 원문), "
    "eligible_degree(0=학부만,1=대학원만,2=모두,3=미상), "
    "eligible_status(0=재학만,1=휴학만,2=모두,3=미상), "
    "job_description, preference_notes, extra_notes, "
    "work_period_text, work_duration_type('short'|'long'|'unknown'), work_time_text"
)

_PARSED_KEYS = ("hourly_wage", "recruit_count", "eligible_degree", "eligible_status",
                "job_description", "preference_notes", "extra_notes",
                "work_period_text", "work_duration_type", "work_time_text")


def build_parse_messages(record: dict) -> list[dict]:
    body = record.get("detail_text", "")
    title = record.get("title", "")
    return [{"role": "user", "content": f"공고 제목: {title}\n\n본문:\n{body}"}]


def parse_response_json(text: str) -> dict:
    """Opus 응답에서 JSON 추출(코드펜스/앞뒤 잡텍스트 허용)."""
    t = (text or "").strip()
    t = re.sub(r"^```(?:json)?", "", t).strip()
    t = re.sub(r"```$", "", t).strip()
    m = re.search(r"\{.*\}", t, re.DOTALL)
    return json.loads(m.group(0)) if m else {}


def to_canonical(record: dict, parsed: dict) -> dict:
    """목록 확정 필드(우선) + 파싱 필드 → 로더 입력 정규 레코드."""
    out = {
        "source": "ssc",
        "external_id": record["external_id"],
        "worksite_name": record["company_name"],
        "title": record.get("title", ""),
        "recruit_until": record.get("recruit_until", ""),   # 목록 우선(파싱 무시)
        "period_text": record.get("period_text", ""),
        "posted_at": record.get("posted_at", ""),           # 게시일자(상세에서, 로더가 created_at으로)
        "source_url": record.get("detail_url", ""),
        "raw_text": record.get("detail_text", ""),
    }
    for k in _PARSED_KEYS:
        out[k] = parsed.get(k)
    return out


def main() -> int:
    import anthropic
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass
    records = json.loads(RAW_FILE.read_text(encoding="utf-8"))
    client = anthropic.Anthropic()
    out = []
    for i, rec in enumerate(records, 1):
        resp = client.messages.create(
            model=MODEL, max_tokens=1500, system=_SYSTEM,
            messages=build_parse_messages(rec))
        parsed = parse_response_json(resp.content[0].text)
        out.append(to_canonical(rec, parsed))
        print(f"  [{i}/{len(records)}] no.{rec.get('board_no')} {rec.get('title','')[:36]}")
    OUT_FILE.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"[done] {len(out)} -> {OUT_FILE}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: 통과 확인**

Run: `python -m pytest crawling_scripts/test_parse_ssc.py -v`
Expected: PASS (3 passed)

- [ ] **Step 5: 커밋**

```bash
git add crawling_scripts/parse_ssc.py crawling_scripts/test_parse_ssc.py
git commit -m "feat(ssc): Opus 파서(메시지·응답·정규화 병합) + 테스트"
```

---

### Task 9: UPSERT 로더 `upsert_worksites.py`

**Files:**
- Create: `crawling_scripts/upsert_worksites.py`
- Create: `crawling_scripts/test_upsert_worksites.py`
- Create: `crawling_scripts/requirements.txt`

**Interfaces:**
- Consumes: `normalize_worksite_name` (Task 1), `data/ssc_parsed.json` (Task 8), 스키마 컬럼(Task 7)
- Produces:
  - `decide_posting_update(existing: dict, parsed: dict) -> dict` — 갱신할 필드만. machine-owned 항상, content는 `manual_override` false일 때만. 순수·TDD.
  - `upsert_worksite(client, canonical: dict) -> int` — normalized_name 키로 조회/insert, worksite id.
  - `upsert_posting(client, worksite_id: int, canonical: dict) -> str` — `(source,external_id)`로 조회 후 insert/update. placeholder 삭제 처리. `"inserted"|"updated"` 반환.
  - `load(client, records: list[dict]) -> dict` — 전체 적재, 통계 dict.
  - `main()` — service_role 클라이언트 만들고 `ssc_parsed.json` 적재.

- [ ] **Step 1: 순수 로직 테스트 작성** — `crawling_scripts/test_upsert_worksites.py`

```python
from upsert_worksites import decide_posting_update, MACHINE_COLS, CONTENT_COLS


def test_machine_cols_always_updated():
    existing = {"manual_override": False}
    parsed = {"recruit_until": "2026-07-24", "is_active": True, "hourly_wage": 9860}
    upd = decide_posting_update(existing, parsed)
    assert upd["recruit_until"] == "2026-07-24"
    assert upd["is_active"] is True

def test_content_updated_when_no_override():
    upd = decide_posting_update({"manual_override": False}, {"hourly_wage": 9860})
    assert upd["hourly_wage"] == 9860

def test_content_skipped_when_override():
    upd = decide_posting_update({"manual_override": True},
                                {"hourly_wage": 9860, "recruit_until": "2026-07-24"})
    assert "hourly_wage" not in upd          # 사람 수정 보호
    assert upd["recruit_until"] == "2026-07-24"  # machine-owned은 여전히 갱신

def test_none_values_not_written():
    upd = decide_posting_update({"manual_override": False}, {"hourly_wage": None})
    assert "hourly_wage" not in upd

def test_col_sets_disjoint():
    assert MACHINE_COLS.isdisjoint(CONTENT_COLS)

def test_or3_preserves_zero_maps_none():
    from upsert_worksites import _or3
    assert _or3(0) == 0        # 학부만/재학만(falsy)이 3으로 뭉개지면 안 됨
    assert _or3(None) == 3     # 파싱 미상 → 3
    assert _or3(2) == 2
```

- [ ] **Step 2: 실패 확인**

Run: `python -m pytest crawling_scripts/test_upsert_worksites.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'upsert_worksites'`

- [ ] **Step 3: 구현** — `crawling_scripts/upsert_worksites.py`

```python
"""SSC/KUPID 공고를 Supabase에 무삭제 멱등 UPSERT(service_role).

- worksites: normalized_name 키로 없으면 insert, 있으면 유지.
- postings: (source, external_id) 키로 없으면 insert, 있으면 machine-owned(+content) 갱신.
- placeholder posting은 진짜 공고 첫 insert 시 삭제(예외).

실행: creds.py에 SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY 필요.
  python crawling_scripts/upsert_worksites.py            # ssc_parsed.json 적재
"""
from __future__ import annotations

import datetime
import json
import sys
from pathlib import Path

from worksite_norm import normalize_worksite_name

ROOT_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = ROOT_DIR / "data"
SSC_PARSED = DATA_DIR / "ssc_parsed.json"

UNIVERSITY_ID = 1                 # 고려대(본교)
ORG_NAME = "고려대학교(본교)"

# 크롤러가 매일 갱신해도 되는 컬럼(모집 판정계).
MACHINE_COLS = {"recruit_until", "is_active", "recruitment_period_text"}
# 사람이 웹에서 고칠 수 있는 컬럼(manual_override면 크롤러가 건너뜀).
CONTENT_COLS = {"hourly_wage", "recruit_count", "job_description", "preference_notes",
                "extra_notes", "work_period_text", "work_duration_type", "work_time_text"}


def decide_posting_update(existing: dict, parsed: dict) -> dict:
    """기존 posting 갱신 시 쓸 필드만 골라 반환. None 값은 제외."""
    upd = {c: parsed[c] for c in MACHINE_COLS if parsed.get(c) is not None}
    if not existing.get("manual_override"):
        upd.update({c: parsed[c] for c in CONTENT_COLS if parsed.get(c) is not None})
    return upd


def _or3(v):
    """eligible 값 None(파싱 미상) → 3(미상). 0(학부만/재학만)은 falsy라 `or 3` 금지."""
    return 3 if v is None else v


def _posting_fields(canonical: dict, today: datetime.date) -> dict:
    """canonical → postings 컬럼 dict(파싱 None은 그대로 둠)."""
    ru = canonical.get("recruit_until") or None
    active = bool(ru and ru >= today.isoformat())
    return {
        "source": canonical["source"],
        "external_id": canonical["external_id"],
        "source_url": canonical.get("source_url"),
        "recruit_until": ru,
        "recruit_until_estimated": False,
        "is_active": active,
        "recruitment_period_text": canonical.get("period_text"),
        "raw_text": canonical.get("raw_text"),
        "hourly_wage": canonical.get("hourly_wage"),
        "recruit_count": canonical.get("recruit_count"),
        "eligible_degree": _or3(canonical.get("eligible_degree")),
        "eligible_status": _or3(canonical.get("eligible_status")),
        "job_description": canonical.get("job_description"),
        "preference_notes": canonical.get("preference_notes"),
        "extra_notes": canonical.get("extra_notes"),
        "work_period_text": canonical.get("work_period_text"),
        "work_duration_type": canonical.get("work_duration_type") or "unknown",
        "work_time_text": canonical.get("work_time_text"),
        "is_placeholder": False,
    }


def upsert_worksite(client, canonical: dict) -> int:
    norm = normalize_worksite_name(canonical["worksite_name"])
    q = (client.table("worksites").select("id")
         .eq("university_id", UNIVERSITY_ID).eq("type", "school")
         .eq("normalized_name", norm).is_("deleted_at", "null").execute())
    if q.data:
        return q.data[0]["id"]
    ins = client.table("worksites").insert({
        "university_id": UNIVERSITY_ID, "type": "school", "location_type": "on_campus",
        "organization_name": ORG_NAME, "workplace_name": canonical["worksite_name"],
        "region": None, "normalized_name": norm,
    }).execute()
    return ins.data[0]["id"]


def upsert_posting(client, worksite_id: int, canonical: dict, today: datetime.date) -> str:
    fields = _posting_fields(canonical, today)
    q = (client.table("postings").select("id, manual_override")
         .eq("source", fields["source"]).eq("external_id", fields["external_id"])
         .limit(1).execute())
    if q.data:
        upd = decide_posting_update(q.data[0], fields)
        if upd:
            client.table("postings").update(upd).eq("id", q.data[0]["id"]).execute()
        return "updated"
    # 진짜 공고 첫 삽입 — 이 근무지의 껍데기 posting 제거(예외적 삭제).
    client.table("postings").delete().eq("worksite_id", worksite_id)\
        .eq("is_placeholder", True).execute()
    fields["worksite_id"] = worksite_id
    if canonical.get("posted_at"):
        fields["created_at"] = canonical["posted_at"]   # SSC 게시일자 보존. 없으면 키 생략→DB default now()
    client.table("postings").insert(fields).execute()
    return "inserted"


def load(client, records: list[dict], today: datetime.date | None = None) -> dict:
    today = today or datetime.date.today()
    stats = {"worksites_seen": 0, "postings_inserted": 0, "postings_updated": 0}
    for rec in records:
        wid = upsert_worksite(client, rec)
        stats["worksites_seen"] += 1
        result = upsert_posting(client, wid, rec, today)
        stats["postings_" + result] += 1
    return stats


def _make_client():
    import creds
    from supabase import create_client
    return create_client(creds.SUPABASE_URL, creds.SUPABASE_SERVICE_ROLE_KEY)


def main() -> int:
    records = json.loads(SSC_PARSED.read_text(encoding="utf-8"))
    client = _make_client()
    stats = load(client, records)
    print(f"[done] {stats}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: 순수 테스트 통과 확인**

Run: `python -m pytest crawling_scripts/test_upsert_worksites.py -v`
Expected: PASS (5 passed)

- [ ] **Step 5: requirements.txt 작성**

`crawling_scripts/requirements.txt`:
```
requests
beautifulsoup4
lxml
playwright
anthropic
openpyxl
supabase
```

- [ ] **Step 6: 멱등성 통합 검증 (수동, 실 DB 소량)**

`data/ssc_parsed.json`을 3건만 남긴 사본으로 로더를 **2회** 실행하고 row 수 불변을 확인:
```bash
python crawling_scripts/upsert_worksites.py    # 1회차: postings_inserted=3
python crawling_scripts/upsert_worksites.py    # 2회차: postings_inserted=0, postings_updated=3
```
Supabase 대시보드에서 `select count(*) from postings where source='ssc'`가 1·2회차 동일한지 확인. 200처럼 늘면 `(source, external_id)` 키 오류.

- [ ] **Step 7: 커밋**

```bash
git add crawling_scripts/upsert_worksites.py crawling_scripts/test_upsert_worksites.py crawling_scripts/requirements.txt
git commit -m "feat(ssc): service_role UPSERT 로더(무삭제·멱등·placeholder예외) + 테스트"
```

---

### Task 10: KUPID 흡수 어댑터 + normalized_name 백필

**Files:**
- Modify: `crawling_scripts/upsert_worksites.py`
- Modify: `crawling_scripts/test_upsert_worksites.py`

**Interfaces:**
- Consumes: KUPID Excel(`data/kupid_parsed_result.xlsx`, 헤더: 제목·부서명·등록일·근무장소·시급·모집인원·학부생가능·대학원생가능·재학생가능·휴학생가능·직무내용·우대조건·기타특이사항·근무기간·근무시간·모집마감일(계산)·출처URL·본문(원본)·단기여부 등)
- Produces:
  - `kupid_external_id(title: str, dept: str, reg_date: str) -> str` — `sha256("제목|부서명|등록일")[:16]`. 순수·TDD.
  - `kupid_rows_to_canonical(xlsx_path) -> list[dict]` — Excel → Task 9 canonical 스키마.
  - `backfill_normalized_names(client) -> int` — 기존 school worksites `normalized_name` 채움.
  - `main()` 확장: `--source ssc|kupid`, `--backfill`.

- [ ] **Step 1: 실패하는 테스트 추가** — `test_upsert_worksites.py`에 append

```python
from upsert_worksites import kupid_external_id


def test_kupid_external_id_stable_and_short():
    a = kupid_external_id("[물리학과] 근로", "물리학과", "2026-03-01")
    b = kupid_external_id("[물리학과] 근로", "물리학과", "2026-03-01")
    c = kupid_external_id("[물리학과] 근로", "물리학과", "2026-03-02")
    assert a == b and a != c
    assert len(a) == 16 and a.isalnum()

def test_eligible_pair_mapping():
    from upsert_worksites import eligible_pair
    assert eligible_pair("O", "O") == 2   # 둘 다
    assert eligible_pair("O", "X") == 0   # 앞만(학부/재학)
    assert eligible_pair("X", "O") == 1   # 뒤만(대학원/휴학)
    assert eligible_pair("", "") == 3     # 미상
```

- [ ] **Step 2: 실패 확인**

Run: `python -m pytest crawling_scripts/test_upsert_worksites.py -k kupid -v`
Expected: FAIL — `ImportError: cannot import name 'kupid_external_id'`

- [ ] **Step 3: 구현 추가** — `upsert_worksites.py`

상단 import 추가:
```python
import hashlib
```

함수 추가:
```python
def kupid_external_id(title: str, dept: str, reg_date: str) -> str:
    """KUPID 공고 자연키 = stable_key(제목·부서·등록일) 해시.
    detail_url(encQS)은 세션마다 바뀌어 불안정하므로 stable_key를 쓴다(spec §4.5)."""
    raw = f"{title or ''}|{dept or ''}|{reg_date or ''}"
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:16]


def _xlsx_cell(row: dict, key: str):
    v = row.get(key)
    return None if v in (None, "") else v


def _flag(v):
    """Excel 'O'/'X'/공백 → True/False/None (generate_school_migration와 동일 규칙)."""
    s = str(v or "").strip().upper()
    return True if s == "O" else False if s == "X" else None


def eligible_pair(a_ok, b_ok):
    """둘 다=2, 앞만=0, 뒤만=1, 그 외(미상)=3. (a=학부/재학, b=대학원/휴학.)"""
    a, b = _flag(a_ok), _flag(b_ok)
    if a and b:
        return 2
    if a and b is False:
        return 0
    if b and a is False:
        return 1
    return 3


def kupid_rows_to_canonical(xlsx_path) -> list[dict]:
    import openpyxl
    wb = openpyxl.load_workbook(xlsx_path, data_only=True)
    ws = wb["파싱결과"]
    headers = [c.value for c in ws[1]]
    out = []
    for r in ws.iter_rows(min_row=2, values_only=True):
        if not any(v not in (None, "") for v in r):
            continue
        row = dict(zip(headers, r))
        dept = str(row.get("부서명") or "").strip()
        if not dept:
            continue
        ru = row.get("모집마감일(계산)")
        ru_iso = ru.isoformat()[:10] if hasattr(ru, "isoformat") else (str(ru)[:10] if ru else "")
        # 등록일도 날짜 정규화 후 해시(엑셀 셀이 datetime일 수 있음 — str()면 '...00:00:00'이 섞여
        # 재export 시 external_id가 흔들려 중복 공고 발생). ru_iso와 동일 가드.
        reg = row.get("등록일")
        reg_iso = reg.isoformat()[:10] if hasattr(reg, "isoformat") else str(reg or "")
        wage = row.get("시급")
        out.append({
            "source": "kupid",
            "external_id": kupid_external_id(str(row.get("제목") or ""), dept, reg_iso),
            "worksite_name": dept,
            "title": str(row.get("제목") or ""),
            "recruit_until": ru_iso,
            "period_text": _xlsx_cell(row, "지원마감일"),
            "source_url": _xlsx_cell(row, "출처URL"),
            "raw_text": _xlsx_cell(row, "본문(원본)"),
            "hourly_wage": int(wage) if isinstance(wage, (int, float)) else None,
            "recruit_count": _xlsx_cell(row, "모집인원"),
            "eligible_degree": eligible_pair(row.get("학부생가능"), row.get("대학원생가능")),
            "eligible_status": eligible_pair(row.get("재학생가능"), row.get("휴학생가능")),
            "job_description": _xlsx_cell(row, "직무내용"),
            "preference_notes": _xlsx_cell(row, "우대조건"),
            "extra_notes": _xlsx_cell(row, "기타특이사항"),
            "work_period_text": _xlsx_cell(row, "근무기간"),
            "work_duration_type": "unknown",
            "work_time_text": _xlsx_cell(row, "근무시간"),
        })
    return out


def backfill_normalized_names(client) -> int:
    """normalized_name이 빈 school worksites를 Python 정규화로 채움(정본 동기화)."""
    rows = (client.table("worksites").select("id, workplace_name")
            .eq("type", "school").is_("normalized_name", "null")
            .is_("deleted_at", "null").execute()).data
    n = 0
    for r in rows:
        norm = normalize_worksite_name(r["workplace_name"])
        client.table("worksites").update({"normalized_name": norm}).eq("id", r["id"]).execute()
        n += 1
    return n
```

`main()` 교체:
```python
def main() -> int:
    import argparse
    ap = argparse.ArgumentParser(description="SSC/KUPID 공고 UPSERT 로더")
    ap.add_argument("--source", choices=["ssc", "kupid"], default="ssc")
    ap.add_argument("--backfill", action="store_true", help="적재 전 normalized_name 백필")
    args = ap.parse_args()
    client = _make_client()
    if args.backfill:
        print(f"[backfill] normalized_name 채움: {backfill_normalized_names(client)}건")
    if args.source == "ssc":
        records = json.loads(SSC_PARSED.read_text(encoding="utf-8"))
    else:
        records = kupid_rows_to_canonical(DATA_DIR / "kupid_parsed_result.xlsx")
    stats = load(client, records)
    print(f"[done] source={args.source} {stats}")
    return 0
```

- [ ] **Step 4: 통과 확인**

Run: `python -m pytest crawling_scripts/test_upsert_worksites.py -v`
Expected: PASS (전체)

- [ ] **Step 5: 백필 실행 (수동, 1회)**

```bash
python crawling_scripts/upsert_worksites.py --backfill --source ssc
```
Expected: `[backfill] normalized_name 채움: N건`(기존 school 근무지 수). **백필 중 unique 위반이 나면** 기존에 이미 중복 근무지가 있다는 신호 — 대시보드에서 중복 확인 후 수동 병합(리뷰 있는 쪽 유지).

- [ ] **Step 6: 커밋**

```bash
git add crawling_scripts/upsert_worksites.py crawling_scripts/test_upsert_worksites.py
git commit -m "feat(ssc): KUPID 흡수 어댑터(stable_key 해시)·normalized_name 백필"
```

---

### Task 11: wipe+reload 은퇴 + README·gitignore·creds 템플릿

**Files:**
- Modify: `crawling_scripts/generate_school_migration.py` (deprecated 배너)
- Modify: `.gitignore`
- Modify: `crawling_scripts/README.md`
- Modify: `crawling_scripts/creds.py`(로컬만, 커밋 안 됨) — 항목 안내는 README에

**Interfaces:** 없음(문서·설정).

- [ ] **Step 1: `.gitignore`에 SSC 산출물 추가**

`.gitignore`의 `kupid_last_crawl.json` 아래에 추가(산출 JSON + 로그인 세션 프로필 디렉터리 둘 다):
```
ssc_*.json
.ssc_playwright_profile/
```

- [ ] **Step 2: generate_school_migration.py에 deprecated 배너**

파일 최상단 docstring 첫 줄 위에 추가:
```python
# ⚠️ DEPRECATED(2026-07-21): wipe+reload는 매일 무인 적재와 충돌(리뷰가드·클로버링).
#    적재는 crawling_scripts/upsert_worksites.py(무삭제 UPSERT)로 이관됨.
#    이 스크립트는 기록·비상 복구용으로만 남긴다. 새 적재에 쓰지 말 것.
#    spec: docs/superpowers/specs/2026-07-21-ssc-job-crawler-design.md §5
```

- [ ] **Step 3: README.md 갱신**

`crawling_scripts/README.md`의 스크립트 목록에 추가/수정:
```markdown
- `ssc_job_crawler.py` — ★신규★ SSC(job.korea.ac.kr) 아르바이트 근로장학 크롤러(목록+상세). `--full`/`--incremental`/`--limit N`/`--auto`(무인 로그인).
- `parse_ssc.py` — SSC raw JSON → Opus 구조화 파싱 → `data/ssc_parsed.json`.
- `upsert_worksites.py` — ★신규 적재 정본★ SSC/KUPID를 service_role로 무삭제 멱등 UPSERT. `--source ssc|kupid` `--backfill`. creds.py에 `SUPABASE_URL`·`SUPABASE_SERVICE_ROLE_KEY`·`SSC_ID`·`SSC_PW` 필요.
- `worksite_norm.py` — 근무지명 정규화 순수 함수(소스 간 매칭 키).
- `generate_school_migration.py` — (DEPRECATED) wipe+reload. upsert_worksites.py로 대체.
- `run_ssc_pipeline.bat` — 매일 스케줄러용: 크롤(--incremental --auto)→파싱→적재.
```

`## 크롤러 실행` 아래에 파이프라인 항목 추가:
```markdown
## SSC 파이프라인(매일 무인)
```bash
python crawling_scripts/ssc_job_crawler.py --incremental --auto   # 1) 수집
python crawling_scripts/parse_ssc.py                              # 2) Opus 파싱
python crawling_scripts/upsert_worksites.py --source ssc          # 3) 적재
```
creds.py(gitignore)에 SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY/SSC_ID/SSC_PW. service_role은 마스터키 — git·프론트에 절대 반입 금지.
```

- [ ] **Step 4: creds.py 항목 추가 (로컬, 커밋 안 됨)**

로컬 `crawling_scripts/creds.py`에 아래를 추가(대시보드 Settings→API에서 복사):
```python
SUPABASE_URL = "https://<프로젝트>.supabase.co"
SUPABASE_SERVICE_ROLE_KEY = "eyJhbG..."   # service_role secret
SSC_ID = "<학번>"
SSC_PW = "<비밀번호>"
```
확인: `git status`에 `creds.py`가 **안 뜨는지**(gitignore 확인).

- [ ] **Step 5: 커밋**

```bash
git add .gitignore crawling_scripts/generate_school_migration.py crawling_scripts/README.md
git commit -m "chore(ssc): wipe+reload 은퇴 배너·ssc_*.json gitignore·README 갱신"
```

---

### Task 12: 매일 파이프라인 배치 + 스케줄러

**Files:**
- Create: `crawling_scripts/run_ssc_pipeline.bat`

**Interfaces:** 없음(운영 스크립트).

- [ ] **Step 1: 배치 스크립트 작성** — `crawling_scripts/run_ssc_pipeline.bat`

기존 `run_kupid_*.bat` 패턴을 따르되 3단계 순차 + 단계 실패 시 중단:
```bat
@echo off
REM SSC 매일 파이프라인: 크롤(무인)->Opus 파싱->UPSERT 적재. 실패 시 중단.
cd /d %~dp0\..
set PYTHONIOENCODING=utf-8

python crawling_scripts\ssc_job_crawler.py --incremental --auto
if errorlevel 1 goto :fail

python crawling_scripts\parse_ssc.py
if errorlevel 1 goto :fail

python crawling_scripts\upsert_worksites.py --source ssc
if errorlevel 1 goto :fail

echo [OK] SSC pipeline done %date% %time%
exit /b 0

:fail
echo [FAIL] SSC pipeline aborted %date% %time%
exit /b 1
```

- [ ] **Step 2: 스모크 실행(수동)**

`--auto` 로그인·파싱·적재가 끝까지 도는지 1회 확인:
```bash
crawling_scripts/run_ssc_pipeline.bat
```
Expected: `[OK] SSC pipeline done`. 실패 시 어느 단계 errorlevel인지 로그 확인(자동로그인 셀렉터·ANTHROPIC_API_KEY·creds 확인).

- [ ] **Step 3: Windows 작업 스케줄러 등록(수동)**

작업 스케줄러 → 작업 만들기 → 트리거: 매일 1회(예: 새벽 3시) → 동작: `crawling_scripts\run_ssc_pipeline.bat` 시작(시작 위치=저장소 루트) → "가장 높은 권한으로 실행", "사용자 로그온 여부와 무관하게 실행". 
Expected: 다음 예약 시각에 자동 실행, `data/ssc_*.json` 갱신·DB 반영.

- [ ] **Step 4: 커밋**

```bash
git add crawling_scripts/run_ssc_pipeline.bat
git commit -m "feat(ssc): 매일 파이프라인 배치(크롤->파싱->적재) 스케줄러용"
```

---

## Self-Review

**1. Spec coverage:**
- §3-① 크롤러(목록+상세) → Task 3·4·5·6 ✓
- §3-② Opus 파서 → Task 8 ✓
- §3-③ service_role UPSERT 로더 → Task 9 ✓
- §4 정규화 + §4.5 스키마 보강(정규화키·external_id·manual_override) → Task 1·7 ✓
- §5 무삭제 UPSERT·수정값 보호·placeholder 예외·KUPID 흡수 → Task 9·10 ✓
- §6 스케줄러/배치 → Task 12 ✓
- §7 service_role 보관 → Task 11(creds 안내)·Global Constraints ✓
- §8 구현 순서(0 스키마→1 크롤러→…→5 스케줄러) → Task 순서 일치(단 스키마 Task 7은 로더 Task 9 직전에 배치 — 코드 Task 1~6은 DB 불필요라 앞서도 무방) ✓
- §9 산출 파일 전부 태스크에 등장 ✓
- §10 미해결: 상세 seq→external_id=board_no로 확정(Task 2), supabase-py→requirements(Task 9), Opus 프롬프트→Task 8, manual_override UI 연기→Global/Task 7, KUPID external_id→Task 10 ✓

**2. Placeholder scan:** "TBD"/"적절히 처리" 없음. 모든 코드 스텝에 실제 코드. 세부 미확정(상세 컨테이너 셀렉터·자동로그인 폼 셀렉터)은 방어적 기본값 + fixture/실물 확인 스텝으로 명시.

**3. Type consistency:** canonical 레코드 키(`source, external_id, worksite_name, recruit_until, period_text, source_url, raw_text, hourly_wage, recruit_count, eligible_degree, eligible_status, job_description, preference_notes, extra_notes, work_period_text, work_duration_type, work_time_text`)를 Task 8(생산)·9·10(소비)에서 동일 사용. `ssc_external_id`(Task 2)↔`external_id` 필드(Task 5·9) 일치. `MACHINE_COLS`/`CONTENT_COLS`(Task 9)↔Task 10 필드 이름 일치.

**알려진 한계(구현자 유의):**
- 파서 셀렉터(Task 3 열 순서, Task 4 상세 컨테이너)와 자동로그인 폼 셀렉터(Task 6)는 실물 HTML로 확인·조정 필요 — 각 태스크에 확인 스텝 있음.
- 멱등성·백필은 실 DB 통합 검증(Task 9-6, 10-5) — 순수 로직은 단위테스트로 커버.
- KUPID `eligible_degree/status`는 Excel의 O/X 4칸을 정밀 매핑하지 않고 3(미상)으로 적재 — 필요 시 후속 개선(현 로더 계약 밖).
