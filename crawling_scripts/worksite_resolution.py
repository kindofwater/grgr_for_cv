"""Deterministic, human-in-the-loop worksite identity resolution.

Exact canonical names and previously approved aliases are free and automatic.
Unknown names or explicit organization conflicts are queued before any LLM
posting parse is attempted.
"""
from __future__ import annotations

import re
from difflib import SequenceMatcher

from worksite_norm import (
    is_joint_graduate_admin_name,
    normalize_worksite_name,
    qualify_special_library_worksite,
    resolve_worksite_name,
    worksite_identity_key,
)

UNIVERSITY_ID = 1
WORKSITE_TYPE = "school"
MAX_CANDIDATES = 3

_EMAIL_RE = re.compile(r"[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}")
_PHONE_RE = re.compile(r"(?<!\d)(?:0\d{1,2}[-.\s]?)?\d{3,4}[-.\s]?\d{4}(?!\d)")
_ORG_SUFFIX = (
    r"(?:행정팀|행정실|지원팀|관리팀|도서관|센터|학과|학부|대학원|"
    r"연구원|연구소|사업단|파트|담당|처|팀|실|부|원)"
)
_ORG_FROM_RE = re.compile(
    rf"(?m)^(?:[-*•]\s*)?([^\n:：]{{2,100}}?{_ORG_SUFFIX}(?:\([^)\n]*\))?)"
    rf"\s*(?:에서|에서는)(?=\s|$)"
)
_BRACKET_RE = re.compile(r"^\s*\[([^\]]+)\]")
_WORK_FIELD_KEY_RE = re.compile(
    r"(?<![가-힣])근무\s*(부서|처|장소|지)(?![가-힣])"
)
_NON_ORGANIZATION_ROOMS = ("사무실", "자료실", "강의실", "연구실", "탕비실")
_ORG_FALSE_POSITIVE_RE = re.compile(
    r"(?:안녕하세요|모집\s*인원|대표하여|학생들|담당할|관련\s*업무|본\s*대학원)"
)
_EVIDENCE_LINE_RE = re.compile(
    r"(근무\s*(?:장소|부서|지)|근무할|근무하실|행정팀|행정실|도서관|"
    r"센터|학과|학부|대학원|연구원|연구소)"
)


def _record_text(record: dict) -> str:
    return "\n".join(str(record.get(key) or "") for key in (
        "title", "body", "raw_text", "job_description", "extra_notes",
        "work_department", "work_location", "근무부서",
    ))


def _work_field_values(text: str) -> list[tuple[str, str]]:
    """Extract workplace field values even when a line has numbering/brackets.

    A heading-only line such as ``[근무장소]`` may use the following line as
    its value. The Korean-boundary check deliberately excludes words such as
    ``근무지원서``.
    """
    lines = [line.strip() for line in str(text or "").splitlines()]
    values: list[tuple[str, str]] = []
    for index, line in enumerate(lines):
        match = _WORK_FIELD_KEY_RE.search(line)
        if not match:
            continue
        # Keep a closing parenthesis when it belongs to the field value, as in
        # ``행정실(R&D센터 418호)``. A parenthesized heading such as
        # ``(근무장소)`` still has no value and falls through to the next line.
        tail = line[match.end():].strip(" \t-–—·:：]}")
        if tail == ")":
            tail = ""
        if not tail:
            for following in lines[index + 1:]:
                if not following:
                    continue
                if _WORK_FIELD_KEY_RE.search(following):
                    break
                if re.match(r"^\s*(?:\d+[.)]|[-*•]|\[[^\]]+])\s*", following):
                    candidate = re.sub(
                        r"^\s*(?:\d+[.)]|[-*•])\s*", "", following
                    ).strip()
                else:
                    candidate = following
                if re.match(r"^[가-힣A-Za-z ]{1,30}\s*[:：]", candidate):
                    break
                tail = candidate
                break
        if tail:
            values.append((match.group(1), tail))
    return values


