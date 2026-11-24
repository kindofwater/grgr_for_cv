"""Deterministic cross-source duplicate detection.

The detector deliberately prefers false negatives over false positives:
uncertain pairs remain as two postings.
"""
from __future__ import annotations

import math
import re
import unicodedata
from collections import Counter
from dataclasses import dataclass
from datetime import date
from difflib import SequenceMatcher

TITLE_THRESHOLD = 0.80
BODY_THRESHOLD = 0.90
MAX_POSTED_DAY_GAP = 3

_NON_ALNUM = re.compile(r"[^0-9a-z가-힣]+", re.IGNORECASE)
_SPACE = re.compile(r"\s+")
_WAGE = re.compile(r"(?<!\d)(\d{1,3}(?:,\d{3})+|\d{4,6})\s*원")
_COUNT = re.compile(r"(?:모집\s*인원|인원)\s*[:：]?\s*([0-9Oo○]{1,3})\s*명")
_TIME_RANGE = re.compile(
    r"(?<!\d)([01]?\d|2[0-3])\s*:\s*([0-5]\d)\s*[-~～]\s*"
    r"([01]?\d|2[0-3])\s*:\s*([0-5]\d)(?!\d)"
)
_EMAIL = re.compile(r"[\w.%+-]+\s*@\s*[\w.-]+\.[a-z]{2,}", re.IGNORECASE)
_PHONE = re.compile(r"0\d{1,2}[-)]\s?\d{3,4}[- ]\d{4}")
_WORK_PERIOD = re.compile(r"근무\s*기간\s*[:：]?\s*([^\n]+)")
_WORK_DAYS = re.compile(
    r"(?:월|화|수|목|금|토|일)(?:요일)?\s*[-~～]\s*(?:월|화|수|목|금|토|일)(?:요일)?"
    r"|(?:월|화|수|목|금|토|일)요일"
)


def _nfkc(value: str | None) -> str:
    return unicodedata.normalize("NFKC", str(value or "")).lower()


def normalize_title(value: str | None) -> str:
    return _SPACE.sub(" ", _NON_ALNUM.sub(" ", _nfkc(value))).strip()


def normalize_body(value: str | None) -> str:
    text = _nfkc(value)
    text = _EMAIL.sub("연락처", text)
    text = _PHONE.sub("연락처", text)
    text = text.replace("[이메일 제거]", "연락처").replace("[연락처 제거]", "연락처")
    # Cross-posted notices commonly vary only in these field labels.
    text = re.sub(r"지원\s*자격", "자격", text)
    text = re.sub(r"(?:담당\s*업무|업무\s*내용)", "업무", text)
    return _NON_ALNUM.sub("", text)


def _char_ngrams(value: str, size: int = 3) -> Counter[str]:
    if not value:
        return Counter()
    if len(value) < size:
        return Counter({value: 1})
    return Counter(value[index:index + size] for index in range(len(value) - size + 1))


def cosine_similarity(left: Counter[str], right: Counter[str]) -> float:
    if not left or not right:
        return 0.0
    dot = sum(count * right.get(token, 0) for token, count in left.items())
    left_norm = math.sqrt(sum(count * count for count in left.values()))
    right_norm = math.sqrt(sum(count * count for count in right.values()))
    return dot / (left_norm * right_norm) if left_norm and right_norm else 0.0


def body_similarity(left: str | None, right: str | None) -> float:
    return cosine_similarity(
        _char_ngrams(normalize_body(left)),
        _char_ngrams(normalize_body(right)),
    )


def title_similarity(left: str | None, right: str | None) -> float:
    """Short-title score tolerant of brackets and one-sided qualifiers."""
    a, b = normalize_title(left), normalize_title(right)
    if not a or not b:
        return 0.0
    sequence = SequenceMatcher(None, a, b, autojunk=False).ratio()
    a_tokens, b_tokens = set(a.split()), set(b.split())
    token_coverage = (
        len(a_tokens & b_tokens) / min(len(a_tokens), len(b_tokens))
        if a_tokens and b_tokens else 0.0
    )
    return max(sequence, token_coverage)


