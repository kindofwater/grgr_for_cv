"""고려대 SSC(job.korea.ac.kr) 아르바이트 게시판 근로장학 공고 크롤러.

kupid_portal_crawler.py 패턴 미러링: Playwright SSO 로그인 → requests 세션 크롤.
목록 표 + 각 공고 상세 본문 수집 → data/ssc_workstudy_raw.json.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
from pathlib import Path
from urllib.parse import quote

import requests
from bs4 import BeautifulSoup
from crawler_pipeline.network import ensure_not_blocked, polite_delay

BASE_URL = "https://job.korea.ac.kr"
LIST_PATH = "/ptfol/ncEm/job/rcrt/arb/index.do"
SEARCH_KEYWORD = "근로장학"
DEFAULT_OLDEST_DATE = "2023-01-01"

ROOT_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = ROOT_DIR / "data"
OUTPUT_FILE = DATA_DIR / "ssc_workstudy_raw.json"
STATE_FILE = DATA_DIR / "ssc_last_crawl.json"
PROFILE_DIR = ROOT_DIR / ".ssc_playwright_profile"
USER_AGENT = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
              "(KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36 Edg/148.0.0.0")

_DATE_RE = re.compile(r"(\d{4})[.\-/](\d{2})[.\-/](\d{2})")


# 상세 링크: <a href="#" onclick="global.write('55394','./view.do')"> — dataSeq가 첫 인자(공고 PK).
_DATASEQ_RE = re.compile(r"global\.write\(\s*['\"](\d+)['\"]")
VIEW_PATH = "/ptfol/ncEm/job/rcrt/arb/view.do"


def _detail_url_from_seq(seq: str) -> str:
    """dataSeq로 상세 view.do 절대 URL 조립(목록 링크 href가 '#'뿐이라 직접 만든다)."""
    return (f"{BASE_URL}{VIEW_PATH}?tabType=tot&currentPageNo=1&placeSh=0000&placeShVal=0000"
            f"&searchType=1&searchTypeVal=1&frDtSh=&toDtSh=&searchValue={quote(SEARCH_KEYWORD)}"
            f"&dataSeq={seq}&parentSeq={seq}")


def ssc_external_id(row: dict) -> str:
    """SSC 공고 자연키 = dataSeq(상세 onclick의 공고 PK). 없으면 게시번호 폴백."""
    return str(row.get("data_seq") or row.get("board_no") or "").strip()


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
        onclick = (link.get("onclick", "") if link else "")
        seq_m = _DATASEQ_RE.search(onclick)
        data_seq = seq_m.group(1) if seq_m else ""
        period_text = _cell_text(tds[5])
        start, until = parse_period(period_text)
        rows.append({
            "board_no": int(board_raw),
            "data_seq": data_seq,
            "category": _cell_text(tds[1]),
            "region_raw": _cell_text(tds[2]),
            "company_name": _cell_text(tds[3]),
            "title": (link.get_text(strip=True) if link else _cell_text(tds[4])),
            "period_text": period_text,
            "period_start": start,
            "recruit_until": until,
            "views": _cell_text(tds[6]),
            "detail_url": (_detail_url_from_seq(data_seq) if data_seq else ""),
            "source": "ssc",
        })
    return rows


# 게시일자 라벨(실물 fixture로 확정). '게시일자/게시일/작성일/등록일' 뒤 날짜.
_POSTED_AT_RE = re.compile(
    r"(?:게시일자|게시일|작성일|등록일)\s*[:：]?\s*(\d{4})[.\-/](\d{1,2})[.\-/](\d{1,2})")

# 상세 본문 컨테이너: SSC는 view 테이블(table.t_view)에 제목·회사명·모집기간·모집대상·내용 전부 담김.
_DETAIL_SELECTORS = ("table.t_view", "div.td_box", "div.ck-contentEditDiv",
                     "div.view_cont", "div.board_view", "div.view_area", "div.cont", "article")


def _view_row_value(soup, label: str) -> str:
    """상세 view 테이블에서 <th>{label}</th> 다음 <td> 텍스트(예: 등록일→'2026.07.21')."""
    for th in soup.select("table.t_view th, table th"):
        if th.get_text(strip=True) == label:
            td = th.find_next_sibling("td")
            return td.get_text(" ", strip=True) if td else ""
    return ""


# 담당자 개인정보(이름·이메일·전화)는 본문에서 제거 — 개인정보 최소수집(스펙: contact 컬럼 drop과 동일 방침).
_CONTACT_LABELS = ("담당자", "담당자 연락처", "담당자연락처")
_PII_EMAIL = re.compile(r"[\w.%+-]+\s*@\s*[\w.-]+\.[A-Za-z]{2,}")   # @ 주변 공백 허용('abc @korea.ac.kr')
_PII_PHONE = re.compile(r"0\d{1,2}[-)]\s?\d{3,4}[- ]\d{4}")


def strip_contact_pii(text: str) -> str:
    """본문 텍스트에서 이메일·전화 마스킹(내용 안에 문의처가 반복될 수 있어 안전망)."""
    text = _PII_EMAIL.sub("[이메일 제거]", text)
    text = _PII_PHONE.sub("[연락처 제거]", text)
    return text


def _clean_text(value: str) -> str:
    value = (value or "").replace("\xa0", " ")
    value = re.sub(r"[ \t]+", " ", value)
    value = re.sub(r"\n[ \t]+", "\n", value)
    value = re.sub(r"\n{3,}", "\n\n", value)
    return value.strip()


def parse_detail(html_text: str) -> dict:
    """상세 페이지 → {"body": 본문텍스트, "posted_at": "YYYY-MM-DD"|""}.

    본문에서 담당자 이름·연락처는 제거한다(개인정보 최소수집).
    """
    soup = BeautifulSoup(html_text, "lxml")
    node = None
    for sel in _DETAIL_SELECTORS:
        node = soup.select_one(sel)
        if node:
            break
    reg = _view_row_value(soup, "등록일")   # 게시일자는 제거 전에 확보
    # 담당자 라벨의 th와 바로 뒤 td만 제거 — 같은 행의 다른 칸(회사명 등)은 보존.
    if node:
        for th in list(node.select("th")):
            if th.get_text(strip=True) in _CONTACT_LABELS:
                td = th.find_next_sibling("td")
                if td:
                    td.decompose()
                th.decompose()
    body = strip_contact_pii(_clean_text(node.get_text("\n", strip=True))) if node else ""
    # 게시일자: 등록일 셀(정확) 우선 → 없으면 라벨 정규식으로 전체 텍스트 폴백.
    m = _DATE_RE.search(reg) or _POSTED_AT_RE.search(soup.get_text(" ", strip=True))
    posted_at = f"{m.group(1)}-{int(m.group(2)):02d}-{int(m.group(3)):02d}" if m else ""
    attachment_names = []
    for th in soup.select("table.t_view th, table th"):
        if th.get_text(strip=True) != "첨부파일":
            continue
        td = th.find_next_sibling("td")
        for link in td.select("a") if td else []:
            name = link.get_text(" ", strip=True)
            if name and name not in attachment_names:
                attachment_names.append(name)
        break
    return {
        "body": body,
        "posted_at": posted_at,
        "attachment_names": attachment_names,
    }


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
        page_has_new = False
        for row in rows:
            if oldest_date and row["period_start"] and row["period_start"] < oldest_date:
                return results
            ext = ssc_external_id(row)
            if ext in seen:
                continue
            seen.add(ext)
            if ext in skip_ids:
                continue
            page_has_new = True
            detail_html = fetch(_abs_url(row["detail_url"]))
            detail = parse_detail(detail_html)
            record = dict(row)
            record["external_id"] = ext
            record["detail_url"] = _abs_url(row["detail_url"])
            record["detail_text"] = detail["body"]
            record["posted_at"] = detail["posted_at"]   # 게시일자(상세에서 추출, 없으면 "")
            record["attachment_names"] = detail["attachment_names"]
            results.append(record)
            if on_progress:
                on_progress(len(results), record)
            if limit is not None and len(results) >= limit:
                return results
        if skip_ids and not page_has_new:
            return results
        page_no += 1
    return results


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
                ensure_not_blocked(resp, "ssc")
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


def capture_session(auto: bool = False) -> requests.Session:
    """Playwright(Edge)로 SSO 로그인 후 쿠키를 requests 세션에 주입.

    auto=False: 사람이 창에서 로그인 후 Enter(수동).
    auto=True : 사용자 환경변수의 포털 계정으로 SSO 폼 자동입력(무인, 2FA 없음 전제).
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
        try:
            if auto:
                _auto_login(page)
            else:
                print("\n[로그인] 열린 Edge 창에서 SSC에 로그인 후, 목록이 보이면 Enter.")
                input("> ")
            cookies = context.cookies()
        finally:
            context.close()
    return session_from_cookies(cookies)


