from __future__ import annotations

import re

# 근무지명 앞에 붙는 대학 접두어(표기 흔들림 흡수). 긴 것부터 매칭.
_PREFIXES = ("고려대학교(본교)", "고려대학교", "고려대")

# 운영 DB에서 확인·병합한 동일 근무지의 표기 차이. 긴 상위 조직명은 화면 표시에
# 남기되, 적재 키는 실제 팀/센터명으로 통일한다.
_EXPLICIT_ALIASES = {
    "중앙도서관": "중앙도서관 학술정보서비스팀",
    # 포털의 공동 게시부서명과 달리 실제 근무지는 대학원별 행정실이다.
    "기술경영전문대학원": "기술경영전문대학원 행정실",
    "기술경영전문대학원행정실": "기술경영전문대학원 행정실",
    "기술경영전문대학원행정팀": "기술경영전문대학원 행정실",
    "에너지환경대학원(그린스쿨)": "에너지환경대학원(그린스쿨) 행정실",
    "에너지환경대학원(그린스쿨)행정실": "에너지환경대학원(그린스쿨) 행정실",
    "에너지환경대학원(그린스쿨)행정팀": "에너지환경대학원(그린스쿨) 행정실",
    # ONE-STOP서비스센터는 인문·사회계, 자연계, 의료공제가 독립적으로
    # 근로장학생을 모집한다. 계열 표기가 없는 공고는 인문·사회계 창구의
    # 관행적 표기로 보고, 위치·과거 표기는 각 공식 센터명으로 통일한다.
    "one-stop서비스센터": "one-stop서비스센터(인문·사회계)",
    "one-stop서비스센터(인문계)": "one-stop서비스센터(인문·사회계)",
    "인문계 one-stop서비스센터": "one-stop서비스센터(인문·사회계)",
    "인문·사회계 one-stop서비스센터": "one-stop서비스센터(인문·사회계)",
    "중앙광장 지하 one-stop서비스센터": "one-stop서비스센터(인문·사회계)",
    "자연계 one-stop서비스센터": "one-stop서비스센터(자연계)",
    "미디어대학 행정팀": "미디어대학행정팀",
    # 미디어학부가 미디어대학으로 개편되기 전 사용한 동일 행정조직 명칭.
    "미디어학부행정실": "미디어대학행정팀",
    "미디어학부행정팀": "미디어대학행정팀",
    # 본관 202호 재무 조직의 과거 명칭.
    "재무부": "재정팀",
    # 백주년기념삼성관 박물관 312호 대학 기록 조직의 과거 명칭.
    "대학기록실": "대학기록팀",
    # 고려대학교박물관 도슨트·학예 근무지의 시기별 표기 — KOSAF 명부의
    # 공식 명칭인 박물관 학예기록팀으로 통일한다(2026-08-11 병합).
    "박물관": "박물관 학예기록팀",
    "학예부": "박물관 학예기록팀",
    "학예기록팀": "박물관 학예기록팀",
    # 국제관 223호 국제대학 행정조직의 과거 학부 명칭.
    "국제학부행정실": "국제대학행정팀",
    "국제학부행정팀": "국제대학행정팀",
    # 국제관 223호·02-3290-1391의 과거 행정실 표기.
    "국제대학 행정실": "국제대학행정팀",
    "국제대학행정실": "국제대학행정팀",
    # 운초우선교육관 401호 사범대 행정조직의 축약·과거 표기.
    "사범대학행정팀": "사범대학행정실",
    "사범대학 행정팀": "사범대학행정실",
    "사범대행정팀": "사범대학행정실",
    "사범대행정실": "사범대학행정실",
    "사범대학 행정실": "사범대학행정실",
    # 최신 공고에서 행정팀을 조직명으로 쓰고, 행정실은 같은 사무실 표기다.
    "안암학사 행정실": "안암학사행정팀",
    "안암학사행정실": "안암학사행정팀",
    "자유전공학부 행정실": "자유전공학부행정팀",
    "자유전공학부행정실": "자유전공학부행정팀",
    "외국어센터 행정실": "외국어센터행정팀",
    "외국어센터행정실": "외국어센터행정팀",
    # 검토된 실제 근무부서와 위치·과거 표기.
    "융합에너지공학과 행정실": "융합에너지공학과",
    "행정고시동": "안암학사 고시동 행정실",
    "서울캠퍼스 안암학사 고시동 행정실": "안암학사 고시동 행정실",
    "생명환경과학대학원 행정실": "생명환경과학대학원행정팀",
    "생명환경과학대학원행정실": "생명환경과학대학원행정팀",
    "생명환경과학대학원 행정팀": "생명환경과학대학원행정팀",
    # 상위기관·실무팀 또는 시기별 명칭으로 확인된 동일 근무지.
    "지속가능경영팀": "지속가능원",
    "인재발굴처": "입학처",
    "입학전형관리팀": "입학처",
    "창업지원팀": "크림슨창업지원단",
    "크림슨창업지원단 행정실": "크림슨창업지원단",
    # 중앙광장 B113호 사회공헌원의 과거 지원조직 명칭.
    "사회공헌지원부": "사회공헌원",
    "사회공헌지원팀": "사회공헌원",
    # 학업코칭 조직의 과거 기관/실무팀 명칭.
    "교수학습개발원": "교수학습지원센터",
    "교수학습지원팀": "교수학습지원센터",
    "학부대학 교수학습지원센터": "교수학습지원센터",
    "교수학습개발원 원격교육센터": "원격교육센터",
    "학부대학 원격교육센터": "원격교육센터",
    "경영대학 행정팀": "경영대학행정팀",
    "경영대학 행정실": "경영대학행정실",
    # R&D센터 418호의 동일 조직으로 이번 검토에서 확인한 표기.
    "ku-kist융합대학원 행정실": "ku-kist융합대학원행정팀",
    # 경영대학 산하기관의 최신 공고·근무장소 표기.
    "경영대학 스타트업연구원": "스타트업연구원 행정실",
    "스타트업 연구원 행정실": "스타트업연구원 행정실",
    "경영전문대학원": "경영전문대학원행정팀",
    "경영대학 홍보팀/학장실": "경영대학 홍보팀·학장실",
    "경영대학 홍보팀 · 학장실": "경영대학 홍보팀·학장실",
    # 의학도서관은 시설명이고, 공식 운영 부서명은 의학정보관리팀이다.
    "의학도서관": "의학정보관리팀",
    "학생처 student success center": "student success center",
    "교무처 교육혁신팀": "교육혁신팀",
    "산학협력단 연구지원팀": "연구지원팀",
    "국제어학원 한국어센터": "한국어센터",
    "국제처 국제교류팀": "국제교류팀",
    "국제처 국제교육팀": "국제교육팀",
    "국제처 글로벌서비스센터": "글로벌서비스센터",
    # 중앙도서관 3층의 같은 상호대차 근무지를 가리키는 표기.
    "상호대차실": "중앙도서관 상호대차센터",
    "제2자료실 내 상호대차센터": "중앙도서관 상호대차센터",
    "중앙도서관 상호대차실": "중앙도서관 상호대차센터",
    "중앙도서관 제2자료실 내 상호대차센터": "중앙도서관 상호대차센터",
}