def _iso_day(value: str | None) -> date | None:
    if not value:
        return None
    try:
        return date.fromisoformat(str(value)[:10])
    except ValueError:
        return None


def posted_day_gap(left: str | None, right: str | None) -> int | None:
    a, b = _iso_day(left), _iso_day(right)
    return abs((a - b).days) if a and b else None


def _signals(record: dict) -> dict[str, set[str]]:
    body = _nfkc(record.get("body") or record.get("raw_text") or "")
    deadline = str(record.get("recruit_until") or "").strip()
    periods = {
        normalize_body(value)
        for value in _WORK_PERIOD.findall(body)
        if normalize_body(value)
    }
    return {
        "deadline": {deadline} if deadline else set(),
        "wage": {match.replace(",", "") for match in _WAGE.findall(body)},
        "count": {match.upper().replace("○", "O") for match in _COUNT.findall(body)},
        "email": {re.sub(r"\s+", "", value) for value in _EMAIL.findall(body)},
        "phone": {re.sub(r"\D", "", value) for value in _PHONE.findall(body)},
        "work_period": periods,
        "work_days": {normalize_body(value) for value in _WORK_DAYS.findall(body)},
        "time": {
            f"{h1.zfill(2)}:{m1}-{h2.zfill(2)}:{m2}"
            for h1, m1, h2, m2 in _TIME_RANGE.findall(body)
        },
    }


def conflicting_fields(left: dict, right: dict) -> tuple[str, ...]:
    """Return explicit conflicts. Missing values are neutral."""
    a, b = _signals(left), _signals(right)
    conflicts = []
    for field in (
        "deadline", "work_period", "work_days", "time",
        "wage", "count", "email", "phone",
    ):
        if a[field] and b[field] and a[field].isdisjoint(b[field]):
            conflicts.append(field)
    return tuple(conflicts)


@dataclass(frozen=True)
class DuplicateDecision:
    is_duplicate: bool
    reason: str
    title_score: float = 0.0
    body_score: float = 0.0
    day_gap: int | None = None
    conflicts: tuple[str, ...] = ()


def decide_duplicate(left: dict, right: dict) -> DuplicateDecision:
    if left.get("source") == right.get("source"):
        return DuplicateDecision(False, "same_source")
    if not left.get("normalized_worksite") or (
        left.get("normalized_worksite") != right.get("normalized_worksite")
    ):
        return DuplicateDecision(False, "different_worksite")

    gap = posted_day_gap(left.get("posted_at"), right.get("posted_at"))
    if gap is None or gap > MAX_POSTED_DAY_GAP:
        return DuplicateDecision(False, "posted_day_gap", day_gap=gap)

    title_score = title_similarity(left.get("title"), right.get("title"))
    if title_score < TITLE_THRESHOLD:
        return DuplicateDecision(
            False, "title_similarity", title_score=title_score, day_gap=gap
        )

    body_score = body_similarity(
        left.get("body") or left.get("raw_text"),
        right.get("body") or right.get("raw_text"),
    )
    if body_score < BODY_THRESHOLD:
        return DuplicateDecision(
            False, "body_similarity", title_score, body_score, gap
        )

    conflicts = conflicting_fields(left, right)
    if conflicts:
        return DuplicateDecision(
            False, "field_conflict", title_score, body_score, gap, conflicts
        )
    return DuplicateDecision(True, "matched", title_score, body_score, gap)


def choose_representative(left: dict, right: dict) -> tuple[dict, dict]:
    """Return (representative, supplement): newest wins; same day prefers SSC."""
    left_day, right_day = _iso_day(left.get("posted_at")), _iso_day(right.get("posted_at"))
    if left_day and right_day and left_day != right_day:
        return (left, right) if left_day > right_day else (right, left)
    if left.get("source") == "ssc":
        return left, right
    if right.get("source") == "ssc":
        return right, left
    return left, right
