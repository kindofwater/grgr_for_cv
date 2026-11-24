# 새 KUPID 포털 교내 근로장학 크롤러 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 차세대 KUPID 포털 일반공지(BO06)에서 "근로장학" 공고를 수집해 `data/kupid_workstudy_notices.json`(기존 파서 입력 스키마)으로 저장하는 크롤러를 만든다.

**Architecture:** 하이브리드 — Playwright로 수동 SSO 로그인 후 쿠키를 캡처해 `requests.Session`에 주입하고, 그 세션으로 검색 결과 목록을 GET → 암호화 encQS 페이지 링크를 순차 추적 → 각 공고 상세를 GET·파싱. 파싱 함수는 순수 함수로 분리해 저장된 HTML 픽스처로 네트워크 없이 TDD한다.

**Tech Stack:** Python 3.13, `requests`(HTTP), `beautifulsoup4`+`lxml`(HTML 파싱), `playwright`(로그인·쿠키 캡처), `pytest`(테스트). 모두 base Python에 설치돼 있음(pytest만 Task 0에서 설치).

## Global Constraints

- 수집 대상은 **BO06(일반공지)만**. 장학금공지(BO10) 제외.
- 검색어 = `근로장학` 단일, `sc=all`. 검색 URL의 encQS 고정 토큰 = `hMHVHi3u3QvCp8G06ziROMeGCw7SfX2Yy034BqtxecY%3D`.
- 출력 파일 = `data/kupid_workstudy_notices.json`. **필드·파일명을 기존 `crawling_scripts/parse_kupid.py`가 읽는 스키마와 정확히 일치**시킬 것(나중에 파싱 단계를 손대지 않기 위함).
- 이번 범위는 **크롤러(①)만**. 파싱(②)·Supabase 적재(③)는 제외.
- 응답 인코딩은 **UTF-8 고정**(`resp.encoding = "utf-8"`), 파일 입출력도 `encoding="utf-8"`.
- 원본 HTML에서 `data-url`·`href` 속성은 HTML 엔티티로 인코딩됨(`&#x2f;`=`/` 등). **반드시 BeautifulSoup로 읽어 자동 디코딩**하거나 `html.unescape()`를 쓸 것(정규식 직접 파싱 금지).
- 요청 간 딜레이 0.4초. 쿠키·자격증명은 파일·로그·git에 저장 금지(메모리 내 Session에만).
- 커밋은 각 Task 끝에서. 푸시는 하지 않음. 브랜치는 이미 정해진 대로 `main`.

---

## File Structure

- Create: `crawling_scripts/kupid_portal_crawler.py` — 크롤러 본체(순수 파서 함수 + Playwright 로그인 + 오케스트레이션 + CLI).
- Create: `crawling_scripts/test_kupid_portal_crawler.py` — pytest 테스트(픽스처 기반, 네트워크 없음).
- Create(이미 배치됨): `crawling_scripts/fixtures/list_page1.html`, `crawling_scripts/fixtures/detail_sample.html` — 실제 서버 원본 HTML 픽스처. **이미 리포에 존재**(정찰 단계에서 저장). 없으면 로그인해 재수집 필요.
- Create: `crawling_scripts/run_kupid_portal_crawler.bat` — 실행 편의 배치.
- Create: `crawling_scripts/README.md` — 폴더 역할·스크립트 목록(폴더 규칙).

`data/kupid_workstudy_notices.json`(출력)과 `data/kupid_last_crawl.json`(증분 상태)은 `.gitignore`의 `kupid_*_notices.json` 및 신규 규칙으로 커밋되지 않음.

---

## Task 0: 스캐폴딩 — pytest 설치 · 모듈 골격 · 픽스처 확인

**Files:**
- Create: `crawling_scripts/kupid_portal_crawler.py`
- Create: `crawling_scripts/test_kupid_portal_crawler.py`
- Verify: `crawling_scripts/fixtures/list_page1.html`, `crawling_scripts/fixtures/detail_sample.html`

**Interfaces:**
- Produces: 모듈 `kupid_portal_crawler`의 상수 `BASE_URL`, `BOARD_PATH`, `SEARCH_TOKEN`, `SEARCH_KEYWORD`, `FIXTURES_DIR`; 테스트가 픽스처를 읽는 헬퍼 `_fixture(name)`.

- [ ] **Step 1: pytest 설치**

Run:
```bash
python -m pip install pytest
```
Expected: `Successfully installed pytest-...` (또는 already satisfied).

- [ ] **Step 2: 픽스처 존재 확인**

Run:
```bash
python -c "from pathlib import Path; d=Path('crawling_scripts/fixtures'); print(sorted(p.name for p in d.glob('*.html')))"
```
Expected: `['detail_sample.html', 'list_page1.html']`
(없으면: 로그인된 브라우저에서 `/p/BO06?encQS=...&sc=all&sw=근로장학` 및 첫 근로장학 상세를 `requests`로 받아 두 파일로 저장.)

- [ ] **Step 3: 모듈 골격 작성**

