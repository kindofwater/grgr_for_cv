"""Inspect business-school worksite assignments without modifying Supabase."""
from __future__ import annotations

import argparse
import json
import sys

from crawler_config import get_supabase_credentials
from supabase import create_client


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--reviews-only", action="store_true")
    parser.add_argument("--summary", action="store_true")
    args = parser.parse_args()
    sys.stdout.reconfigure(encoding="utf-8")
    url, key = get_supabase_credentials()
    client = create_client(url, key)
    business_admin_names = (
        "경영대학행정팀",
        "경영대학 행정팀",
        "경영전문대학원행정팀",
    )
    worksites = (
        client.table("worksites")
        .select("id,workplace_name,normalized_name,address,deleted_at")
        .eq("university_id", 1)
        .eq("type", "school")
        .in_("workplace_name", business_admin_names)
        .execute()
        .data
    )
    publicity_worksites = (
        client.table("worksites")
        .select("id,workplace_name,normalized_name,address,deleted_at")
        .eq("university_id", 1)
        .eq("type", "school")
        .ilike("workplace_name", "%홍보%")
        .execute()
        .data
    )
    by_id = {row["id"]: row for row in (*worksites, *publicity_worksites)}
    worksites = list(by_id.values())
    worksite_ids = [row["id"] for row in worksites]
    postings = (
        client.table("postings")
        .select(
            "id,worksite_id,source,external_id,title,source_url,raw_text,"
            "job_description,work_period_text,work_time_text,created_at,deleted_at"
        )
        .in_("worksite_id", worksite_ids)
        .order("created_at")
        .execute()
        .data
    )
    reviews = (
        client.table("reviews")
        .select("id,worksite_id,work_year,work_semester,work_content,opinion,deleted_at")
        .in_("worksite_id", worksite_ids)
        .order("created_at")
        .execute()
        .data
    )
    if args.reviews_only:
        payload = {"reviews": reviews}
    elif args.summary:
        names = {row["id"]: row["workplace_name"] for row in worksites}
        payload = {
            "worksites": worksites,
            "posting_counts": {
                names[worksite_id]: sum(
                    row["worksite_id"] == worksite_id and row["deleted_at"] is None
                    for row in postings
                )
                for worksite_id in worksite_ids
            },
            "posting_ids": {
                names[worksite_id]: [
                    row["id"] for row in postings
                    if row["worksite_id"] == worksite_id and row["deleted_at"] is None
                ]
                for worksite_id in worksite_ids
            },
            "review_count": len([row for row in reviews if row["deleted_at"] is None]),
        }
    else:
        payload = {"worksites": worksites, "postings": postings, "reviews": reviews}
    print(json.dumps(
        payload,
        ensure_ascii=False,
        indent=2,
    ))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