def _looks_like_organization(value: str) -> bool:
    value = str(value or "").strip(" -_·:：")
    return bool(
        value
        and len(value) <= 80
        and not value.startswith(("및 ", "또는 ", "등 "))
        and not _ORG_FALSE_POSITIVE_RE.search(value)
        and not value.endswith(_NON_ORGANIZATION_ROOMS)
        and re.search(_ORG_SUFFIX + r"(?:\([^)\n]*\))?$", value)
    )


def _organization_from_field(value: str) -> str:
    """Return an organization embedded in a work department/location field."""
    value = re.sub(r"\s+", " ", str(value or "")).strip(" -_·:：")
    if not value:
        return ""

    without_parens = re.sub(r"\([^)]*\)", " ", value)
    without_parens = re.sub(r"\s+", " ", without_parens).strip()
    candidates = []

    # Prefer text after an explicit floor/room marker.
    tail = re.sub(
        r"^.*(?:지하\s*\d+\s*층|\d+\s*층|\d+(?:[-A-Za-z0-9]*)\s*호(?:실)?)\s*",
        "",
        without_parens,
    ).strip()
    if tail and tail != without_parens:
        candidates.append(tail)
    candidates.append(without_parens)

    # Parentheses often contain the operating department after an address.
    candidates.extend(re.findall(r"\(([^()]*)\)", value))

    # A facility name before the floor marker can itself be the workplace.
    prefix = re.split(
        r"(?:지하\s*\d+\s*층|\d+\s*층|\d+(?:[-A-Za-z0-9]*)\s*호(?:실)?)",
        without_parens,
        maxsplit=1,
    )[0].strip()
    if prefix and prefix != without_parens:
        candidates.append(prefix)

    for candidate in candidates:
        candidate = re.split(r"\s+(?:또는|및)\s+", candidate, maxsplit=1)[0].strip()
        if _looks_like_organization(candidate):
            return candidate
    return ""


def _dedupe_organizations(values: list[str]) -> list[str]:
    out = []
    seen = set()
    for value in values:
        identity = worksite_identity_key(value)
        if identity and identity not in seen:
            seen.add(identity)
            out.append(value)
    return out


def strongest_explicit_worksite_names(record: dict) -> list[str]:
    """Return only the strongest available workplace evidence tier."""
    title = str(record.get("title") or "")
    text = _record_text(record)

    direct_values = []
    for key in ("work_department", "근무부서"):
        direct = _organization_from_field(str(record.get(key) or ""))
        if direct:
            direct_values.append(direct)
    if direct_values:
        return _dedupe_organizations(direct_values)

    fields = _work_field_values(text)
    department_values = []
    for field_name, field_value in fields:
        if field_name in {"부서", "처"}:
            organization = _organization_from_field(field_value)
            if organization:
                department_values.append(organization)
    if department_values:
        return _dedupe_organizations(department_values)

    location_values = []
    for _field_name, field_value in fields:
        organization = _organization_from_field(field_value)
        if organization:
            location_values.append(organization)
    if location_values:
        return _dedupe_organizations(location_values)

    from_values = [
        value
        for match in _ORG_FROM_RE.finditer(text)
        if _looks_like_organization(
            value := match.group(1).strip(" -_·:")
        )
    ]
    if from_values:
        return _dedupe_organizations(from_values)

    bracket = _BRACKET_RE.match(title)
    if bracket and _looks_like_organization(bracket.group(1).strip()):
        return [bracket.group(1).strip()]
    return []


def preferred_explicit_worksite_name(record: dict) -> str:
    """Choose the first organization from the strongest evidence tier."""
    values = strongest_explicit_worksite_names(record)
    return values[0] if values else ""


