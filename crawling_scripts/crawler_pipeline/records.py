"""Adapters from source crawler records to one canonical raw shape."""
from __future__ import annotations

import json
import re

from deadline_policy import decide_deadline, extract_recruitment_deadline
from upsert_worksites import kupid_external_id, resolve_kupid_worksite_name
from worksite_norm import (
    normalize_worksite_name,
    qualify_special_library_worksite,
    resolve_worksite_name,
)

_ORG_SUFFIX_RE = re.compile(
    r"(?:팀|센터|center|실|처|학과|도서관|대학원|행정팀|행정실|사업단|연구소)"
    r"(?:\([^)]*\))?$",
    re.IGNORECASE,
)
_OFFICE_PHONE_RE = re.compile(
    r"(?<!\d)0(?:2|[3-6]\d)[-. ]?\d{3,4}[-. ]?\d{4}(?!\d)"
)


def attachment_names(value) -> list[str]:
    """Return clean, de-duplicated attachment labels from either crawler."""
    if isinstance(value, str):
        try:
            value = json.loads(value)
        except json.JSONDecodeError:
            value = []
    if isinstance(value, dict):
        value = [value]
    if not isinstance(value, list):
        return []

    names = []
    for item in value:
        name = item.get("label") if isinstance(item, dict) else item
        name = str(name or "").strip()
        if name and name not in names:
            names.append(name)
    return names


def _looks_like_worksite_name(value: str | None) -> bool:
    value = str(value or "").strip()
    return bool(normalize_worksite_name(value) and _ORG_SUFFIX_RE.search(value))


def _extract_org_before_recruit(text: str | None) -> str:
    match = re.match(r"(.+?)\s*근로장학생", str(text or "").strip())
    if not match:
        return ""
    candidate = match.group(1).strip(" -_·:[]()")
    return candidate if _looks_like_worksite_name(candidate) else ""


def _office_phone(value) -> str | None:
    match = _OFFICE_PHONE_RE.search(str(value or ""))
    return match.group(0).strip() if match else None


def infer_worksite_name(record: dict) -> str:
    """Infer the SSC worksite when its company field is only '고려대학교'."""
    company = str(record.get("company_name") or "").strip()
    title = str(record.get("title") or "").strip()
    match = re.match(r"^\[([^\]]+)\]\s*(.*)$", title)
    # 두 도서관은 상위 기관명과 하위 팀을 함께 보존한다. 회사명이 이미
    # '고려대학교 중앙도서관'처럼 들어와도, 제목의 실제 팀명을 우선한다.
    if match and ("중앙도서관" in title or "과학도서관" in title):
        bracket, rest = match.group(1).strip(), match.group(2).strip()
        detailed = _extract_org_before_recruit(rest)
        return qualify_special_library_worksite(detailed or bracket, title, company)

    if normalize_worksite_name(company):
        return qualify_special_library_worksite(company, title)

    if match:
        bracket, rest = match.group(1).strip(), match.group(2).strip()
        detailed = _extract_org_before_recruit(rest)
        if detailed:
            return qualify_special_library_worksite(detailed, title, company)
        if _looks_like_worksite_name(bracket):
            return qualify_special_library_worksite(bracket, title, company)

    return qualify_special_library_worksite(_extract_org_before_recruit(title) or company, title)


def _ssc_body(row: dict) -> str:
    text = str(row.get("detail_text") or "")
    marker = "\n내용\n"
    text = text.split(marker, 1)[1] if marker in text else text
    if "\n첨부파일" in text:
        text = text.split("\n첨부파일", 1)[0]
    return text.strip()


def _kupid_body(row: dict) -> str:
    text = str(row.get("_body") or row.get("detail_text") or "")
    if not row.get("_body") and text.startswith("제목 "):
        text = text.split("\n\n", 1)[1] if "\n\n" in text else text
    if "\n\n첨부파일" in text:
        text = text.split("\n\n첨부파일", 1)[0]
    return text.strip()


