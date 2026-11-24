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
import datetime
import html
import json
import re
import sys
import time
from pathlib import Path
from urllib.parse import quote

import requests
from bs4 import BeautifulSoup
from crawler_pipeline.network import ensure_not_blocked, polite_delay
from source_metadata import (
    title_has_strong_closed_marker,
    title_without_closed_marker,
)

BASE_URL = "https://portal.korea.ac.kr"
BOARD_PATH = "/p/BO06"
SEARCH_TOKEN = "hMHVHi3u3QvCp8G06ziROMeGCw7SfX2Yy034BqtxecY%3D"
SEARCH_KEYWORD = "근로장학"
ASSISTANT_SEARCH_KEYWORD = "조교"

ROOT_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = ROOT_DIR / "data"
FIXTURES_DIR = Path(__file__).resolve().parent / "fixtures"
OUTPUT_FILE = DATA_DIR / "kupid_workstudy_notices.json"
STATE_FILE = DATA_DIR / "kupid_last_crawl.json"
ASSISTANT_STATE_FILE = DATA_DIR / "kupid_assistant_last_crawl.json"
DEFAULT_OLDEST_DATE = "2023-01-01"
# --incremental 컷오프를 며칠 뒤로 물릴지. 과거 날짜 등록·기존 글 수정으로 컷오프보다
# 과거가 된 공고를 놓치지 않기 위한 여유. 중복은 stable_key가 걸러낸다(load_cutoff 주석 참고).
INCREMENTAL_LOOKBACK_DAYS = 7

USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36 Edg/148.0.0.0"
)

# "근로 장학"처럼 띄어 쓴 표기도 허용한다. 조교 검색 결과는 본문에 이
# 표현이 있어야만 근로장학 공고 후보로 저장한다.
WORKSTUDY_TERM_RE = re.compile(r"근로\s*장학(?:생)?")


def parse_iso_date_arg(value: str) -> str:
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", value or ""):
        return value
    raise argparse.ArgumentTypeError("expected YYYY-MM-DD")