def _dismiss_sso_popups(page) -> int:
    """sso.korea.ac.kr 로그인 폼을 덮는 공지 팝업(.noptice_popup_container)을 닫는다.
    2026-09-23부터 "멀티 LLM 서비스 오픈 안내" 팝업이 로그인 버튼 클릭을 가로막았다.
    '그만보기' 체크박스가 있으면 먼저 체크해 프로필에 억제 쿠키를 남기고 닫기 버튼을 누른다.
    닫은 팝업 수를 돌려준다."""
    closed = 0
    for popup in page.query_selector_all(".noptice_popup_container"):
        try:
            if not popup.is_visible():
                continue
            close_btn = popup.query_selector(".foot_close_btn")
            if close_btn is None:
                continue
            stop_box = popup.query_selector("input[type=checkbox]")
            if stop_box is not None:
                try:
                    stop_box.check(timeout=2000)
                except Exception:
                    pass
            close_btn.click(timeout=2000)
            closed += 1
        except Exception:
            continue
    return closed


def _confirm_pre_session_modal(page) -> None:
    """로그인 직후 '이전 세션 안내' 모달(#preSessionInfoModal)이 뜨면 확인(confirmLogin)을 누른다."""
    try:
        modal = page.query_selector("#preSessionInfoModal")
        if modal is not None and modal.is_visible():
            page.click("#preSessionInfoModal button[onclick*='confirmLogin']", timeout=3000)
    except Exception:
        pass



