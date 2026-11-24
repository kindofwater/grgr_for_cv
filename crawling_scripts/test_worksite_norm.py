from worksite_norm import (
    canonicalize_worksite_display_name,
    normalize_worksite_name,
    qualify_special_library_worksite,
    resolve_worksite_name,
    worksite_identity_key,
)


def test_strips_university_prefix():
    assert normalize_worksite_name("고려대학교 물리학과") == "물리학과"
    assert normalize_worksite_name("고려대 물리학과") == "물리학과"


def test_display_name_omits_redundant_university_prefix():
    assert canonicalize_worksite_display_name(
        "고려대학교 경영대학 경력개발센터"
    ) == "경영대학 경력개발센터"
    assert canonicalize_worksite_display_name(
        "고려대학교(본교) 중앙도서관"
    ) == "중앙도서관 학술정보서비스팀"
    assert canonicalize_worksite_display_name("고려대 물리학과") == "물리학과"

def test_strips_bracket_tags():
    assert normalize_worksite_name("[Student Success Center] 근로") == "근로"

def test_strips_bonkyo_and_collapses_space():
    assert normalize_worksite_name("고려대학교(본교)  중앙도서관") == "중앙도서관 학술정보서비스팀"

def test_case_and_trim():
    assert normalize_worksite_name("  학생처 Student Success Center ") == \
        normalize_worksite_name("학생처 student success center")

def test_same_dept_two_sources_match():
    assert normalize_worksite_name("고려대학교 물리학과") == normalize_worksite_name("물리학과")

def test_known_parent_organization_aliases_match():
    assert normalize_worksite_name("국제처 국제교육팀") == normalize_worksite_name("국제교육팀")
    assert normalize_worksite_name("산학협력단 연구지원팀") == normalize_worksite_name("연구지원팀")

def test_administration_office_is_not_globally_rewritten_to_team():
    assert normalize_worksite_name("이과대학행정실") != normalize_worksite_name(
        "이과대학행정팀"
    )

def test_one_stop_spacing_matches():
    assert normalize_worksite_name("ONE-STOP 서비스센터") == normalize_worksite_name("ONE-STOP서비스센터")


def test_one_stop_variants_resolve_to_three_independent_worksites():
    humanities = "ONE-STOP서비스센터(인문·사회계)"
    natural = "ONE-STOP서비스센터(자연계)"
    medical = "ONE-STOP서비스센터(의료공제)"

    assert canonicalize_worksite_display_name("ONE-STOP서비스센터") == humanities
    assert canonicalize_worksite_display_name("인문계 ONE-STOP서비스센터") == humanities
    assert canonicalize_worksite_display_name("자연계 ONE-STOP서비스센터") == natural
    assert resolve_worksite_name(
        "ONE-STOP서비스센터",
        "[ONE-STOP서비스센터] 의료공제 근로장학생 모집",
    ) == medical
    assert resolve_worksite_name(
        "ONE-STOP서비스센터",
        "ONE-STOP서비스센터(자연계) 근로장학생 모집",
        "모집인원: 인문사회계 O명",
    ) == natural
    assert resolve_worksite_name(
        "ONE-STOP서비스센터",
        "[ONE-STOP서비스센터] 근로장학생 모집",
    ) == humanities

def test_empty_and_none_safe():
    assert normalize_worksite_name("") == ""
    assert normalize_worksite_name(None) == ""


def test_media_college_administration_team_spacing_matches():
    assert normalize_worksite_name("미디어대학 행정팀") == normalize_worksite_name("미디어대학행정팀")


def test_former_media_division_administration_names_match_media_college():
    canonical = normalize_worksite_name("미디어대학행정팀")
    assert normalize_worksite_name("미디어학부행정실") == canonical
    assert normalize_worksite_name("미디어학부행정팀") == canonical
    assert canonicalize_worksite_display_name("미디어학부행정실") == "미디어대학행정팀"


def test_former_finance_division_name_matches_finance_team():
    assert normalize_worksite_name("재무부") == normalize_worksite_name("재정팀")
    assert canonicalize_worksite_display_name("재무부") == "재정팀"


def test_former_university_archives_office_matches_archives_team():
    assert normalize_worksite_name("대학기록실") == normalize_worksite_name("대학기록팀")
    assert canonicalize_worksite_display_name("대학기록실") == "대학기록팀"


def test_museum_worksite_names_merge_into_curation_records_team():
    canonical = normalize_worksite_name("박물관 학예기록팀")
    assert normalize_worksite_name("박물관") == canonical
    assert normalize_worksite_name("학예부") == canonical
    assert normalize_worksite_name("학예기록팀") == canonical
    # 팀 아래 파트 표기는 파트 절단 후 같은 정본으로 수렴한다.
    assert normalize_worksite_name("학예기록팀 기록파트") == canonical
    assert canonicalize_worksite_display_name("박물관") == "박물관 학예기록팀"
    assert canonicalize_worksite_display_name("학예부") == "박물관 학예기록팀"


