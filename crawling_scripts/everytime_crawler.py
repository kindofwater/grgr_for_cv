"""Collect Everytime work-study recruitment posts through the Aside browser.

Aside holds the logged-in session, so this crawler never handles a password.
Every browser step is deterministic JavaScript run through ``aside repl`` — no
model is involved until ``everytime_postings`` hands a new post to the shared
Sonnet parser, and only new recruitment posts ever get that far.

The board is mostly student chatter, so titles are filtered before any detail
request: a post must say both "모집" and "근로장학"/"근로학생".  Post bodies stay
in memory; only the structured facts reach disk.

Usage:
    python crawling_scripts/everytime_crawler.py --dry-run
    python crawling_scripts/everytime_crawler.py
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import random
import subprocess
import sys
import time
from pathlib import Path

from everytime_postings import clean_body, is_recruitment, merge_new

BOARD_ID = 496548  # 고려대 서울캠 · 🧑‍💻근장게시판👩‍💻
BOARD_URL = f"https://everytime.kr/{BOARD_ID}"
API = "https://api.everytime.kr"

ROOT_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = ROOT_DIR / "data"
OUTPUT_FILE = DATA_DIR / "manual_everytime_postings.json"
STATE_FILE = DATA_DIR / "everytime_seen.json"

LIST_SIGNAL = "PAYLOAD:"
DEFAULT_ASIDE = Path(
    os.environ.get("LOCALAPPDATA", "")
) / "Aside" / "CLI" / "current" / "aside.exe"
DEFAULT_ASIDE_BROWSER = Path(
    os.environ.get("ProgramFiles", r"C:\Program Files")
) / "Aside" / "Application" / "Aside.exe"

# 사람이 읽는 속도에 맞춰 상세를 띄엄띄엄 가져온다. 기존 크롤러와 같은 정책.
DETAIL_DELAY_RANGE = (5.0, 10.0)

# 새로 띄운 Aside는 10초 안팎에 데몬이 응답한다. 여유를 두고 기다린다.
ASIDE_START_TIMEOUT = 60.0


def aside_cli() -> str:
    """Locate the Aside CLI, preferring an explicit override."""
    override = os.environ.get("ASIDE_CLI")
    if override:
        return override
    if DEFAULT_ASIDE.exists():
        return str(DEFAULT_ASIDE)
    return "aside"


def aside_ready() -> bool:
    """True when the Aside Browser daemon answers the CLI."""
    try:
        result = subprocess.run(
            [aside_cli(), "repl", "console.log(1)"],
            capture_output=True, text=True, encoding="utf-8", timeout=30,
        )
    except subprocess.TimeoutExpired:
        return False
    return result.returncode == 0


def launch_aside() -> None:
    """Start Aside Browser detached so it outlives this batch run."""
    browser = os.environ.get("ASIDE_BROWSER") or str(DEFAULT_ASIDE_BROWSER)
    subprocess.Popen(
        [browser],
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        creationflags=subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP,
    )


def ensure_aside(ready=aside_ready, launch=launch_aside, wait=time.sleep,
                 timeout: float = ASIDE_START_TIMEOUT, interval: float = 2.0) -> None:
    """Start Aside Browser when it is closed — the daily run usually finds it so."""
    if ready():
        return
    launch()
    waited = 0.0
    while waited < timeout:
        wait(interval)
        waited += interval
        if ready():
            return
    raise RuntimeError(f"Aside Browser did not answer within {timeout:.0f}s of launch")


def decode_payload(stdout: str) -> dict:
    """Read the one base64 payload line Aside printed, ignoring its chatter."""
    for line in stdout.splitlines():
        stripped = line.strip()
        if stripped.startswith(LIST_SIGNAL):
            raw = base64.b64decode(stripped[len(LIST_SIGNAL):])
            return json.loads(raw.decode("utf-8"))
    raise ValueError("no payload line in Aside output")


def run_aside(code: str, timeout: float = 120.0) -> dict:
    """Run deterministic JavaScript in the Aside browser and read its payload."""
    result = subprocess.run(
        [aside_cli(), "repl", code],
        capture_output=True, text=True, encoding="utf-8", timeout=timeout,
    )
    if result.returncode != 0:
        raise RuntimeError(f"aside repl failed ({result.returncode}): {result.stderr.strip()}")
    return decode_payload(result.stdout)


def _emit(expression: str) -> str:
    """JS tail that base64-encodes a value so non-ASCII survives the pipe."""
    return (
        f"const payload = JSON.stringify({expression});\n"
        f"console.log('{LIST_SIGNAL}' + btoa(unescape(encodeURIComponent(payload))));"
    )


def build_list_script(board_id: int = BOARD_ID) -> str:
    return f"""
const r = await fetch('{API}/v2/find/board/article/list', {{
  method: 'POST', credentials: 'include',
  headers: {{ 'Content-Type': 'application/json',
             'Referer': 'https://everytime.kr/{board_id}',
             'Origin': 'https://everytime.kr' }},
  body: JSON.stringify({{ mode: 'board', boardId: {board_id}, isBoardInfoRequired: false }})
}});
const j = await r.json();
const arts = (j.result && j.result.articles) || [];
{_emit("{ status: j.status, articles: arts.map(a => ({ id: a.id, title: a.title, "
       "text: a.text, createdAt: a.createdAt })) }")}
"""


def build_article_script(article_id: int, board_id: int = BOARD_ID) -> str:
    """Fetch one post in full. The list API truncates bodies at 160 characters."""
    return f"""
