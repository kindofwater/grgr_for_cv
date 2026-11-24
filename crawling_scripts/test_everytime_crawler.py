import base64
import json

import pytest

from everytime_crawler import (
    LIST_SIGNAL,
    decode_payload,
    ensure_aside,
    pick_new_recruitments,
    select_body,
)


def encoded(obj):
    return LIST_SIGNAL + base64.b64encode(
        json.dumps(obj, ensure_ascii=False).encode("utf-8")
    ).decode("ascii")


def test_decode_payload_reads_the_signal_line_among_other_output():
    stdout = "\n".join([
        "✔︎ Opened a new tab",
        encoded({"articles": [{"id": 1, "title": "가"}]}),
        "[ok | 120ms]",
    ])
    assert decode_payload(stdout) == {"articles": [{"id": 1, "title": "가"}]}


def test_decode_payload_survives_non_ascii_content():
    payload = {"title": "[박물관] 근로장학생 모집", "text": "시급 10,400원"}
    assert decode_payload(encoded(payload)) == payload


def test_decode_payload_without_a_signal_line_is_an_error():
    with pytest.raises(ValueError, match="no payload"):
        decode_payload("✔︎ Opened a new tab\n[ok | 3ms]")


ARTICLES = [
    {"id": 11, "title": "[입학처] 전형보조 근로장학생 모집(10월 단기)"},
    {"id": 12, "title": "월급언제주냐 ㅡㅡ"},
    {"id": 13, "title": "고려대학교 박물관 근로장학생 모집"},
    {"id": 14, "title": "하스 헬스장 근로 모집 (평일 오전 6:00~12:00)"},
]


def test_pick_new_recruitments_keeps_only_unseen_recruitment_posts():
    picked = pick_new_recruitments(ARTICLES, seen_ids=set())
    assert [a["id"] for a in picked] == [11, 13]


def test_pick_new_recruitments_skips_articles_already_handled():
    picked = pick_new_recruitments(ARTICLES, seen_ids={11})
    assert [a["id"] for a in picked] == [13]


def test_pick_new_recruitments_treats_seen_ids_as_strings_too():
    picked = pick_new_recruitments(ARTICLES, seen_ids={"11", "13"})
    assert picked == []


def test_select_body_prefers_the_full_detail_over_the_list_preview():
    preview = "가" * 160
    full = "가" * 900
    assert select_body(preview, full) == full


def test_select_body_falls_back_to_the_preview_when_detail_is_empty():
    preview = "시급 10,400원"
    assert select_body(preview, "") == preview


def test_select_body_keeps_the_longer_text_when_detail_is_truncated():
    preview = "가" * 160
    assert select_body(preview, "가" * 20) == preview


class FakeAside:
    """Aside daemon that answers only after `ready_after` pings."""

    def __init__(self, ready_after):
        self.ready_after = ready_after
        self.pings = 0
        self.launches = 0

    def ready(self):
        self.pings += 1
        return self.pings > self.ready_after

    def launch(self):
        self.launches += 1


def test_ensure_aside_leaves_a_running_browser_alone():
    aside = FakeAside(ready_after=0)
    ensure_aside(ready=aside.ready, launch=aside.launch, wait=lambda s: None)
    assert aside.launches == 0


def test_ensure_aside_starts_the_browser_and_waits_for_its_daemon():
    aside = FakeAside(ready_after=3)
    ensure_aside(ready=aside.ready, launch=aside.launch, wait=lambda s: None)
    assert aside.launches == 1
    assert aside.pings == 4


def test_ensure_aside_gives_up_when_the_daemon_never_answers():
    aside = FakeAside(ready_after=10**6)
    with pytest.raises(RuntimeError, match="Aside"):
        ensure_aside(ready=aside.ready, launch=aside.launch,
                     wait=lambda s: None, timeout=10, interval=2)
    assert aside.launches == 1
