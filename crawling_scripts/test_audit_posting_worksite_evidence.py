from audit_posting_worksite_evidence import audit_rows


def test_audit_reports_only_explicit_worksite_mismatch():
    rows = [
        {
            "id": 1, "source": "kupid", "external_id": "a",
            "title": "[입학처] 모집", "raw_text": "근무부서: 학생지원팀",
            "worksites": {"id": 10, "workplace_name": "입학처"},
        },
        {
            "id": 2, "source": "kupid", "external_id": "b",
            "title": "[의학도서관] 모집",
            "raw_text": "근무장소: 의학도서관 3층 자료실",
            "worksites": {"id": 11, "workplace_name": "의학정보관리팀"},
        },
    ]
    issues = audit_rows(rows)
    assert [item["posting_id"] for item in issues] == [1]


def test_audit_treats_admin_office_with_parenthesized_room_as_same_worksite():
    rows = [{
        "id": 3,
        "source": "kupid",
        "external_id": "ku-kist",
        "title": "[KU-KIST융합대학원] 근로장학생 모집",
        "raw_text": (
            "근무장소: KU-KIST융합대학원 행정실"
            "(R&D센터 418호)"
        ),
        "worksites": {
            "id": 12,
            "workplace_name": "KU-KIST융합대학원행정팀",
        },
    }]

    assert audit_rows(rows) == []


def test_audit_keeps_confirmed_library_room_as_talent_team_location():
    rows = [{
        "id": 4,
        "source": "kupid",
        "external_id": "talent-team",
        "title": "대학원 근로장학생 모집",
        "raw_text": (
            "대학원혁신본부 인재양성팀에서 근로장학생을 모집합니다.\n"
            "근무장소: 서울캠퍼스 대학원도서관 1층 124호"
        ),
        "worksites": {
            "id": 13,
            "workplace_name": "인재양성팀",
        },
    }]

    assert audit_rows(rows) == []


def test_audit_omits_previously_confirmed_noisy_aliases():
    rows = [
        {
            "id": 5,
            "source": "kupid",
            "external_id": "business-graduate",
            "title": "근로장학생 모집",
            "raw_text": "경영대학교 경영전문대학원에서 근무합니다.",
            "worksites": {
                "id": 14,
                "workplace_name": "경영전문대학원행정팀",
            },
        },
        {
            "id": 6,
            "source": "kupid",
            "external_id": "academic-coaching",
            "title": "근로장학생 모집",
            "raw_text": (
                "근무부서: 교수학습개발원 "
                "교수학습개발원 학업코칭 파트"
            ),
            "worksites": {
                "id": 15,
                "workplace_name": "교수학습지원센터",
            },
        },
        {
            "id": 7,
            "source": "kupid",
            "external_id": "finance-room",
            "title": "근로장학생 모집",
            "raw_text": "근무장소: 재무부(본관 202호)",
            "worksites": {
                "id": 16,
                "workplace_name": "재정팀",
            },
        },
    ]

    assert audit_rows(rows) == []
