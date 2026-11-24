import re
from ssc_job_crawler import ssc_external_id, parse_period, parse_list_page, parse_detail, crawl, build_list_url


def test_ssc_external_id_prefers_data_seq():
    assert ssc_external_id({"data_seq": "55394", "board_no": 71}) == "55394"
    assert ssc_external_id({"board_no": 71}) == "71"   # data_seq 없으면 게시번호 폴백
    assert ssc_external_id({"board_no": "70"}) == "70"

def test_parse_period_range():
    assert parse_period("2026.07.20 00:00~2026.07.24 12:00") == ("2026-07-20", "2026-07-24")

def test_parse_period_dates_only():
    assert parse_period("2026.06.22~2026.06.30") == ("2026-06-22", "2026-06-30")

def test_parse_period_garbage_returns_empty():
    assert parse_period("상시모집") == ("", "")
    assert parse_period("") == ("", "")


# 실물 목록: 공고명 링크가 href='#' + onclick="global.write('<dataSeq>','./view.do')".
_MIN_LIST_HTML = """
<table class="board"><thead><tr>
<th>번호</th><th>구분</th><th>지역</th><th>회사명</th><th>공고명</th><th>모집기간</th><th>조회수</th>
</tr></thead><tbody>
<tr>
  <td>71</td><td>교내</td><td>서울</td><td>학생처 Student Success Center</td>
  <td class="title"><a href="#" onclick="global.write('55394','./view.do')">[Student Success Center] 근로장학생 모집</a></td>
  <td>2026.07.20 00:00~2026.07.24 12:00</td><td>41</td>
</tr>
<tr>
  <td>70</td><td>교내</td><td>서울</td><td>4단계 BK21 컴퓨터학교육연구단</td>
  <td class="title"><a href="#" onclick="global.write('54634','./view.do')">[4단계 BK21 컴퓨터학교육연구단] 근로장학생 모집</a></td>
  <td>2026.07.16 00:00~2026.07.22 00:00</td><td>35</td>
</tr>
</tbody></table>
"""


def test_parse_list_page_extracts_rows():
    rows = parse_list_page(_MIN_LIST_HTML)
    assert len(rows) == 2
    r = rows[0]
    assert r["board_no"] == 71
    assert r["data_seq"] == "55394"
    assert ssc_external_id(r) == "55394"          # external_id = dataSeq
    assert r["category"] == "교내"
    assert r["region_raw"] == "서울"
    assert r["company_name"] == "학생처 Student Success Center"
    assert r["title"] == "[Student Success Center] 근로장학생 모집"
    assert r["period_start"] == "2026-07-20"
    assert r["recruit_until"] == "2026-07-24"
    assert "view.do" in r["detail_url"] and "dataSeq=55394" in r["detail_url"]
    assert "parentSeq=55394" in r["detail_url"]
    assert r["source"] == "ssc"

def test_parse_list_page_empty_table():
    assert parse_list_page("<table><tbody></tbody></table>") == []


# 실물 상세: <table class="t_view">에 <th>라벨</th><td>값</td>. 본문은 div.ck-contentEditDiv, 게시일자는 '등록일' 셀.
# 담당자 이름·연락처 행은 파서가 제거해야 한다(개인정보 최소수집).
_MIN_DETAIL_HTML = """
<div class="table_wrap"><table class="table t_view"><tbody>
<tr><th>제목</th><td colspan="3">[테스트부서] 근로장학생 모집</td></tr>
<tr><th>회사명</th><td>테스트부서</td><th>담당자</th><td>홍길동</td></tr>
<tr><th>담당자 연락처</th><td colspan="3">이메일 : test@korea.ac.kr 사무실 번호 : 02-3290-1144</td></tr>
<tr><th>모집기간</th><td>2026.07.20 00:00 ~2026.07.24 12:00</td><th>근무지역</th><td>서울</td></tr>
<tr><th>아르바이트 구분</th><td>교내</td><th>등록일</th><td>2026.07.20</td></tr>
<tr><th>내용</th><td colspan="3"><div class="ck-contentEditDiv">
  <p>1. 모집인원: 2명</p><p>2. 급여: 시급 9,860원</p>
  <p>3. 근무시간: 주 15시간</p><p>4. 지원자격: 학부 재학생</p>
  <p>문의: test@korea.ac.kr</p>
</div></td></tr>
</tbody></table></div>
"""


