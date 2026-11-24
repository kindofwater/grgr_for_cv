"""Select new rows, merge high-confidence pairs, parse once, and load."""
from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path

from .llm import LLMBudgetExceeded, LLMUnavailable, parse_posting
from .records import apply_parse, kupid_record, ssc_record
from .similarity import choose_representative, decide_duplicate
from .state import CrawlerState


@dataclass
class ProcessResult:
    candidates: int = 0
    parsed: int = 0
    merged: int = 0
    inserted: int = 0
    pending: int = 0
    deferred: int = 0
    failed: int = 0
    ai_calls_used: int = 0
    ai_calls_remaining: int = 0
    unavailable: str | None = None
    new_worksites: list[str] = field(default_factory=list)
    updated_worksites: list[str] = field(default_factory=list)
    updated_posting_titles: list[str] = field(default_factory=list)
    pending_queue_ids: list[int] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)


def _record_load_result(result: ProcessResult, outcome) -> None:
    if isinstance(outcome, dict):
        inserted = outcome.get("posting") == "inserted"
        result.inserted += int(inserted)
        worksite_name = str(outcome.get("worksite_name") or "").strip()
        if inserted and worksite_name and worksite_name not in result.updated_worksites:
            result.updated_worksites.append(worksite_name)
        posting_title = str(outcome.get("posting_title") or "").strip()
        if inserted and posting_title and posting_title not in result.updated_posting_titles:
            result.updated_posting_titles.append(posting_title)
        new_worksite = outcome.get("new_worksite")
        if new_worksite and new_worksite not in result.new_worksites:
            result.new_worksites.append(new_worksite)
    else:
        result.inserted += int(outcome == "inserted")


def _load_json(path: Path) -> list[dict]:
    if not path.exists():
        return []
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, list):
        raise ValueError(f"{path} must contain a JSON array")
    return value


def bootstrap_state(state: CrawlerState, ssc_rows: list[dict], kupid_rows: list[dict],
                    *, save: bool = True) -> bool:
    """Initialize from current caches so historical rows are never reprocessed."""
    changed = False
    for name, rows, adapter in (
        ("ssc", ssc_rows, ssc_record),
        ("kupid", kupid_rows, kupid_record),
    ):
        source = state.source(name)
        if source.get("last_success_posted_date"):
            continue
        records = [adapter(row) for row in rows]
        dated = [row for row in records if row.get("posted_at")]
        if not dated:
            raise ValueError(f"cannot initialize {name}: no posted dates in existing cache")
        source["last_success_posted_date"] = max(row["posted_at"] for row in dated)
        source["processed_ids"] = sorted({
            row["external_id"] for row in records if row.get("external_id")
        })
        changed = True
    if changed and save:
        state.save()
    return changed


def select_candidates(state: CrawlerState, rows: list[dict], source: str) -> list[dict]:
    adapter = ssc_record if source == "ssc" else kupid_record
    selected = []
    for raw in rows:
        row = adapter(raw)
        if not row["external_id"] or not row["posted_at"]:
            continue
        if state.is_processed(source, row["external_id"]):
            continue
        if state.is_pending(source, row["external_id"]):
            selected.append(row)
            continue
        if state.is_deferred(source, row["external_id"]):
            selected.append(row)
            continue
        if state.is_failed(source, row["external_id"]):
            if state.should_retry(source, row["external_id"]):
                selected.append(row)
            continue
        if not state.candidate_date(source, row["posted_at"]):
            continue
        selected.append(row)
    return selected


def pair_candidates(ssc_rows: list[dict], kupid_rows: list[dict]):
    remaining_kupid = list(kupid_rows)
    pairs = []
    singles = []
    for ssc in ssc_rows:
        best = None
        for kupid in remaining_kupid:
            decision = decide_duplicate(ssc, kupid)
            if decision.is_duplicate and (
                best is None or decision.body_score > best[0].body_score
            ):
                best = (decision, kupid)
        if best:
            remaining_kupid.remove(best[1])
            representative, supplement = choose_representative(ssc, best[1])
            pairs.append((representative, supplement, best[0]))
        else:
            singles.append((ssc, None, None))
    singles.extend((row, None, None) for row in remaining_kupid)
    return pairs + singles


