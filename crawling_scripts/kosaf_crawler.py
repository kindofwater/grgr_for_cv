"""
한국장학재단 희망근로지 크롤러
- 목록 + 상세보기 데이터를 수집해 Excel로 저장
- 실행 전: pip install requests beautifulsoup4 lxml pandas openpyxl

[쿠키 복사 방법]
DevTools → Network → jspActionSafe.do 클릭
→ Headers 탭 → Request Headers → Cookie: 옆 값 전체 복사
→ 아래 COOKIE_STRING 에 붙여넣기
"""

import re
import time
import requests
import pandas as pd
from bs4 import BeautifulSoup

BASE_URL  = "https://portal.kosaf.go.kr"
LIST_URL  = f"{BASE_URL}/CO/jspActionSafe.do"

# ───── 여기에 브라우저에서 복사한 Cookie 값을 붙여넣으세요 ─────
COOKIE_STRING = ""  # DevTools → Cookie 헤더 값 붙여넣기
CSRF_TOKEN    = ""  # DevTools → Payload → csrfTokenPortal 값 붙여넣기
USER_PARAMS   = {
    "custNo":            "",   # 장학재단 고객번호
    "scrsAplyNo":        "",   # 근로장학 신청번호 (예: J2026XXXXXXXX)
    "univCd":            "",   # 대학코드 (예: U000000057)
    "scrsYr":            "2026",
    "scrsSmtr":          "1",
    "lbrClssCd":         "02",
    "hopeLbrOgnAplyDgre": "1",
}

# creds.py 가 있으면 거기서 덮어씌움 (gitignore됨 — 개인정보 보호)
try:
    from creds import COOKIE_STRING, CSRF_TOKEN, USER_PARAMS  # noqa: F811
except ImportError:
    pass

# ────────────────────────────────────────────────────────────────────
DETAIL_URL = f"{BASE_URL}/CO/jspAction.do"
# ─────────────────────────────────────────────────────

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/148.0.0.0 Safari/537.36 Edg/148.0.0.0"
    ),
    "Referer":         LIST_URL,
    "Origin":          BASE_URL,
    "X-Requested-With": "XMLHttpRequest",
}

PAGE_SIZE  = 10    # 한 페이지 행 수
DELAY      = 0.4   # 요청 간 대기 (초)
DEBUG_HTML = False # True로 바꾸면 HTML 파일 저장 (파싱 디버깅용)
MAX_PAGES  = None  # None = 전체 수집 / 숫자 = 디버깅용 제한


# ── 세션 생성 ──────────────────────────────────────────

def create_session() -> requests.Session:
    session = requests.Session()
    session.headers.update(HEADERS)

    if not COOKIE_STRING:
        print("[오류] COOKIE_STRING 이 비어 있습니다.")
        print("   위 주석을 참고해 쿠키를 붙여넣고 다시 실행하세요.")
        raise SystemExit(1)

    for part in COOKIE_STRING.split(";"):
        part = part.strip()
        if "=" in part:
            name, _, value = part.partition("=")
            session.cookies.set(name.strip(), value.strip(), domain="portal.kosaf.go.kr")

    print("[OK] 쿠키 로드 완료")
    return session


# ── CSRF 토큰 추출 ────────────────────────────────────

def extract_csrf(html: str) -> str:
    soup = BeautifulSoup(html, "lxml")

    tag = soup.find("input", {"name": "csrfTokenPortal"})
    if tag and tag.get("value"):
        return tag["value"]

    tag = soup.find("meta", {"name": "csrfTokenPortal"})
    if tag and tag.get("content"):
        return tag["content"]

    m = re.search(r'csrfTokenPortal["\']?\s*[=:]\s*["\']([a-f0-9]{64})', html)
    if m:
        return m.group(1)

    return ""


# ── 목록 페이지 요청 ──────────────────────────────────