def _skip_password_change_nag(page) -> bool:
    """로그인 직후 뜨는 '90일 이상 비밀번호 미변경' 안내(#pwd_dthr_over_dlg)를 '다음에 변경'으로 넘긴다.
    alert("장기간 비밀번호를 변경하지 않으셨습니다…") 뒤에 이 다이얼로그가 SAML 복귀를 막는다.
    다이얼로그가 있어 눌렀으면 True."""
    # 바깥 div는 fixed 자식만 있어 높이 0(is_visible False) → 버튼 자체의 가시성으로 판정.
    try:
        btn = page.query_selector("#pwd_dthr_over_dlg a.btnNo")   # javascript:changePwdLater()
        if btn is None or not btn.is_visible():
            return False
        btn.click(timeout=3000)
        return True
    except Exception:
        return False


def _auto_login(page) -> None:
    """job 로그인 페이지 → 중앙 SSO(oauthFrm) → sso.korea.ac.kr 폼 자동입력 → doLogin() → job 복귀.
    이미 로그인된 세션이면 목록(global.write 링크)이 보이므로 그대로 통과.
    실물 SSO 폼(sso.korea.ac.kr/saml/Auth.eps): #user_id · #ipt_password · button.btn_primary(doLogin())."""
    from crawler_config import get_portal_credentials
    portal_id, portal_password = get_portal_credentials()
    try:
        page.wait_for_load_state("networkidle", timeout=8000)
    except Exception:
        pass
    if page.query_selector("a[onclick*='global.write']"):
        return  # 이미 로그인 상태(목록 보임)
    # job 로그인 페이지면 중앙 SSO로 유도(oauthFrm.submit — job 로그인 페이지의 SSO 트리거).
    if "sso.korea.ac.kr" not in (page.url or ""):
        try:
            page.evaluate("(function(){ if (typeof oauthFrm !== 'undefined') oauthFrm.submit(); })()")
        except Exception:
            try:
                page.click("a[href*='oauthFrm']", timeout=3000)
            except Exception:
                pass
        try:
            page.wait_for_url("**sso.korea.ac.kr**", timeout=15000)
        except Exception:
            pass
    # 중앙 SSO 폼: 보이는 필드 채우고 로그인 버튼 클릭 → doLogin()이 비번 암호화·제출.
    try:
        page.wait_for_selector("#user_id", timeout=10000)
        page.fill("#user_id", portal_id)
        page.fill("#ipt_password", portal_password)
        if _dismiss_sso_popups(page):
            page.wait_for_timeout(300)   # 팝업 닫힘 애니메이션 후 클릭
        page.click("button.btn_primary", timeout=5000)
        try:
            page.wait_for_url("**job.korea.ac.kr**", timeout=8000)    # SAML 복귀 = 로그인 성공
        except Exception:
            # 복귀를 막는 중간 화면 두 가지: 비밀번호 장기 미변경 안내 / 이전 세션 안내
            if _skip_password_change_nag(page):
                print("[ssc] 비밀번호 장기 미변경 안내 → '다음에 변경'으로 진행(비밀번호 변경 권장)")
            _confirm_pre_session_modal(page)
            page.wait_for_url("**job.korea.ac.kr**", timeout=25000)
        page.wait_for_load_state("networkidle", timeout=10000)
    except Exception as exc:
        raise RuntimeError(f"SSO 자동 로그인 실패(셀렉터/비번/2FA/캡차 확인): {exc}") from exc


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
    except RuntimeError as exc:
        print(f"[stopped] {exc}")
        return 1
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
