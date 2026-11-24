from crawler_pipeline.records import apply_parse, attachment_names, classify_work_duration, kupid_record


def test_attachment_names_preserves_labels_from_both_crawler_shapes():
    assert attachment_names('[{"label": "지원서 양식.hwp"}, {"label": "안내문.pdf"}]') == [
        "지원서 양식.hwp", "안내문.pdf"
    ]
    assert attachment_names(["지원서 양식.hwp", "지원서 양식.hwp"]) == ["지원서 양식.hwp"]


def test_kupid_record_preserves_attachment_names():
    record = kupid_record({
        "title": "[중앙도서관] 근로장학생 모집",
        "department": "중앙도서관",
        "registered_date": "2026-08-04",
        "detail_text": "본문",
        "attachments_json": '[{"label": "지원서.hwp"}]',
    })
    assert record["attachment_names"] == ["지원서.hwp"]


def test_duration_under_six_weeks_is_short():
    assert classify_work_duration({
        "work_period_days": 41,
        "work_duration_type": "long",
    }) == "short"


def test_duration_at_six_weeks_is_long():
    assert classify_work_duration({
        "work_period_days": 42,
        "work_duration_type": "short",
    }) == "long"


def test_duration_uses_longest_option_reported_by_parser():
    assert classify_work_duration({
        "work_period_days": 91,
        "work_duration_type": "short",
    }) == "long"


def test_duration_falls_back_to_explicit_label_when_days_unknown():
    assert classify_work_duration({
        "work_period_days": None,
        "work_duration_type": "short",
    }) == "short"
    assert classify_work_duration({
        "work_period_days": None,
        "work_duration_type": "invalid",
    }) == "unknown"


def test_kupid_record_uses_explicit_workplace_over_posting_department():
    record = kupid_record({
        "title": "[경영대학행정팀] 근로장학생 모집",
        "department": "경영대학행정팀",
        "registered_date": "2026-03-05",
        "detail_text": (
            "고려대학교 경영전문대학원에서 근무할 근로장학생을 모집합니다.\n"
            "근무장소: 경영본관 307호"
        ),
    })
    assert record["worksite_name"] == "경영전문대학원행정팀"
    assert record["normalized_worksite"] == "경영전문대학원행정팀"


def test_kupid_record_extracts_yearless_deadline_before_later_interview_date():
    record = kupid_record({
        "title": "[경영대학] 경영대학 행정팀 근로장학생 모집",
        "department": "경영대학행정팀",
        "registered_date": "2026-07-31",
        "detail_text": (
            "제목 [경영대학] 경영대학 행정팀 근로장학생 모집\n\n"
            "9. 접수기간 : 8/2(일)까지 접수, 8/3(월) 면접 후 인수인계\n"
        ),
        "due_date": "",
    })

    assert record["recruit_until"] == "2026-08-02"
    assert record["recruit_until_estimated"] is False


def test_kupid_record_extracts_end_of_full_date_application_range():
    record = kupid_record({
        "title": "[안암학사행정팀] 생활조교 모집",
        "department": "안암학사행정팀",
        "registered_date": "2026-07-23",
        "detail_text": (
            "제목 [안암학사행정팀] 생활조교 모집\n\n"
            "지원기간: 2026.07.23.(목) ~\n"
            "2026.08.02.(일) 23:59\n"
            "마감\n"
        ),
        "due_date": "",
    })

    assert record["recruit_until"] == "2026-08-02"
    assert record["recruit_until_estimated"] is False


def test_kupid_record_does_not_treat_single_reception_date_as_deadline():
    record = kupid_record({
        "title": "[국제교육팀] 근로장학생 모집",
        "department": "국제교육팀",
        "registered_date": "2024-10-29",
        "detail_text": (
            "제목 [국제교육팀] 근로장학생 모집\n\n"
            "2. 모집기간 및 방법\n"
            "가. 서류 접수: 2024년 10월 29일(화)\n"
            "나. 면접: 2024년 11월 6일(수)\n"
        ),
        "due_date": "",
    })

    assert record["recruit_until"] == ""