Create `crawling_scripts/kupid_portal_crawler.py`:
```python
"""
새 차세대 KUPID 포털 일반공지(BO06) 교내 근로장학 공고 크롤러.

흐름:
1. Playwright로 Edge를 열어 사용자가 SSO 로그인.
2. 로그인 쿠키를 requests.Session에 주입.
3. "근로장학" 검색 결과 목록을 GET → 암호화 encQS 페이지 링크를 순차 추적.
4. 각 공고 상세를 GET·파싱 → data/kupid_workstudy_notices.json 저장.

실행:
    python crawling_scripts/kupid_portal_crawler.py --full
    python crawling_scripts/kupid_portal_crawler.py --incremental
    python crawling_scripts/kupid_portal_crawler.py --limit 3   # 스모크 테스트
"""
from __future__ import annotations

import argparse
import html
import json
import re
import sys
import time
from pathlib import Path
from urllib.parse import quote

import requests
from bs4 import BeautifulSoup

BASE_URL = "https://portal.korea.ac.kr"
BOARD_PATH = "/p/BO06"
SEARCH_TOKEN = "hMHVHi3u3QvCp8G06ziROMeGCw7SfX2Yy034BqtxecY%3D"
SEARCH_KEYWORD = "근로장학"

ROOT_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = ROOT_DIR / "data"
FIXTURES_DIR = Path(__file__).resolve().parent / "fixtures"
OUTPUT_FILE = DATA_DIR / "kupid_workstudy_notices.json"
STATE_FILE = DATA_DIR / "kupid_last_crawl.json"

REQUEST_DELAY_SEC = 0.4
USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36 Edg/148.0.0.0"
)
```

- [ ] **Step 4: 테스트 파일 골격 작성**

Create `crawling_scripts/test_kupid_portal_crawler.py`:
```python
from pathlib import Path

import kupid_portal_crawler as kp

FIXTURES = Path(__file__).resolve().parent / "fixtures"


def _fixture(name: str) -> str:
    return (FIXTURES / name).read_text(encoding="utf-8")


def test_fixtures_present_and_utf8():
    html = _fixture("list_page1.html")
    assert 'data-name="post_list"' in html
    assert "근로장학" in html  # UTF-8 그대로 읽히는지
```

- [ ] **Step 5: 테스트 실행(스모크)**

Run:
```bash
cd crawling_scripts && python -m pytest test_kupid_portal_crawler.py -v
```
Expected: `test_fixtures_present_and_utf8 PASSED`

- [ ] **Step 6: 커밋**

```bash
git add crawling_scripts/kupid_portal_crawler.py crawling_scripts/test_kupid_portal_crawler.py crawling_scripts/fixtures/
git commit -m "feat(crawler): KUPID 포털 크롤러 스캐폴딩 + HTML 픽스처"
```

---

## Task 1: 순수 헬퍼 — 날짜 정규화 · 안정 키 · detail_text 조립

**Files:**
- Modify: `crawling_scripts/kupid_portal_crawler.py`
- Test: `crawling_scripts/test_kupid_portal_crawler.py`

**Interfaces:**
- Produces:
  - `to_iso_date(raw: str) -> str` — `"2026.07.14"` → `"2026-07-14"`. 이미 ISO거나 파싱 실패 시 원문 반환.
  - `stable_key(row: dict) -> tuple[str, str, str]` — `(title, department, registered_date)`.
  - `build_detail_text(title: str, body: str, attachments: list[dict]) -> str` — 기존 `parse_kupid.extract_body()` 계약(맨 앞 `제목 ` 줄, 본문, `첨부파일` 마커) 충족 문자열.

- [ ] **Step 1: 실패 테스트 작성**

Append to `test_kupid_portal_crawler.py`:
```python
def test_to_iso_date_converts_dots():
    assert kp.to_iso_date("2026.07.14") == "2026-07-14"


def test_to_iso_date_passthrough_on_iso():
    assert kp.to_iso_date("2026-07-14") == "2026-07-14"


def test_to_iso_date_passthrough_on_garbage():
    assert kp.to_iso_date("") == ""


def test_stable_key_tuple():
    row = {"title": "[학사팀] 근로장학생 모집", "department": "학사팀",
           "registered_date": "2026-06-01", "views": "663"}
    assert kp.stable_key(row) == ("[학사팀] 근로장학생 모집", "학사팀", "2026-06-01")


def test_build_detail_text_satisfies_parser_contract():
    text = kp.build_detail_text(
        "[학사팀] 근로장학생 모집",
        "1. 모집인원: 1명\n2. 근무장소: 학사팀",
        [{"label": "지원서.docx", "url": "/ctt/bb/bulletin?encQS=x&fs=1"}],
    )
    assert text.startswith("제목 [학사팀] 근로장학생 모집")
    assert "1. 모집인원: 1명" in text
    assert "첨부파일" in text
    # parse_kupid.extract_body 모방: '제목 ' 줄 이후 ~ '첨부파일' 이전
    import re as _re
    m = _re.search(r"^제목 .+", text, _re.MULTILINE)
    body = text[m.end():].strip()
    body = body[: body.find("첨부파일")].strip()
    assert body.startswith("1. 모집인원: 1명")
```

- [ ] **Step 2: 실패 확인**

Run:
```bash
cd crawling_scripts && python -m pytest test_kupid_portal_crawler.py -k "iso_date or stable_key or detail_text" -v
```
Expected: FAIL (`AttributeError: module 'kupid_portal_crawler' has no attribute 'to_iso_date'`)

- [ ] **Step 3: 구현**

Append to `kupid_portal_crawler.py`:
```python
def to_iso_date(raw: str) -> str:
    raw = (raw or "").strip()
    m = re.match(r"(\d{4})[.\-](\d{2})[.\-](\d{2})", raw)
    if not m:
        return raw
    return f"{m.group(1)}-{m.group(2)}-{m.group(3)}"


def stable_key(row: dict) -> tuple[str, str, str]:
    return (row.get("title", ""), row.get("department", ""), row.get("registered_date", ""))


def build_detail_text(title: str, body: str, attachments: list[dict]) -> str:
    parts = [f"제목 {title}", "", body.strip()]
    if attachments:
        parts.append("")
        parts.append("첨부파일")
        for att in attachments:
            parts.append(att.get("label", ""))
    else:
        parts.append("")
        parts.append("첨부파일 없음")
    return "\n".join(parts).strip()
```