def fetch_list(session: requests.Session, csrf: str, page: int = 1) -> str:
    data = {
        "beanName":    "PTJHHopeLbrOgnAplySVC",
        "methodName":  "getHopeLbrOgnAplyList",
        "inputVOName": "kr.go.kosaf.portal.pt.jh.laborscholar.hopeLbrOgnAply.svc.PTJHHopeLbrOgnAplySVO",
        "forwardPage": "pt/jh/laborscholar/hopelbrognaply/PTJHHopeLbrOgnAply_02M",
        "forwardOnlyFlag": "N",
        "procType":    "chk",
        "stat":        "",
        "lbrOgnClssCd": "01",
        "page":        str(page),
        "lbrOgnNo":    "",
        "lbrScrsLaplNo": "",
        "lbrCondDtalNo": "",
        "rows":        "",
        "schLbrOgnNm": "",
        "schLbrScrsOgnClsfCd": "",
        "schBztpCd":   "",
        "schLbrScrsDmnDivCd":  "",
        "schLbrScrsDmnDivNm":  "",
        "schLbrOgnNm01": "",
        "schLbrScrsOgnClsfCd01": "",
        "schBztpCd01": "",
        "schLbrScrsDmnDivCd01": "",
        "schLbrScrsDmnDivNm01": "",
        "lbrOngClssCd02Cnt": str(PAGE_SIZE),
        "hopeLbrOgnRnk01": "0",
        "hopeLbrOgnRnk02": "0",
        "csrfTokenPortal": csrf,
        **USER_PARAMS,
    }
    resp = session.post(LIST_URL, data=data, timeout=30)
    resp.raise_for_status()
    if DEBUG_HTML:
        with open(f"debug_list_p{page}.html", "w", encoding="utf-8") as f:
            f.write(resp.text)
    return resp.text


# ── 목록 HTML 파싱 ────────────────────────────────────

def parse_list(html: str):
    soup = BeautifulSoup(html, "lxml")
    rows = []

    # 전체 건수 추출
    total = 0
    for text in soup.stripped_strings:
        m = re.search(r"총\s*([\d,]+)\s*개", text)
        if m:
            total = int(m.group(1).replace(",", ""))
            break

    # 상세보기 버튼의 onclick에서 ID 3개 추출 (중복 방지)
    seen = set()
    for el in soup.select("[onclick]"):
        # "상세보기" 버튼만 처리 (선택 버튼 등 제외)
        if "상세보기" not in el.get_text():
            continue

        onclick = el.get("onclick", "")
        # fn_openDetail(pScrsYr, pScrsSmtr, pLbrCondDtalNo, pLbrClssCd,
        #               pHopeLbrOgnAplyDgre, pLbrOgnNo, pLbrScrsLaplNo, pOpenMode)
        ids = re.findall(r"'(\d+)'", onclick)
        if len(ids) < 7:
            continue

        lbr_cond_dtal_no = ids[2]   # pLbrCondDtalNo  (행마다 고유)
        lbr_ogn_no       = ids[5]   # pLbrOgnNo       (기관 ID)
        lbr_scrs_lapl_no = ids[6]   # pLbrScrsLaplNo

        key = (lbr_ogn_no, lbr_cond_dtal_no)
        if key in seen:
            continue
        seen.add(key)

        tr = el.find_parent("tr")
        if not tr:
            continue

        tds = [td.get_text(strip=True) for td in tr.find_all("td")]
        if len(tds) < 5:
            continue

        if DEBUG_HTML and len(rows) == 0:
            print(f"    [목록 tds 샘플] {tds}")

        rows.append({
            "구분":            tds[1] if len(tds) > 1 else "",
            "근로기관명-근로지명": tds[2] if len(tds) > 2 else "",
            "근로세부유형":      tds[3] if len(tds) > 3 else "",
            "지역":            tds[4] if len(tds) > 4 else "",
            "모집(명)":        tds[5] if len(tds) > 5 else "",
            "지원(명)":        tds[6] if len(tds) > 6 else "",
            "_lbrOgnNo":      lbr_ogn_no,
            "_lbrScrsLaplNo": lbr_scrs_lapl_no,
            "_lbrCondDtalNo": lbr_cond_dtal_no,
        })

    return rows, total


# ── 상세 페이지 요청 ──────────────────────────────────