_LIBRARY_WORKSITES = ("중앙도서관", "과학도서관")
_BUSINESS_ADMIN_KEY = "경영대학행정팀"
_BUSINESS_ADMIN_OFFICE_KEY = "경영대학행정실"
_BUSINESS_GRADUATE_KEY = "경영전문대학원행정팀"
_BUSINESS_PUBLICITY_KEY = "경영대학 홍보팀·학장실"
_MOT_ADMIN_KEY = "기술경영전문대학원 행정실"
_GREEN_SCHOOL_ADMIN_KEY = "에너지환경대학원(그린스쿨) 행정실"
_JOINT_GRADUATE_ADMIN_IDENTITIES = {
    "공학대학원·에너지환경대학원(그린스쿨)·기술경영전문대학원행정실",
    "공학대학원·에너지환경대학원(그린스쿨)·기술경영전문대학원행정팀",
}
_CANONICAL_DISPLAY_NAMES = {
    "중앙도서관 학술정보서비스팀": "중앙도서관 학술정보서비스팀",
    _MOT_ADMIN_KEY: _MOT_ADMIN_KEY,
    _GREEN_SCHOOL_ADMIN_KEY: _GREEN_SCHOOL_ADMIN_KEY,
    "one-stop서비스센터(인문·사회계)": "ONE-STOP서비스센터(인문·사회계)",
    "one-stop서비스센터(자연계)": "ONE-STOP서비스센터(자연계)",
    "one-stop서비스센터(의료공제)": "ONE-STOP서비스센터(의료공제)",
    "미디어대학행정팀": "미디어대학행정팀",
    "재정팀": "재정팀",
    "대학기록팀": "대학기록팀",
    "박물관 학예기록팀": "박물관 학예기록팀",
    "국제대학행정팀": "국제대학행정팀",
    "사범대학행정실": "사범대학행정실",
    "안암학사행정팀": "안암학사행정팀",
    "자유전공학부행정팀": "자유전공학부행정팀",
    "외국어센터행정팀": "외국어센터행정팀",
    "융합에너지공학과": "융합에너지공학과",
    "안암학사 고시동 행정실": "안암학사 고시동 행정실",
    "생명환경과학대학원행정팀": "생명환경과학대학원행정팀",
    "지속가능원": "지속가능원",
    "입학처": "입학처",
    "크림슨창업지원단": "크림슨창업지원단",
    "스타트업연구원 행정실": "스타트업연구원 행정실",
    "중앙도서관 상호대차센터": "중앙도서관 상호대차센터",
    "사회공헌원": "사회공헌원",
    "교수학습지원센터": "교수학습지원센터",
    "원격교육센터": "원격교육센터",
    "국제교류팀": "국제교류팀",
    "국제교육팀": "국제교육팀",
    "글로벌서비스센터": "글로벌서비스센터",
    "학생지원팀": "학생지원팀",
    "의학정보관리팀": "의학정보관리팀",
    _BUSINESS_ADMIN_KEY: _BUSINESS_ADMIN_KEY,
    _BUSINESS_GRADUATE_KEY: _BUSINESS_GRADUATE_KEY,
    _BUSINESS_PUBLICITY_KEY: _BUSINESS_PUBLICITY_KEY,
}