const Q = String.fromCharCode(34);
const r = await fetch('{API}/find/board/comment/list', {{
  method: 'POST', credentials: 'include',
  headers: {{ 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
             'Referer': 'https://everytime.kr/{board_id}/v/{article_id}',
             'Origin': 'https://everytime.kr' }},
  body: 'id={article_id}&limit_num=-1&articleInfo=true'
}});
const xml = await r.text();
function pick(name) {{
  const k = ' ' + name + '=' + Q;
  const i = xml.indexOf(k);
  if (i < 0) return '';
  const s = i + k.length;
  return xml.slice(s, xml.indexOf(Q, s));
}}
{_emit("{ id: '%d', title: pick('title'), text: pick('text'), "
       "created_at: pick('created_at') }" % article_id)}
"""


def pick_new_recruitments(articles: list[dict], seen_ids: set) -> list[dict]:
    """Keep unseen posts whose titles read as an actual call for applicants."""
    seen = {str(value) for value in seen_ids}
    return [
        article for article in articles
        if str(article.get("id")) not in seen and is_recruitment(article.get("title"))
    ]


def select_body(preview: str | None, full: str | None) -> str:
    """Prefer the detail body, but never trade a longer text for a shorter one."""
    preview_text = str(preview or "")
    full_text = str(full or "")
    return full_text if len(full_text) > len(preview_text) else preview_text


def load_state() -> dict:
    if not STATE_FILE.exists():
        return {}
    return json.loads(STATE_FILE.read_text(encoding="utf-8"))


def load_seen() -> set:
    return {str(value) for value in load_state().get("seen_ids", [])}


def load_failures() -> dict:
    return {str(k): int(v) for k, v in load_state().get("parse_failures", {}).items()}


def save_seen(seen: set, failures: dict | None = None) -> None:
    """Persist seen ids; ``failures`` (article_id -> count) is kept when omitted."""
    failures = load_failures() if failures is None else failures
    state = {"seen_ids": sorted(seen)}
    if failures:
        state["parse_failures"] = dict(sorted(failures.items()))
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(
        json.dumps(state, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


def load_existing() -> list[dict]:
    if not OUTPUT_FILE.exists():
        return []
    return json.loads(OUTPUT_FILE.read_text(encoding="utf-8"))


def collect(limit: int | None = None, pace: bool = True) -> list[dict]:
    """Return new recruitment posts as raw records ready for the parser."""
    ensure_aside()
    listing = run_aside(build_list_script())
    articles = listing.get("articles", [])
    candidates = pick_new_recruitments(articles, load_seen())
    if limit is not None:
        candidates = candidates[:limit]

    collected = []
    for index, article in enumerate(candidates):
        if pace and index:
            time.sleep(random.uniform(*DETAIL_DELAY_RANGE))
        detail = run_aside(build_article_script(int(article["id"])))
        body = clean_body(select_body(article.get("text"), detail.get("text")))
        if not body:
            continue
        collected.append({
            "article_id": str(article["id"]),
            "title": detail.get("title") or article.get("title") or "",
            "body": body,
            "posted_at": (detail.get("created_at") or article.get("createdAt") or "")[:10],
            "source_url": f"{BOARD_URL}/v/{article['id']}",
        })
    return collected


def main() -> int:
    parser = argparse.ArgumentParser(description="Collect Everytime work-study posts")
    parser.add_argument("--dry-run", action="store_true",
                        help="수집만 하고 파싱·적재·상태 저장을 하지 않는다")
    parser.add_argument("--limit", type=int, default=None)
    args = parser.parse_args()

    posts = collect(limit=args.limit, pace=not args.dry_run)
    print(f"[everytime] 신규 모집공고 {len(posts)}건", file=sys.stderr)
    for post in posts:
        print(f"  - {post['title'][:60]}  ({len(post['body'])}자)", file=sys.stderr)

    if args.dry_run:
        for post in posts:
            print(json.dumps({k: v for k, v in post.items() if k != "body"},
                             ensure_ascii=False))
        return 0

    if not posts:
        return 0

    # 파싱은 별도 단계다. 본문은 여기서 표준출력으로만 넘기고 디스크에 남기지 않는다.
    from everytime_parse import MAX_PARSE_FAILURES, handled_ids, parse_and_store, track_failures

    outcomes: dict = {}
    stored = parse_and_store(posts, load_existing(), outcomes=outcomes)
    merged = merge_new(load_existing(), stored)
    OUTPUT_FILE.write_text(
        json.dumps(merged, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    # 파싱 실패·상한 초과 글은 seen에 넣지 않는다. 다음 실행이 다시 가져온다.
    # 단, 내용 때문에 MAX_PARSE_FAILURES번 실패한 글은 포기하고 seen에 넣는다.
    failures, given_up = track_failures(posts, outcomes, load_failures())
    for post in posts:
        if str(post["article_id"]) in given_up:
            print(f"[everytime] 파싱 {MAX_PARSE_FAILURES}회 실패로 포기: {post['source_url']}",
                  file=sys.stderr)
    handled = handled_ids(posts, outcomes) | given_up
    save_seen(load_seen() | handled, failures)
    print(f"[everytime] {len(stored)}건 구조화 완료 → {OUTPUT_FILE.name}", file=sys.stderr)
    if len(handled) < len(posts):
        print(f"[everytime] {len(posts) - len(handled)}건은 다음 실행에서 다시 시도",
              file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