def process_cached_new(*, state_path: Path, ssc_path: Path, kupid_path: Path,
                       anthropic_client, load_record=None, resolve_worksite=None,
                       dry_run: bool = False) -> ProcessResult:
    state = CrawlerState.load(state_path)
    budget_before = state.llm_budget_summary()
    ssc_raw, kupid_raw = _load_json(ssc_path), _load_json(kupid_path)
    if bootstrap_state(state, ssc_raw, kupid_raw, save=not dry_run):
        # First run only establishes the future-only boundary.
        return ProcessResult()

    ssc_new = select_candidates(state, ssc_raw, "ssc")
    kupid_new = select_candidates(state, kupid_raw, "kupid")
    result = ProcessResult(candidates=len(ssc_new) + len(kupid_new))
    if dry_run:
        # A dry run is a deterministic discovery preview: no Sonnet calls,
        # database writes, state mutations, or API-key requirement.
        result.ai_calls_remaining = budget_before["remaining"]
        return result

    valid_ssc = []
    for row in ssc_new:
        if row.get("validation_error"):
            result.failed += 1
            message = row["validation_error"]
            result.errors.append(f"ssc:{row['external_id']}: {message}")
            state.mark_failed("ssc", row["external_id"], message)
        else:
            valid_ssc.append(row)
    groups = pair_candidates(valid_ssc, kupid_new)

    queue = list(groups)
    while queue:
        representative, supplement, decision = queue.pop(0)
        source_ids = [(representative["source"], representative["external_id"])]
        if supplement:
            source_ids.append((supplement["source"], supplement["external_id"]))
        try:
            parsed = state.get_cached_parse(source_ids)
            if parsed is None:
                def reserve_call():
                    if not state.reserve_llm_call():
                        raise LLMBudgetExceeded("daily AI call limit reached")
                    # Persist before the request because a timeout may still
                    # have consumed provider tokens.
                    state.save()

                parsed = parse_posting(
                    anthropic_client,
                    representative,
                    supplement,
                    before_request=reserve_call,
                )
                state.cache_parse(source_ids, parsed)
                # Persist immediately so a database/load failure never spends
                # another Sonnet call for the same source records.
                state.save()
            if parsed.get("conflict_fields"):
                # The deterministic check found a likely duplicate, but Sonnet
                # saw a structured conflict. Keep the records separate.
                if supplement:
                    state.clear_parse_cache(source_ids)
                    state.save()
                    queue.insert(0, (supplement, None, None))
                    queue.insert(0, (representative, None, None))
                    continue
                raise ValueError(f"Sonnet conflict: {parsed['conflict_fields']}")
            canonical = apply_parse(representative, parsed)
            canonical["_source_records"] = [
                row for row in (representative, supplement) if row
            ]
            resolution = None
            if resolve_worksite:
                resolution = resolve_worksite(canonical)
                if resolution.get("status") == "pending":
                    result.pending += 1
                    queue_id = resolution.get("queue_id")
                    if queue_id and queue_id not in result.pending_queue_ids:
                        result.pending_queue_ids.append(queue_id)
                    for source, external_id in source_ids:
                        state.mark_pending(source, external_id, queue_id)
                    continue
                if resolution.get("status") == "skipped":
                    state.clear_parse_cache(source_ids)
                    for source, external_id in source_ids:
                        posted = representative["posted_at"]
                        if supplement and source == supplement["source"]:
                            posted = supplement["posted_at"]
                        state.mark_processed(source, external_id, posted)
                    continue
            if load_record:
                outcome = (
                    load_record(canonical, resolution)
                    if resolve_worksite else load_record(canonical)
                )
                _record_load_result(result, outcome)
            result.parsed += 1
            result.merged += int(supplement is not None)
            state.clear_parse_cache(source_ids)
            for source, external_id in source_ids:
                posted = representative["posted_at"]
                if supplement and source == supplement["source"]:
                    posted = supplement["posted_at"]
                state.mark_processed(source, external_id, posted)
        except LLMBudgetExceeded as exc:
            result.deferred += len(source_ids)
            for source, external_id in source_ids:
                state.mark_deferred(source, external_id, str(exc))
        except LLMUnavailable as exc:
            # The provider failed, not the posting. Keep its retry budget
            # intact and stop here: the remaining candidates would only burn
            # the daily allowance on calls that cannot succeed today.
            result.deferred += len(source_ids)
            result.unavailable = str(exc)
            result.errors.append(f"llm unavailable: {exc}")
            for source, external_id in source_ids:
                state.mark_deferred(source, external_id, str(exc))
            break
        except Exception as exc:
            result.failed += 1
            result.errors.append(f"{representative['source']}:{representative['external_id']}: {exc}")
            for source, external_id in source_ids:
                state.mark_failed(source, external_id, str(exc))

    budget_after = state.llm_budget_summary()
    result.ai_calls_used = budget_after["used"] - budget_before["used"]
    result.ai_calls_remaining = budget_after["remaining"]
    state.save()
    return result