- [ ] **Step 4: 통과 확인**

Run:
```bash
cd crawling_scripts && python -m pytest test_kupid_portal_crawler.py -k "iso_date or stable_key or detail_text" -v
```
Expected: 5 passed

- [ ] **Step 5: 커밋**

```bash
git add crawling_scripts/kupid_portal_crawler.py crawling_scripts/test_kupid_portal_crawler.py
git commit -m "feat(crawler): 날짜 정규화·안정키·detail_text 조립 헬퍼"
```

---

## Task 2: `parse_list_page` — 목록 HTML → 공고 행 리스트

**Files:**
- Modify: `crawling_scripts/kupid_portal_crawler.py`
- Test: `crawling_scripts/test_kupid_portal_crawler.py`

**Interfaces:**
- Consumes: `to_iso_date`.
- Produces: `parse_list_page(html: str) -> list[dict]`. 각 dict 키: `title`(str), `department`(str), `registered_date`(str, ISO), `views`(str), `has_file`(bool), `detail_url`(str, 엔티티 디코딩된 절대경로 `/p/BO06?encQS=...`).

- [ ] **Step 1: 실패 테스트 작성**

Append:
```python
def test_parse_list_page_returns_20_rows():
    rows = kp.parse_list_page(_fixture("list_page1.html"))
    assert len(rows) == 20


def test_parse_list_page_first_row_fields():
    rows = kp.parse_list_page(_fixture("list_page1.html"))
    r = rows[0]
    assert "근로장학" in r["title"]
    assert r["registered_date"] == "2026-07-14"
    assert r["department"]  # 비어있지 않음
    assert r["views"].isdigit()
    assert r["has_file"] is True


def test_parse_list_page_decodes_dataurl_entities():
    rows = kp.parse_list_page(_fixture("list_page1.html"))
    for r in rows:
        assert r["detail_url"].startswith("/p/BO06?encQS=")
        assert "&#x" not in r["detail_url"]  # HTML 엔티티가 디코딩됨


def test_parse_list_page_all_rows_have_keys():
    rows = kp.parse_list_page(_fixture("list_page1.html"))
    for r in rows:
        assert set(r) >= {"title", "department", "registered_date",
                          "views", "has_file", "detail_url"}
```

- [ ] **Step 2: 실패 확인**

Run:
```bash
cd crawling_scripts && python -m pytest test_kupid_portal_crawler.py -k parse_list -v
```
Expected: FAIL (`has no attribute 'parse_list_page'`)

- [ ] **Step 3: 구현**

Append:
```python
def parse_list_page(html_text: str) -> list[dict]:
    soup = BeautifulSoup(html_text, "lxml")
    rows = []
    for item in soup.select("div.board_item"):
        span = item.select_one(".col_title .txt_title span")
        title = (span.get("title") or span.get_text(strip=True)) if span else ""
        dept_el = item.select_one(".col_cre_user_dept_name div")
        dept = (dept_el.get("title") or dept_el.get_text(strip=True)) if dept_el else ""
        date_el = item.select_one(".col_cre_dt")
        views_el = item.select_one(".col_visit_cnt")
        rows.append({
            "title": title,
            "department": dept,
            "registered_date": to_iso_date(date_el.get_text(strip=True) if date_el else ""),
            "views": views_el.get_text(strip=True) if views_el else "",
            "has_file": bool(item.select_one(".col_file_cnt button")),
            "detail_url": item.get("data-url", ""),  # bs4가 &#x2f; 등 자동 디코딩
        })
    return rows
```

- [ ] **Step 4: 통과 확인**

Run:
```bash
cd crawling_scripts && python -m pytest test_kupid_portal_crawler.py -k parse_list -v
```
Expected: 4 passed

- [ ] **Step 5: 커밋**

```bash
git add crawling_scripts/kupid_portal_crawler.py crawling_scripts/test_kupid_portal_crawler.py
git commit -m "feat(crawler): parse_list_page — 목록 행 추출"
```

---

## Task 3: `find_next_page_url` — 다음 페이지 링크(암호화 encQS) 추적

**Files:**
- Modify: `crawling_scripts/kupid_portal_crawler.py`
- Test: `crawling_scripts/test_kupid_portal_crawler.py`

**Interfaces:**
- Produces: `find_next_page_url(html: str, current_page: int) -> str | None`. 현재 페이지 다음(=current_page+1)으로 가는 절대경로 href를 반환. 블록 경계(10,20,…)에서는 `.bc-s-pageidxnext` 화살표 href를 사용. 다음 페이지가 없으면 `None`.

로직: `.page_skip` 안에서 텍스트가 `str(current_page+1)`인 `<a>`가 있으면 그 href. 없으면 `.bc-s-pageidxnext` `<a[href]>`가 있으면 그 href. 둘 다 없으면 None.

- [ ] **Step 1: 실패 테스트 작성**

