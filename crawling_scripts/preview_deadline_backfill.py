"""Read-only preview for the approved 21-day school-posting deadline policy.

The default command never writes. Applying requires both ``--apply`` and the
literal confirmation phrase, and the database RPC aborts if the target count
has changed since this preview.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json

from crawler_config import get_supabase_credentials
from deadline_policy import decide_deadline
from supabase import create_client

SOURCES = {"ssc", "kupid", "everytime_manual"}
HUMAN_CONFIRMED_CLOSED_IDS = {7257}
CONFIRMATION = "APPLY_21_DAY_BACKFILL"


def _effective_active(row: dict, today: dt.date) -> bool:
    deadline = row.get("recruit_until")
    return (
        str(deadline)[:10] >= today.isoformat()
        if deadline
        else bool(row.get("is_active"))
    )


def build_preview(rows: list[dict], today: dt.date) -> dict:
    changes = []
    exclusions = {
        "manual_override": 0,
        "explicit_deadline": 0,
        "placeholder": 0,
        "unsupported_source": 0,
    }
    protected = []
    for row in rows:
        if row.get("is_placeholder"):
            exclusions["placeholder"] += 1
            continue
        if row.get("source") not in SOURCES:
            exclusions["unsupported_source"] += 1
            continue
        if row.get("manual_override"):
            exclusions["manual_override"] += 1
            continue
        if (
            not row.get("recruit_until_estimated")
            and row.get("recruit_until")
        ):
            exclusions["explicit_deadline"] += 1
            continue
        if row.get("id") in HUMAN_CONFIRMED_CLOSED_IDS:
            protected.append({
                "id": row["id"],
                "title": row.get("title"),
                "workplace_name": (row.get("worksites") or {}).get("workplace_name"),
                "action": "keep_closed_human_confirmed",
            })
            continue

        source = row["source"]
        created_at = row.get("created_at")
        decision = decide_deadline(
            source=source,
            posted_at=created_at if source in {"ssc", "kupid"} else None,
            first_seen_at=created_at if source == "everytime_manual" else None,
        )
        new_row = {**row, "recruit_until": decision.recruit_until}
        old_active = _effective_active(row, today)
        new_active = _effective_active(new_row, today)
        transition = (
            "reopen" if not old_active and new_active
            else "close" if old_active and not new_active
            else "unchanged_status"
        )
        changes.append({
            "id": row["id"],
            "title": row.get("title"),
            "workplace_name": (row.get("worksites") or {}).get("workplace_name"),
            "old_recruit_until": (
                str(row.get("recruit_until"))[:10]
                if row.get("recruit_until") else None
            ),
            "new_recruit_until": decision.recruit_until,
            "deadline_basis": decision.basis,
            "old_active": old_active,
            "new_active": new_active,
            "transition": transition,
        })

    return {
        "as_of": today.isoformat(),
        "expected_apply_count": len(changes),
        "changed_deadlines": sum(
            item["old_recruit_until"] != item["new_recruit_until"]
            for item in changes
        ),
        "reopened": sum(item["transition"] == "reopen" for item in changes),
        "closed": sum(item["transition"] == "close" for item in changes),
        "protected": protected,
        "exclusions": exclusions,
        "changes": changes,
    }


def fetch_school_postings(client) -> list[dict]:
    rows = []
    start = 0
    page_size = 1000
    while True:
        page = (
            client.table("postings")
            .select(
                "id,source,title,created_at,recruit_until,"
                "recruit_until_estimated,is_active,is_placeholder,"
                "manual_override,worksites!inner(university_id,type,"
                "deleted_at,workplace_name)"
            )
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
    parser = argparse.ArgumentParser(description="21일 추정마감 백필 미리보기")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--confirm")
    args = parser.parse_args()

    url, key = get_supabase_credentials()
    client = create_client(url, key)
    preview = build_preview(fetch_school_postings(client), dt.date.today())
    if args.json:
        print(json.dumps(preview, ensure_ascii=False, indent=2))
    else:
        print(
            f"대상 {preview['expected_apply_count']}건 / "
            f"날짜 변경 {preview['changed_deadlines']}건 / "
            f"재개 {preview['reopened']}건 / 마감 {preview['closed']}건"
        )
        for item in preview["changes"]:
            if item["transition"] != "unchanged_status":
                print(
                    f"  [{item['transition']}] #{item['id']} "
                    f"{item['workplace_name']}: "
                    f"{item['old_recruit_until']} → {item['new_recruit_until']}"
                )
        for item in preview["protected"]:
            print(
                f"  [사람 확인 보호] #{item['id']} "
                f"{item['workplace_name']}: 닫힘 유지"
            )
        print("제외:", json.dumps(preview["exclusions"], ensure_ascii=False))

    if not args.apply:
        return 0
    if args.confirm != CONFIRMATION:
        parser.error(f"--apply에는 --confirm {CONFIRMATION}가 필요합니다")
    response = client.rpc("apply_school_deadline_backfill", {
        "p_expected_count": preview["expected_apply_count"],
    }).execute()
    print(json.dumps({"applied": response.data}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