def fetch_detail(
    session: requests.Session,
    csrf: str,
    lbr_ogn_no: str,
    lbr_scrs_lapl_no: str,
    lbr_cond_dtal_no: str,
) -> str:
    data = {
        "beanName":    "PTJHHopeLbrOgnAplySVC",
        "methodName":  "getDetailedLbrOgnInfo",
        "inputVOName": "kr.go.kosaf.portal.pt.jh.laborscholar.hopeLbrOgnAply.svc.PTJHHopeLbrOgnAplySVO",
        "forwardPage": "pt/jh/laborscholar/hopelbrognaply/PTJHHopeLbrOgnAply_01P",
        "forwardOnlyFlag": "N",
        "stat":        "E",
        "lbrOgnNo":    lbr_ogn_no,
        "lbrScrsLaplNo": lbr_scrs_lapl_no,
        "lbrCondDtalNo": lbr_cond_dtal_no,
        "openMode":    "D",
        "isPopUpYn":   "Y",
        "ignoreSession": "Y",
        "hopeLbrOgnRnk": "",
        "csrfTokenPortal": csrf,
        **USER_PARAMS,
    }
    resp = session.post(DETAIL_URL, data=data, timeout=30)
    resp.raise_for_status()
    if DEBUG_HTML:
        with open(f"debug_detail_{lbr_ogn_no}.html", "w", encoding="utf-8") as f:
            f.write(resp.text)
    return resp.text


# ── 상세 HTML 파싱 ────────────────────────────────────

def parse_detail(html: str) -> dict:
    soup = BeautifulSoup(html, "lxml")
    detail = {}

    # 각 <th> 바로 다음 형제 <td>를 값으로 매핑 (이미지 셀 오염 방지)
    for th in soup.find_all("th"):
        key = th.get_text(strip=True)
        if not key:
            continue
        td = th.find_next_sibling("td")
        if td:
            detail[key] = td.get_text(" ", strip=True)

    if DEBUG_HTML:
        print(f"    [상세 추출 키] {list(detail.keys())}")

    return detail


# ── Excel 저장 ───────────────────────────────────────

def _save(rows: list, filename: str):
    df = pd.DataFrame(rows)
    df = df[[c for c in df.columns if not c.startswith("_")]]
    df.to_excel(filename, index=False)


# ── 세션 유지 ping ────────────────────────────────────

def ping(session: requests.Session):
    try:
        session.get(BASE_URL, timeout=10)
    except Exception:
        pass


# ── 메인 크롤러 ───────────────────────────────────────

def crawl():
    session = create_session()
    print(f"CSRF 토큰: {CSRF_TOKEN[:16]}...")

    csrf = CSRF_TOKEN
    all_rows = []
    total    = None
    page     = 1

    while True:
        print(f"\n[페이지 {page}] 목록 수집 중...")
        html = fetch_list(session, csrf, page)

        # 페이지마다 CSRF 갱신 시도
        new_csrf = extract_csrf(html)
        if new_csrf:
            csrf = new_csrf

        rows, page_total = parse_list(html)

        if total is None and page_total:
            total = page_total
            print(f"  → 전체 {total:,}개")

        if not rows:
            print("  → 데이터 없음. 수집 종료.")
            break

        print(f"  → {len(rows)}개 행 파싱")

        for i, row in enumerate(rows, 1):
            label = row["근로기관명-근로지명"][:25]
            print(f"  상세 [{i}/{len(rows)}] {label}...")
            try:
                detail_html = fetch_detail(
                    session, csrf,
                    row["_lbrOgnNo"],
                    row["_lbrScrsLaplNo"],
                    row["_lbrCondDtalNo"],
                )
                detail = parse_detail(detail_html)
                row.update(detail)
            except Exception as e:
                print(f"    [주의]  상세 실패: {e}")
            time.sleep(DELAY)

        all_rows.extend(rows)

        # 10페이지마다 ping + 중간 저장
        if page % 10 == 0:
            ping(session)
            _save(all_rows, f"kosaf_jobs_중간저장_p{page}.xlsx")
            print(f"  [중간저장] {len(all_rows)}개 저장됨")

        # 마지막 페이지 체크
        if MAX_PAGES and page >= MAX_PAGES:
            print(f"  [디버그] MAX_PAGES={MAX_PAGES} 도달, 중단")
            break
        if total and page * PAGE_SIZE >= total:
            break
        if len(rows) < PAGE_SIZE:
            break

        page += 1
        time.sleep(DELAY)

    if not all_rows:
        print("\n[오류] 수집된 데이터가 없습니다.")
        print("   → DEBUG_HTML = True 로 바꾸고 다시 실행해 HTML 파일을 확인하세요.")
        return

    _save(all_rows, "kosaf_jobs.xlsx")
    print(f"\n[OK] 완료! 총 {len(all_rows)}개 → kosaf_jobs.xlsx")


if __name__ == "__main__":
    crawl()
