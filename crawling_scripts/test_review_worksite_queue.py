import json

import review_worksite_queue as review


class _Response:
    def __init__(self, data):
        self.data = data


class _RpcClient:
    def __init__(self, result):
        self.result = result
        self.calls = []

    def rpc(self, name, params):
        self.calls.append((name, params))
        return self

    def execute(self):
        return _Response(self.result)


def _row():
    return {
        "id": 12,
        "source": "kupid",
        "raw_worksite_name": "경영대학 행정실",
        "title": "근로장학생 모집",
        "resolution_reason": "new_name",
        "explicit_worksite_names": [],
        "evidence_text": "근무장소: 경영본관 103호",
        "candidate_scores": [{
            "worksite_id": 6761,
            "workplace_name": "경영대학행정팀",
            "address": "경영본관 103호",
            "score": 0.94,
        }],
    }


def test_existing_resolution_uses_one_atomic_rpc():
    client = _RpcClient({
        "queue_id": 12,
        "status": "resolved",
        "worksite": {"id": 6761, "workplace_name": "Business Office"},
        "alias_learned": True,
    })

    result = review.resolve_existing(client, 12, 6761)

    assert result["status"] == "resolved"
    assert len(client.calls) == 1
    name, params = client.calls[0]
    assert name == "resolve_worksite_review"
    assert params["p_action"] == "existing"
    assert params["p_queue_id"] == 12
    assert params["p_worksite_id"] == 6761
    assert params["p_learn_alias"] is None


def test_new_resolution_normalizes_before_atomic_rpc():
    client = _RpcClient({
        "queue_id": 13,
        "status": "resolved",
        "worksite": {"id": 7000, "workplace_name": "New Center"},
        "alias_learned": True,
    })

    review.resolve_new(client, 13, "  New   Center  ", " Room 101 ")

    _, params = client.calls[0]
    assert params["p_action"] == "new"
    assert params["p_new_name"] == "New Center"
    assert params["p_normalized_name"] == "new center"
    assert params["p_address"] == "Room 101"
    assert params["p_learn_alias"] is False


def test_skip_uses_atomic_rpc():
    client = _RpcClient({
        "queue_id": 14,
        "status": "skipped",
        "alias_learned": False,
    })

    assert review.skip(client, 14)["status"] == "skipped"
    assert client.calls[0][1]["p_action"] == "skip"


def test_reprocess_pending_postings_runs_pipeline_cli(monkeypatch):
    calls = []

    class _Completed:
        returncode = 0
        stdout = json.dumps({"inserted": 1, "pending": 0}) + "\n"
        stderr = ""

    def fake_run(command, **kwargs):
        calls.append((command, kwargs))
        return _Completed()

    monkeypatch.setattr(review.subprocess, "run", fake_run)

    result = review.reprocess_pending_postings()

    assert result == {"inserted": 1, "pending": 0}
    assert calls[0][0] == [review.sys.executable, str(review.PIPELINE_CLI)]
    assert calls[0][1]["cwd"] == review.ROOT
    assert calls[0][1]["env"]["PYTHONIOENCODING"] == "utf-8"


def test_resolution_with_reprocessing_keeps_review_and_pipeline_results():
    result = review.resolution_with_reprocessing(
        {"queue_id": 12, "status": "resolved"},
        reprocess_fn=lambda: {"inserted": 1, "pending": 0},
    )

    assert result == {
        "queue_id": 12,
        "status": "resolved",
        "pipeline": {"inserted": 1, "pending": 0},
    }


def test_interactive_reprocessing_failure_reports_saved_review():
    output = []

    def fail():
        raise RuntimeError("pipeline unavailable")

    assert not review.finish_interactive_resolution(
        {"queue_id": 12, "status": "resolved"},
        reprocess_fn=fail,
        output_fn=output.append,
    )
    assert any("검토 결정은 저장됐지만" in line for line in output)
    assert any("pipeline unavailable" in line for line in output)


def test_interactive_review_selects_candidate_by_number(monkeypatch):
    calls = []
    reprocess_calls = []
    output = []
    monkeypatch.setattr(review, "list_queue", lambda _client: [_row()])
    monkeypatch.setattr(
        review,
        "resolve_existing",
        lambda _client, queue_id, worksite_id: (
            calls.append((queue_id, worksite_id))
            or {"worksite": {"workplace_name": "경영대학행정팀"}}
        ),
    )

    result = review.interactive_review(
        object(),
        input_fn=lambda _prompt: "1",
        output_fn=output.append,
        reprocess_fn=lambda: (
            reprocess_calls.append(True)
            or {"inserted": 1, "pending": 0}
        ),
    )

    assert result == 0
    assert calls == [(12, 6761)]
    assert reprocess_calls == [True]
    assert any("연결 완료" in line for line in output)
    assert any("공고 DB 반영 완료" in line for line in output)


def test_interactive_review_can_leave_item_for_later(monkeypatch):
    output = []
    monkeypatch.setattr(review, "list_queue", lambda _client: [_row()])

    result = review.interactive_review(
        object(),
        input_fn=lambda _prompt: "l",
        output_fn=output.append,
    )

    assert result == 0
    assert any("나중" in line for line in output)
