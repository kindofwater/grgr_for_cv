from pathlib import Path

import requests

import kupid_portal_crawler as kp

FIXTURES = Path(__file__).resolve().parent / "fixtures"


def _fixture(name: str) -> str:
    return (FIXTURES / name).read_text(encoding="utf-8")


def test_fixtures_present_and_utf8():
    html = _fixture("list_page1.html")
    assert 'data-name="post_list"' in html
    assert "근로장학" in html  # UTF-8 그대로 읽히는지


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


def test_stable_key_ignores_only_strong_closed_title_marker():
    open_row = {
        "title": "[학사팀] 근로장학생 모집",
        "department": "학사팀",
        "registered_date": "2026-06-01",
    }
    closed_row = {
        **open_row,
        "title": "[학사팀] 근로장학생 모집 [마감]",
    }
    ambiguous = {
        **open_row,
        "title": "[학사팀] 근로장학생 모집 마감 임박",
    }
    assert kp.stable_key(open_row) == kp.stable_key(closed_row)
    assert kp.title_has_strong_closed_marker(closed_row["title"])
    assert not kp.title_has_strong_closed_marker(ambiguous["title"])
    assert kp.stable_key(open_row) != kp.stable_key(ambiguous)


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


def test_build_search_url_has_keyword_and_token():
    url = kp.build_search_url("근로장학")
    assert url.startswith("https://portal.korea.ac.kr/p/BO06?encQS=")
    assert "sc=all" in url
    assert "sw=" in url


def test_has_workstudy_term_accepts_spacing_and_student_suffix():
    assert kp.has_workstudy_term("본교 근로장학생 시급 규정에 따름") is True
    assert kp.has_workstudy_term("근로 장학 시급을 적용") is True
    assert kp.has_workstudy_term("연구조교 수당 지급") is False


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


def test_crawl_workstudy_notices_keeps_only_qualified_assistant_results():
    def row(title, dept, date, token):
        return f'''<div class="board_item" data-url="/p/BO06?encQS={token}">
          <div class="col_title"><div class="txt_title"><span title="{title}">x</span></div></div>
          <div class="col_cre_user_dept_name"><div title="{dept}">y</div></div>
          <div class="col_cre_dt">{date}</div><div class="col_visit_cnt">1</div>
        </div>'''

    standard_list = row("근로장학 행정조교 모집", "A", "2026.07.20", "STANDARD")
    assistant_list = "".join([
        row("근로장학 행정조교 모집", "A", "2026.07.20", "DUPLICATE"),
        row("단기 근무 조교 모집", "B", "2026.07.19", "QUALIFIED"),
        row("연구 조교 모집", "C", "2026.07.18", "REJECTED"),
    ])

    def detail(body):
        return f'''<div class="view_board"><div class="tit">공고</div>
          <div class="text_area">{body}</div></div>'''

    details = {
        "STANDARD": detail("근로장학 모집"),
        "QUALIFIED": detail("급여는 본교 근로장학생 시급 규정에 따름"),
        "REJECTED": detail("연구 업무를 보조하고 연구비에서 수당 지급"),
    }
    fetched_detail_tokens = []

    def fetch(url):
        if url == kp.build_search_url("근로장학"):
            return standard_list
        if url == kp.build_search_url("조교"):
            return assistant_list
        token = url.rsplit("=", 1)[-1]
        fetched_detail_tokens.append(token)
        return details[token]

    out = kp.crawl_workstudy_notices(fetch, oldest_date="2023-01-01")

    assert [r["title"] for r in out] == ["근로장학 행정조교 모집", "단기 근무 조교 모집"]
    assert [r["matched_keyword"] for r in out] == ["근로장학", "조교"]
    assert fetched_detail_tokens == ["STANDARD", "QUALIFIED", "REJECTED"]


def test_crawl_cutoff_stops_early():
    fetch, rows = _make_fake_fetch()
    # 픽스처 1페이지 날짜는 2026-06-01 ~ 2026-07-14. cutoff를 미래로 주면 0건.
    out = kp.crawl(fetch, cutoff_date="2027-01-01")
    assert out == []