def qualify_special_library_worksite(worksite_name: str | None, *sources: str | None) -> str:
    """중앙·과학도서관은 소속 팀을 붙여 별도 근무지명으로 만든다."""
    library = ""
    for value in (worksite_name, *sources):
        text = str(value or "")
        library = next((name for name in _LIBRARY_WORKSITES if name in text), "")
        if library:
            break
    if not library:
        return str(worksite_name or "").strip()

    name = str(worksite_name or "").strip()
    for prefix in _PREFIXES:
        if name.startswith(prefix):
            name = name[len(prefix):].strip()
            break
    name = re.sub(r"^\[[^\]]*\]\s*", "", name)
    name = re.sub(r"^도서관\s+", "", name)
    if library == "중앙도서관" and name in {
        "학술정보개발팀",
        "중앙도서관 학술정보개발팀",
    }:
        return "학술정보개발팀"
    if library == "중앙도서관" and name in {
        "상호대차실",
        "상호대차센터",
        "제2자료실 내 상호대차센터",
        "중앙도서관 상호대차실",
        "중앙도서관 상호대차센터",
        "중앙도서관 제2자료실 내 상호대차센터",
    }:
        return "중앙도서관 상호대차센터"
    if not name or name == library:
        return "중앙도서관 학술정보서비스팀" if library == "중앙도서관" else library
    if name.startswith(f"{library} "):
        return name
    return f"{library} {name}"


def normalize_worksite_name(name: str | None) -> str:
    """근무지명을 소스 간 매칭용 정규화 키로 변환.

    - '[태그]' 제거, 대학 접두어 제거, 공백 1칸 축약, 소문자, 양끝 트림.
    - SSC '고려대학교 물리학과'와 KUPID '물리학과'가 같은 키가 되게 한다.
    """
    if not name:
        return ""
    s = str(name)
    s = s.replace("\xa0", " ")
    # 바깥 이모지/장식은 제거하되, 이름 전체를 감싼 대괄호는 내용만 보존한다.
    s = re.sub(r"^[^\w가-힣\[(]+", "", s)
    s = re.sub(r"[^\w가-힣\])]+$", "", s)
    whole_bracket = re.fullmatch(r"\s*\[([^\]]+)\]\s*", s)
    if whole_bracket:
        s = whole_bracket.group(1)
    else:
        s = re.sub(r"\[[^\]]*\]", " ", s)      # 문장 앞 [게시판 태그] 제거
    s = re.sub(r"\s+", " ", s).strip()
    for p in _PREFIXES:
        if s.startswith(p):
            s = s[len(p):].strip()
            break
    s = re.sub(r"\s+", " ", s).strip().lower()
    s = re.sub(r"(?<=[a-z0-9-])\s+(?=[가-힣])", "", s)
    # 사회공헌원이 시기별로 사용한 영문 약칭은 같은 조직의 표시 변화다.
    s = re.sub(r"\s*\((?:kusso|kusr|kuis)\)\s*$", "", s)
    # 팀 아래 파트/담당은 별도 근무지로 만들지 않는다. 담당자·담당업무처럼
    # 조직명이 아닌 표현은 이 패턴에 들어오지 않는다.
    subunit = re.fullmatch(
        r"(.+?팀)\s*(?:[-·]\s*)?[^()\s·/-]{0,20}(?:파트|담당)",
        s,
    )
    if subunit:
        s = subunit.group(1)
    return _EXPLICIT_ALIASES.get(s, s)