Append:
```python
def test_find_next_page_url_from_fixture_page1():
    url = kp.find_next_page_url(_fixture("list_page1.html"), current_page=1)
    assert url is not None
    assert url.startswith("/p/BO06?encQS=")


def test_find_next_page_url_block_boundary_uses_arrow():
    html = '''<div class="page_skip">
      <a href="/p/BO06?encQS=P9" role="button">9</a>
      <a aria-current="page" class="on" href="javascript:;">10</a>
      <a class="bc-s-pageidxnext" href="/p/BO06?encQS=NEXTBLOCK" role="button"></a>
      <a class="bc-s-pageidxlast" href="/p/BO06?encQS=LAST" role="button"></a>
    </div>'''
    assert kp.find_next_page_url(html, current_page=10) == "/p/BO06?encQS=NEXTBLOCK"


def test_find_next_page_url_last_page_returns_none():
    html = '''<div class="page_skip">
      <a href="/p/BO06?encQS=P114" role="button">114</a>
      <a aria-current="page" class="on" href="javascript:;">115</a>
    </div>'''
    assert kp.find_next_page_url(html, current_page=115) is None


def test_find_next_page_url_mid_block_uses_number():
    html = '''<div class="page_skip">
      <a aria-current="page" class="on" href="javascript:;">3</a>
      <a href="/p/BO06?encQS=PAGE4" role="button">4</a>
      <a class="bc-s-pageidxnext" href="/p/BO06?encQS=WRONGBLOCK" role="button"></a>
    </div>'''
    assert kp.find_next_page_url(html, current_page=3) == "/p/BO06?encQS=PAGE4"
```

- [ ] **Step 2: 실패 확인**

Run:
```bash
cd crawling_scripts && python -m pytest test_kupid_portal_crawler.py -k next_page -v
```
Expected: FAIL (`has no attribute 'find_next_page_url'`)

- [ ] **Step 3: 구현**

Append:
```python
def find_next_page_url(html_text: str, current_page: int) -> str | None:
    soup = BeautifulSoup(html_text, "lxml")
    skip = soup.select_one(".page_skip")
    if not skip:
        return None
    target = str(current_page + 1)
    for a in skip.find_all("a"):
        if a.get_text(strip=True) == target and a.get("href", "").startswith("/"):
            return a["href"]
    arrow = skip.select_one("a.bc-s-pageidxnext[href^='/']")
    if arrow:
        return arrow["href"]
    return None
```

- [ ] **Step 4: 통과 확인**

Run:
```bash
cd crawling_scripts && python -m pytest test_kupid_portal_crawler.py -k next_page -v
```
Expected: 4 passed

- [ ] **Step 5: 커밋**

```bash
git add crawling_scripts/kupid_portal_crawler.py crawling_scripts/test_kupid_portal_crawler.py
git commit -m "feat(crawler): find_next_page_url — 암호화 페이지 링크 추적"
```

---

## Task 4: `parse_detail` — 상세 HTML → 본문·첨부

**Files:**
- Modify: `crawling_scripts/kupid_portal_crawler.py`
- Test: `crawling_scripts/test_kupid_portal_crawler.py`

**Interfaces:**
- Consumes: `build_detail_text`.
- Produces: `parse_detail(html: str) -> dict` — 키: `title`(str), `posted_at`(str, `YYYY-MM-DD HH:MM:SS` 또는 ""), `body`(str, 정리된 본문 텍스트), `attachments`(list[{"label","url"}]), `detail_text`(str, `build_detail_text` 결과).

- [ ] **Step 1: 실패 테스트 작성**

Append:
```python
def test_parse_detail_title_and_body():
    d = kp.parse_detail(_fixture("detail_sample.html"))
    assert "근로장학" in d["title"]
    assert "모집인원" in d["body"]
    assert d["posted_at"].startswith("2026-07-14")


def test_parse_detail_attachment():
    d = kp.parse_detail(_fixture("detail_sample.html"))
    assert len(d["attachments"]) >= 1
    att = d["attachments"][0]
    assert att["label"].endswith(".docx") or ".docx" in att["label"]
    assert "/ctt/bb/bulletin" in att["url"]
    assert "&#x" not in att["url"]


def test_parse_detail_detail_text_parser_contract():
    d = kp.parse_detail(_fixture("detail_sample.html"))
    assert d["detail_text"].startswith("제목 ")
    assert "첨부파일" in d["detail_text"]
    assert "모집인원" in d["detail_text"]
```

Note(첨부 label 정리): 화면 원문 label은 `근로장학지원_학번_성명.docx(17.85KB KB / 다운로드)` 형태다. `(` 앞까지를 파일명으로 잘라 저장한다.

- [ ] **Step 2: 실패 확인**

Run:
```bash
cd crawling_scripts && python -m pytest test_kupid_portal_crawler.py -k parse_detail -v
```
Expected: FAIL (`has no attribute 'parse_detail'`)

- [ ] **Step 3: 구현**

Append:
```python
def _clean_text(value: str) -> str:
    value = (value or "").replace("\xa0", " ")
    value = re.sub(r"[ \t]+", " ", value)
    value = re.sub(r"\n[ \t]+", "\n", value)
    value = re.sub(r"\n{3,}", "\n\n", value)
    return value.strip()


def parse_detail(html_text: str) -> dict:
    soup = BeautifulSoup(html_text, "lxml")
    view = soup.select_one(".view_board")
    title_el = view.select_one(".tit") if view else None
    title = title_el.get_text(strip=True) if title_el else ""

    meta_text = view.get_text(" ", strip=True) if view else ""
    m = re.search(r"작성일\s*(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})", meta_text)
    posted_at = m.group(1) if m else ""

    body_el = view.select_one(".text_area") if view else None
    body = _clean_text(body_el.get_text("\n", strip=True)) if body_el else ""

    attachments = []
    scope = view if view else soup
    for a in scope.select("a[href*='/ctt/bb/bulletin'], a[href*='download']"):
        label = a.get_text(strip=True)
        label = label.split("(")[0].strip()  # 파일크기/다운로드 꼬리 제거
        href = html.unescape(a.get("href", ""))
        if label and href:
            attachments.append({"label": label, "url": href})

    return {
        "title": title,
        "posted_at": posted_at,
        "body": body,
        "attachments": attachments,
        "detail_text": build_detail_text(title, body, attachments),
    }
```