def test_crawl_oldest_date_includes_boundary_and_stops_before():
    detail = _fixture("detail_sample.html")
    list_html = '''
    <div class="board_item" data-url="/p/BO06?encQS=A">
      <div class="col_title"><div class="txt_title"><span title="A">x</span></div></div>
      <div class="col_cre_user_dept_name"><div title="Dept">y</div></div>
      <div class="col_cre_dt">2024.01.02</div>
      <div class="col_visit_cnt">10</div>
    </div>
    <div class="board_item" data-url="/p/BO06?encQS=B">
      <div class="col_title"><div class="txt_title"><span title="B">x</span></div></div>
      <div class="col_cre_user_dept_name"><div title="Dept">y</div></div>
      <div class="col_cre_dt">2023.01.01</div>
      <div class="col_visit_cnt">11</div>
    </div>
    <div class="board_item" data-url="/p/BO06?encQS=C">
      <div class="col_title"><div class="txt_title"><span title="C">x</span></div></div>
      <div class="col_cre_user_dept_name"><div title="Dept">y</div></div>
      <div class="col_cre_dt">2022.12.31</div>
      <div class="col_visit_cnt">12</div>
    </div>'''
    calls = []

    def fetch(url):
        calls.append(url)
        if len(calls) == 1:
            return list_html
        return detail

    out = kp.crawl(fetch, oldest_date="2023-01-01")
    assert [r["registered_date"] for r in out] == ["2024-01-02", "2023-01-01"]
    assert len(calls) == 3


def test_crawl_resume_skips_existing_keys():
    detail = _fixture("detail_sample.html")
    list_html = '''
    <div class="board_item" data-url="/p/BO06?encQS=A">
      <div class="col_title"><div class="txt_title"><span title="A">x</span></div></div>
      <div class="col_cre_user_dept_name"><div title="Dept">y</div></div>
      <div class="col_cre_dt">2025.05.23</div>
      <div class="col_visit_cnt">10</div>
    </div>
    <div class="board_item" data-url="/p/BO06?encQS=B">
      <div class="col_title"><div class="txt_title"><span title="B">x</span></div></div>
      <div class="col_cre_user_dept_name"><div title="Dept">y</div></div>
      <div class="col_cre_dt">2025.05.22</div>
      <div class="col_visit_cnt">11</div>
    </div>'''
    calls = []
    skipped = []

    def fetch(url):
        calls.append(url)
        if len(calls) == 1:
            return list_html
        return detail

    out = kp.crawl(
        fetch,
        skip_keys={("A", "Dept", "2025-05-23")},
        on_skip=skipped.append,
    )
    assert [r["title"] for r in out] == ["B"]
    assert [r["title"] for r in skipped] == ["A"]
    assert calls == [
        kp.build_search_url("근로장학"),
        "https://portal.korea.ac.kr/p/BO06?encQS=B",
    ]


def test_crawl_follows_pagination_to_second_page():
    list1 = _fixture("list_page1.html")
    detail = _fixture("detail_sample.html")
    # page-2 URL as the site renders it (encrypted encQS extracted from page 1)
    p2_path = kp.find_next_page_url(list1, 1)
    p2_url = kp._abs_url(p2_path)
    # synthetic page 2: two distinct rows, no .page_skip so pagination terminates
    page2 = '''
    <div class="board_item" data-url="/p/BO06?encQS=PAGE2A">
      <div class="col_title"><div class="txt_title"><span title="[페이지2팀] 근로장학생 모집 A">x</span></div></div>
      <div class="col_cre_user_dept_name"><div title="페이지2팀">y</div></div>
      <div class="col_cre_dt">2026.05.01</div>
      <div class="col_visit_cnt">10</div>
    </div>
    <div class="board_item" data-url="/p/BO06?encQS=PAGE2B">
      <div class="col_title"><div class="txt_title"><span title="[페이지2팀] 근로장학생 모집 B">x</span></div></div>
      <div class="col_cre_user_dept_name"><div title="페이지2팀">y</div></div>
      <div class="col_cre_dt">2026.05.01</div>
      <div class="col_visit_cnt">11</div>
    </div>'''

    def fetch(url):
        if url == kp.build_search_url("근로장학"):
            return list1
        if url == p2_url:
            return page2
        return detail

    out = kp.crawl(fetch)
    titles = [r["title"] for r in out]
    assert len(out) == 22            # 20 (page 1) + 2 (page 2)
    assert any("페이지2팀" in t for t in titles)  # page-2 rows were actually traversed


def test_merge_into_json_dedupes_by_key(tmp_path):
    import json
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


