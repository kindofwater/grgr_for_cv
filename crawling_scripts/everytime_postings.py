"""Structure Everytime work-study posts into the manual loader's record shape.

A human reads the board and supplies the post text; this module turns that text
into the structured facts ``manual_postings.py`` accepts.  Post bodies are used
only to call the parser and are never placed in the returned record — the
loader's ``ALLOWED_FIELDS`` has no field that could hold one.

Usage:
    python crawling_scripts/everytime_postings.py raw_posts.json
"""
from __future__ import annotations

import html
import re

from source_metadata import title_has_strong_closed_marker

SOURCE = "everytime_manual"

# "근로 장학"처럼 띄어 쓴 표기와 "교내근로" 표현까지 근로장학 공고로 본다.
WORKSTUDY_TERM_RE = re.compile(r"근로\s*장학(?:생)?|교내\s*근로")

# 제목 판별은 더 좁게 본다. 근장게시판은 절반 이상이 잡담이고, 잡담도 "근장"·"근로"를
# 쓰기 때문이다. 실제 표본 20건에서 아래 두 조건을 함께 요구하면 모집공고 8건을 모두
# 잡아내고 잡담 12건(교외 알바 "헬스장 근로 모집" 포함)을 모두 걸렀다.
RECRUIT_CALL_RE = re.compile(r"모집")
WORKSTUDY_STRICT_RE = re.compile(r"근로\s*장학(?:생)?|근로\s*학생")

# 파서가 내는 이름 → 로더가 받는 이름.
RENAMED_FIELDS = {
    "recruitment_period_text": "period_text",
    "posting_department": "source_department",
}

# 파서는 내지만 로더가 거부하는 필드. 넘기면 canonicalize가 예외를 던진다.
DROPPED_FIELDS = ("work_period_days", "worksite_evidence", "conflict_fields")

# 파서 출력에서 이름 그대로 넘어가는 필드.
PASSTHROUGH_FIELDS = (
    "hourly_wage", "recruit_count", "eligible_degree", "eligible_status",
    "job_description", "preference_notes", "extra_notes", "work_period_text",
    "work_duration_type", "work_time_text", "recruit_until", "work_start_date",
    "work_department", "work_location", "office_phone",
)

# 글에서 그대로 가져오는 필드. 본문은 여기에 없다.
POST_FIELDS = ("title", "source_url", "posted_at")


def is_workstudy(title: str | None, body: str | None) -> bool:
    """True when the post is a work-study call, by title or body wording."""
    return bool(WORKSTUDY_TERM_RE.search(f"{title or ''}\n{body or ''}"))


_BR_RE = re.compile(r"<br\s*/?>", re.IGNORECASE)
_TAG_RE = re.compile(r"<[^>]+>")
_BLANK_RUN_RE = re.compile(r"\n{3,}")


def clean_body(text: str | None) -> str:
    """Turn the API's escaped post markup into the plain text the parser reads.

    Bodies arrive inside an XML attribute, so their markup is escaped twice:
    ``&lt;br />`` is a line break and ``&amp;quot;`` is a quote the author typed.
    Unescape, drop the markup, then unescape what the author actually wrote.
    """
    unescaped = html.unescape(str(text or ""))
    with_breaks = _BR_RE.sub("\n", unescaped)
    stripped = _TAG_RE.sub("", with_breaks)
    return _BLANK_RUN_RE.sub("\n\n", html.unescape(stripped)).strip()


def is_recruitment(title: str | None) -> bool:
    """True when a board title is an actual, still-open call for applicants.

    Requires both a recruiting word and a work-study term, because chatter on
    the board says "근장"/"근로" constantly and an off-campus part-time ad says
    "근로 모집" without ever saying "근로장학".  A bracketed [마감] closes the
    posting — collecting it would show students a position that is already gone.
    """
    text = str(title or "")
    if title_has_strong_closed_marker(text):
        return False
    return bool(RECRUIT_CALL_RE.search(text) and WORKSTUDY_STRICT_RE.search(text))


def to_representative(raw: dict) -> dict:
    """Shape a supplied post for ``crawler_pipeline.llm.parse_posting``."""
    return {
        "source": SOURCE,
        "title": raw.get("title") or "",
        "posted_at": raw.get("posted_at") or "",
        "source_department": raw.get("source_department") or "",
        "body": raw.get("body") or "",
    }


def to_manual_record(parsed: dict, raw: dict) -> dict:
    """Map parser output onto the loader's schema, leaving the body behind."""
    worksite_name = (
        str(parsed.get("work_department") or "").strip()
        or str(parsed.get("posting_department") or "").strip()
    )
    if not worksite_name:
        raise ValueError("cannot determine worksite: no work or posting department")

    record: dict = {"worksite_name": worksite_name}
    for field in PASSTHROUGH_FIELDS:
        if parsed.get(field) is not None:
            record[field] = parsed[field]
    for source_name, loader_name in RENAMED_FIELDS.items():
        if parsed.get(source_name) is not None:
            record[loader_name] = parsed[source_name]
    for field in POST_FIELDS:
        if raw.get(field) is not None:
            record[field] = raw[field]
    return record


def merge_new(existing: list[dict], incoming: list[dict]) -> list[dict]:
    """Append only posts whose source_url has not been loaded before."""
    seen = {row.get("source_url") for row in existing if row.get("source_url")}
    merged = list(existing)
    for row in incoming:
        url = row.get("source_url")
        if url and url in seen:
            continue
        if url:
            seen.add(url)
        merged.append(row)
    return merged
