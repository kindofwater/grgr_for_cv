import pytest

from everytime_parse import parse_and_store

POST = {
    "article_id": "111",
    "title": "[박물관] 근로장학생 모집",
    "body": "시급 10,400원\n근무기간 3개월",
    "posted_at": "2026-09-18",
    "source_url": "https://everytime.kr/496548/v/111",
}

PARSED = {
    "hourly_wage": 10400,
    "job_description": "자료 정리",
    "work_period_text": "3개월",
    "posting_department": "박물관 학예기록팀",
    "work_department": None,
    "work_period_days": 90,
    "conflict_fields": [],
}


def fake_parse(_representative):
    return dict(PARSED)


def test_parsed_post_becomes_a_loader_ready_record():
    [record] = parse_and_store([POST], existing=[], parse=fake_parse)
    assert record["worksite_name"] == "박물관 학예기록팀"
    assert record["hourly_wage"] == 10400
    assert record["source_url"] == POST["source_url"]


def test_the_post_body_never_reaches_the_stored_record():
    [record] = parse_and_store([POST], existing=[], parse=fake_parse)
    assert POST["body"] not in repr(record)
    assert "body" not in record


def test_a_hand_entered_post_is_matched_by_title_not_by_url():
    """손으로 넣은 기록의 source_url은 학과 홈페이지나 신청 폼을 가리킨다.

    에타 글 주소와 절대 일치하지 않으므로 URL만 보면 중복을 놓친다.
    """
    calls = []

    def counting_parse(rep):
        calls.append(rep)
        return dict(PARSED)

    existing = [{
        "title": "[박물관] 근로장학생 모집",
        "source_url": "https://int.korea.ac.kr/kuis_ko/under/forms.do?articleNo=253255",
        "posted_at": "2026-09-16",
    }]
    assert parse_and_store([POST], existing=existing, parse=counting_parse) == []
    assert calls == []


def test_a_closed_marker_does_not_hide_an_already_loaded_post():
    existing = [{"title": "[마감] [박물관] 근로장학생 모집", "posted_at": "2026-09-16"}]
    assert parse_and_store([POST], existing=existing, parse=fake_parse) == []


def test_spacing_differences_in_a_title_still_count_as_the_same_post():
    existing = [{"title": "[박물관]근로장학생  모집", "posted_at": "2026-09-16"}]
    assert parse_and_store([POST], existing=existing, parse=fake_parse) == []


def test_the_same_title_a_semester_later_is_a_new_posting():
    existing = [{"title": "[박물관] 근로장학생 모집", "posted_at": "2026-02-01"}]
    [record] = parse_and_store([POST], existing=existing, parse=fake_parse)
    assert record["title"] == POST["title"]


def test_one_office_reposting_the_same_title_next_month_is_a_new_posting():
    """실제 사례: 기술경영전문대학원이 8/5와 9/15에 같은 제목으로 각각 모집했다.

    근무시간도 마감일도 다른 별개 공고다. 이걸 중복으로 삼키면 공고를 놓친다.
    """
    def parse(_rep):
        return dict(PARSED, work_department=None,
                    posting_department="기술경영전문대학원 행정실")

    post = dict(POST, posted_at="2026-09-15",
                title="[기술경영전문대학원] 행정실 근로장학생 모집(학부/대학원 재학생, 휴학생)")
    existing = [{
        "title": "[기술경영전문대학원] 행정실 근로장학생 모집(학부/대학원 재학생, 휴학생)",
        "worksite_name": "기술경영전문대학원 행정실",
        "posted_at": "2026-08-05",
    }]
    assert len(parse_and_store([post], existing=existing, parse=parse)) == 1


def test_a_cross_posting_lag_of_a_few_days_is_still_one_posting():
    """실제 사례: 법전원 건은 손입력 9/9, 에타 글 9/15로 6일 차이가 났다."""
    def parse(_rep):
        return dict(PARSED, work_department=None,
                    posting_department="법학전문대학원행정팀")

    post = dict(POST, posted_at="2026-09-15",
                title="[법학전문대학원 행정팀] 전문석사과정 입학전형 서류접수 근로학생 모집")
    existing = [{
        "title": "[법학전문대학원 행정팀] 전문석사과정 입학전형 서류접수 근로학생 모집",
        "worksite_name": "법학전문대학원행정팀",
        "posted_at": "2026-09-09",
    }]
    assert parse_and_store([post], existing=existing, parse=parse) == []