- [ ] **Step 4: 통과 확인**

Run:
```bash
cd crawling_scripts && python -m pytest test_kupid_portal_crawler.py -k parse_detail -v
```
Expected: 3 passed

- [ ] **Step 5: 커밋**

```bash
git add crawling_scripts/kupid_portal_crawler.py crawling_scripts/test_kupid_portal_crawler.py
git commit -m "feat(crawler): parse_detail — 상세 본문·첨부 추출"
```

---

## Task 5: 세션 — 쿠키 주입 헬퍼(순수) + Playwright 로그인 캡처

**Files:**
- Modify: `crawling_scripts/kupid_portal_crawler.py`
- Test: `crawling_scripts/test_kupid_portal_crawler.py`

**Interfaces:**
- Produces:
  - `session_from_cookies(cookies: list[dict]) -> requests.Session` — Playwright `context.cookies()` 형식 리스트(`{name,value,domain,path,...}`)를 받아 `korea.ac.kr` 쿠키만 주입한 Session 반환. UA·Referer 헤더 설정.
  - `is_login_redirect(resp: requests.Response) -> bool` — 응답이 SSO로 튕겼거나 로그인 폼이면 True(세션 만료 감지).
  - `capture_session() -> requests.Session` — Playwright로 Edge 실행→수동 로그인 대기(Enter)→`context.cookies()`→`session_from_cookies`. (네트워크·수동이라 단위테스트 없음. 아래 단계는 코드만.)

- [ ] **Step 1: 실패 테스트 작성(순수 함수만)**

Append:
```python
def test_session_from_cookies_injects_korea_only():
    cookies = [
        {"name": "JSESSIONID", "value": "abc", "domain": "portal.korea.ac.kr", "path": "/"},
        {"name": "ssosession", "value": "xyz", "domain": ".sso.korea.ac.kr", "path": "/"},
        {"name": "junk", "value": "no", "domain": "example.com", "path": "/"},
    ]
    s = kp.session_from_cookies(cookies)
    names = {c.name for c in s.cookies}
    assert "JSESSIONID" in names
    assert "junk" not in names
    assert s.headers.get("User-Agent")


class _FakeResp:
    def __init__(self, url, text=""):
        self.url = url
        self.text = text


def test_is_login_redirect_detects_sso():
    assert kp.is_login_redirect(_FakeResp("https://sso.korea.ac.kr/svc/tk/Auth.eps")) is True


def test_is_login_redirect_false_on_board():
    resp = _FakeResp("https://portal.korea.ac.kr/p/BO06?encQS=x",
                     '<div class="board_item"></div>')
    assert kp.is_login_redirect(resp) is False
```

- [ ] **Step 2: 실패 확인**

Run:
```bash
cd crawling_scripts && python -m pytest test_kupid_portal_crawler.py -k "session_from_cookies or login_redirect" -v
```
Expected: FAIL

- [ ] **Step 3: 구현(순수 함수 + Playwright 래퍼)**

Append:
```python
def session_from_cookies(cookies: list[dict]) -> requests.Session:
    session = requests.Session()
    session.headers.update({"User-Agent": USER_AGENT, "Referer": BASE_URL + BOARD_PATH})
    for c in cookies:
        domain = (c.get("domain") or "").lstrip(".")
        if "korea.ac.kr" in domain:
            session.cookies.set(c["name"], c["value"], domain=domain, path=c.get("path", "/"))
    return session


def is_login_redirect(resp) -> bool:
    if "sso.korea.ac.kr" in getattr(resp, "url", ""):
        return True
    text = getattr(resp, "text", "") or ""
    return ("board_item" not in text) and ("아이디를 입력" in text or "Auth.eps" in text)


def capture_session() -> requests.Session:
    from playwright.sync_api import sync_playwright

    profile_dir = ROOT_DIR / ".kupid_playwright_profile"
    with sync_playwright() as p:
        try:
            context = p.chromium.launch_persistent_context(
                user_data_dir=str(profile_dir), channel="msedge", headless=False,
                viewport={"width": 1400, "height": 900})
        except Exception:
            context = p.chromium.launch_persistent_context(
                user_data_dir=str(profile_dir), headless=False,
                viewport={"width": 1400, "height": 900})
        page = context.pages[0] if context.pages else context.new_page()
        page.goto(BASE_URL + BOARD_PATH, wait_until="domcontentloaded")
        print("\n[로그인] 열린 Edge 창에서 KUPID에 로그인하세요.")
        print("일반공지 목록이 보이면 이 창으로 돌아와 Enter를 누르세요.")
        input("> ")
        cookies = context.cookies()
        context.close()
    return session_from_cookies(cookies)
```

- [ ] **Step 4: 통과 확인**

Run:
```bash
cd crawling_scripts && python -m pytest test_kupid_portal_crawler.py -k "session_from_cookies or login_redirect" -v
```
Expected: 3 passed

- [ ] **Step 5: 커밋**

```bash
git add crawling_scripts/kupid_portal_crawler.py crawling_scripts/test_kupid_portal_crawler.py
git commit -m "feat(crawler): 쿠키 주입 세션 + Playwright 로그인 캡처 + 만료감지"
```