def resolved_record_name(record: dict) -> str:
    explicit = preferred_explicit_worksite_name(record)
    supplied_name = record.get("worksite_name")
    # 대학원도서관은 이 공고의 모집 부서가 아니라 인재양성팀 사무실이
    # 입주한 건물이다. 건물명이 강한 근무장소 필드에 있더라도 부서를
    # 도서관으로 바꾸지 않는다.
    if (
        normalize_worksite_name(supplied_name) == "인재양성팀"
        and worksite_identity_key(explicit)
        == worksite_identity_key("서울캠퍼스 대학원도서관")
    ):
        explicit = str(supplied_name or "")
    title = record.get("title")
    scoped_name = qualify_special_library_worksite(
        explicit or record.get("worksite_name"),
        title,
        record.get("body"),
        record.get("raw_text"),
    )
    return resolve_worksite_name(
        scoped_name,
        title,
        record.get("body"),
        record.get("raw_text"),
        record.get("job_description"),
        record.get("extra_notes"),
    )


def extract_explicit_worksite_names(record: dict) -> list[str]:
    """Extract only strong organization phrases; false negatives are safer."""
    title = str(record.get("title") or "")
    text = _record_text(record)
    values: list[str] = []
    bracket = _BRACKET_RE.match(title)
    if bracket and re.search(_ORG_SUFFIX + r"$", bracket.group(1).strip()):
        values.append(bracket.group(1).strip())
    values.extend(
        organization
        for _field_name, field_value in _work_field_values(text)
        if (organization := _organization_from_field(field_value))
    )
    values.extend(
        value
        for match in _ORG_FROM_RE.finditer(text)
        if _looks_like_organization(
            value := match.group(1).strip(" -_·:")
        )
    )

    out = []
    seen = set()
    for value in values:
        resolved = resolve_worksite_name(value, title, text)
        norm = worksite_identity_key(resolved)
        if norm and norm not in seen:
            seen.add(norm)
            out.append(resolved)
    return out


def safe_evidence_text(record: dict, limit: int = 1500) -> str:
    """Keep short organization/location evidence and remove contact details."""
    title = str(record.get("title") or "").strip()
    lines = [line.strip() for line in _record_text(record).splitlines() if line.strip()]
    selected = []
    if title:
        selected.append(f"제목: {title}")
    selected.extend(line for line in lines if _EVIDENCE_LINE_RE.search(line))
    if len(selected) <= int(bool(title)):
        selected.extend(lines[:3])
    text = "\n".join(dict.fromkeys(selected))
    text = _EMAIL_RE.sub("[이메일 제거]", text)
    text = _PHONE_RE.sub("[연락처 제거]", text)
    return text[:limit]


def _phone_digits(value) -> str:
    return re.sub(r"\D", "", str(value or ""))


def _phone_match(input_phone: str, candidate_phone: str) -> str | None:
    left, right = _phone_digits(input_phone), _phone_digits(candidate_phone)
    if len(left) < 8 or len(right) < 8:
        return None
    if left == right:
        return "exact"
    if len(left) == len(right) and left[:-1] == right[:-1]:
        return "extension_group"
    return None


def rank_worksite_candidates(name: str, evidence: str, worksites: list[dict],
                             office_phone: str | None = None,
                             limit: int = MAX_CANDIDATES) -> list[dict]:
    """Return explainable fuzzy suggestions; never use them for auto-merge."""
    norm = worksite_identity_key(name)
    evidence_norm = worksite_identity_key(evidence)
    ranked = []
    for row in worksites:
        candidate = worksite_identity_key(
            row.get("normalized_name") or row.get("workplace_name")
        )
        if not candidate:
            continue
        score = SequenceMatcher(None, norm, candidate).ratio()
        if norm and (norm in candidate or candidate in norm):
            score = max(score, 0.72)
        if candidate and candidate in evidence_norm:
            score = min(1.0, score + 0.18)
        phone_matches = [
            _phone_match(office_phone, posting.get("office_phone"))
            for posting in (row.get("postings") or [])
        ]
        phone_match = (
            "exact" if "exact" in phone_matches
            else "extension_group" if "extension_group" in phone_matches
            else None
        )
        if phone_match == "exact":
            score = max(score, 0.98)
        elif phone_match == "extension_group":
            score = max(score, 0.9)
        if score < 0.35:
            continue
        item = {
            "worksite_id": row["id"],
            "workplace_name": row.get("workplace_name"),
            "address": row.get("address"),
            "score": round(score, 3),
        }
        if phone_match:
            item["phone_match"] = phone_match
        ranked.append(item)
    ranked.sort(key=lambda item: (-item["score"], item["worksite_id"]))
    return ranked[:limit]


