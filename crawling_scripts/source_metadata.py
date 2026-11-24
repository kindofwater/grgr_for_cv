"""Stable source-list identity and explicit closure markers."""
from __future__ import annotations

import re

_CLOSED_STATUS = (
    r"(?:모집\s*마감|채용\s*마감|선발\s*마감|"
    r"모집\s*완료|채용\s*완료|선발\s*완료|마감)"
)
_CLOSED_MARKER_RE = re.compile(
    rf"\s*(?:\[\s*{_CLOSED_STATUS}\s*]|\(\s*{_CLOSED_STATUS}\s*\))\s*",
    re.IGNORECASE,
)


def title_has_strong_closed_marker(title: str | None) -> bool:
    """Only bracketed/parenthesized exact status words close an old posting."""
    return bool(_CLOSED_MARKER_RE.search(str(title or "")))


def title_without_closed_marker(title: str | None) -> str:
    return _CLOSED_MARKER_RE.sub(" ", str(title or "")).strip()
