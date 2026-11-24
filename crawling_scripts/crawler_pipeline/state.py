"""Small, atomic, gitignored local state for incremental crawling."""
from __future__ import annotations

import json
import os
from copy import deepcopy
from dataclasses import dataclass
from datetime import date, timedelta
from pathlib import Path

STATE_VERSION = 1
MAX_FAILURE_ATTEMPTS = 3
RETRY_DELAYS_DAYS = (1, 3)
DEFAULT_DAILY_LLM_LIMIT = 5
PARSE_CACHE_VERSION = 2


def _empty_source() -> dict:
    return {
        "last_success_posted_date": None,
        "processed_ids": [],
        "failed_ids": {},
        "pending_ids": {},
        "deferred_ids": {},
        "blocked_until": None,
    }


@dataclass
class CrawlerState:
    path: Path
    data: dict

    @classmethod
    def load(cls, path: Path) -> "CrawlerState":
        if path.exists():
            data = json.loads(path.read_text(encoding="utf-8"))
            if data.get("version") != STATE_VERSION:
                raise ValueError("unsupported crawler state version")
        else:
            data = {
                "version": STATE_VERSION,
                "sources": {"ssc": _empty_source(), "kupid": _empty_source()},
                "last_completed_date": None,
                "parse_cache": {},
                "llm_budget": {},
            }
        data.setdefault("parse_cache", {})
        data.setdefault("llm_budget", {})
        for source in ("ssc", "kupid"):
            data.setdefault("sources", {}).setdefault(source, _empty_source())
            data["sources"][source].setdefault("pending_ids", {})
            data["sources"][source].setdefault("deferred_ids", {})
        return cls(path=path, data=data)

    def save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.path.with_suffix(self.path.suffix + ".tmp")
        temporary.write_text(
            json.dumps(self.data, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        os.replace(temporary, self.path)

    def source(self, name: str) -> dict:
        return self.data["sources"][name]

    def candidate_date(self, name: str, posted_at: str | None) -> bool:
        watermark = self.source(name).get("last_success_posted_date")
        if not watermark:
            raise ValueError(f"{name} watermark is not initialized")
        return bool(posted_at and str(posted_at)[:10] >= watermark)

    def is_processed(self, name: str, external_id: str) -> bool:
        return str(external_id) in set(self.source(name).get("processed_ids") or [])

    def is_failed(self, name: str, external_id: str) -> bool:
        return str(external_id) in (self.source(name).get("failed_ids") or {})

    def should_retry(self, name: str, external_id: str,
                     today: date | None = None) -> bool:
        row = (self.source(name).get("failed_ids") or {}).get(str(external_id))
        if not row:
            return False
        attempts = int(row.get("attempts") or 0)
        if row.get("exhausted") or attempts >= MAX_FAILURE_ATTEMPTS:
            return False
        next_retry = row.get("next_retry_date")
        return not next_retry or next_retry <= (today or date.today()).isoformat()

    def is_pending(self, name: str, external_id: str) -> bool:
        return str(external_id) in (self.source(name).get("pending_ids") or {})

    def is_deferred(self, name: str, external_id: str) -> bool:
        return str(external_id) in (self.source(name).get("deferred_ids") or {})

    def mark_processed(self, name: str, external_id: str, posted_at: str) -> None:
        source = self.source(name)
        ids = set(source.get("processed_ids") or [])
        ids.add(str(external_id))
        source["processed_ids"] = sorted(ids)
        day = str(posted_at)[:10]
        current = source.get("last_success_posted_date")
        if day and (not current or day > current):
            source["last_success_posted_date"] = day
            # IDs older than the watermark are no longer needed. The caller may
            # replace this list with boundary-day IDs after a successful scan.
        source.get("failed_ids", {}).pop(str(external_id), None)
        source.get("pending_ids", {}).pop(str(external_id), None)
        source.get("deferred_ids", {}).pop(str(external_id), None)

    def mark_failed(self, name: str, external_id: str, message: str,
                    today: date | None = None) -> int:
        failed = self.source(name).setdefault("failed_ids", {})
        row = failed.setdefault(str(external_id), {"attempts": 0, "error": ""})
        row["attempts"] += 1
        row["error"] = str(message)[:500]
        attempts = row["attempts"]
        exhausted = attempts >= MAX_FAILURE_ATTEMPTS
        row["exhausted"] = exhausted
        row["next_retry_date"] = (
            None
            if exhausted
            else (
                (today or date.today())
                + timedelta(days=RETRY_DELAYS_DAYS[attempts - 1])
            ).isoformat()
        )
        return row["attempts"]

    def mark_pending(self, name: str, external_id: str, queue_id: int | None) -> None:
        pending = self.source(name).setdefault("pending_ids", {})
        pending[str(external_id)] = {"queue_id": queue_id}
        self.source(name).get("failed_ids", {}).pop(str(external_id), None)
        self.source(name).get("deferred_ids", {}).pop(str(external_id), None)

    def mark_deferred(self, name: str, external_id: str, reason: str) -> None:
        deferred = self.source(name).setdefault("deferred_ids", {})
        deferred[str(external_id)] = {"reason": str(reason)[:100]}
        self.source(name).get("failed_ids", {}).pop(str(external_id), None)

    def block_until_tomorrow(self, name: str, today: date | None = None) -> str:
        blocked = ((today or date.today()) + timedelta(days=1)).isoformat()
        self.source(name)["blocked_until"] = blocked
        return blocked

    def is_blocked(self, name: str, today: date | None = None) -> bool:
        value = self.source(name).get("blocked_until")
        return bool(value and value > (today or date.today()).isoformat())

    @staticmethod
    def parse_cache_key(source_ids: list[tuple[str, str]]) -> str:
        suffix = "|".join(
            f"{source}:{external_id}"
            for source, external_id in sorted(
                (str(source), str(external_id))
                for source, external_id in source_ids
            )
        )
        return f"v{PARSE_CACHE_VERSION}|{suffix}"

    def get_cached_parse(self, source_ids: list[tuple[str, str]]) -> dict | None:
        cached = self.data.setdefault("parse_cache", {}).get(
            self.parse_cache_key(source_ids)
        )
        return deepcopy(cached) if isinstance(cached, dict) else None

    def cache_parse(self, source_ids: list[tuple[str, str]], parsed: dict) -> None:
        self.data.setdefault("parse_cache", {})[
            self.parse_cache_key(source_ids)
        ] = deepcopy(parsed)

    def clear_parse_cache(self, source_ids: list[tuple[str, str]]) -> None:
        self.data.setdefault("parse_cache", {}).pop(
            self.parse_cache_key(source_ids),
            None,
        )

    def _daily_budget(self, today: date | None = None) -> dict:
        day = (today or date.today()).isoformat()
        budget = self.data.setdefault("llm_budget", {})
        if budget.get("date") != day:
            budget.clear()
            budget.update({"date": day, "used": 0, "bonus": 0})
        return budget

    def reserve_llm_call(self, today: date | None = None) -> bool:
        budget = self._daily_budget(today)
        allowed = DEFAULT_DAILY_LLM_LIMIT + int(budget.get("bonus") or 0)
        if int(budget.get("used") or 0) >= allowed:
            return False
        budget["used"] = int(budget.get("used") or 0) + 1
        return True

    def grant_llm_calls(self, count: int = 5, today: date | None = None) -> dict:
        if count <= 0:
            raise ValueError("LLM quota grant must be positive")
        budget = self._daily_budget(today)
        budget["bonus"] = int(budget.get("bonus") or 0) + int(count)
        return self.llm_budget_summary(today)

    def llm_budget_summary(self, today: date | None = None) -> dict:
        budget = self._daily_budget(today)
        allowed = DEFAULT_DAILY_LLM_LIMIT + int(budget.get("bonus") or 0)
        used = int(budget.get("used") or 0)
        return {
            "date": budget["date"],
            "used": used,
            "allowed": allowed,
            "remaining": max(0, allowed - used),
        }