def test_former_international_studies_division_admin_matches_college_admin():
    canonical = normalize_worksite_name("국제대학행정팀")
    assert normalize_worksite_name("국제학부행정실") == canonical
    assert normalize_worksite_name("국제학부행정팀") == canonical
    assert normalize_worksite_name("국제대학 행정실") == canonical
    assert normalize_worksite_name("국제대학행정실") == canonical
    assert canonicalize_worksite_display_name("국제학부행정실") == "국제대학행정팀"
    assert canonicalize_worksite_display_name("국제대학 행정실") == "국제대학행정팀"


def test_teacher_college_admin_abbreviations_use_latest_office_name():
    canonical = normalize_worksite_name("사범대학행정실")
    assert normalize_worksite_name("사범대학행정팀") == canonical
    assert normalize_worksite_name("사범대학 행정팀") == canonical
    assert normalize_worksite_name("사범대행정팀") == canonical
    assert normalize_worksite_name("사범대행정실") == canonical
    assert normalize_worksite_name("사범대학 행정실") == canonical
    assert canonicalize_worksite_display_name("사범대행정팀") == "사범대학행정실"


def test_confirmed_admin_office_labels_use_latest_team_names():
    aliases = {
        "안암학사행정실": "안암학사행정팀",
        "자유전공학부행정실": "자유전공학부행정팀",
        "외국어센터행정실": "외국어센터행정팀",
    }
    for office_name, team_name in aliases.items():
        assert normalize_worksite_name(office_name) == normalize_worksite_name(
            team_name
        )
        assert canonicalize_worksite_display_name(office_name) == team_name


def test_confirmed_split_worksite_aliases_use_canonical_names():
    assert canonicalize_worksite_display_name(
        "융합에너지공학과 행정실"
    ) == "융합에너지공학과"
    assert canonicalize_worksite_display_name(
        "행정고시동"
    ) == "안암학사 고시동 행정실"
    assert canonicalize_worksite_display_name(
        "서울캠퍼스 안암학사 고시동 행정실"
    ) == "안암학사 고시동 행정실"
    assert canonicalize_worksite_display_name(
        "생명환경과학대학원행정실"
    ) == "생명환경과학대학원행정팀"


def test_reviewed_parent_and_team_names_use_one_worksite():
    assert canonicalize_worksite_display_name(
        "지속가능경영팀"
    ) == "지속가능원"
    assert canonicalize_worksite_display_name("인재발굴처") == "입학처"
    assert canonicalize_worksite_display_name(
        "입학전형관리팀"
    ) == "입학처"
    assert canonicalize_worksite_display_name(
        "창업지원팀"
    ) == "크림슨창업지원단"
    assert normalize_worksite_name(
        "크림슨창업지원단 행정실"
    ) == normalize_worksite_name("크림슨창업지원단")


def test_social_contribution_historical_names_match_current_institute():
    canonical = normalize_worksite_name("사회공헌원")
    assert normalize_worksite_name("사회공헌지원부") == canonical
    assert normalize_worksite_name("사회공헌지원팀") == canonical
    assert normalize_worksite_name("사회공헌원 (KUSSO)") == canonical
    assert normalize_worksite_name("고려대학교 사회공헌원(KUSR)") == canonical
    assert normalize_worksite_name("사회공헌원(KUIS)") == canonical
    assert canonicalize_worksite_display_name("사회공헌지원부") == "사회공헌원"
    assert canonicalize_worksite_display_name(
        "고려대학교 사회공헌원(KUIS)"
    ) == "사회공헌원"


def test_former_teaching_learning_names_match_current_support_center():
    canonical = normalize_worksite_name("교수학습지원센터")
    assert normalize_worksite_name("교수학습개발원") == canonical
    assert normalize_worksite_name("교수학습지원팀") == canonical
    assert canonicalize_worksite_display_name("교수학습개발원") == "교수학습지원센터"


def test_remote_education_parent_names_match_center():
    canonical = normalize_worksite_name("원격교육센터")
    assert normalize_worksite_name("교수학습개발원 원격교육센터") == canonical
    assert normalize_worksite_name("학부대학 원격교육센터") == canonical


def test_reviewed_international_parent_prefixes_are_removed():
    assert normalize_worksite_name("국제처 국제교류팀") == normalize_worksite_name("국제교류팀")
    assert normalize_worksite_name("국제처 글로벌서비스센터") == normalize_worksite_name("글로벌서비스센터")
    assert canonicalize_worksite_display_name("국제처 국제교육팀") == "국제교육팀"


def test_team_part_and_assignment_collapse_but_contact_words_do_not():
    assert normalize_worksite_name("학생지원팀 장학파트") == "학생지원팀"
    assert normalize_worksite_name("연구지원팀 2파트") == "연구지원팀"
    assert normalize_worksite_name("학생지원팀 장학담당") == "학생지원팀"
    assert normalize_worksite_name("학생지원팀 담당자") != "학생지원팀"