def test_list_metadata_closes_cached_post_without_removing_body(tmp_path):
    import json
    p = tmp_path / "out.json"
    p.write_text(json.dumps([{
        "title": "[학사팀] 근로장학생 모집",
        "department": "학사팀",
        "registered_date": "2026-06-01",
        "detail_text": "기존 본문",
    }], ensure_ascii=False), encoding="utf-8")
    rows = kp.apply_list_metadata_updates(p, [{
        "title": "[학사팀] 근로장학생 모집 (마감)",
        "department": "학사팀",
        "registered_date": "2026-06-01",
    }], observed_at="2026-07-29")
    assert rows[0]["detail_text"] == "기존 본문"
    assert rows[0]["source_closed_at"] == "2026-07-29"
    assert rows[0]["source_closed_reason"] == "title_marker"


def test_save_and_load_cutoff(tmp_path):
    import json
    p = tmp_path / "state.json"
    rows = [
        {"registered_date": "2026-06-01"},
        {"registered_date": "2026-07-14"},
        {"registered_date": "2026-05-05"},
    ]
    kp.save_cutoff(p, rows)
    # 저장은 최대 등록일 그대로, 읽을 때만 여유(LOOKBACK)만큼 물러난다.
    assert json.loads(p.read_text(encoding="utf-8"))["last_max_date"] == "2026-07-14"
    assert kp.load_cutoff(p) == "2026-07-07"   # 14 - 7일


def test_load_cutoff_missing_returns_none(tmp_path):
    assert kp.load_cutoff(tmp_path / "nope.json") is None


def test_load_cutoff_lookback_matches_constant(tmp_path):
    """여유 일수는 상수와 일치해야 한다 — 상수만 바꿔도 동작이 따라오게."""
    import datetime, json
    p = tmp_path / "state.json"
    p.write_text(json.dumps({"last_max_date": "2026-03-10"}), encoding="utf-8")
    expected = (datetime.date(2026, 3, 10)
                - datetime.timedelta(days=kp.INCREMENTAL_LOOKBACK_DAYS)).isoformat()
    assert kp.load_cutoff(p) == expected


def test_load_cutoff_handles_month_boundary(tmp_path):
    """월초에서 뒤로 물러나면 이전 달로 넘어가야 한다(문자열 연산이면 깨지는 자리)."""
    import json
    p = tmp_path / "state.json"
    p.write_text(json.dumps({"last_max_date": "2026-03-03"}), encoding="utf-8")
    assert kp.load_cutoff(p) == "2026-02-24"


def test_load_cutoff_garbage_date_returns_raw(tmp_path):
    """날짜 형식이 깨졌으면 계산하지 말고 원본을 그대로 — 판정 불가 시 보수적으로."""
    import json
    p = tmp_path / "state.json"
    p.write_text(json.dumps({"last_max_date": "not-a-date"}), encoding="utf-8")
    assert kp.load_cutoff(p) == "not-a-date"


def test_load_cutoff_empty_value_returns_none(tmp_path):
    import json
    p = tmp_path / "state.json"
    p.write_text(json.dumps({"last_max_date": ""}), encoding="utf-8")
    assert kp.load_cutoff(p) is None


def test_build_detail_text_no_attachments_has_marker():
    text = kp.build_detail_text("[X] 근로장학생 모집", "본문", [])
    assert "첨부파일" in text  # extract_body 계약: 마커 존재해야 본문이 잘림


def test_parse_detail_missing_view_board_is_graceful():
    d = kp.parse_detail("<html><body>no board here</body></html>")
    assert d["title"] == "" and d["body"] == "" and d["attachments"] == []
    assert d["detail_text"].startswith("제목 ")  # 크래시 없이 계약 유지


def test_detail_is_broken_only_when_page_yielded_nothing():
    """제목·본문·첨부가 모두 비면 상세 응답이 깨진 것.

    본문만 비고 제목·첨부가 있는 공고는 '첨부에만 내용이 있는 정상 공고'다
    (ONE-STOP서비스센터 공고 등). 이를 깨진 응답으로 오판하면 안 된다.
    """
    empty_page = {"title": "", "body": "", "attachments": []}
    attachment_only = {
        "title": "[ONE-STOP서비스센터] 근로장학생 모집",
        "body": "",
        "attachments": [{"label": "(양식) 지원서.hwp", "url": "/ctt/bb/bulletin?encQS=x"}],
    }
    normal = {"title": "[학사팀] 모집", "body": "1. 모집인원 1명", "attachments": []}

    assert kp.detail_is_broken(empty_page) is True
    assert kp.detail_is_broken(attachment_only) is False
    assert kp.detail_is_broken(normal) is False


