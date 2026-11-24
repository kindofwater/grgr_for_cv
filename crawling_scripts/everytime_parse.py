"""Turn collected Everytime posts into records the manual loader accepts.

This is the only step that spends tokens, and it spends them once per post:
posts already present in the output file are skipped without a model call, and
a per-run budget caps the rest.  Bodies are passed to the parser and dropped —
``to_manual_record`` has no field that could carry one.
"""
from __future__ import annotations

import datetime as dt
import re
import sys

from crawler_pipeline.llm import LLMUnavailable
from everytime_postings import to_manual_record, to_representative
from source_metadata import title_without_closed_marker
from worksite_norm import worksite_identity_key

# 근장게시판에 하루 여덟 건이 한꺼번에 올라오는 일은 없다. 상한은 사고 방지용이다.
DEFAULT_MAX_CALLS = 5

# 같은 제목이 이 기간 안에 다시 보이면 같은 공고로 본다.
#
# 실제 데이터로 정한 값이다. 손입력 기록과 에타 글의 간격은 박물관·국제대학 0일,
# 법전원 6일이었고(같은 공고를 며칠 뒤 에타에 올리거나 뒤늦게 손으로 넣은 경우),
# 기술경영전문대학원은 8/5와 9/15에 같은 제목으로 **다른** 공고를 냈다(41일).
# 7일이면 앞의 셋은 막고 뒤의 하나는 통과시킨다. 창을 넓히면 매달 다시 올라오는
# 재공고를 삼켜, 공고를 놓치지 않으려고 만든 물건이 공고를 놓치게 된다.
DUPLICATE_WINDOW_DAYS = 7

_SPACE_RE = re.compile(r"\s+")
_LEADING_TAG_RE = re.compile(r"^\s*\[[^\]]*\]")


def title_key(title: str | None) -> str:
    """Normalize a title so spacing and a [마감] marker do not hide a duplicate."""
    return _SPACE_RE.sub("", title_without_closed_marker(title)).lower()


def title_core(title: str | None) -> str:
    """The title with its leading [부서] tag dropped.

    Hand-entered records often carry a tag the Everytime title never had —
    "[박물관] 고려대학교 박물관 …" vs "고려대학교 박물관 …".  The tag alone is
    too weak to merge on, so this is only compared alongside the worksite.
    """
    stripped = _LEADING_TAG_RE.sub("", title_without_closed_marker(title))
    return _SPACE_RE.sub("", stripped).lower()


def same_posting(record: dict, other: dict) -> bool:
    """True when two records describe one posting at one worksite.

    The date window matters as much as the names: one office reuses its wording
    every time it hires, so a match far apart is a fresh call, not a copy.
    """
    key = worksite_identity_key(record.get("worksite_name"))
    if not key or worksite_identity_key(other.get("worksite_name")) != key:
        return False
    core = title_core(record.get("title"))
    if not core or title_core(other.get("title")) != core:
        return False
    return within_window(record.get("posted_at"), other.get("posted_at"))


def _as_date(value) -> dt.date | None:
    try:
        return dt.date.fromisoformat(str(value or "")[:10])
    except ValueError:
        return None


def within_window(one, other) -> bool:
    """True when two posting dates are close enough to be the same call.

    A missing date on either side counts as close: an undated hand-entered
    record is more likely a copy of what we just found than a fresh posting.
    """
    left, right = _as_date(one), _as_date(other)
    if left is None or right is None:
        return True
    return abs((left - right).days) <= DUPLICATE_WINDOW_DAYS


def already_loaded(post: dict, existing: list[dict]) -> bool:
    """True when this post is already in the output file.

    ``source_url`` alone is not enough: hand-entered records point at the
    department page or the application form, never at the Everytime post, so
    the URLs never match.  Titles carry the identity instead.
    """
    url = post.get("source_url")
    key = title_key(post.get("title"))
    post_date = _as_date(post.get("posted_at"))

    for row in existing:
        if url and row.get("source_url") == url:
            return True
        if not key or title_key(row.get("title")) != key:
            continue
        if within_window(post.get("posted_at"), row.get("posted_at")):
            return True
    return False


def _default_parse(representative: dict) -> dict:
    from anthropic_key import get_anthropic_api_key
    from anthropic import Anthropic
    from crawler_pipeline.llm import parse_posting

    key = get_anthropic_api_key()
    if not key:
        raise RuntimeError("ANTHROPIC_API_KEY is not configured")
    return parse_posting(Anthropic(api_key=key), representative)


