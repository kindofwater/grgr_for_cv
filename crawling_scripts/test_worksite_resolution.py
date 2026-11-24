from worksite_resolution import (
    extract_explicit_worksite_names,
    preferred_explicit_worksite_name,
    rank_worksite_candidates,
    resolve_worksite_record,
    resolved_record_name,
    safe_evidence_text,
)
from worksite_norm import normalize_worksite_name


class _Response:
    def __init__(self, data):
        self.data = data


class _Query:
    def __init__(self, client, table):
        self.client = client
        self.table = table
        self.operation = "select"
        self.payload = None
        self.filters = {}

    def select(self, *_args):
        return self

    def eq(self, key, value):
        self.filters[key] = value
        return self

    def in_(self, key, value):
        self.filters[key] = value
        return self

    def is_(self, *_args):
        return self

    def limit(self, *_args):
        return self

    def upsert(self, payload, **_kwargs):
        self.operation = "upsert"
        self.payload = payload
        return self

    def execute(self):
        if self.table == "worksites":
            return _Response(self.client.worksites)
        if self.table == "worksite_aliases":
            return _Response(self.client.aliases)
        if self.table == "worksite_resolution_queue" and self.operation == "select":
            rows = [
                row for row in self.client.queue
                if all(row.get(key) == value for key, value in self.filters.items())
            ]
            return _Response(rows)
        if self.table == "worksite_resolution_queue" and self.operation == "upsert":
            row = dict(self.payload, id=len(self.client.queue) + 1)
            self.client.queue.append(row)
            return _Response([row])
        raise AssertionError((self.table, self.operation))


class _Client:
    def __init__(self, *, worksites=None, aliases=None, queue=None):
        self.worksites = worksites or []
        self.aliases = aliases or []
        self.queue = queue or []

    def table(self, name):
        return _Query(self, name)


def test_known_business_conflict_is_resolved_before_queueing():
    record = {
        "worksite_name": "경영대학행정팀",
        "title": "근로장학생 모집",
        "raw_text": "고려대학교 경영전문대학원에서 근무할 근로장학생을 모집합니다.",
    }
    assert resolved_record_name(record) == "경영전문대학원행정팀"
    assert extract_explicit_worksite_names(record) == ["경영전문대학원행정팀"]


def test_extracts_unknown_explicit_child_organization_conservatively():
    record = {
        "worksite_name": "상위행정팀",
        "title": "[상위행정팀] 근로장학생 모집",
        "raw_text": "신규데이터센터에서 근무할 근로장학생을 모집합니다.",
    }
    assert extract_explicit_worksite_names(record) == [
        "상위행정팀",
        "신규데이터센터",
    ]
    assert preferred_explicit_worksite_name(record) == "신규데이터센터"


def test_explicit_work_department_has_priority_over_title_and_recruiting_body():
    record = {
        "worksite_name": "학부대학행정팀",
        "title": "[학부대학행정팀] 근로장학생 모집",
        "raw_text": (
            "학부대학에서 근로장학생을 모집합니다.\n"
            "근무부서: 교수학습지원팀"
        ),
    }
    assert resolved_record_name(record) == "교수학습지원센터"
    assert preferred_explicit_worksite_name(record) == "교수학습지원팀"


def test_explicit_joint_graduate_admin_team_overrides_broad_college_assignment():
    record = {
        "worksite_name": "정경대학행정팀",
        "title": "근로장학생 모집",
        "raw_text": (
            "정책대학원·융합데이터과학대학원 행정팀에서 "
            "근무할 학부 휴학생을 모집합니다.\n"
            "근무장소: 정책대학원·융합데이터과학대학원 "
            "행정팀(SK미래관 515호실)"
        ),
    }
    assert (
        resolved_record_name(record)
        == "정책대학원·융합데이터과학대학원 행정팀"
    )


def test_talent_development_team_keeps_library_room_as_location_only():
    record = {
        "worksite_name": "인재양성팀",
        "title": "대학원 근로장학생 모집",
        "raw_text": (
            "대학원혁신본부 인재양성팀에서 근로장학생을 모집합니다.\n"
            "근무장소: 서울캠퍼스 대학원도서관 1층 124호"
        ),
    }
    assert preferred_explicit_worksite_name(record) == "서울캠퍼스 대학원도서관"
    assert resolved_record_name(record) == "인재양성팀"