def worksite_identity_key(name: str | None) -> str:
    """Comparison-only key that absorbs harmless spacing and separators.

    The stored normalized name remains readable. This stricter key is used only
    to prevent a second worksite from being created for ``A / B`` vs ``A·B`` or
    Korean spacing variations.
    """
    s = normalize_worksite_name(name)
    s = s.replace("/", "·").replace("ㆍ", "·").replace("・", "·")
    s = re.sub(r"\s*·\s*", "·", s)
    return re.sub(r"\s+", "", s)


def is_joint_graduate_admin_name(name: str | None) -> bool:
    """공학·그린스쿨·기술경영이 함께 적힌 포털 공동 게시부서인지 판정한다."""
    identity = worksite_identity_key(name)
    return (
        identity in _JOINT_GRADUATE_ADMIN_IDENTITIES
        or (
            "공학대학원" in identity
            and "에너지환경대학원" in identity
            and "기술경영전문대학원" in identity
            and identity.endswith(("행정실", "행정팀"))
        )
    )


def canonicalize_worksite_display_name(name: str | None) -> str:
    """Return the school-worksite label shown beneath its organization.

    ``organization_name`` already carries the university, so a leading
    university prefix is redundant in ``workplace_name``. Confirmed aliases
    also use one stable display spelling.
    """
    if not name:
        return ""
    display = str(name).replace("\xa0", " ")
    display = re.sub(r"\s+", " ", display).strip()
    for prefix in _PREFIXES:
        if display.startswith(prefix):
            display = display[len(prefix):].strip()
            break
    if not display:
        return ""
    normalized = normalize_worksite_name(display)
    return _CANONICAL_DISPLAY_NAMES.get(normalized, display)


def resolve_worksite_name(worksite_name: str | None, *evidence: str | None) -> str:
    """Resolve a supplied label using explicit organization evidence.

    A source's posting department can be broader than the actual workplace.
    Reassign only known ambiguous families, and only from explicit organization
    phrases in the title/body. Addresses and phone numbers are deliberately not
    used as standalone identity keys.
    """
    name = canonicalize_worksite_display_name(worksite_name)
    normalized = normalize_worksite_name(name)
    text = "\n".join(str(value or "") for value in evidence)

    if is_joint_graduate_admin_name(name):
        compact_text = re.sub(r"\s+", "", text)
        candidates = []
        if "기술경영전문대학원" in compact_text:
            candidates.append(_MOT_ADMIN_KEY)
        if (
            "에너지환경대학원" in compact_text
            or "그린스쿨" in compact_text
        ):
            candidates.append(_GREEN_SCHOOL_ADMIN_KEY)
        # 공동 게시부서명 자체는 근무지 근거가 아니다. 본문·제목에서 한
        # 대학원만 명확할 때만 분리하고, 없거나 둘 다면 기존 이름을 남겨
        # worksite_resolution의 검토 큐로 보낸다.
        if len(set(candidates)) == 1:
            return candidates[0]
        return name

    one_stop_keys = {
        "one-stop서비스센터(인문·사회계)",
        "one-stop서비스센터(자연계)",
        "one-stop서비스센터(의료공제)",
    }
    if normalized in one_stop_keys:
        compact_text = re.sub(r"\s+", "", text).lower()
        if normalized == "one-stop서비스센터(의료공제)" or "의료공제" in compact_text:
            return "ONE-STOP서비스센터(의료공제)"
        if (
            normalized == "one-stop서비스센터(자연계)"
            or "one-stop서비스센터(자연계)" in compact_text
            or "자연계one-stop서비스센터" in compact_text
        ):
            return "ONE-STOP서비스센터(자연계)"
        return "ONE-STOP서비스센터(인문·사회계)"

    if normalized == _BUSINESS_GRADUATE_KEY:
        return _BUSINESS_GRADUATE_KEY
    if normalized == _BUSINESS_PUBLICITY_KEY:
        return _BUSINESS_PUBLICITY_KEY
    if normalized not in {_BUSINESS_ADMIN_KEY, _BUSINESS_ADMIN_OFFICE_KEY}:
        return name

    if "경영전문대학원" in text:
        return _BUSINESS_GRADUATE_KEY
    if re.search(r"경영대학\s*홍보팀\s*[/·]\s*학장실", text):
        return _BUSINESS_PUBLICITY_KEY
    return _BUSINESS_ADMIN_KEY