def test_explicit_deadline_wins_over_all_estimates():
    result = apply_parse({
        "source": "kupid",
        "posted_at": "2026-07-13",
        "recruit_until": "2026-07-20",
    }, {
        "recruit_until": "2026-07-21",
        "work_start_date": "2026-08-10",
    })
    assert result["recruit_until"] == "2026-07-20"
    assert result["recruit_until_estimated"] is False


def test_kupid_without_deadline_is_visible_for_twenty_one_calendar_days():
    result = apply_parse({
        "source": "kupid",
        "posted_at": "2026-07-13",
        "recruit_until": None,
    }, {
        "recruit_until": None,
        "work_start_date": "2026-08-10",
    })
    assert result["recruit_until"] == "2026-08-02"
    assert result["recruit_until_estimated"] is True


def test_work_start_estimate_is_only_the_last_fallback():
    result = apply_parse({
        "source": "kupid",
        "posted_at": None,
        "recruit_until": None,
    }, {
        "recruit_until": None,
        "work_start_date": "2026-08-10",
    })
    assert result["recruit_until"] == "2026-08-09"
    assert result["recruit_until_estimated"] is True


def test_work_start_caps_the_window_when_it_lands_first():
    """근무가 이미 시작한 뒤까지 모집 중으로 보이면 안 된다."""
    result = apply_parse({
        "source": "everytime_manual",
        "posted_at": "2026-08-13",
        "recruit_until": None,
    }, {
        "recruit_until": None,
        "work_start_date": "2026-08-24",
    })
    assert result["recruit_until"] == "2026-08-23"
    assert result["recruit_until_estimated"] is True
    assert result["deadline_basis"] == "work_start"


def test_first_seen_window_is_also_capped_by_work_start():
    result = apply_parse({
        "source": "everytime_manual",
        "posted_at": None,
        "first_seen_at": "2026-07-29",
        "recruit_until": None,
    }, {
        "recruit_until": None,
        "work_start_date": "2026-08-05",
    })
    assert result["recruit_until"] == "2026-08-04"
    assert result["deadline_basis"] == "work_start"


def test_ssc_without_explicit_deadline_uses_same_twenty_one_day_policy():
    result = apply_parse({
        "source": "ssc",
        "posted_at": "2026-07-13",
        "recruit_until": None,
    }, {
        "recruit_until": None,
        "work_start_date": None,
    })
    assert result["recruit_until"] == "2026-08-02"
    assert result["recruit_until_estimated"] is True


def test_first_seen_date_is_used_when_source_posted_date_is_missing():
    result = apply_parse({
        "source": "everytime_manual",
        "posted_at": None,
        "first_seen_at": "2026-07-29",
        "recruit_until": None,
    }, {
        "recruit_until": None,
        "work_start_date": "2026-09-01",
    })
    assert result["recruit_until"] == "2026-08-18"
    assert result["deadline_basis"] == "first_seen_window"


def test_sonnet_worksite_fields_override_source_candidate():
    result = apply_parse({
        "source": "kupid",
        "posted_at": "2026-07-13",
        "recruit_until": None,
        "worksite_name": "학생지원팀",
        "source_department": "학생지원팀",
    }, {
        "work_department": "장애학생지원센터",
        "work_location": "4.18기념관 1층",
        "worksite_evidence": "5. 근무지: 장애학생지원센터",
        "office_phone": "02-3290-0000",
    })
    assert result["worksite_name"] == "장애학생지원센터"
    assert result["worksite_requires_confirmation"] is False
    assert result["work_location"] == "4.18기념관 1층"
    assert result["office_phone"] == "02-3290-0000"


def test_sonnet_mobile_number_is_not_accepted_as_office_phone():
    result = apply_parse({
        "source": "kupid",
        "posted_at": "2026-07-13",
        "worksite_name": "학생지원팀",
    }, {
        "work_department": "학생지원팀",
        "office_phone": "010-1234-5678",
    })
    assert result["office_phone"] is None