def test_crawl_skips_row_whose_detail_came_back_empty():
    """빈 껍데기 상세는 저장하지 않는다 — 빈 본문이 Sonnet까지 흘러가면 안 된다."""
    list_html = '''<div class="board_item" data-url="/p/BO06?encQS=BROKEN">
      <div class="col_title"><div class="txt_title"><span title="[학생지원팀] 근로장학생 모집">x</span></div></div>
      <div class="col_cre_user_dept_name"><div title="학생지원팀">y</div></div>
      <div class="col_cre_dt">2026.08.13</div><div class="col_visit_cnt">113</div>
      <div class="col_file_cnt"><button>1</button></div>
    </div>'''

    def fetch(url):
        if url == kp.build_search_url("근로장학"):
            return list_html
        return "<html><body></body></html>"   # 내용 없는 껍데기 응답

    skipped = []
    out = kp.crawl(fetch, oldest_date="2023-01-01",
                   on_broken_detail=lambda row: skipped.append(row["title"]))

    assert out == []
    assert skipped == ["[학생지원팀] 근로장학생 모집"]


def test_crawl_keeps_attachment_only_posting():
    """본문 없이 첨부에만 내용이 있는 공고는 그대로 수집한다."""
    list_html = '''<div class="board_item" data-url="/p/BO06?encQS=ATTONLY">
      <div class="col_title"><div class="txt_title"><span title="[ONE-STOP서비스센터] 근로장학생 모집">x</span></div></div>
      <div class="col_cre_user_dept_name"><div title="학생지원팀">y</div></div>
      <div class="col_cre_dt">2026.08.13</div><div class="col_visit_cnt">113</div>
    </div>'''
    detail_html = '''<div class="view_board"><div class="tit">[ONE-STOP서비스센터] 근로장학생 모집</div>
      <div class="text_area"></div>
      <a href="/ctt/bb/bulletin?encQS=x">(양식) 지원서.hwp (28.5KB)</a></div>'''

    def fetch(url):
        return list_html if url == kp.build_search_url("근로장학") else detail_html

    out = kp.crawl(fetch, oldest_date="2023-01-01")

    assert len(out) == 1
    assert out[0]["attachments_json"] != "[]"


def test_crawl_respects_max_pages():
    list1 = _fixture("list_page1.html")   # page 1 has a real next-page link
    detail = _fixture("detail_sample.html")
    # 목록 URL과 상세 URL은 접두사가 같으므로(/p/BO06?encQS=) 행의 data-url로 구분한다.
    detail_urls = {
        "https://portal.korea.ac.kr" + r["detail_url"]
        for r in kp.parse_list_page(list1)
    }

    def fetch(url):
        if url in detail_urls:
            return detail
        return list1  # any list-page url → same page (would loop without a cap)

    out = kp.crawl(fetch, max_pages=1)
    assert len(out) == 20  # only page 1 processed, capped before page 2


class _FakeResp2:
    def __init__(self, status, url):
        self.status_code = status
        self.url = url
        self.encoding = None
        self.text = ""
    def raise_for_status(self):
        if self.status_code >= 400:
            raise requests.HTTPError(str(self.status_code))


class _FakeSession:
    def __init__(self, resp=None, exc=None):
        self._resp = resp
        self._exc = exc
    def get(self, url, timeout=None):
        if self._exc:
            raise self._exc
        return self._resp


def test_make_session_fetch_http_error_becomes_runtimeerror():
    import pytest
    sess = _FakeSession(resp=_FakeResp2(500, "https://portal.korea.ac.kr/x"))
    fetch = kp.make_session_fetch(sess, max_retries=1)
    with pytest.raises(RuntimeError):
        fetch("https://portal.korea.ac.kr/x")


def test_make_session_fetch_connection_error_becomes_runtimeerror():
    import pytest
    sess = _FakeSession(exc=requests.ConnectionError("boom"))
    fetch = kp.make_session_fetch(sess, max_retries=1)
    with pytest.raises(RuntimeError):
        fetch("https://portal.korea.ac.kr/x")