def ssc_record(row: dict) -> dict:
    worksite = infer_worksite_name(row)
    body = _ssc_body(row)
    worksite = resolve_worksite_name(worksite, row.get("title"), body)
    return {
        "source": "ssc",
        "external_id": str(row.get("external_id") or row.get("data_seq") or row.get("board_no") or ""),
        "worksite_name": worksite,
        "source_department": str(row.get("company_name") or ""),
        "normalized_worksite": normalize_worksite_name(worksite),
        "title": str(row.get("title") or ""),
        "posted_at": str(row.get("posted_at") or "")[:10],
        "recruit_until": str(row.get("recruit_until") or "")[:10],
        "recruit_until_estimated": False,
        "period_text": str(row.get("period_text") or ""),
        "source_url": str(row.get("detail_url") or ""),
        "source_closed_at": row.get("source_closed_at"),
        "source_closed_reason": row.get("source_closed_reason"),
        "attachment_names": attachment_names(row.get("attachment_names")),
        "body": body,
        "raw_text": body,
        "validation_error": None,
    }


def kupid_record(row: dict) -> dict:
    title = str(row.get("title") or "")
    department = str(row.get("department") or "")
    posted = str(row.get("registered_date") or row.get("posted_at") or "")[:10]
    body = _kupid_body(row)
    source_deadline = (
        str(row.get("due_date") or "")[:10]
        or extract_recruitment_deadline(body, posted)
        or ""
    )
    worksite = resolve_worksite_name(
        resolve_kupid_worksite_name(title, "", department),
        title,
        body,
    )
    return {
        "source": "kupid",
        "external_id": kupid_external_id(title, department, posted),
        "worksite_name": worksite,
        "source_department": department,
        "normalized_worksite": normalize_worksite_name(worksite),
        "title": title,
        "posted_at": posted,
        "recruit_until": source_deadline,
        "recruit_until_estimated": False,
        "period_text": source_deadline,
        "source_url": str(row.get("detail_url") or ""),
        "source_closed_at": row.get("source_closed_at"),
        "source_closed_reason": row.get("source_closed_reason"),
        "attachment_names": attachment_names(row.get("attachments_json")),
        "body": body,
        "raw_text": body,
        "validation_error": None,
    }


def classify_work_duration(parsed: dict) -> str:
    """Apply the 6-week policy deterministically when the parser found a duration."""
    days = parsed.get("work_period_days")
    if isinstance(days, bool):
        days = None
    try:
        days = int(days) if days is not None else None
    except (TypeError, ValueError):
        days = None
    if days is not None and days >= 0:
        return "long" if days >= 42 else "short"

    value = parsed.get("work_duration_type")
    return value if value in ("short", "long", "unknown") else "unknown"


def apply_parse(representative: dict, parsed: dict) -> dict:
    result = dict(representative)
    for key in (
        "hourly_wage", "recruit_count", "eligible_degree", "eligible_status",
        "job_description", "preference_notes", "extra_notes", "work_period_text",
        "work_time_text",
    ):
        result[key] = parsed.get(key)
    result["work_duration_type"] = classify_work_duration(parsed)
    result["posting_department"] = (
        parsed.get("posting_department")
        or representative.get("source_department")
    )
    result["work_department"] = parsed.get("work_department")
    result["work_location"] = parsed.get("work_location")
    result["worksite_evidence"] = parsed.get("worksite_evidence")
    result["office_phone"] = _office_phone(parsed.get("office_phone"))
    if result["work_department"]:
        result["worksite_name"] = str(result["work_department"]).strip()
        result["worksite_requires_confirmation"] = False
    else:
        # The source/heading-derived name is only a review candidate.  It must
        # not be silently accepted as the actual workplace.
        result["worksite_requires_confirmation"] = True

    deadline = decide_deadline(
        source=representative.get("source"),
        explicit_until=(
            representative.get("recruit_until") or parsed.get("recruit_until")
        ),
        posted_at=representative.get("posted_at"),
        first_seen_at=representative.get("first_seen_at"),
        work_start_date=(
            representative.get("work_start_date") or parsed.get("work_start_date")
        ),
    )
    result["recruit_until"] = deadline.recruit_until
    result["recruit_until_estimated"] = deadline.estimated
    result["deadline_basis"] = deadline.basis

    result["period_text"] = (
        representative.get("period_text")
        or parsed.get("recruitment_period_text")
        or result.get("recruit_until")
    )
    return result