def test_parse_detail_extracts_body_and_posted_at():
    d = parse_detail(_MIN_DETAIL_HTML)
    assert "모집인원" in d["body"]
    assert "9,860" in d["body"]
    assert d["posted_at"] == "2026-07-20"          # 등록일 셀에서 추출

def test_parse_detail_strips_contact_pii():
    d = parse_detail(_MIN_DETAIL_HTML)
    assert "홍길동" not in d["body"]                # 담당자 이름 제거
    assert "test@korea.ac.kr" not in d["body"]      # 이메일 제거(담당자 행 + 내용 문의 둘 다)
    assert "3290-1144" not in d["body"]             # 전화 제거
    assert "테스트부서" in d["body"]                 # 같은 행의 회사명은 보존

def test_parse_detail_missing_container_returns_empty():
    d = parse_detail("<html><body></body></html>")
    assert d["body"] == ""
    assert d["attachment_names"] == []


def test_parse_detail_extracts_attachment_names():
    html = """
    <table class="t_view"><tbody><tr>
      <th>첨부파일</th><td><ul class="ul_file">
        <li><a href="/download/1">지원서 양식.hwp</a></li>
        <li><a href="/download/2">안내문.pdf</a></li>
      </ul></td>
    </tr></tbody></table>
    """
    assert parse_detail(html)["attachment_names"] == ["지원서 양식.hwp", "안내문.pdf"]

def test_parse_detail_no_date_returns_empty_posted_at():
    d = parse_detail('<table class="t_view"><tbody><tr><th>제목</th><td>공고</td></tr></tbody></table>')
    assert d["posted_at"] == ""

def test_parse_detail_posted_at_label_fallback():
    # table 밖 라벨(작성일 등)도 정규식 폴백으로 잡는다.
    html = '<div class="view_cont">작성일: 2026.05.15 근무내용: 도서정리</div>'
    assert parse_detail(html)["posted_at"] == "2026-05-15"


def _fake_fetch_factory(pages: dict[int, str], detail_html: str):
    """currentPageNo→목록HTML 매핑. 상세(view.do) URL은 전부 detail_html 반환."""
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
    assert "모집인원" in rows[0]["detail_text"]
    assert rows[0]["posted_at"] == "2026-07-20"
    assert rows[0]["attachment_names"] == []

def test_crawl_stops_at_oldest_date():
    # period_start 2026-07-20, 2026-07-16 — oldest 2026-07-18이면 첫 행만 남고 둘째서 중단
    fetch = _fake_fetch_factory({1: _MIN_LIST_HTML}, _MIN_DETAIL_HTML)
    rows = crawl(fetch, oldest_date="2026-07-18")
    assert [r["board_no"] for r in rows] == [71]

def test_crawl_skips_known_ids():
    # skip_ids는 external_id(dataSeq) 기준 — 55394를 스킵하면 둘째(board 70)만 남는다.
    fetch = _fake_fetch_factory({1: _MIN_LIST_HTML, 2: "<table><tbody></tbody></table>"}, _MIN_DETAIL_HTML)
    rows = crawl(fetch, skip_ids={"55394"})
    assert [r["board_no"] for r in rows] == [70]

def test_crawl_limit():
    fetch = _fake_fetch_factory({1: _MIN_LIST_HTML}, _MIN_DETAIL_HTML)
    rows = crawl(fetch, limit=1)
    assert len(rows) == 1


