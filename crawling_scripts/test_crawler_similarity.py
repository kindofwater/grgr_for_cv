from crawler_pipeline.similarity import (
    body_similarity,
    choose_representative,
    decide_duplicate,
    title_similarity,
)


SSC_BODY = """
고려대학교 경영전략실에서 근무할 근로장학생을 모집합니다.
가. 지원 자격 : 본교 대학원 재학생 및 휴학생
나. 담당 업무 : 경영전략실 업무보조
다. 모집 인원 : 1명
라. 근무 기간 : 2026년 8월 초
근무 시간 : 월~금 09:00 - 17:30
지급금액 : 시간 당 10,400원
제출기간 : 2026년 7월 28일까지
"""

KUPID_BODY = """
고려대학교 경영전략실에서 근무할 근로장학생을 모집합니다.
가. 자격 : 본교 대학원 재학생 및 휴학생
나. 업무 내용 : 경영전략실 업무보조
다. 모집 인원 : 1명
라. 근무 기간 : 2026년 8월 초
근무 시간 : 월~금 09:00 - 17:30
지급금액 : 시간 당 10,400원
제출기간 : 2026년 7월 28일까지
"""


def record(source, body, *, posted="2026-07-22", title=None, deadline="2026-07-28"):
    return {
        "source": source,
        "normalized_worksite": "경영전략실",
        "posted_at": posted,
        "title": title or "[경영전략실] 대학원생 근로장학생 모집",
        "body": body,
        "recruit_until": deadline,
    }


def test_user_example_is_high_similarity_duplicate():
    assert title_similarity(
        "[경영전략실] 대학원생 근로장학생 모집",
        "경영전략실 대학원생 근로장학생 모집",
    ) >= 0.80
    assert body_similarity(SSC_BODY, KUPID_BODY) >= 0.90
    assert decide_duplicate(record("ssc", SSC_BODY), record("kupid", KUPID_BODY)).is_duplicate


def test_one_extra_polite_sentence_still_matches():
    # Real notices are much longer than this fixture. Repeat the common
    # structure so one or two closing sentences have a realistic weight.
    ssc = SSC_BODY * 3
    kupid = KUPID_BODY * 3
    longer = ssc + "\n좋은 하루 되시길 바랍니다. 많은 지원 바랍니다."
    assert body_similarity(longer, kupid) >= 0.90
    assert decide_duplicate(record("ssc", longer), record("kupid", kupid)).is_duplicate


def test_explicit_wage_conflict_prevents_merge():
    changed = KUPID_BODY.replace("10,400원", "12,000원")
    decision = decide_duplicate(record("ssc", SSC_BODY), record("kupid", changed))
    assert not decision.is_duplicate
    assert decision.reason == "field_conflict"
    assert "wage" in decision.conflicts


def test_title_or_date_gate_keeps_separate():
    assert not decide_duplicate(
        record("ssc", SSC_BODY),
        record("kupid", KUPID_BODY, title="영상 편집 조교 모집"),
    ).is_duplicate
    assert not decide_duplicate(
        record("ssc", SSC_BODY),
        record("kupid", KUPID_BODY, posted="2026-07-30"),
    ).is_duplicate


def test_representative_same_day_ssc_otherwise_newest():
    ssc = record("ssc", SSC_BODY)
    kupid = record("kupid", KUPID_BODY)
    assert choose_representative(ssc, kupid)[0]["source"] == "ssc"
    newer_kupid = record("kupid", KUPID_BODY, posted="2026-07-23")
    assert choose_representative(ssc, newer_kupid)[0]["source"] == "kupid"
