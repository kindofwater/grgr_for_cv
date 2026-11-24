"""Command-line entry point for the future-only SSC/KUPID pipeline."""
from __future__ import annotations

import argparse
import contextlib
import json
import os
import sys
import uuid
from dataclasses import asdict
from datetime import date, datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "crawling_scripts"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

from anthropic_key import get_anthropic_api_key
from upsert_worksites import (
    _make_client,
    apply_source_closures,
    upsert_crawl_notice,
    upsert_posting,
)
from worksite_resolution import resolve_worksite_record

from crawler_pipeline.processor import bootstrap_state, process_cached_new
from crawler_pipeline.records import apply_parse, kupid_record, ssc_record
from crawler_pipeline.similarity import choose_representative, decide_duplicate
from crawler_pipeline.state import CrawlerState

DATA = ROOT / "data"
DEFAULT_STATE = DATA / "crawler_state.json"
DEFAULT_STATUS = DATA / "crawl_status.json"
SSC_RAW = DATA / "ssc_workstudy_raw.json"
KUPID_RAW = DATA / "kupid_workstudy_notices.json"
LOCK_FILE = DATA / "crawler_pipeline.lock"


def _anthropic_client():
    from anthropic import Anthropic

    key = get_anthropic_api_key()
    if not key:
        raise RuntimeError("ANTHROPIC_API_KEY is not configured")
    return Anthropic(api_key=key)


def _loader(client):
    def load(canonical: dict, resolution: dict) -> dict:
        worksite_id = resolution["worksite_id"]
        # The new cross-source matcher already made the conservative decision.
        # Do not let the older description+deadline shortcut silently collapse
        # an ambiguous pair that should remain as two postings.
        posting = upsert_posting(
            client,
            worksite_id,
            canonical,
            date.today(),
            check_legacy_duplicate=False,
        )
        return {
            "posting": posting,
            "new_worksite": None,
            "worksite_name": (
                resolution.get("resolved_name") or canonical.get("worksite_name")
            ),
            "posting_title": canonical.get("title"),
        }

    return load