---

## Task 6: `crawl` — 목록 순회 + 페이지 추적 + 상세 수집 (fetch 주입)

**Files:**
- Modify: `crawling_scripts/kupid_portal_crawler.py`
- Test: `crawling_scripts/test_kupid_portal_crawler.py`

**Interfaces:**
- Consumes: `parse_list_page`, `find_next_page_url`, `parse_detail`, `stable_key`, `build_search_url`.
- Produces:
  - `build_search_url(keyword: str) -> str` — 검색 첫 페이지 절대 URL.
  - `crawl(fetch, keyword=SEARCH_KEYWORD, cutoff_date=None, limit=None, on_progress=None) -> list[dict]`. `fetch(url: str) -> str`는 주입되는 HTML 취득 함수(테스트는 픽스처 dict, 운영은 세션 GET). 반환 각 dict: 목록 행 필드 + `detail_text`, `attachments_json`, `detail_url`(절대 URL), `matched_keyword`, `board`.
  - 동작: 1페이지부터 `parse_list_page` → 각 행 상세 `fetch` → `parse_detail` 병합. `find_next_page_url`로 다음 페이지. `cutoff_date`가 있으면 행 `registered_date < cutoff_date`에서 즉시 종료(목록 날짜 내림차순). `limit`이면 상세 그 개수에서 종료. 페이지 시그니처 반복 시 종료(루프 방지). 같은 실행 내 `stable_key` 중복 스킵.

- [ ] **Step 1: 실패 테스트 작성**

Append:
```python
def test_build_search_url_has_keyword_and_token():
    url = kp.build_search_url("근로장학")
    assert url.startswith("https://portal.korea.ac.kr/p/BO06?encQS=")
    assert "sc=all" in url
    assert "sw=" in url


def _make_fake_fetch():
    """1페이지(픽스처) → 상세(픽스처). 2페이지는 없음(단일 페이지로 종료)."""
    list_html = _fixture("list_page1.html")
    detail_html = _fixture("detail_sample.html")
    rows = kp.parse_list_page(list_html)

    # 목록 URL은 search URL 하나만, 이후 페이지 없음이 되도록 page_skip 제거본 사용
    single = list_html.replace('class="page_skip"', 'class="page_skip_disabled"')

    def fetch(url):
        if url == kp.build_search_url("근로장학"):
            return single
        return detail_html  # 모든 detail_url → 동일 상세 픽스처

    return fetch, rows


def test_crawl_collects_rows_with_detail_text():
    fetch, rows = _make_fake_fetch()
    out = kp.crawl(fetch, limit=3)
    assert len(out) == 3
    for r in out:
        assert r["detail_text"].startswith("제목 ")
        assert r["board"] == "일반공지"
        assert r["detail_url"].startswith("https://portal.korea.ac.kr/p/BO06?encQS=")
        assert isinstance(r["attachments_json"], str)


def test_crawl_cutoff_stops_early():
    fetch, rows = _make_fake_fetch()
    # 픽스처 1페이지 날짜는 2026-06-01 ~ 2026-07-14. cutoff를 미래로 주면 0건.
    out = kp.crawl(fetch, cutoff_date="2027-01-01")
    assert out == []
```

- [ ] **Step 2: 실패 확인**

Run:
```bash
cd crawling_scripts && python -m pytest test_kupid_portal_crawler.py -k "search_url or crawl" -v
```
Expected: FAIL

- [ ] **Step 3: 구현**

Append:
```python
def build_search_url(keyword: str = SEARCH_KEYWORD) -> str:
    return (f"{BASE_URL}{BOARD_PATH}?encQS={SEARCH_TOKEN}"
            f"&px=&sc=all&sw={quote(keyword)}&cuid=&cuname=&cudpname=")


def _abs_url(path_or_url: str) -> str:
    if path_or_url.startswith("http"):
        return path_or_url
    return BASE_URL + path_or_url


def crawl(fetch, keyword=SEARCH_KEYWORD, cutoff_date=None, limit=None, on_progress=None):
    results: list[dict] = []
    seen_keys: set = set()
    seen_page_sigs: set = set()
    url = build_search_url(keyword)
    page_no = 1

    while url:
        list_html = fetch(url)
        rows = parse_list_page(list_html)
        if not rows:
            break
        sig = "|".join(r["detail_url"] for r in rows)
        if sig in seen_page_sigs:
            break
        seen_page_sigs.add(sig)

        for row in rows:
            if cutoff_date and row["registered_date"] and row["registered_date"] < cutoff_date:
                return results
            key = stable_key(row)
            if key in seen_keys:
                continue
            seen_keys.add(key)

            detail_html = fetch(_abs_url(row["detail_url"]))
            detail = parse_detail(detail_html)
            record = dict(row)
            record["board"] = "일반공지"
            record["matched_keyword"] = keyword
            record["detail_url"] = _abs_url(row["detail_url"])
            record["detail_text"] = detail["detail_text"]
            record["attachments_json"] = json.dumps(detail["attachments"], ensure_ascii=False)
            results.append(record)
            if on_progress:
                on_progress(len(results), record)
            if limit and len(results) >= limit:
                return results

        next_path = find_next_page_url(list_html, page_no)
        url = _abs_url(next_path) if next_path else None
        page_no += 1

    return results
```

- [ ] **Step 4: 통과 확인**

Run:
```bash
cd crawling_scripts && python -m pytest test_kupid_portal_crawler.py -k "search_url or crawl" -v
```
Expected: 4 passed