def _active_worksites(client) -> list[dict]:
    return (
        client.table("worksites")
        .select("id, workplace_name, normalized_name, address, postings(office_phone)")
        .eq("university_id", UNIVERSITY_ID)
        .eq("type", WORKSITE_TYPE)
        .is_("deleted_at", "null")
        .execute()
        .data
    ) or []


def _existing_queue(client, source: str, external_id: str) -> dict | None:
    rows = (
        client.table("worksite_resolution_queue")
        .select("id, status, resolved_worksite_id, resolution_method")
        .eq("university_id", UNIVERSITY_ID)
        .eq("source", source)
        .eq("external_id", external_id)
        .limit(1)
        .execute()
        .data
    ) or []
    return rows[0] if rows else None


def _paired_source_conflict(record: dict) -> tuple[bool, list[str]]:
    """Compare explicit workplace evidence in paired source records."""
    groups: list[set[str]] = []
    names: list[str] = []
    for source_record in record.get("_source_records") or []:
        strongest = strongest_explicit_worksite_names(source_record)
        identities = {
            _evidence_resolved_identity(value, source_record) for value in strongest
            if _evidence_resolved_identity(value, source_record)
        }
        if identities:
            groups.append(identities)
            names.extend(strongest)

    paired_conflict = (
        len(groups) >= 2
        and not set.intersection(*groups)
    )
    sonnet_identity = _evidence_resolved_identity(
        str(record.get("work_department") or ""), record
    )
    sonnet_conflict = bool(
        sonnet_identity
        and any(sonnet_identity not in group for group in groups)
    )
    return paired_conflict or sonnet_conflict, _dedupe_organizations(names)


def _evidence_resolved_identity(value: str, record: dict) -> str:
    """공동 게시부서는 실제 대학원이 명시된 경우에만 그 근무지로 해석한다."""
    if not is_joint_graduate_admin_name(value):
        return worksite_identity_key(value)
    resolved = resolve_worksite_name(
        value,
        record.get("title"),
        record.get("body"),
        record.get("raw_text"),
        record.get("job_description"),
        record.get("extra_notes"),
    )
    return worksite_identity_key(resolved)


def _enqueue_review(client, payload: dict):
    """Use the atomic database RPC in production, with a small test fallback."""
    if hasattr(client, "rpc"):
        return client.rpc(
            "enqueue_worksite_review", {"p_payload": payload}
        ).execute()
    return (
        client.table("worksite_resolution_queue")
        .upsert(payload, on_conflict="university_id,source,external_id")
        .execute()
    )