def parse_year_arg(value: str) -> int:
    try:
        year = int(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("expected YYYY") from exc
    if year < 1900 or year > 2100:
        raise argparse.ArgumentTypeError("expected year between 1900 and 2100")
    return year


def resolve_stop_before_date(cutoff_date: str | None, oldest_date: str | None) -> str | None:
    dates = [d for d in (cutoff_date, oldest_date) if d]
    return max(dates) if dates else None


def to_iso_date(raw: str) -> str:
    raw = (raw or "").strip()
    m = re.match(r"(\d{4})[.\-](\d{2})[.\-](\d{2})", raw)
    if not m:
        return raw
    return f"{m.group(1)}-{m.group(2)}-{m.group(3)}"


def stable_key(row: dict) -> tuple[str, str, str]:
    return (
        title_without_closed_marker(row.get("title")),
        str(row.get("department") or "").strip(),
        str(row.get("registered_date") or "")[:10],
    )


def has_workstudy_term(text: str | None) -> bool:
    """'근로장학' 또는 '근로장학생' 표현(띄어쓰기 변형 포함) 여부."""
    return bool(WORKSTUDY_TERM_RE.search(text or ""))


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
        label = label.rsplit("(", 1)[0].strip()  # 파일크기/다운로드 꼬리 제거(파일명 내 괄호 보존)
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


def detail_is_broken(detail: dict) -> bool:
    """상세 응답이 기사 페이지가 아니었는지 판정한다.

    포털은 드물게 내용 없는 껍데기 HTML을 돌려준다(같은 encQS URL이 다른
    실행에서는 정상 본문을 준 사례로 확인). 이때 parse_detail은 제목·본문·
    첨부가 모두 빈 결과를 내는데, 그대로 저장하면 빈 본문이 Sonnet 파서까지
    흘러가 '의미 있는 필드 없음'으로 실패하고 3회 재시도 후 영구 소진된다.

    ⚠️ 본문만 비고 제목·첨부가 있으면 '첨부에만 내용이 있는 정상 공고'다
    (ONE-STOP서비스센터 공고 등). 셋 다 비었을 때만 깨진 응답으로 본다.
    """
    return not (
        str(detail.get("title") or "").strip()
        or str(detail.get("body") or "").strip()
        or detail.get("attachments")
    )


def build_search_url(keyword: str = SEARCH_KEYWORD) -> str:
    return (f"{BASE_URL}{BOARD_PATH}?encQS={SEARCH_TOKEN}"
            f"&px=&sc=all&sw={quote(keyword)}&cuid=&cuname=&cudpname=")


def _abs_url(path_or_url: str) -> str:
    if path_or_url.startswith("http"):
        return path_or_url
    return BASE_URL + path_or_url


def crawl(
    fetch,
    keyword=SEARCH_KEYWORD,
    cutoff_date=None,
    oldest_date=None,
    limit=None,
    on_progress=None,
    on_skip=None,
    max_pages=300,
    results=None,
    skip_keys=None,
    exclude_title_workstudy=False,
    require_workstudy_body=False,
    on_broken_detail=None,
):
    if results is None:
        results = []
    if skip_keys is None:
        skip_keys = set()
    seen_keys: set = set()
    seen_page_sigs: set = set()
    stop_before_date = resolve_stop_before_date(cutoff_date, oldest_date)
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
        page_has_new = False

        for row in rows:
            if stop_before_date and row["registered_date"] and row["registered_date"] < stop_before_date:
                return results
            if exclude_title_workstudy and has_workstudy_term(row["title"]):
                continue
            key = stable_key(row)
            if key in seen_keys:
                continue
            seen_keys.add(key)
            if key in skip_keys:
                if on_skip:
                    on_skip(row)
                continue
            page_has_new = True

            detail_html = fetch(_abs_url(row["detail_url"]))
            detail = parse_detail(detail_html)
            if detail_is_broken(detail):
                # 저장하지 않으므로 stable_key가 남지 않고, 다음 실행에서 자연히
                # 다시 시도한다. 빈 본문을 저장해 Sonnet 재시도를 태우는 것보다
                # 요청 한 건을 더 쓰는 편이 싸다.
                print(f"  [KUPID 경고] 상세 응답이 비어 건너뜀: {row['title'][:34]}")
                if on_broken_detail:
                    on_broken_detail(row)
                continue
            if require_workstudy_body and not has_workstudy_term(detail["body"]):
                continue
            record = dict(row)
            record["board"] = "일반공지"
            record["matched_keyword"] = keyword
            record["detail_url"] = _abs_url(row["detail_url"])
            record["detail_text"] = detail["detail_text"]
            record["attachments_json"] = json.dumps(detail["attachments"], ensure_ascii=False)
            record["due_date"] = ""  # 목록엔 게시기한 컬럼이 없어 통합 파서가 본문에서 추출
            if title_has_strong_closed_marker(record["title"]):
                record["source_closed_at"] = datetime.date.today().isoformat()
                record["source_closed_reason"] = "title_marker"
            results.append(record)
            if on_progress:
                on_progress(len(results), record)
            if limit is not None and len(results) >= limit:
                return results

        if skip_keys and not page_has_new:
            return results

        next_path = find_next_page_url(list_html, page_no)
        url = _abs_url(next_path) if next_path else None
        page_no += 1
        if url and page_no > max_pages:
            print(f"  [경고] max_pages({max_pages}) 도달 — 순회 중단(일부 공고 누락 가능)")
            break

    return results


def crawl_workstudy_notices(
    fetch,
    cutoff_date=None,
    assistant_cutoff_date=None,
    oldest_date=None,
    limit=None,
    on_progress=None,
    on_skip=None,
    max_pages=300,
    results=None,
    skip_keys=None,
    on_broken_detail=None,
):
    """근로장학 검색과 조교 보완 검색을 결합해 대상 공고만 수집한다.

    1) '근로장학' 검색은 기존과 동일하게 모두 수집한다.
    2) '조교' 검색에서는 제목에 근로장학 표현이 있는 행을 제외한다.
       (1번에서 이미 수집됐으므로 중복 방지.)
    3) 나머지는 상세 본문에 근로장학 표현이 있을 때만 저장한다.

    Sonnet 파서는 이 함수를 통과해 저장된 공고에만 호출된다.
    """
    if results is None:
        results = []
    if skip_keys is None:
        skip_keys = set()

    crawl(
        fetch,
        keyword=SEARCH_KEYWORD,
        cutoff_date=cutoff_date,
        oldest_date=oldest_date,
        limit=limit,
        on_progress=on_progress,
        on_skip=on_skip,
        max_pages=max_pages,
        results=results,
        skip_keys=skip_keys,
        on_broken_detail=on_broken_detail,
    )

    if limit is not None and len(results) >= limit:
        return results

    # 같은 실행에서 근로장학 검색으로 이미 추가한 공고도 조교 검색에서 건너뛴다.
    assistant_skip_keys = set(skip_keys)
    assistant_skip_keys.update(stable_key(row) for row in results)
    crawl(
        fetch,
        keyword=ASSISTANT_SEARCH_KEYWORD,
        cutoff_date=assistant_cutoff_date,
        oldest_date=oldest_date,
        limit=limit,
        on_progress=on_progress,
        on_skip=on_skip,
        max_pages=max_pages,
        results=results,
        skip_keys=assistant_skip_keys,
        exclude_title_workstudy=True,
        require_workstudy_body=True,
        on_broken_detail=on_broken_detail,
    )
    return results


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


def merge_into_json(path: Path, rows: list[dict]) -> list[dict]:
    existing = []
    if path.exists():
        existing = json.loads(path.read_text(encoding="utf-8"))
    by_key = {stable_key(r): r for r in existing}
    for r in rows:
        by_key[stable_key(r)] = r
    return list(by_key.values())


def apply_list_metadata_updates(path: Path, rows: list[dict], *,
                                observed_at: str | None = None) -> list[dict]:
    """Persist strong list-title closures without revisiting old post bodies."""
    if not path.exists():
        return []
    existing = json.loads(path.read_text(encoding="utf-8"))
    by_key = {stable_key(row): row for row in existing}
    observed_at = observed_at or datetime.date.today().isoformat()
    changed = False
    for row in rows:
        if not title_has_strong_closed_marker(row.get("title")):
            continue
        current = by_key.get(stable_key(row))
        if not current or current.get("source_closed_at"):
            continue
        current["title"] = row.get("title") or current.get("title")
        current["source_closed_at"] = observed_at
        current["source_closed_reason"] = "title_marker"
        changed = True
    if changed:
        path.write_text(
            json.dumps(existing, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
    return existing


def load_existing_keys(path: Path) -> set[tuple[str, str, str]]:
    if not path.exists():
        return set()
    existing = json.loads(path.read_text(encoding="utf-8"))
    return {stable_key(r) for r in existing}


def load_cutoff(path: Path) -> str | None:
    """증분 컷오프. 저장된 마지막 날짜에서 INCREMENTAL_LOOKBACK_DAYS만큼 뒤로 물려서 돌려준다.

    ⚠️ 여유를 두는 이유: 컷오프가 등록일 기준이라, 학교가 과거 날짜로 글을 올리거나
    기존 글을 수정해 등록일이 바뀌면 컷오프보다 과거가 되어 **영영 수집되지 않는다**.
    며칠 겹쳐 훑으면 그 구멍이 막힌다. 중복은 stable_key(제목·부서·등록일)가 걸러내므로
    손해는 목록 페이지 한두 개 더 읽는 것뿐이다(주당 신규가 평균 2건이라 무시할 수준).
    """
    if not path.exists():
        return None
    data = json.loads(path.read_text(encoding="utf-8"))
    last = data.get("last_max_date")
    if not last:
        return None
    try:
        d = datetime.date.fromisoformat(last) - datetime.timedelta(days=INCREMENTAL_LOOKBACK_DAYS)
    except ValueError:
        return last          # 날짜 형식이 깨졌으면 원본 그대로(판정 불가 시 보수적으로)
    return d.isoformat()


def save_cutoff(path: Path, rows: list[dict]) -> None:
    dates = [r.get("registered_date", "") for r in rows if r.get("registered_date")]
    if not dates:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"last_max_date": max(dates)}, ensure_ascii=False), encoding="utf-8")