def test_outer_decorations_unwrap_and_identity_absorbs_spacing_and_separators():
    assert normalize_worksite_name("🧌🧌[미디어대학 행정팀]🎉") == "미디어대학행정팀"
    assert worksite_identity_key("A / B 팀") == worksite_identity_key("AㆍB팀")
    assert worksite_identity_key("국제 대학 행정팀") == worksite_identity_key("국제대학행정팀")


def test_business_college_admin_office_keeps_its_suffix():
    assert normalize_worksite_name("경영대학 행정실") == "경영대학행정실"
    assert normalize_worksite_name("경영대학행정팀") == "경영대학행정팀"


def test_startup_institute_uses_latest_admin_office_name():
    canonical = normalize_worksite_name("스타트업연구원 행정실")
    assert normalize_worksite_name("경영대학 스타트업연구원") == canonical
    assert normalize_worksite_name("스타트업 연구원 행정실") == canonical
    assert canonicalize_worksite_display_name(
        "경영대학 스타트업연구원"
    ) == "스타트업연구원 행정실"


def test_explicit_business_graduate_school_overrides_broad_posting_department():
    assert resolve_worksite_name(
        "경영대학행정팀",
        "고려대학교 경영전문대학원에서 근무할 근로장학생을 모집합니다.",
    ) == "경영전문대학원행정팀"


def test_joint_graduate_posting_department_routes_to_mot_from_evidence():
    joint = "공학대학원·에너지환경대학원(그린스쿨)·기술경영전문대학원행정팀"
    assert resolve_worksite_name(
        joint,
        "[기술경영전문대학원] 행정실 근로장학생 모집",
        "근무장소: 창의관 201호",
    ) == "기술경영전문대학원 행정실"


def test_joint_graduate_posting_department_routes_to_green_school_from_evidence():
    joint = "공학대학원·에너지환경대학원(그린스쿨)·기술경영전문대학원행정실"
    assert resolve_worksite_name(
        joint,
        "에너지환경대학원(그린스쿨)에서 근무할 근로장학생을 모집합니다.",
        "근무장소: KU R&D센터 520호",
    ) == "에너지환경대학원(그린스쿨) 행정실"


def test_joint_graduate_posting_department_is_not_resolved_without_child_evidence():
    joint = "공학대학원·에너지환경대학원(그린스쿨)·기술경영전문대학원행정팀"
    assert resolve_worksite_name(
        joint,
        "근로장학생을 모집합니다.",
    ) == joint


def test_graduate_admin_display_aliases_use_official_office_names():
    assert canonicalize_worksite_display_name(
        "기술경영전문대학원행정팀"
    ) == "기술경영전문대학원 행정실"
    assert canonicalize_worksite_display_name(
        "에너지환경대학원(그린스쿨)행정팀"
    ) == "에너지환경대학원(그린스쿨) 행정실"


def test_business_publicity_and_deans_office_is_separate_worksite():
    assert resolve_worksite_name(
        "경영대학행정실",
        "경영대학 홍보팀/학장실에서 근무하실 근로장학생을 모집합니다.",
    ) == "경영대학 홍보팀·학장실"


def test_phone_or_room_alone_does_not_change_worksite_identity():
    assert resolve_worksite_name(
        "경영대학 행정팀",
        "문의 02-3290-1308, 경영본관 307호",
    ) == "경영대학행정팀"


def test_medical_library_maps_to_official_management_team():
    assert normalize_worksite_name("의학도서관") == normalize_worksite_name("의학정보관리팀")

def test_special_libraries_are_preserved_as_distinct_worksites():
    assert qualify_special_library_worksite(
        "학술정보개발팀", "[중앙도서관] 학술정보개발팀 근로장학생 모집"
    ) == "학술정보개발팀"
    assert qualify_special_library_worksite("고려대학교 중앙도서관") == "중앙도서관 학술정보서비스팀"
    assert qualify_special_library_worksite(
        "도서관 학술정보큐레이션팀", "[과학도서관] 학술정보큐레이션팀 근로장학생 모집"
    ) == "과학도서관 학술정보큐레이션팀"
    assert qualify_special_library_worksite("도서관 학술정보서비스팀") == "도서관 학술정보서비스팀"


def test_central_library_interlibrary_loan_names_share_one_worksite():
    canonical = normalize_worksite_name("중앙도서관 상호대차센터")
    assert normalize_worksite_name("상호대차실") == canonical
    assert normalize_worksite_name("제2자료실 내 상호대차센터") == canonical
    assert normalize_worksite_name(
        "중앙도서관 제2자료실 내 상호대차센터"
    ) == canonical
    assert qualify_special_library_worksite(
        "제2자료실 내 상호대차센터",
        "[중앙도서관] 일반대학원생 근로장학생 모집",
    ) == "중앙도서관 상호대차센터"
