from __future__ import annotations

import json
import sys
from collections import defaultdict

from worksite_norm import (
    canonicalize_worksite_display_name,
    normalize_worksite_name,
    worksite_identity_key,
)


def audit_worksite_rows(rows: list[dict]) -> dict:
    """Return normalization issues for active school worksites."""
    groups: dict[tuple[int, str], list[dict]] = defaultdict(list)
    empty_norm = []
    db_mismatches = []
    display_mismatches = []

    for row in rows:
        code_norm = normalize_worksite_name(row.get("workplace_name"))
        item = {
            "id": row.get("id"),
            "university_id": row.get("university_id"),
            "workplace_name": row.get("workplace_name"),
            "normalized_name": row.get("normalized_name") or "",
            "code_norm": code_norm,
            "canonical_display_name": canonicalize_worksite_display_name(
                row.get("workplace_name")
            ),
        }
        if not code_norm:
            empty_norm.append(item)
            continue
        groups[(
            int(row.get("university_id") or 0),
            worksite_identity_key(row.get("workplace_name")),
        )].append(item)
        if item["normalized_name"] != code_norm:
            db_mismatches.append(item)
        if item["workplace_name"] != item["canonical_display_name"]:
            display_mismatches.append(item)

    duplicates = {}
    for (university_id, norm), items in groups.items():
        if len(items) > 1:
            duplicates[f"{university_id}:{norm}"] = items

    return {
        "empty_code_norm": empty_norm,
        "duplicate_code_norms": duplicates,
        "db_norm_mismatches": db_mismatches,
        "display_name_mismatches": display_mismatches,
    }


def has_issues(report: dict) -> bool:
    return any(bool(value) for value in report.values())


def _make_client():
    from crawler_config import get_supabase_credentials
    from supabase import create_client

    url, key = get_supabase_credentials()
    return create_client(url, key)


def main() -> int:
    client = _make_client()
    rows = (
        client.table("worksites")
        .select("id, university_id, workplace_name, normalized_name")
        .eq("type", "school")
        .is_("deleted_at", "null")
        .execute()
        .data
    )
    report = audit_worksite_rows(rows)
    if has_issues(report):
        print("[FAIL] worksite normalization audit found issues")
        print(json.dumps(report, ensure_ascii=False, indent=2))
        return 1
    print(f"[OK] worksite normalization audit passed ({len(rows)} active school worksites)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
