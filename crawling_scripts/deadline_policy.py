"""Shared recruitment-deadline policy for school work-study postings."""
from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
import re

RECRUITMENT_WINDOW_DAYS = 21
SCHOOL_POSTING_SOURCES = frozenset({"ssc", "kupid", "everytime_manual"})
KST = timezone(timedelta(hours=9))

_RECRUITMENT_DEADLINE_LABEL_RE = re.compile(
    r"(?:모집|신청|지원|접수|제출)(?:서류|서)?\s*"
    r"(?:기간|기한|마감(?:일)?|일정)"
)
_FULL_DATE_RE = re.compile(
    r"(?<!\d)(20\d{2})\s*(?:[.\-/년]\s*)"
    r"(\d{1,2})\s*(?:[.\-/월]\s*)(\d{1,2})(?:\s*일)?"
)
_MONTH_DAY_RE = re.compile(
    r"(?<!\d)(\d{1,2})\s*(?:[.\-/]\s*|월\s*)"
    r"(\d{1,2})(?:\s*일)?"
)
_DEADLINE_TERMINATOR_RE = re.compile(r"까지|마감")


def iso_date(value) -> date | None:
    if not value:
        return None
    if isinstance(value, datetime):
        return value.astimezone(KST).date() if value.tzinfo else value.date()
    if isinstance(value, date):
        return value
    text = str(value).strip()
    if "T" in text or " " in text:
        try:
            parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
            return parsed.astimezone(KST).date() if parsed.tzinfo else parsed.date()
        except ValueError:
            pass
    try:
        return date.fromisoformat(text[:10])
    except (TypeError, ValueError):
        return None


def _date_mentions(text: str, reference: date) -> list[tuple[int, int, date]]:
    mentions: list[tuple[int, int, date]] = []
    full_spans: list[tuple[int, int]] = []
    for match in _FULL_DATE_RE.finditer(text):
        try:
            value = date(int(match[1]), int(match[2]), int(match[3]))
        except ValueError:
            continue
        mentions.append((match.start(), match.end(), value))
        full_spans.append(match.span())

    for match in _MONTH_DAY_RE.finditer(text):
        if any(start <= match.start() < end for start, end in full_spans):
            continue
        month, day = int(match[1]), int(match[2])
        year = reference.year
        try:
            value = date(year, month, day)
            # A yearless January/February deadline in a November/December
            # posting normally belongs to the following calendar year.
            if reference.month >= 11 and month <= 2 and value < reference:
                value = date(year + 1, month, day)
        except ValueError:
            continue
        mentions.append((match.start(), match.end(), value))
    return sorted(mentions, key=lambda item: item[0])


def extract_recruitment_deadline(text, reference_date) -> str | None:
    """Extract an explicit application deadline from labelled source text.

    This intentionally ignores unlabelled dates so work periods and interview
    dates cannot silently replace the recruitment deadline. Yearless dates use
    the posting date as their calendar-year reference.
    """
    reference = iso_date(reference_date)
    if not reference:
        return None
    lines = [line.strip() for line in str(text or "").splitlines()]
    for index, line in enumerate(lines):
        label = _RECRUITMENT_DEADLINE_LABEL_RE.search(line)
        if not label:
            continue
        segment = line[label.start():]
        mentions = _date_mentions(segment, reference)
        if not mentions:
            continue

        # Some portal HTML splits a labelled range after the first date:
        # ``지원기간: 2026.07.23 ~`` / ``2026.08.02 23:59`` / ``마감``.
        # Only extend a line that already contains a date; extending a bare
        # heading such as ``모집기간 및 방법`` can mistake a later reception
        # start date for the application deadline.
        if index + 1 < len(lines):
            continued = " ".join(lines[index:index + 3])
            continued_mentions = _date_mentions(continued, reference)
            if (
                len(continued_mentions) > len(mentions)
                and ("~" in segment or "부터" in segment)
            ):
                segment = continued
                mentions = continued_mentions

        terminator = _DEADLINE_TERMINATOR_RE.search(segment, label.end() - label.start())
        if terminator:
            before_terminator = [
                mention for mention in mentions if mention[1] <= terminator.start()
            ]
            if before_terminator:
                return before_terminator[-1][2].isoformat()
        if "마감" in label.group(0):
            return mentions[0][2].isoformat()
        if len(mentions) >= 2 and ("~" in segment or "부터" in segment):
            return max(mention[2] for mention in mentions).isoformat()
    return None


@dataclass(frozen=True)
class DeadlineDecision:
    recruit_until: str | None
    estimated: bool
    basis: str | None


def decide_deadline(
    *,
    source: str,
    explicit_until=None,
    posted_at=None,
    first_seen_at=None,
    work_start_date=None,
) -> DeadlineDecision:
    """Apply explicit date -> earliest of (21-day window, work-start eve).

    ``first_seen_at`` is deliberately separate from ``posted_at``.  Manual
    records without a source date use the first database insertion date and
    must not move their deadline forward when they are re-submitted later.

    When both estimates exist the earlier one wins: a posting whose work
    already started cannot still be accepting applications, so the 21-day
    window must not outlive the work start date.
    """
    explicit = iso_date(explicit_until)
    if explicit:
        return DeadlineDecision(explicit.isoformat(), False, "explicit")

    if str(source or "") not in SCHOOL_POSTING_SOURCES:
        return DeadlineDecision(None, False, None)

    estimates: list[tuple[date, str]] = []

    posted = iso_date(posted_at)
    if posted:
        estimates.append((
            posted + timedelta(days=RECRUITMENT_WINDOW_DAYS - 1),
            "posted_window",
        ))
    else:
        first_seen = iso_date(first_seen_at)
        if first_seen:
            estimates.append((
                first_seen + timedelta(days=RECRUITMENT_WINDOW_DAYS - 1),
                "first_seen_window",
            ))

    work_start = iso_date(work_start_date)
    if work_start:
        estimates.append((work_start - timedelta(days=1), "work_start"))

    if not estimates:
        return DeadlineDecision(None, False, None)

    deadline, basis = min(estimates, key=lambda item: item[0])
    return DeadlineDecision(deadline.isoformat(), True, basis)
