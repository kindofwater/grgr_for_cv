import datetime as dt

from preview_deadline_backfill import build_preview


def test_preview_reports_reopen_close_and_human_protection():
    rows = [
        {
            "id": 1, "source": "kupid", "title": "A",
            "created_at": "2026-07-10T00:00:00+00:00",
            "recruit_until": "2026-07-24",
            "recruit_until_estimated": True,
            "is_active": False, "is_placeholder": False,
            "manual_override": False,
            "worksites": {"workplace_name": "A팀"},
        },
        {
            "id": 2, "source": "everytime_manual", "title": "B",
            "created_at": "2026-06-01T00:00:00+00:00",
            "recruit_until": None,
            "recruit_until_estimated": False,
            "is_active": True, "is_placeholder": False,
            "manual_override": False,
            "worksites": {"workplace_name": "B팀"},
        },
        {
            "id": 7257, "source": "kupid", "title": "보호",
            "created_at": "2026-07-13T00:00:00+00:00",
            "recruit_until": "2026-07-27",
            "recruit_until_estimated": True,
            "is_active": False, "is_placeholder": False,
            "manual_override": False,
            "worksites": {"workplace_name": "산학협력단 연구지원팀"},
        },
    ]
    preview = build_preview(rows, dt.date(2026, 7, 29))
    assert preview["expected_apply_count"] == 2
    assert preview["reopened"] == 1
    assert preview["closed"] == 1
    assert preview["protected"][0]["id"] == 7257