# parse_and_store가 글마다 남기는 결과. 다시 볼 이유가 없는 결과만 HANDLED다.
# 파싱 실패와 상한 초과는 내일 달라질 수 있으니 '본 글'로 치지 않는다 — 2026-10-08
# 크레딧 소진으로 파싱이 실패한 입학처 공고가 seen에 들어가 영영 재수집되지 않았다.
HANDLED = frozenset({"stored", "already_loaded", "no_worksite", "duplicate"})

# 내용 때문에 파싱이 실패한 글은 이 횟수만큼 실행해 본 뒤 포기한다(seen 처리).
# 2026-10-13~19: 본문 185자짜리 원스탑 공고가 매일 실패하며 API를 2번씩 썼다.
MAX_PARSE_FAILURES = 3


def track_failures(posts: list[dict], outcomes: dict,
                   failures: dict) -> tuple[dict, set[str]]:
    """Count content parse failures and pick the posts to give up on.

    Returns the updated failure counts and the article ids that reached
    ``MAX_PARSE_FAILURES``. Given-up and handled posts drop out of the counts;
    an API outage leaves a post's count untouched.
    """
    counts = {str(k): int(v) for k, v in failures.items()}
    given_up: set[str] = set()
    for post in posts:
        article_id = str(post.get("article_id"))
        outcome = outcomes.get(article_id)
        if outcome in HANDLED:
            counts.pop(article_id, None)
        elif outcome == "parse_failed":
            counts[article_id] = counts.get(article_id, 0) + 1
            if counts[article_id] >= MAX_PARSE_FAILURES:
                given_up.add(article_id)
                counts.pop(article_id)
    return counts, given_up


def handled_ids(posts: list[dict], outcomes: dict) -> set[str]:
    """Article ids the crawler may mark as seen.

    A post with no outcome was never reached, so it is not handled either.
    """
    return {
        str(post.get("article_id")) for post in posts
        if outcomes.get(str(post.get("article_id"))) in HANDLED
    }


def parse_and_store(
    posts: list[dict],
    existing: list[dict],
    parse=None,
    max_calls: int = DEFAULT_MAX_CALLS,
    outcomes: dict | None = None,
) -> list[dict]:
    """Structure each unseen post, skipping the ones that cannot be used.

    ``outcomes`` (article_id -> outcome name) is filled in when given, so the
    caller can tell a post that is done from one to try again next run.
    """
    parse = parse or _default_parse
    outcomes = {} if outcomes is None else outcomes

    stored: list[dict] = []
    for post in posts:
        article_id = str(post.get("article_id"))
        if len(stored) >= max_calls:
            outcomes[article_id] = "over_budget"
            continue
        if already_loaded(post, existing) or already_loaded(post, stored):
            outcomes[article_id] = "already_loaded"
            continue
        try:
            parsed = parse(to_representative(post))
        except LLMUnavailable as exc:  # API 쪽 문제다. 글의 재시도 횟수를 깎지 않는다.
            print(f"[everytime] API 장애로 보류 {post.get('source_url')}: {exc}",
                  file=sys.stderr)
            outcomes[article_id] = "unavailable"
            continue
        except Exception as exc:  # 한 건이 실패해도 나머지는 계속 처리한다.
            print(f"[everytime] 파싱 실패 {post.get('source_url')}: {exc}",
                  file=sys.stderr)
            outcomes[article_id] = "parse_failed"
            continue
        try:
            record = to_manual_record(parsed, post)
        except ValueError as exc:  # 근무지를 못 찾으면 적재하지 않는다.
            print(f"[everytime] 근무지 불명으로 건너뜀 {post.get('source_url')}: {exc}",
                  file=sys.stderr)
            outcomes[article_id] = "no_worksite"
            continue
        # 근무지는 파싱해야 알 수 있다. 제목만으로 못 걸러낸 중복을 여기서 한 번 더 본다.
        if any(same_posting(record, row) for row in existing + stored):
            print(f"[everytime] 같은 근무지의 같은 공고라 건너뜀: {record.get('title')}",
                  file=sys.stderr)
            outcomes[article_id] = "duplicate"
            continue
        stored.append(record)
        outcomes[article_id] = "stored"
    return stored
