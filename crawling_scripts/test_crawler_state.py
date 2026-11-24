import json
from datetime import date

import pytest

from crawler_pipeline.state import CrawlerState


def test_state_is_atomic_and_inclusive_at_watermark(tmp_path):
    path = tmp_path / "crawler_state.json"
    state = CrawlerState.load(path)
    state.source("ssc")["last_success_posted_date"] = "2026-07-22"
    state.mark_processed("ssc", "55", "2026-07-22")
    state.save()

    loaded = CrawlerState.load(path)
    assert loaded.candidate_date("ssc", "2026-07-22")
    assert loaded.candidate_date("ssc", "2026-07-23")
    assert not loaded.candidate_date("ssc", "2026-07-21")
    assert loaded.is_processed("ssc", "55")
    assert json.loads(path.read_text(encoding="utf-8"))["version"] == 1


def test_missing_watermark_fails_closed(tmp_path):
    state = CrawlerState.load(tmp_path / "crawler_state.json")
    with pytest.raises(ValueError, match="watermark"):
        state.candidate_date("kupid", "2026-07-22")


def test_block_until_tomorrow(tmp_path):
    state = CrawlerState.load(tmp_path / "crawler_state.json")
    assert state.block_until_tomorrow("kupid", date(2026, 7, 24)) == "2026-07-25"
    assert state.is_blocked("kupid", date(2026, 7, 24))
    assert not state.is_blocked("kupid", date(2026, 7, 25))


def test_failed_id_is_remembered_for_retry(tmp_path):
    state = CrawlerState.load(tmp_path / "crawler_state.json")
    state.mark_failed("ssc", "55", "temporary error")
    assert state.is_failed("ssc", "55")
    state.mark_processed("ssc", "55", "2026-07-22")
    assert not state.is_failed("ssc", "55")


def test_failed_id_uses_backoff_and_stops_after_three_attempts(tmp_path):
    state = CrawlerState.load(tmp_path / "crawler_state.json")
    today = date(2026, 7, 28)

    state.mark_failed("ssc", "55", "first", today)
    assert not state.should_retry("ssc", "55", today)
    assert state.should_retry("ssc", "55", date(2026, 7, 29))

    state.mark_failed("ssc", "55", "second", today)
    assert not state.should_retry("ssc", "55", date(2026, 7, 30))
    assert state.should_retry("ssc", "55", date(2026, 7, 31))

    state.mark_failed("ssc", "55", "third", today)
    failed = state.source("ssc")["failed_ids"]["55"]
    assert failed["attempts"] == 3
    assert failed["exhausted"] is True
    assert failed["next_retry_date"] is None
    assert not state.should_retry("ssc", "55", date(2030, 1, 1))


def test_parse_cache_is_keyed_independently_of_source_order(tmp_path):
    state = CrawlerState.load(tmp_path / "crawler_state.json")
    source_ids = [("ssc", "10"), ("kupid", "abc")]
    parsed = {"job_description": "admin"}
    state.cache_parse(source_ids, parsed)

    assert state.get_cached_parse(list(reversed(source_ids))) == parsed
    state.clear_parse_cache(source_ids)
    assert state.get_cached_parse(source_ids) is None


def test_pending_id_is_retried_and_cleared_when_processed(tmp_path):
    state = CrawlerState.load(tmp_path / "crawler_state.json")
    state.mark_pending("ssc", "55", 12)
    assert state.is_pending("ssc", "55")
    assert state.source("ssc")["pending_ids"]["55"]["queue_id"] == 12
    state.mark_processed("ssc", "55", "2026-07-22")
    assert not state.is_pending("ssc", "55")


def test_daily_llm_budget_defaults_to_five_and_can_be_extended(tmp_path):
    state = CrawlerState.load(tmp_path / "crawler_state.json")
    today = date(2026, 7, 29)
    for _ in range(5):
        assert state.reserve_llm_call(today)
    assert not state.reserve_llm_call(today)
    assert state.llm_budget_summary(today)["remaining"] == 0
    state.grant_llm_calls(5, today)
    assert state.reserve_llm_call(today)
    assert state.llm_budget_summary(today) == {
        "date": "2026-07-29",
        "used": 6,
        "allowed": 10,
        "remaining": 4,
    }


def test_ai_deferred_id_is_retried_without_becoming_failure(tmp_path):
    state = CrawlerState.load(tmp_path / "crawler_state.json")
    state.mark_deferred("kupid", "abc", "daily AI call limit reached")
    assert state.is_deferred("kupid", "abc")
    assert not state.is_failed("kupid", "abc")
    state.mark_processed("kupid", "abc", "2026-07-22")
    assert not state.is_deferred("kupid", "abc")
