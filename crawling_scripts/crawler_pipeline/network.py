"""Shared conservative request pacing and access-block detection."""
from __future__ import annotations

import random
import time

MIN_REQUEST_DELAY_SEC = 5.0
MAX_REQUEST_DELAY_SEC = 10.0
BLOCK_STATUS_CODES = {403, 429}
BLOCK_MARKERS = (
    "접근이 제한",
    "비정상적인 접근",
    "too many requests",
    "temporarily blocked",
    "access denied",
)


class SourceBlockedError(RuntimeError):
    """The source appears to be rate-limiting or blocking this client."""


def ensure_not_blocked(response, source: str) -> None:
    status = int(getattr(response, "status_code", 0) or 0)
    if status in BLOCK_STATUS_CODES:
        raise SourceBlockedError(f"{source} returned HTTP {status}")
    body = str(getattr(response, "text", "") or "").lower()
    if any(marker in body for marker in BLOCK_MARKERS):
        raise SourceBlockedError(f"{source} returned an access-block page")


def polite_delay() -> None:
    time.sleep(random.uniform(MIN_REQUEST_DELAY_SEC, MAX_REQUEST_DELAY_SEC))