def test_a_title_match_without_a_date_is_treated_as_a_duplicate():
    existing = [{"title": "[박물관] 근로장학생 모집"}]
    assert parse_and_store([POST], existing=existing, parse=fake_parse) == []


def test_a_department_tag_in_only_one_title_still_counts_as_the_same_post():
    """기존 기록은 '[박물관] 고려대학교 박물관 …', 에타 제목은 접두사가 없다.

    제목만으로는 못 잡고, 파싱해서 근무지를 알아야 같은 공고임이 드러난다.
    """
    def parse(_rep):
        return dict(PARSED, work_department=None,
                    posting_department="고려대학교 박물관 학예기록팀 기록파트")

    post = dict(POST, title="고려대학교 박물관 근로장학생 모집")
    existing = [{
        "title": "[박물관] 고려대학교 박물관 근로장학생 모집",
        "worksite_name": "박물관 학예기록팀",
        "posted_at": "2026-09-14",
    }]
    assert parse_and_store([post], existing=existing, parse=parse) == []


def test_two_postings_from_one_office_are_kept_apart():
    """입학처는 9월 공고와 10월 단기 공고를 따로 올린다. 근무지가 같다고 합치면 안 된다."""
    def parse(_rep):
        return dict(PARSED, work_department=None, posting_department="입학처")

    post = dict(POST, title="[입학처] 2027학년도 수시전형 전형보조 근로장학생 모집(10월 단기)")
    existing = [{
        "title": "[입학처] 2027학년도 수시전형 전형보조 근로장학생 모집(9월)",
        "worksite_name": "입학처",
        "posted_at": "2026-08-25",
    }]
    [record] = parse_and_store([post], existing=existing, parse=parse)
    assert "10월 단기" in record["title"]


def test_same_core_title_at_different_offices_is_not_a_duplicate():
    def parse(_rep):
        return dict(PARSED, work_department=None, posting_department="법무대학원행정팀")

    post = dict(POST, title="[법무대학원행정팀] 근로장학생 모집")
    existing = [{
        "title": "[법학전문대학원행정팀] 근로장학생 모집",
        "worksite_name": "법학전문대학원행정팀",
        "posted_at": "2026-09-14",
    }]
    assert len(parse_and_store([post], existing=existing, parse=parse)) == 1


def test_a_post_already_in_the_file_is_not_parsed_again():
    calls = []

    def counting_parse(rep):
        calls.append(rep)
        return dict(PARSED)

    existing = [{"source_url": POST["source_url"]}]
    assert parse_and_store([POST], existing=existing, parse=counting_parse) == []
    assert calls == []


def test_the_call_budget_caps_how_many_posts_are_parsed():
    posts = [
        dict(POST, article_id=str(i), source_url=f"u{i}",
             title=f"{i}학부 행정실 근로장학생 모집")
        for i in range(5)
    ]
    seen = []

    def parse(rep):
        seen.append(rep["title"])
        return dict(PARSED, work_department=None,
                    posting_department=f"{rep['title'][0]}학부 행정실")

    stored = parse_and_store(posts, existing=[], parse=parse, max_calls=2)
    assert len(stored) == 2
    assert len(seen) == 2  # 상한을 넘으면 모델을 더 부르지 않는다


def test_two_collected_posts_with_the_same_title_only_store_once():
    posts = [
        dict(POST, article_id="1", source_url="u1"),
        dict(POST, article_id="2", source_url="u2"),
    ]
    assert len(parse_and_store(posts, existing=[], parse=fake_parse)) == 1


