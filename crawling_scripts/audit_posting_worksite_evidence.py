"""Read-only audit for historical postings whose explicit workplace disagrees.

This script reports candidates only. It never moves postings or edits worksites.
"""
from __future__ import annotations

import json

from crawler_config import get_supabase_credentials
from supabase import create_client
from worksite_norm import worksite_identity_key
from worksite_resolution import strongest_explicit_worksite_names

SOURCES = ("ssc", "kupid", "everytime_manual")
_CONFIRMED_LOCATION_ONLY_PAIRS = {
    (
        worksite_identity_key("인재양성팀"),
        worksite_identity_key("서울캠퍼스 대학원도서관"),
    ),
    (
        worksite_identity_key("경영전문대학원행정팀"),
        worksite_identity_key("경영대학교 경영전문대학원"),
    ),
    (
        worksite_identity_key("교수학습지원센터"),
        worksite_identity_key(
            "교수학습개발원 교수학습개발원 학업코칭 파트"
        ),
    ),
    (
        worksite_identity_key("재정팀"),
        worksite_identity_key("재무부(본관 202호)"),
    ),
}


def _same_organization(actual_key: str, explicit_key: str) -> bool:
    if not actual_key or not explicit_key:
        return False
    if actual_key == explicit_key:
        return True
    if (actual_key, explicit_key) in _CONFIRMED_LOCATION_ONLY_PAIRS:
        return True
    # Parent-organization prefixes and room suffixes are common in source
    # prose (e.g. "디지털정보처 정보인프라팀"). Containment is evidence of
    # the same unit, not a suspicious merge.
    return (
        len(actual_key) >= 3
        and len(explicit_key) >= 3
        and (actual_key in explicit_key or explicit_key in actual_key)
    )


def audit_rows(rows: list[dict]) -> list[dict]:
    issues = []
    for row in rows:
        worksite = row.get("worksites") or {}
        actual_name = worksite.get("workplace_name")
        actual_key = worksite_identity_key(actual_name)
        explicit = strongest_explicit_worksite_names({
            "title": row.get("title"),
            "raw_text": row.get("raw_text"),
        })
        explicit_keys = {
            worksite_identity_key(value) for value in explicit
            if worksite_identity_key(value)
        }
        if not explicit_keys or any(
            _same_organization(actual_key, explicit_key)
            for explicit_key in explicit_keys
        ):
            continue
        issues.append({
            "posting_id": row.get("id"),
            "source": row.get("source"),
            "external_id": row.get("external_id"),
            "current_worksite_id": worksite.get("id"),
            "current_worksite": actual_name,
            "explicit_worksites": explicit,
            "action": "review_only",
        })
    return issues


def fetch_rows(client) -> list[dict]:
    rows = []
    start = 0
    page_size = 1000
    while True:
        page = (
            client.table("postings")
            .select(
                "id,source,external_id,title,raw_text,"
                "worksites!inner(id,university_id,type,deleted_at,workplace_name)"
            )
            .in_("source", list(SOURCES))
            .is_("deleted_at", "null")
            .eq("worksites.university_id", 1)
            .eq("worksites.type", "school")
            .is_("worksites.deleted_at", "null")
            .range(start, start + page_size - 1)
            .execute()
            .data
        ) or []
        rows.extend(page)
        if len(page) < page_size:
            break
        start += page_size
    return rows


def main() -> int:
    url, key = get_supabase_credentials()
    client = create_client(url, key)
    rows = fetch_rows(client)
    issues = audit_rows(rows)
    print(json.dumps({
        "checked": len(rows),
        "suspected_merges": len(issues),
        "auto_changes": 0,
        "issues": issues,
    }, ensure_ascii=False, indent=2))
    return 1 if issues else 0


if __name__ == "__main__":
    raise SystemExit(main())