def resolve_worksite_record(client, record: dict) -> dict:
    """Resolve exactly, use a learned alias, or enqueue for human review."""
    source = str(record.get("source") or "").strip()
    external_id = str(record.get("external_id") or "").strip()
    if not source or not external_id:
        raise ValueError("source and external_id are required for worksite resolution")

    queued = _existing_queue(client, source, external_id)
    worksites = _active_worksites(client)
    by_id = {row["id"]: row for row in worksites}
    queued_target_active = bool(
        queued
        and queued.get("resolved_worksite_id") in by_id
    )
    if queued and queued["status"] == "resolved" and queued_target_active:
        return {
            "status": "matched",
            "worksite_id": queued["resolved_worksite_id"],
            "method": queued.get("resolution_method") or "human",
            "queue_id": queued["id"],
            "resolved_name": by_id[queued["resolved_worksite_id"]].get("workplace_name"),
        }
    if queued and queued["status"] == "skipped":
        return {"status": "skipped", "queue_id": queued["id"], "method": "human_skip"}

    resolved_name = resolved_record_name(record)
    norm = normalize_worksite_name(resolved_name)
    if not norm:
        raise ValueError("worksite name normalizes to empty")
    identity = worksite_identity_key(resolved_name)
    exact = next((
        row for row in worksites
        if worksite_identity_key(row.get("normalized_name") or row.get("workplace_name"))
        == identity
    ), None)

    aliases = (
        client.table("worksite_aliases")
        .select("source, worksite_id, resolution_method")
        .eq("university_id", UNIVERSITY_ID)
        .eq("normalized_alias", norm)
        .in_("source", [source, "*"])
        .execute()
        .data
    ) or []
    aliases.sort(key=lambda row: row.get("source") != source)
    alias = next((row for row in aliases if row.get("worksite_id") in by_id), None)

    explicit_names = extract_explicit_worksite_names(record)
    paired_conflict, paired_names = _paired_source_conflict(record)
    explicit_names = _dedupe_organizations(explicit_names + paired_names)
    strongest_names = strongest_explicit_worksite_names(record)
    explicit_norms = {
        _evidence_resolved_identity(value, record) for value in strongest_names
        if _evidence_resolved_identity(value, record)
    }
    conflicting = sorted(value for value in explicit_norms if value != identity)
    requires_confirmation = bool(record.get("worksite_requires_confirmation"))
    inactive_human_target = bool(
        queued
        and queued["status"] == "resolved"
        and not queued_target_active
    )

    if not conflicting and not paired_conflict and not requires_confirmation and exact:
        return {
            "status": "matched",
            "worksite_id": exact["id"],
            "method": "exact_name",
            "resolved_name": exact.get("workplace_name"),
        }
    if not conflicting and not paired_conflict and not requires_confirmation and alias:
        return {
            "status": "matched",
            "worksite_id": alias["worksite_id"],
            "method": alias.get("resolution_method") or "alias",
            "resolved_name": by_id[alias["worksite_id"]].get("workplace_name"),
        }
    evidence = safe_evidence_text(record)
    candidates = rank_worksite_candidates(
        resolved_name, evidence, worksites, record.get("office_phone")
    )
    if inactive_human_target:
        reason = "resolved_target_inactive"
    elif paired_conflict or conflicting:
        reason = "explicit_conflict"
    elif requires_confirmation:
        reason = "missing_worksite"
    else:
        reason = "new_name"
    payload = {
        "university_id": UNIVERSITY_ID,
        "source": source,
        "external_id": external_id,
        "raw_worksite_name": str(record.get("worksite_name") or resolved_name)[:200],
        "normalized_worksite": norm[:200],
        "title": str(record.get("title") or "")[:500] or None,
        "evidence_text": evidence or None,
        "office_phone": str(record.get("office_phone") or "")[:30] or None,
        "resolution_reason": reason,
        "explicit_worksite_names": explicit_names,
        "candidate_worksite_ids": [item["worksite_id"] for item in candidates],
        "candidate_scores": candidates,
        "status": "pending",
        "updated_at": "now()",
    }
    # PostgREST does not interpret SQL expressions in JSON; omit updated_at and
    # let the database default cover inserts. Review actions set it explicitly.
    payload.pop("updated_at")
    response = _enqueue_review(client, payload)
    response_data = response.data
    row = (
        response_data[0]
        if isinstance(response_data, list) and response_data
        else response_data if isinstance(response_data, dict)
        else {}
    )
    return {
        "status": "pending",
        "queue_id": row.get("id") or (queued or {}).get("id"),
        "reason": reason,
        "resolved_name": resolved_name,
        "candidates": candidates,
    }