def test_explicit_library_child_keeps_its_parent_library_scope():
    record = {
        "worksite_name": "중앙도서관 인포메이션센터",
        "work_department": "인포메이션센터",
        "title": "[중앙도서관] 인포메이션센터 근로장학생 모집",
        "raw_text": (
            "중앙도서관(신관) 인포메이션센터에서 근무할 "
            "근로장학생을 모집합니다."
        ),
    }
    assert preferred_explicit_worksite_name(record) == "인포메이션센터"
    assert resolved_record_name(record) == "중앙도서관 인포메이션센터"


def test_work_location_separates_room_from_department():
    record = {
        "worksite_name": "고려대학교",
        "title": "[미디어대학 행정팀] 근로장학생 모집",
        "raw_text": "근무장소: 미디어관 201호 미디어대학행정팀",
    }
    assert preferred_explicit_worksite_name(record) == "미디어대학행정팀"
    assert resolved_record_name(record) == "미디어대학행정팀"


def test_location_with_only_building_and_room_falls_back_to_title_department():
    record = {
        "worksite_name": "고려대학교",
        "title": "[미디어대학 행정팀] 근로장학생 모집",
        "raw_text": "근무장소: 미디어관 201호",
    }
    assert preferred_explicit_worksite_name(record) == "미디어대학 행정팀"
    assert resolved_record_name(record) == "미디어대학행정팀"


def test_workplace_field_can_appear_after_numbering_or_on_next_line():
    numbered = {
        "title": "근로장학생 모집",
        "raw_text": "7. 근무 장소 : 미디어관 201호 미디어대학행정팀",
    }
    heading = {
        "title": "근로장학생 모집",
        "raw_text": "[근무지]\n경영본관 103호 경영대학 행정팀",
    }
    assert preferred_explicit_worksite_name(numbered) == "미디어대학행정팀"
    assert preferred_explicit_worksite_name(heading) == "경영대학 행정팀"


def test_workplace_field_does_not_include_parenthesized_room_in_department():
    record = {
        "title": "[KU-KIST융합대학원] 근로장학생 모집",
        "raw_text": (
            "4. 근무장소 : "
            "KU-KIST융합대학원 행정실(R&D센터 418호)"
        ),
    }
    assert (
        preferred_explicit_worksite_name(record)
        == "KU-KIST융합대학원 행정실"
    )


def test_work_application_form_is_not_mistaken_for_worksite_field():
    record = {
        "title": "[입학처] 근로장학생 모집",
        "raw_text": "제출서류: 근무지원서\n신청방법: 이메일 제출",
    }
    assert preferred_explicit_worksite_name(record) == "입학처"


def test_worksite_and_recruit_count_heading_is_not_an_organization():
    record = {
        "title": "근로장학생 모집",
        "raw_text": "3. 근무지 및 모집 인원: 추후 협의",
    }
    assert preferred_explicit_worksite_name(record) == ""


def test_generic_this_graduate_school_phrase_is_not_an_organization_name():
    record = {
        "title": "근로장학생 모집",
        "raw_text": "본 대학원에서는 성실하게 근무할 학생을 모집합니다.",
    }
    assert preferred_explicit_worksite_name(record) == ""


def test_evidence_removes_contact_details_and_keeps_organization_lines():
    evidence = safe_evidence_text({
        "title": "[신규센터] 근로장학생 모집",
        "raw_text": (
            "신규센터에서 근무할 학생을 모집합니다.\n"
            "근무장소: 미래관 101호\n"
            "문의: person@korea.ac.kr / 02-3290-1234"
        ),
    })
    assert "신규센터에서 근무" in evidence
    assert "근무장소" in evidence
    assert "person@korea.ac.kr" not in evidence
    assert "02-3290-1234" not in evidence


