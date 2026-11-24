from manual_postings import canonicalize, infer_work_duration_type


def test_three_months_is_long():
    assert infer_work_duration_type("3개월") == "long"


def test_five_weeks_is_short_and_six_weeks_is_long():
    assert infer_work_duration_type("5주") == "short"
    assert infer_work_duration_type("6주") == "long"


def test_explicit_date_range_uses_inclusive_days():
    assert infer_work_duration_type("2026-07-01~2026-08-10") == "short"
    assert infer_work_duration_type("2026-07-01~2026-08-11") == "long"


def test_canonicalize_overrides_inconsistent_manual_label():
    record = canonicalize({
        "external_id": "stable-id",
        "worksite_name": "경영대학 행정팀",
        "work_period_text": "3개월",
        "work_duration_type": "short",
    })
    assert record["work_duration_type"] == "long"
    assert record["external_id"] == "stable-id"