- [ ] **Step 5: 전체 테스트 회귀 확인**

Run:
```bash
cd crawling_scripts && python -m pytest test_kupid_portal_crawler.py -v
```
Expected: 모든 테스트 PASS

- [ ] **Step 6: 커밋**

```bash
git add crawling_scripts/kupid_portal_crawler.py crawling_scripts/test_kupid_portal_crawler.py
git commit -m "feat(crawler): crawl — 목록 순회·페이지 추적·상세 수집(fetch 주입)"
```

---

## Task 7: CLI · 증분 상태 · JSON 병합 저장 · 실행 배치 · README

**Files:**
- Modify: `crawling_scripts/kupid_portal_crawler.py`
- Test: `crawling_scripts/test_kupid_portal_crawler.py`
- Create: `crawling_scripts/run_kupid_portal_crawler.bat`
- Create: `crawling_scripts/README.md`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: `crawl`, `capture_session`, `is_login_redirect`, `stable_key`, `build_search_url`.
- Produces:
  - `merge_into_json(path: Path, rows: list[dict]) -> list[dict]` — 기존 JSON을 `stable_key`로 병합(신규가 기존 덮어씀), 리스트 반환(저장은 호출부).
  - `load_cutoff(path: Path) -> str | None`, `save_cutoff(path: Path, rows: list[dict]) -> None` — 증분 상태(최신 `registered_date`) 로드/저장.
  - `make_session_fetch(session) -> callable` — `fetch(url)`; 딜레이·UTF-8·만료 감지 포함.
  - `main()` — argparse(`--full`/`--incremental`/`--limit N`/`--out PATH`), 로그인→crawl→병합 저장.

- [ ] **Step 1: 실패 테스트 작성(순수 함수)**

Append:
```python
def test_merge_into_json_dedupes_by_key(tmp_path):
    p = tmp_path / "out.json"
    p.write_text(json.dumps([
        {"title": "A", "department": "d", "registered_date": "2026-01-01", "views": "1"},
    ], ensure_ascii=False), encoding="utf-8")
    new = [
        {"title": "A", "department": "d", "registered_date": "2026-01-01", "views": "99"},  # 덮어씀
        {"title": "B", "department": "d", "registered_date": "2026-02-02", "views": "2"},   # 추가
    ]
    merged = kp.merge_into_json(p, new)
    by_key = {kp.stable_key(r): r for r in merged}
    assert len(merged) == 2
    assert by_key[("A", "d", "2026-01-01")]["views"] == "99"


def test_save_and_load_cutoff(tmp_path):
    p = tmp_path / "state.json"
    rows = [
        {"registered_date": "2026-06-01"},
        {"registered_date": "2026-07-14"},
        {"registered_date": "2026-05-05"},
    ]
    kp.save_cutoff(p, rows)
    assert kp.load_cutoff(p) == "2026-07-14"


def test_load_cutoff_missing_returns_none(tmp_path):
    assert kp.load_cutoff(tmp_path / "nope.json") is None
```

- [ ] **Step 2: 실패 확인**

Run:
```bash
cd crawling_scripts && python -m pytest test_kupid_portal_crawler.py -k "merge_into_json or cutoff" -v
```
Expected: FAIL

- [ ] **Step 3: 구현(헬퍼 + fetch 래퍼 + main)**

Append:
```python
def merge_into_json(path: Path, rows: list[dict]) -> list[dict]:
    existing = []
    if path.exists():
        existing = json.loads(path.read_text(encoding="utf-8"))
    by_key = {stable_key(r): r for r in existing}
    for r in rows:
        by_key[stable_key(r)] = r
    return list(by_key.values())


def load_cutoff(path: Path) -> str | None:
    if not path.exists():
        return None
    data = json.loads(path.read_text(encoding="utf-8"))
    return data.get("last_max_date")


def save_cutoff(path: Path, rows: list[dict]) -> None:
    dates = [r.get("registered_date", "") for r in rows if r.get("registered_date")]
    if not dates:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"last_max_date": max(dates)}, ensure_ascii=False), encoding="utf-8")


def make_session_fetch(session):
    def fetch(url: str) -> str:
        resp = session.get(url, timeout=20)
        resp.encoding = "utf-8"
        if is_login_redirect(resp):
            raise RuntimeError("세션 만료(로그인 필요). 다시 실행해 로그인하세요.")
        time.sleep(REQUEST_DELAY_SEC)
        return resp.text
    return fetch


def main() -> int:
    parser = argparse.ArgumentParser(description="새 KUPID 포털 근로장학 공지 크롤러")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--full", action="store_true", help="전량 수집(기본)")
    mode.add_argument("--incremental", action="store_true", help="지난 실행 이후 신규만")
    parser.add_argument("--limit", type=int, default=None, help="상세 N건만(스모크)")
    parser.add_argument("--out", default=str(OUTPUT_FILE), help="출력 JSON 경로")
    args = parser.parse_args()

    cutoff = load_cutoff(STATE_FILE) if args.incremental else None
    if cutoff:
        print(f"[증분] {cutoff} 이후 신규만 수집")

    session = capture_session()
    fetch = make_session_fetch(session)

    def progress(n, rec):
        print(f"  [{n}] {rec['registered_date']} {rec['title'][:40]}")

    try:
        rows = crawl(fetch, cutoff_date=cutoff, limit=args.limit, on_progress=progress)
    except RuntimeError as exc:
        print(f"[중단] {exc}")
        return 1

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    merged = merge_into_json(out_path, rows)
    out_path.write_text(json.dumps(merged, ensure_ascii=False, indent=2), encoding="utf-8")
    save_cutoff(STATE_FILE, merged)
    print(f"\n[완료] 이번 수집 {len(rows)}건 · 누적 {len(merged)}건 → {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: 통과 확인**

Run:
```bash
cd crawling_scripts && python -m pytest test_kupid_portal_crawler.py -v
```
Expected: 전체 PASS

- [ ] **Step 5: 실행 배치 · README · gitignore**

Create `crawling_scripts/run_kupid_portal_crawler.bat`:
```bat
@echo off
cd /d %~dp0\..
python crawling_scripts\kupid_portal_crawler.py %*
pause
```

Create `crawling_scripts/README.md`:
```markdown
# crawling_scripts — 공고 크롤러/파서/적재