from ssc_job_crawler import merge_into_json


def test_merge_dedups_by_external_id():
    existing = [{"external_id": "55394", "views": "10"}]
    new = [{"external_id": "55394", "views": "41"}, {"external_id": "54634", "views": "35"}]
    merged = merge_into_json(existing, new)
    by = {r["external_id"]: r for r in merged}
    assert set(by) == {"54634", "55394"}
    assert by["55394"]["views"] == "41"   # 새 값이 이김


# --- SSO 공지 팝업 처리 -------------------------------------------------------
# sso.korea.ac.kr 로그인 폼 위에 공지 팝업(.noptice_popup_container, "14일동안 그만보기"
# 체크박스 + .foot_close_btn 닫기)이 뜨면 로그인 버튼 클릭이 가로막힌다(2026-09-23~).

class _FakeEl:
    def __init__(self, visible=True, children=None):
        self._visible = visible
        self._children = children or {}
        self.clicked = 0
        self.checked = 0

    def is_visible(self):
        return self._visible

    def query_selector(self, sel):
        return self._children.get(sel)

    def click(self, **kw):
        self.clicked += 1

    def check(self, **kw):
        self.checked += 1


class _FakePage:
    def __init__(self, popups):
        self._popups = popups

    def query_selector_all(self, sel):
        assert sel == ".noptice_popup_container"
        return self._popups


def test_dismiss_sso_popups_clicks_close_on_visible_popup():
    from ssc_job_crawler import _dismiss_sso_popups
    close = _FakeEl()
    stop = _FakeEl()
    popup = _FakeEl(visible=True, children={".foot_close_btn": close, "input[type=checkbox]": stop})
    assert _dismiss_sso_popups(_FakePage([popup])) == 1
    assert stop.checked == 1      # 그만보기 체크 → 프로필에 14일 억제 쿠키
    assert close.clicked == 1


def test_dismiss_sso_popups_ignores_hidden_popup():
    from ssc_job_crawler import _dismiss_sso_popups
    close = _FakeEl()
    hidden = _FakeEl(visible=False, children={".foot_close_btn": close})
    assert _dismiss_sso_popups(_FakePage([hidden])) == 0
    assert close.clicked == 0


def test_dismiss_sso_popups_without_checkbox_still_closes():
    from ssc_job_crawler import _dismiss_sso_popups
    close = _FakeEl()
    popup = _FakeEl(visible=True, children={".foot_close_btn": close})
    assert _dismiss_sso_popups(_FakePage([popup])) == 1
    assert close.clicked == 1


# --- 비밀번호 장기 미변경 안내(90일) 다이얼로그 ---------------------------------
# 로그인 직후 #pwd_dthr_over_dlg("비밀번호 재설정 / 다음에 변경")가 SAML 복귀를 막는다.

class _NagPage:
    # 바깥 #pwd_dthr_over_dlg는 fixed 자식만 있어 높이 0이므로 버튼(a.btnNo) 가시성으로 판정한다.
    def __init__(self, btn):
        self._btn = btn

    def query_selector(self, sel):
        assert sel == "#pwd_dthr_over_dlg a.btnNo"
        return self._btn


def test_skip_password_change_nag_clicks_later_when_visible():
    from ssc_job_crawler import _skip_password_change_nag
    btn = _FakeEl(visible=True)
    assert _skip_password_change_nag(_NagPage(btn)) is True
    assert btn.clicked == 1


def test_skip_password_change_nag_noop_when_absent():
    from ssc_job_crawler import _skip_password_change_nag
    assert _skip_password_change_nag(_NagPage(None)) is False


def test_skip_password_change_nag_noop_when_hidden():
    from ssc_job_crawler import _skip_password_change_nag
    btn = _FakeEl(visible=False)
    assert _skip_password_change_nag(_NagPage(btn)) is False
    assert btn.clicked == 0