def _write_status(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    temporary.replace(path)


@contextlib.contextmanager
def _pipeline_lock():
    """Serialize scheduled, notification-triggered, and direct CLI runs."""
    LOCK_FILE.parent.mkdir(parents=True, exist_ok=True)
    handle = LOCK_FILE.open("a+b")
    if handle.tell() == 0:
        handle.write(b"0")
        handle.flush()
    handle.seek(0)
    try:
        if os.name == "nt":
            import msvcrt
            msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
        else:
            import fcntl
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except (OSError, BlockingIOError):
        handle.close()
        raise RuntimeError("다른 크롤러 처리가 이미 실행 중입니다.")
    try:
        yield
    finally:
        handle.seek(0)
        if os.name == "nt":
            msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
        else:
            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
        handle.close()


def _main() -> int:
    parser = argparse.ArgumentParser(description="SSC/KUPID 신규 공고 통합 처리")
    parser.add_argument("--dry-run", action="store_true", help="DB와 상태 파일을 변경하지 않음")
    parser.add_argument("--initialize", action="store_true",
                        help="현재 캐시를 처리 완료 기준선으로 기록하고 종료")
    parser.add_argument("--sample-title",
                        help="양쪽 캐시의 제목 일부로 병합+Sonnet 1회 검증(DB/상태 변경 없음)")
    parser.add_argument("--state", type=Path, default=DEFAULT_STATE)
    parser.add_argument("--status", type=Path, default=DEFAULT_STATUS)
    parser.add_argument("--add-ai-quota", type=int, metavar="N",
                        help="오늘의 Sonnet 실제 요청 허용량을 N건 추가하고 종료")
    args = parser.parse_args()

    if args.add_ai_quota is not None:
        state = CrawlerState.load(args.state)
        summary = state.grant_llm_calls(args.add_ai_quota)
        state.save()
        print(json.dumps({"ai_quota": summary}, ensure_ascii=False))
        return 0

    ssc_rows = json.loads(SSC_RAW.read_text(encoding="utf-8"))
    kupid_rows = json.loads(KUPID_RAW.read_text(encoding="utf-8"))
    if args.initialize:
        changed = bootstrap_state(
            CrawlerState.load(args.state), ssc_rows, kupid_rows, save=True
        )
        print(json.dumps({"initialized": changed, "state": str(args.state)}, ensure_ascii=False))
        return 0

    if args.sample_title:
        ssc = next(
            ssc_record(row) for row in reversed(ssc_rows)
            if args.sample_title in str(row.get("title") or "")
        )
        kupid = next(
            kupid_record(row) for row in reversed(kupid_rows)
            if args.sample_title in str(row.get("title") or "")
        )
        decision = decide_duplicate(ssc, kupid)
        if not decision.is_duplicate:
            print(json.dumps({"matched": False, **asdict(decision)}, ensure_ascii=False))
            return 1
        representative, supplement = choose_representative(ssc, kupid)
        from crawler_pipeline.llm import parse_posting
        parsed = parse_posting(_anthropic_client(), representative, supplement)
        canonical = apply_parse(representative, parsed)
        safe = {
            key: value for key, value in canonical.items()
            if key not in {"body", "raw_text"}
        }
        print(json.dumps({
            "matched": True,
            "decision": asdict(decision),
            "representative": representative["source"],
            "canonical": safe,
        }, ensure_ascii=False, indent=2))
        return 0

    client = None if args.dry_run else _make_client()
    closure_records = [
        kupid_record(row) for row in kupid_rows
        if row.get("source_closed_at")
    ]
    closures_applied = (
        0 if args.dry_run else apply_source_closures(client, closure_records)
    )
    result = process_cached_new(
        state_path=args.state,
        ssc_path=SSC_RAW,
        kupid_path=KUPID_RAW,
        anthropic_client=None if args.dry_run else _anthropic_client(),
        load_record=None if args.dry_run else _loader(client),
        resolve_worksite=(
            None if args.dry_run
            else lambda record: resolve_worksite_record(client, record)
        ),
        dry_run=args.dry_run,
    )
    payload = {
        "run_id": str(uuid.uuid4()),
        "date": date.today().isoformat(),
        "completed_at": datetime.now(timezone.utc).isoformat(),
        "dry_run": args.dry_run,
        "source_closures_detected": len(closure_records),
        "source_closures_applied": closures_applied,
        **asdict(result),
        "notice": None,
    }

    if not args.dry_run and result.inserted:
        try:
            payload["notice"] = upsert_crawl_notice(
                client,
                result.inserted,
                posting_titles=result.updated_posting_titles,
            )
        except Exception as exc:
            # Core inserts remain successful. The Windows notification/status
            # makes the notice-only failure visible.
            payload["notice"] = "failed"
            result.errors.append(f"notice: {exc}")
            payload["errors"] = result.errors

    if not args.dry_run:
        final_state = CrawlerState.load(args.state)
        payload["deferred_total"] = sum(
            len(final_state.source(source).get("deferred_ids") or {})
            for source in ("ssc", "kupid")
        )
        payload["exhausted_total"] = sum(
            sum(
                bool(item.get("exhausted"))
                for item in (
                    final_state.source(source).get("failed_ids") or {}
                ).values()
            )
            for source in ("ssc", "kupid")
        )
        _write_status(args.status, payload)
    print(json.dumps(payload, ensure_ascii=False))
    if result.failed or result.unavailable:
        # An outage must not be mistaken for a quiet day: the batch marks the
        # run partial and the guard retries on the next trigger.
        return 1
    return 2 if payload["notice"] == "failed" else 0


def main() -> int:
    try:
        with _pipeline_lock():
            return _main()
    except RuntimeError as exc:
        print(json.dumps({"error": str(exc)}, ensure_ascii=False))
        return 3


if __name__ == "__main__":
    raise SystemExit(main())
