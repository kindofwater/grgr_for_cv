"""Load human-curated job postings into Supabase without retaining post bodies.

Input is a JSON array of canonical records.  The loader intentionally stores
only structured job information; it does not accept ``raw_text`` or contact
fields.  Re-submitting unchanged data is idempotent through a content-derived
external ID.

Usage:
    python crawling_scripts/manual_postings.py data/manual_everytime_postings.json
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import re
from pathlib import Path

from crawler_config import get_supabase_credentials
from supabase import create_client
from upsert_worksites import upsert_crawl_notice, upsert_posting
from worksite_resolution import resolve_worksite_record

SOURCE = "everytime_manual"
ALLOWED_FIELDS = {
    "external_id", "worksite_name", "title", "source_url", "recruit_until",
    "recruit_until_estimated", "period_text", "hourly_wage", "recruit_count",
    "eligible_degree", "eligible_status", "job_description", "preference_notes",
    "extra_notes", "work_period_text", "work_duration_type", "work_time_text",
    "posted_at", "source_department", "work_department", "work_location",
    "office_phone", "work_start_date",
}

_MONTH_RE = re.compile(r"(\d+)\s*개월")
_WEEK_RE = re.compile(r"(\d+)\s*주")
_DATE_RE = re.compile(r"(20\d{2})[-./년]\s*(\d{1,2})[-./월]\s*(\d{1,2})")


def external_id(record: dict) -> str:
    """Stable, non-identifying key for an unchanged manually supplied posting."""
    payload = json.dumps(record, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()[:32]


def infer_work_duration_type(text: str | None) -> str | None:
    """Infer short/long from explicit duration text using the shared 42-day policy."""
    value = str(text or "")
    candidates: list[int] = []
    candidates.extend(int(months) * 30 for months in _MONTH_RE.findall(value))
    candidates.extend(int(weeks) * 7 for weeks in _WEEK_RE.findall(value))

    dates = []
    for year, month, day in _DATE_RE.findall(value):
        try:
            dates.append(dt.date(int(year), int(month), int(day)))
        except ValueError:
            continue
    if len(dates) >= 2:
        candidates.append((max(dates) - min(dates)).days + 1)

    if re.search(r"(?:한|1)\s*학기\s*이상", value):
        candidates.append(42)
    if not candidates:
        return None
    return "long" if max(candidates) >= 42 else "short"


def canonicalize(record: dict) -> dict:
    unexpected = set(record) - ALLOWED_FIELDS
    if unexpected:
        raise ValueError(f"unsupported fields: {', '.join(sorted(unexpected))}")
    if not str(record.get("worksite_name") or "").strip():
        raise ValueError("worksite_name is required")

    safe = {key: record.get(key) for key in ALLOWED_FIELDS if key in record}
    safe["worksite_name"] = safe["worksite_name"].strip()
    inferred_duration = infer_work_duration_type(safe.get("work_period_text"))
    if inferred_duration:
        safe["work_duration_type"] = inferred_duration
    safe["source"] = SOURCE
    supplied_external_id = str(safe.get("external_id") or "").strip()
    safe["external_id"] = supplied_external_id or external_id(safe)
    return safe


def load_json(path: Path) -> list[dict]:
    parsed = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(parsed, list):
        raise ValueError("input must be a JSON array")
    return [canonicalize(row) for row in parsed]


def main() -> int:
    parser = argparse.ArgumentParser(description="Load manually curated job postings")
    parser.add_argument("input", type=Path, help="JSON array of structured postings")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    records = load_json(args.input)
    if args.dry_run:
        print(json.dumps(records, ensure_ascii=False, indent=2))
        return 0

    url, key = get_supabase_credentials()
    client = create_client(url, key)
    stats = {
        "postings_inserted": 0,
        "postings_updated": 0,
        "postings_skipped_duplicate": 0,
        "pending": 0,
        "pending_queue_ids": [],
        "notice": None,
    }
    inserted_titles = []
    for record in records:
        resolution = resolve_worksite_record(client, record)
        if resolution["status"] == "pending":
            stats["pending"] += 1
            queue_id = resolution.get("queue_id")
            if queue_id is not None and queue_id not in stats["pending_queue_ids"]:
                stats["pending_queue_ids"].append(queue_id)
            continue
        if resolution["status"] == "skipped":
            continue
        outcome = upsert_posting(
            client,
            resolution["worksite_id"],
            record,
            dt.date.today(),
        )
        stats[f"postings_{outcome}"] += 1
        if outcome == "inserted":
            title = str(record.get("title") or "").strip()
            if title and title not in inserted_titles:
                inserted_titles.append(title)
    if stats["postings_inserted"]:
        stats["notice"] = upsert_crawl_notice(
            client,
            stats["postings_inserted"],
            posting_titles=inserted_titles,
        )
    print(json.dumps(stats, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