def test_fuzzy_candidates_are_suggestions_only_and_ranked():
    candidates = rank_worksite_candidates(
        "경영대학 행정팀",
        "근무장소: 경영본관 103호",
        [
            {
                "id": 1,
                "workplace_name": "경영대학행정팀",
                "normalized_name": "경영대학행정팀",
                "address": "경영본관 103호",
            },
            {
                "id": 2,
                "workplace_name": "입학처",
                "normalized_name": "입학처",
                "address": "라이시움",
            },
        ],
    )
    assert candidates[0]["worksite_id"] == 1
    assert candidates[0]["score"] > 0.9


def test_office_phone_last_digit_group_ranks_candidate_but_does_not_auto_match():
    candidates = rank_worksite_candidates(
        "처음 보는 이름",
        "",
        [{
            "id": 3,
            "workplace_name": "기존 행정팀",
            "normalized_name": "기존 행정팀",
            "address": None,
            "postings": [{"office_phone": "02-3290-1403"}],
        }],
        "02-3290-1404",
    )
    assert candidates[0]["worksite_id"] == 3
    assert candidates[0]["phone_match"] == "extension_group"
    assert candidates[0]["score"] == 0.9


def test_exact_database_name_is_accepted_without_queue():
    name = "Alpha Center"
    client = _Client(worksites=[{
        "id": 10,
        "workplace_name": name,
        "normalized_name": normalize_worksite_name(name),
        "address": None,
    }])
    result = resolve_worksite_record(client, {
        "source": "ssc",
        "external_id": "exact-1",
        "worksite_name": name,
        "title": "Student assistant",
    })
    assert result["status"] == "matched"
    assert result["worksite_id"] == 10
    assert result["method"] == "exact_name"
    assert client.queue == []


def test_exact_canonical_name_wins_over_conflicting_learned_alias():
    name = "Alpha Center"
    client = _Client(
        worksites=[
            {
                "id": 10,
                "workplace_name": name,
                "normalized_name": normalize_worksite_name(name),
                "address": None,
            },
            {
                "id": 20,
                "workplace_name": "Other Center",
                "normalized_name": normalize_worksite_name("Other Center"),
                "address": None,
            },
        ],
        aliases=[{
            "source": "*",
            "worksite_id": 20,
            "resolution_method": "bad_alias",
        }],
    )
    result = resolve_worksite_record(client, {
        "source": "ssc",
        "external_id": "exact-over-alias",
        "worksite_name": name,
        "title": "Student assistant",
    })
    assert result["worksite_id"] == 10
    assert result["method"] == "exact_name"


def test_spacing_and_separator_variants_match_existing_worksite():
    client = _Client(worksites=[{
        "id": 30,
        "workplace_name": "A·B팀",
        "normalized_name": normalize_worksite_name("A·B팀"),
        "address": None,
    }])
    result = resolve_worksite_record(client, {
        "source": "ssc",
        "external_id": "spacing-variant",
        "worksite_name": "A / B 팀",
        "title": "Student assistant",
    })
    assert result["worksite_id"] == 30
    assert result["method"] == "exact_name"


def test_unknown_database_name_is_queued_without_auto_creation():
    client = _Client()
    result = resolve_worksite_record(client, {
        "source": "ssc",
        "external_id": "unknown-1",
        "worksite_name": "Brand New Center",
        "title": "Student assistant",
        "raw_text": "Contact person@korea.ac.kr or 02-3290-1234",
    })
    assert result["status"] == "pending"
    assert result["queue_id"] == 1
    assert len(client.queue) == 1
    assert "person@korea.ac.kr" not in (client.queue[0]["evidence_text"] or "")
    assert "02-3290-1234" not in (client.queue[0]["evidence_text"] or "")


def test_missing_sonnet_worksite_requires_review_even_if_fallback_name_is_exact():
    client = _Client(worksites=[{
        "id": 10,
        "workplace_name": "입학처",
        "normalized_name": normalize_worksite_name("입학처"),
        "address": None,
    }])
    result = resolve_worksite_record(client, {
        "source": "ssc",
        "external_id": "missing-1",
        "worksite_name": "입학처",
        "worksite_requires_confirmation": True,
        "title": "[입학처] 근로장학생 모집",
    })
    assert result["status"] == "pending"
    assert result["reason"] == "missing_worksite"