def test_one_failing_post_does_not_stop_the_others():
    posts = [dict(POST, article_id="1", source_url="u1"),
             dict(POST, article_id="2", source_url="u2")]

    def parse(rep):
        # 대표 레코드에는 url이 없으므로 제목으로 구분한다.
        if rep["title"].endswith("1"):
            raise RuntimeError("model said no")
        return dict(PARSED)

    posts[0]["title"] = "근로장학생 모집 1"
    posts[1]["title"] = "근로장학생 모집 2"
    stored = parse_and_store(posts, existing=[], parse=parse)
    assert len(stored) == 1
    assert stored[0]["title"] == "근로장학생 모집 2"


def test_a_post_with_no_identifiable_worksite_is_skipped_not_fatal():
    def parse(_rep):
        return dict(PARSED, posting_department=None, work_department=None)

    assert parse_and_store([POST], existing=[], parse=parse) == []


def test_a_post_whose_parse_failed_is_left_for_the_next_run():
    """파싱이 실패한 글은 '본 글'이 아니다. 다음 실행에서 다시 가져와야 한다.

    실제 사례(2026-10-08): 크레딧 소진으로 파싱이 실패한 입학처 공고가 seen에
    들어가, 크레딧을 채운 뒤에도 자동으로 다시 수집되지 않았다.
    """
    from everytime_parse import handled_ids

    def parse(_rep):
        raise RuntimeError("credit balance is too low")

    outcomes = {}
    assert parse_and_store([POST], existing=[], parse=parse, outcomes=outcomes) == []
    assert handled_ids([POST], outcomes) == set()


def test_posts_beyond_the_call_budget_are_left_for_the_next_run():
    from everytime_parse import handled_ids

    posts = [
        dict(POST, article_id=str(i), source_url=f"u{i}",
             title=f"{i}학부 행정실 근로장학생 모집")
        for i in range(3)
    ]

    def parse(rep):
        return dict(PARSED, work_department=None,
                    posting_department=f"{rep['title'][0]}학부 행정실")

    outcomes = {}
    parse_and_store(posts, existing=[], parse=parse, max_calls=2, outcomes=outcomes)
    assert handled_ids(posts, outcomes) == {"0", "1"}


def test_a_post_skipped_as_a_duplicate_is_still_handled():
    """중복이라 건너뛴 글은 다시 볼 이유가 없다. seen에 들어가야 한다."""
    from everytime_parse import handled_ids

    existing = [{"source_url": POST["source_url"]}]
    outcomes = {}
    parse_and_store([POST], existing=existing, parse=fake_parse, outcomes=outcomes)
    assert handled_ids([POST], outcomes) == {POST["article_id"]}


def test_an_api_outage_is_not_recorded_as_a_parse_failure():
    """크레딧·연결 장애는 글 탓이 아니다. 실패 횟수로 세면 안 된다."""
    from crawler_pipeline.llm import LLMUnavailable

    def parse(_rep):
        raise LLMUnavailable("credit balance is too low")

    outcomes = {}
    parse_and_store([POST], existing=[], parse=parse, outcomes=outcomes)
    assert outcomes == {POST["article_id"]: "unavailable"}


def test_parse_failures_are_counted_until_the_post_is_given_up():
    """실제 사례(2026-10-13~19): 본문이 짧은 원스탑 공고가 매일 파싱에 실패했다."""
    from everytime_parse import MAX_PARSE_FAILURES, track_failures

    failed = {POST["article_id"]: "parse_failed"}
    counts = {}
    for _ in range(MAX_PARSE_FAILURES - 1):
        counts, given_up = track_failures([POST], failed, counts)
        assert given_up == set()
    assert counts == {POST["article_id"]: MAX_PARSE_FAILURES - 1}

    counts, given_up = track_failures([POST], failed, counts)
    assert given_up == {POST["article_id"]}
    assert counts == {}


def test_an_outage_or_a_success_leaves_no_stale_failure_count():
    from everytime_parse import track_failures

    counts, given_up = track_failures(
        [POST], {POST["article_id"]: "unavailable"}, {POST["article_id"]: 2})
    assert counts == {POST["article_id"]: 2} and given_up == set()

    counts, given_up = track_failures(
        [POST], {POST["article_id"]: "stored"}, {POST["article_id"]: 2})
    assert counts == {} and given_up == set()
