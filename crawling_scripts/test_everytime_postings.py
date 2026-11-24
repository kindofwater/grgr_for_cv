import pytest

from everytime_postings import (
    clean_body,
    is_recruitment,
    is_workstudy,
    merge_new,
    to_manual_record,
    to_representative,
)


def test_clean_body_turns_escaped_breaks_into_newlines():
    assert clean_body("첫 줄&lt;br />둘째 줄") == "첫 줄\n둘째 줄"


def test_clean_body_decodes_html_entities():
    assert clean_body("&amp;quot; &amp;amp; &lt;b>굵게&lt;/b>") == '" & 굵게'


def test_clean_body_keeps_link_targets_readable():
    cleaned = clean_body(
        '&lt;a href=&quot;https://forms.gle/abc&quot; target=&quot;_blank&quot;>'
        'https://forms.gle/abc&lt;/a>'
    )
    assert "https://forms.gle/abc" in cleaned
    assert "<a" not in cleaned


def test_clean_body_collapses_runs_of_blank_lines():
    assert clean_body("가&lt;br />&lt;br />&lt;br />나") == "가\n\n나"


def test_clean_body_handles_none():
    assert clean_body(None) == ""


# 근장게시판 실제 표본(2026-09 최근 20건)의 제목. 모집공고 8건 + 잡담 12건.
REAL_RECRUITMENT_TITLES = [
    "[입학처] 2027학년도 수시전형 전형보조 근로장학생 모집(10월 단기) (휴학/학위유예/수료/졸업)",
    "국제대학 행정실 학부 근로장학생 모집",
    "[법학전문대학원 행정팀] 전문석사과정 입학전형 서류접수 근로학생 모집",
    "[기술경영전문대학원] 행정실 근로장학생 모집(학부/대학원 재학생, 휴학생)",
    "고려대학교 박물관 근로장학생 모집",
    "[국제교육팀] 근로장학생 (장기) 모집 (국제동하계대학)",
    "[국제교육팀] 근로장학생(장기) 모집 (국제동하계대학)",
]

REAL_CHATTER_TITLES = [
    "근장 개인시간", "국근장 2차", "일반근로근무일지등록",
    "국근장 2차 결과 언제나옴??", "국근장 신청해놨는데", "근장", "국근장",
    "국장 2차", "학기 근로 후 방학 근로", "풀타임 근장 이어받으실 분",
    "월급언제주냐 ㅡㅡ",
    "하스 헬스장 근로 모집 (평일 오전 6:00~12:00)",
    # 실제로 게시판에 있던 마감 공고. 끝난 자리를 모집 중으로 올리면 안 된다.
    "[마감]고려대학교 생명과학부 행정실에서 성실하게 근무할 근로장학생을 모집합니다.",
]


@pytest.mark.parametrize("title", REAL_RECRUITMENT_TITLES)
def test_real_recruitment_titles_are_kept(title):
    assert is_recruitment(title) is True


@pytest.mark.parametrize("title", REAL_CHATTER_TITLES)
def test_real_chatter_titles_are_dropped(title):
    assert is_recruitment(title) is False


def test_recruitment_needs_both_the_call_and_the_workstudy_term():
    assert is_recruitment("근로장학생 구합니다") is False
    assert is_recruitment("행정실 조교 모집") is False


def test_a_closed_posting_is_not_collected():
    """[마감]이 붙은 글을 모집 중으로 올리면 학생이 끝난 자리에 지원한다."""
    assert is_recruitment(
        "[마감]고려대학교 생명과학부 행정실에서 성실하게 근무할 근로장학생을 모집합니다."
    ) is False


def test_a_closed_word_inside_a_sentence_does_not_close_a_live_posting():
    assert is_recruitment("근로장학생 모집 (선발 시 마감)") is True


def test_workstudy_title_is_detected():
    assert is_workstudy("[박물관] 근로장학생 모집", "") is True


def test_spaced_workstudy_term_is_detected():
    assert is_workstudy("행정실 근로 장학생 모집", "") is True


def test_workstudy_only_in_body_is_detected():
    assert is_workstudy("행정실 조교 모집", "교내 근로장학 프로그램입니다") is True


def test_unrelated_posting_is_rejected():
    assert is_workstudy("중고 계산기 팝니다", "거의 새것입니다") is False