근로고래 공고 데이터 파이프라인. 웹앱(`web/`)과 무관한 독립 배치 스크립트.

## 스크립트
- `kupid_portal_crawler.py` — ★현행★ 새 차세대 KUPID 포털 일반공지(BO06) "근로장학" 공고 수집 → `data/kupid_workstudy_notices.json`. 하이브리드(Playwright 로그인+requests 크롤). `--full`/`--incremental`/`--limit N`.
- `kupid_notice_crawler.py` — (레거시) 구 포털용 Playwright 클릭 크롤러. 포털 교체로 미동작. 참고용.
- `parse_kupid.py` — 수집 JSON → Haiku 구조화 파싱 → Excel.
- `kosaf_crawler.py` — 한국장학재단(KOSAF) 희망근로지 크롤러.
- `import_to_supabase.py` — 파싱 결과 Supabase 적재. ⚠️ RLS 컷오버 후 anon 키로 INSERT 막힘 — 적재 수단 재결정 필요.
- `fixtures/` — 크롤러 파서 단위테스트용 실제 서버 HTML.

## 테스트
```bash
cd crawling_scripts && python -m pytest test_kupid_portal_crawler.py -v
```

## 크롤러 실행
```bash
python crawling_scripts/kupid_portal_crawler.py --limit 3   # 스모크
python crawling_scripts/kupid_portal_crawler.py --full      # 전량
python crawling_scripts/kupid_portal_crawler.py --incremental
```
Edge 창이 열리면 KUPID 로그인 후 일반공지 목록이 보일 때 콘솔에서 Enter.
```

Modify `.gitignore` — 증분 상태 파일 무시 추가(`kupid_last_crawl.json`은 `kupid_*_notices.json` 패턴에 안 걸림):
```
kupid_last_crawl.json
```

- [ ] **Step 6: 스모크(수동, 네트워크·로그인 필요 — 실행 검증)**

Run:
```bash
python crawling_scripts/kupid_portal_crawler.py --limit 3
```
Edge에서 로그인→Enter. Expected: 콘솔에 3건 진행 로그, `data/kupid_workstudy_notices.json` 생성, 각 레코드에 한글 `title`·`detail_text`(제목/모집/첨부) 정상. 확인:
```bash
python -c "import json;d=json.load(open('data/kupid_workstudy_notices.json',encoding='utf-8'));print(len(d));print(d[0]['title']);print('첨부파일' in d[0]['detail_text'])"
```
Expected: `3` / 한글 제목 / `True`

- [ ] **Step 7: 회귀 — 기존 파서 호환 확인(선택, 파싱 단계는 이번 범위 밖이지만 스키마 계약 검증)**

Run:
```bash
python -c "
import sys; sys.path.insert(0,'crawling_scripts')
import parse_kupid, json
d=json.load(open('data/kupid_workstudy_notices.json',encoding='utf-8'))
body=parse_kupid.extract_body(d[0]['detail_text'])
print('extract_body len:', len(body)); print(body[:80])
"
```
Expected: 본문이 잘려 나오고(제목/첨부 제외) 길이 > 0.

- [ ] **Step 8: 커밋**

```bash
git add crawling_scripts/kupid_portal_crawler.py crawling_scripts/test_kupid_portal_crawler.py crawling_scripts/run_kupid_portal_crawler.bat crawling_scripts/README.md .gitignore
git commit -m "feat(crawler): CLI·증분·JSON병합 저장 + 실행배치 + README"
```

---

## Self-Review (작성자 체크)

- **스펙 커버리지**: 인증(Task 5)·검색 GET(Task 6 build_search_url)·목록 파싱(Task 2)·암호화 페이지네이션(Task 3)·상세/첨부(Task 4)·출력 스키마(Task 1 build_detail_text + Task 6/7)·증분(Task 6 cutoff + Task 7 state)·세션 만료(Task 5 is_login_redirect + Task 7 fetch)·인코딩(Global + 전 파서)·엔티티 디코딩(Task 2/4). 모두 태스크 있음.
- **플레이스홀더**: 없음. 모든 코드 스텝에 실제 코드.
- **타입 일관성**: `parse_list_page`(list[dict])→`crawl` 소비, `parse_detail`(dict: detail_text/attachments)→`crawl` 병합, `stable_key`(tuple) 전역 일관, `find_next_page_url(html,current_page)` 시그니처 Task3=Task6 일치, `session_from_cookies`/`is_login_redirect` Task5=Task7 일치.

## 미해결(범위 밖, 기록만)
- 파싱(②)·Supabase 적재(③) 미구현(사용자 확정). 적재는 RLS 인증 이슈 별도 해결 필요.
- 첫 전량 실행(~2,296건, 약 15~20분)은 60분 세션 내. 만료 시 재실행(증분이면 소량).