def save_rows(out_path: Path, rows: list[dict]) -> list[dict]:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    merged = merge_into_json(out_path, rows)
    out_path.write_text(json.dumps(merged, ensure_ascii=False, indent=2), encoding="utf-8")
    save_cutoff(STATE_FILE, merged)
    return merged


def make_session_fetch(session, max_retries: int = 3):
    def fetch(url: str) -> str:
        for attempt in range(1, max_retries + 1):
            try:
                resp = session.get(url, timeout=20)
                ensure_not_blocked(resp, "kupid")
                resp.raise_for_status()
            except requests.RequestException as exc:
                if attempt < max_retries:
                    time.sleep(2 * attempt)
                    continue
                raise RuntimeError(f"요청 실패({url[:60]}): {exc}") from exc
            resp.encoding = "utf-8"
            if is_login_redirect(resp):
                raise RuntimeError("세션 만료(로그인 필요). 다시 실행해 로그인하세요.")
            polite_delay()
            return resp.text
    return fetch


def main() -> int:
    parser = argparse.ArgumentParser(description="새 KUPID 포털 근로장학 공지 크롤러")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--full", action="store_true", help="전량 수집(기본)")
    mode.add_argument("--incremental", action="store_true", help="지난 실행 이후 신규만")
    parser.add_argument("--limit", type=int, default=None, help="상세 N건만(스모크)")
    parser.add_argument("--out", default=str(OUTPUT_FILE), help="출력 JSON 경로")
    parser.add_argument(
        "--oldest-date",
        default=DEFAULT_OLDEST_DATE,
        type=parse_iso_date_arg,
        help="Oldest registered_date to include (YYYY-MM-DD). Default: 2023-01-01",
    )
    parser.add_argument(
        "--until-year",
        type=parse_year_arg,
        help="Shortcut for --oldest-date YYYY-01-01, e.g. --until-year 2023",
    )
    parser.add_argument("--resume-existing", action="store_true", help="Skip rows already present in --out.")
    parser.add_argument("--all-history", action="store_true", help="Disable the oldest-date stop.")
    args = parser.parse_args()
    if args.all_history and args.until_year is not None:
        parser.error("--all-history cannot be combined with --until-year")
    oldest_date = None if args.all_history else args.oldest_date
    if args.until_year is not None:
        oldest_date = f"{args.until_year:04d}-01-01"

    cutoff = load_cutoff(STATE_FILE) if args.incremental else None
    assistant_cutoff = load_cutoff(ASSISTANT_STATE_FILE) if args.incremental else None
    if cutoff:
        print(f"[증분] {cutoff} 이후 신규만 수집")
    if args.incremental and not assistant_cutoff:
        print(f"[조교 백필] {oldest_date or '전체'}부터 최초 수집")

    if oldest_date:
        print(f"[range] include notices dated {oldest_date} or newer")

    out_path = Path(args.out)
    skip_keys = load_existing_keys(out_path) if args.resume_existing else set()
    if skip_keys:
        print(f"[resume] skipping {len(skip_keys)} existing rows from {out_path}")

    try:
        session = capture_session()
    except KeyboardInterrupt:
        print("\n[stopped] interrupted before crawling; nothing to save.")
        return 130
    fetch = make_session_fetch(session)

    def progress(n, rec):
        print(f"  [{n}] {rec['registered_date']} {rec['title'][:40]}")

    skipped = 0

    def skip_progress(rec):
        nonlocal skipped
        skipped += 1
        if skipped == 1 or skipped % 20 == 0:
            print(f"  [skip {skipped}] {rec['registered_date']} {rec['title'][:40]}")

    rows: list[dict] = []
    stop_message = None
    exit_code = 0
    assistant_crawl_completed = False
    try:
        crawl_workstudy_notices(
            fetch,
            cutoff_date=cutoff,
            assistant_cutoff_date=assistant_cutoff,
            oldest_date=oldest_date,
            limit=args.limit,
            on_progress=progress,
            on_skip=skip_progress,
            results=rows,
            skip_keys=skip_keys,
        )
        assistant_crawl_completed = True
    except KeyboardInterrupt:
        stop_message = "interrupted by Ctrl+C"
        exit_code = 130
    except RuntimeError as exc:
        if not rows:
            print(f"[stopped] {exc}")
            return 1
        stop_message = str(exc)
        exit_code = 1

    merged = save_rows(out_path, rows)
    if assistant_crawl_completed and args.limit is None:
        # 조교 검색은 첫 증분 실행 때 최근 3개년을 백필한 뒤 별도 상태로 전환한다.
        # 원본 근로장학 공고까지 포함한 최대 등록일을 사용해 다음 실행의 lookback을 맞춘다.
        save_cutoff(ASSISTANT_STATE_FILE, merged)
    if stop_message:
        print(f"\n[saved partial] {len(rows)} collected, {len(merged)} total -> {out_path}")
        print(f"[stopped] {stop_message}")
        return exit_code
    print(f"\n[done] collected {len(rows)}, total {len(merged)} -> {out_path}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