def test_representative_carries_body_for_the_parser():
    raw = {
        "title": "박물관 근로장학생 모집",
        "body": "시급 10030원",
        "posted_at": "2026-09-20",
        "source_url": "https://everytime.kr/000000/v/111",
    }
    rep = to_representative(raw)
    assert rep["source"] == "everytime_manual"
    assert rep["body"] == "시급 10030원"
    assert rep["title"] == "박물관 근로장학생 모집"


PARSED = {
    "hourly_wage": 10030,
    "recruit_count": "2명",
    "eligible_degree": 0,
    "eligible_status": 2,
    "job_description": "자료 정리",
    "preference_notes": None,
    "extra_notes": None,
    "work_period_text": "3개월",
    "work_period_days": 90,
    "work_duration_type": "long",
    "work_time_text": "주 15시간",
    "recruitment_period_text": "2026-09-01~2026-09-30",
    "recruit_until": "2026-09-30",
    "work_start_date": "2026-10-01",
    "posting_department": "박물관 학예기록팀",
    "work_department": "박물관 전시실",
    "work_location": "박물관 2층",
    "worksite_evidence": "박물관 전시실에서 근무합니다",
    "office_phone": "02-3290-0000",
    "conflict_fields": [],
}

RAW = {
    "title": "[박물관] 근로장학생 모집",
    "body": "박물관 전시실에서 근무합니다. 시급 10030원",
    "posted_at": "2026-09-20",
    "source_url": "https://everytime.kr/000000/v/111",
}


def test_manual_record_never_carries_the_post_body():
    record = to_manual_record(PARSED, RAW)
    assert "body" not in record
    assert "raw_text" not in record
    assert RAW["body"] not in repr(record)


def test_manual_record_drops_fields_the_loader_rejects():
    record = to_manual_record(PARSED, RAW)
    for dropped in ("work_period_days", "worksite_evidence", "conflict_fields"):
        assert dropped not in record


def test_manual_record_renames_parser_fields_to_loader_names():
    record = to_manual_record(PARSED, RAW)
    assert record["period_text"] == "2026-09-01~2026-09-30"
    assert record["source_department"] == "박물관 학예기록팀"
    assert "recruitment_period_text" not in record
    assert "posting_department" not in record


def test_worksite_name_prefers_the_actual_work_department():
    record = to_manual_record(PARSED, RAW)
    assert record["worksite_name"] == "박물관 전시실"


def test_worksite_name_falls_back_to_posting_department():
    parsed = dict(PARSED, work_department=None)
    record = to_manual_record(parsed, RAW)
    assert record["worksite_name"] == "박물관 학예기록팀"


def test_record_without_any_department_is_rejected():
    parsed = dict(PARSED, work_department=None, posting_department=None)
    with pytest.raises(ValueError, match="worksite"):
        to_manual_record(parsed, RAW)


def test_manual_record_keeps_title_and_source_url_from_the_post():
    record = to_manual_record(PARSED, RAW)
    assert record["title"] == "[박물관] 근로장학생 모집"
    assert record["source_url"] == "https://everytime.kr/000000/v/111"
    assert record["posted_at"] == "2026-09-20"


def test_mapped_record_is_accepted_by_the_real_loader():
    from manual_postings import canonicalize

    record = canonicalize(to_manual_record(PARSED, RAW))
    assert record["source"] == "everytime_manual"
    assert record["worksite_name"] == "박물관 전시실"
    assert record["external_id"]


def test_loader_rejects_a_record_that_still_carries_the_body():
    from manual_postings import canonicalize

    with pytest.raises(ValueError, match="unsupported fields"):
        canonicalize(dict(to_manual_record(PARSED, RAW), body=RAW["body"]))


def test_merge_new_skips_a_url_already_loaded():
    existing = [{"source_url": "https://everytime.kr/000000/v/111", "title": "기존"}]
    incoming = [{"source_url": "https://everytime.kr/000000/v/111", "title": "중복"}]
    assert merge_new(existing, incoming) == existing


def test_merge_new_appends_an_unseen_url():
    existing = [{"source_url": "https://everytime.kr/000000/v/111"}]
    incoming = [{"source_url": "https://everytime.kr/000000/v/222"}]
    merged = merge_new(existing, incoming)
    assert len(merged) == 2
    assert merged[1]["source_url"].endswith("/222")
