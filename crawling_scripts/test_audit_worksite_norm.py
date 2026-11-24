from audit_worksite_norm import audit_worksite_rows, has_issues


def test_audit_passes_clean_rows():
    report = audit_worksite_rows([
        {"id": 1, "university_id": 1, "workplace_name": "학술정보개발팀", "normalized_name": "학술정보개발팀"},
        {"id": 2, "university_id": 1, "workplace_name": "재정팀", "normalized_name": "재정팀"},
        {"id": 6845, "university_id": 1, "workplace_name": "평생교육원행정실", "normalized_name": "평생교육원행정실"},
    ])
    assert not has_issues(report)


def test_audit_finds_empty_generic_worksite():
    report = audit_worksite_rows([
        {"id": 1, "university_id": 1, "workplace_name": "고려대학교", "normalized_name": ""},
    ])
    assert has_issues(report)
    assert report["empty_code_norm"][0]["id"] == 1


def test_audit_finds_code_duplicate_with_spacing_difference():
    report = audit_worksite_rows([
        {"id": 1, "university_id": 1, "workplace_name": "ONE-STOP 서비스센터", "normalized_name": "one-stop서비스센터(인문·사회계)"},
        {"id": 2, "university_id": 1, "workplace_name": "ONE-STOP서비스센터", "normalized_name": "one-stop서비스센터(인문·사회계)"},
    ])
    assert has_issues(report)
    assert "1:one-stop서비스센터(인문·사회계)" in report["duplicate_code_norms"]


def test_audit_finds_korean_spacing_and_separator_identity_duplicate():
    report = audit_worksite_rows([
        {"id": 1, "university_id": 1, "workplace_name": "A / B 팀", "normalized_name": "a / b 팀"},
        {"id": 2, "university_id": 1, "workplace_name": "A·B팀", "normalized_name": "a·b팀"},
    ])
    assert has_issues(report)
    assert "1:a·b팀" in report["duplicate_code_norms"]


def test_audit_finds_db_norm_mismatch():
    report = audit_worksite_rows([
        {"id": 1, "university_id": 1, "workplace_name": "ONE-STOP 서비스센터", "normalized_name": "one-stop 서비스센터"},
    ])
    assert has_issues(report)
    assert report["db_norm_mismatches"][0]["code_norm"] == "one-stop서비스센터(인문·사회계)"


def test_audit_finds_redundant_university_prefix_in_display_name():
    report = audit_worksite_rows([{
        "id": 1,
        "university_id": 1,
        "workplace_name": "고려대학교 경영대학 경력개발센터",
        "normalized_name": "경영대학 경력개발센터",
    }])
    assert has_issues(report)
    assert report["display_name_mismatches"][0]["canonical_display_name"] == \
        "경영대학 경력개발센터"