def test_conflicting_explicit_worksites_in_paired_sources_require_review():
    client = _Client(worksites=[{
        "id": 10,
        "workplace_name": "입학처",
        "normalized_name": normalize_worksite_name("입학처"),
        "address": None,
    }])
    result = resolve_worksite_record(client, {
        "source": "ssc",
        "external_id": "paired-1",
        "worksite_name": "입학처",
        "work_department": "입학처",
        "title": "[입학처] 근로장학생 모집",
        "_source_records": [
            {
                "title": "[입학처] 근로장학생 모집",
                "raw_text": "근무부서: 입학처",
            },
            {
                "title": "[학생지원팀] 근로장학생 모집",
                "raw_text": "근무부서: 학생지원팀",
            },
        ],
    })
    assert result["status"] == "pending"
    assert result["reason"] == "explicit_conflict"


def test_deleted_human_resolution_target_is_not_reused():
    client = _Client(queue=[{
        "id": 7,
        "university_id": 1,
        "source": "ssc",
        "external_id": "inactive-target",
        "status": "resolved",
        "resolved_worksite_id": 44,
        "resolution_method": "human_existing",
    }])
    result = resolve_worksite_record(client, {
        "source": "ssc",
        "external_id": "inactive-target",
        "worksite_name": "Any Center",
    })
    assert result["status"] == "pending"
    assert result["reason"] == "resolved_target_inactive"


def test_human_queue_decision_wins_on_retry():
    client = _Client(
        worksites=[{
            "id": 44,
            "workplace_name": "Any text",
            "normalized_name": normalize_worksite_name("Any text"),
            "address": None,
        }],
        queue=[{
            "id": 7,
            "university_id": 1,
            "source": "everytime_manual",
            "external_id": "manual-1",
            "status": "resolved",
            "resolved_worksite_id": 44,
            "resolution_method": "human_existing",
        }],
    )
    result = resolve_worksite_record(client, {
        "source": "everytime_manual",
        "external_id": "manual-1",
        "worksite_name": "Any text",
    })
    assert result == {
        "status": "matched",
        "worksite_id": 44,
        "method": "human_existing",
        "queue_id": 7,
        "resolved_name": "Any text",
    }


def test_joint_graduate_posting_department_matches_mot_from_title_evidence():
    client = _Client(worksites=[{
        "id": 6767,
        "workplace_name": "기술경영전문대학원 행정실",
        "normalized_name": normalize_worksite_name("기술경영전문대학원 행정실"),
        "address": "창의관 201호",
    }])
    result = resolve_worksite_record(client, {
        "source": "everytime_manual",
        "external_id": "mot-evidence",
        "worksite_name": (
            "공학대학원·에너지환경대학원(그린스쿨)·"
            "기술경영전문대학원행정팀"
        ),
        "work_department": (
            "공학대학원·에너지환경대학원(그린스쿨)·"
            "기술경영전문대학원행정팀"
        ),
        "title": "[기술경영전문대학원] 행정실 근로장학생 모집",
    })
    assert result["status"] == "matched"
    assert result["worksite_id"] == 6767
    assert result["method"] == "exact_name"


def test_joint_graduate_posting_department_without_child_evidence_queues():
    client = _Client(worksites=[{
        "id": 6767,
        "workplace_name": "기술경영전문대학원 행정실",
        "normalized_name": normalize_worksite_name("기술경영전문대학원 행정실"),
        "address": "창의관 201호",
    }])
    result = resolve_worksite_record(client, {
        "source": "kupid",
        "external_id": "joint-unknown",
        "worksite_name": (
            "공학대학원·에너지환경대학원(그린스쿨)·"
            "기술경영전문대학원행정팀"
        ),
        "work_department": (
            "공학대학원·에너지환경대학원(그린스쿨)·"
            "기술경영전문대학원행정팀"
        ),
        "title": "근로장학생 모집",
    })
    assert result["status"] == "pending"
    assert result["reason"] == "new_name"
