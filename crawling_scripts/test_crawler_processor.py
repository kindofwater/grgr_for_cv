import json

import anthropic
import httpx

from crawler_pipeline.processor import bootstrap_state, process_cached_new
from crawler_pipeline.records import infer_worksite_name
from crawler_pipeline.state import CrawlerState


COMMON_BODY = (
    "고려대학교 경영전략실에서 근무할 근로장학생을 모집합니다.\n"
    "지원 자격: 본교 대학원 재학생 및 휴학생\n"
    "담당 업무: 경영전략실 업무보조\n모집 인원: 1명\n"
    "근무 기간: 2026년 8월 초 (협의 후 결정)\n"
    "근무 장소: 고려대학교 본관 3층\n"
    "근무 시간: 월~금 09:00-17:30\n"
    "지급금액: 시간 당 10,400원\n"
    "제출기간: 2026년 7월 28일까지\n"
) * 3


def _ssc(seq="10", posted="2026-07-22"):
    return {
        "data_seq": seq,
        "external_id": seq,
        "company_name": "고려대학교 경영전략실",
        "title": "[경영전략실] 대학원생 근로장학생 모집",
        "posted_at": posted,
        "recruit_until": "2026-07-28",
        "period_text": "2026.07.22~2026.07.28",
        "detail_url": "https://job.korea.ac.kr/view",
        "detail_text": COMMON_BODY,
    }


def _kupid(posted="2026-07-22"):
    return {
        "title": "[경영전략실] 대학원생 근로장학생 모집",
        "department": "경영전략실",
        "registered_date": posted,
        "detail_url": "https://portal.korea.ac.kr/p/BO06",
        "detail_text": (
            "제목 [경영전략실] 대학원생 근로장학생 모집\n\n"
            + COMMON_BODY.replace("담당 업무", "업무 내용")
        ),
        "due_date": "",
    }


def _parsed(conflicts=None):
    return {
        "hourly_wage": 10400,
        "recruit_count": "1명",
        "eligible_degree": 1,
        "eligible_status": 2,
        "job_description": "업무보조",
        "preference_notes": None,
        "extra_notes": None,
        "work_period_text": "2026년 8월 초",
        "work_duration_type": "unknown",
        "work_time_text": "월~금 09:00-17:30",
        "recruit_until": "2026-07-28",
        "work_department": "경영전략실",
        "work_location": "본관 3층",
        "conflict_fields": conflicts or [],
    }


def test_duplicate_is_parsed_once_and_marks_both_sources(tmp_path, monkeypatch):
    ssc_path, kupid_path = tmp_path / "ssc.json", tmp_path / "kupid.json"
    state_path = tmp_path / "state.json"
    ssc_path.write_text(json.dumps([_ssc("9", "2026-07-21")]), encoding="utf-8")
    kupid_path.write_text(json.dumps([_kupid("2026-07-21")]), encoding="utf-8")
    bootstrap_state(
        CrawlerState.load(state_path),
        json.loads(ssc_path.read_text()),
        json.loads(kupid_path.read_text()),
    )
    ssc_path.write_text(json.dumps([_ssc("9", "2026-07-21"), _ssc()]), encoding="utf-8")
    kupid_path.write_text(json.dumps([_kupid("2026-07-21"), _kupid()]), encoding="utf-8")

    calls = []
    monkeypatch.setattr(
        "crawler_pipeline.processor.parse_posting",
        lambda client, representative, supplement=None, **_kwargs: calls.append(
            (representative["source"], supplement["source"] if supplement else None)
        ) or _parsed(),
    )
    loaded = []
    result = process_cached_new(
        state_path=state_path,
        ssc_path=ssc_path,
        kupid_path=kupid_path,
        anthropic_client=object(),
        load_record=lambda row: loaded.append(row) or {
            "posting": "inserted",
            "worksite_name": row["worksite_name"],
            "posting_title": row["title"],
        },
    )

    assert calls == [("ssc", "kupid")]
    assert result.inserted == result.merged == 1
    assert result.updated_worksites == ["경영전략실"]
    assert result.updated_posting_titles == [loaded[0]["title"]]
    assert loaded[0]["source"] == "ssc"
    state = CrawlerState.load(state_path)
    assert state.is_processed("ssc", "10")
    assert len(state.source("kupid")["processed_ids"]) == 2


def test_sonnet_conflict_falls_back_to_two_posts(tmp_path, monkeypatch):
    ssc_path, kupid_path = tmp_path / "ssc.json", tmp_path / "kupid.json"
    state_path = tmp_path / "state.json"
    ssc_path.write_text(json.dumps([_ssc("9", "2026-07-21")]), encoding="utf-8")
    kupid_path.write_text(json.dumps([_kupid("2026-07-21")]), encoding="utf-8")
    bootstrap_state(
        CrawlerState.load(state_path),
        json.loads(ssc_path.read_text()),
        json.loads(kupid_path.read_text()),
    )
    ssc_path.write_text(json.dumps([_ssc("9", "2026-07-21"), _ssc()]), encoding="utf-8")
    kupid_path.write_text(json.dumps([_kupid("2026-07-21"), _kupid()]), encoding="utf-8")

    def parse(client, representative, supplement=None, **_kwargs):
        return _parsed(["work_period"]) if supplement else _parsed()

    monkeypatch.setattr("crawler_pipeline.processor.parse_posting", parse)
    loaded = []
    result = process_cached_new(
        state_path=state_path,
        ssc_path=ssc_path,
        kupid_path=kupid_path,
        anthropic_client=object(),
        load_record=lambda row: loaded.append(row) or "inserted",
    )
    assert len(loaded) == 2
    assert result.inserted == 2
    assert result.merged == 0


def test_unknown_worksite_is_parsed_once_before_human_queue(tmp_path, monkeypatch):
    ssc_path, kupid_path = tmp_path / "ssc.json", tmp_path / "kupid.json"
    state_path = tmp_path / "state.json"
    ssc_path.write_text(json.dumps([_ssc("9", "2026-07-21")]), encoding="utf-8")
    kupid_path.write_text(json.dumps([_kupid("2026-07-21")]), encoding="utf-8")
    bootstrap_state(
        CrawlerState.load(state_path),
        json.loads(ssc_path.read_text()),
        json.loads(kupid_path.read_text()),
    )
    ssc_path.write_text(json.dumps([
        _ssc("9", "2026-07-21"),
        _ssc("10", "2026-07-22"),
    ]), encoding="utf-8")
    kupid_path.write_text(json.dumps([_kupid("2026-07-21")]), encoding="utf-8")

    calls = []
    monkeypatch.setattr(
        "crawler_pipeline.processor.parse_posting",
        lambda *_args, **_kwargs: calls.append("called") or _parsed(),
    )
    result = process_cached_new(
        state_path=state_path,
        ssc_path=ssc_path,
        kupid_path=kupid_path,
        anthropic_client=object(),
        resolve_worksite=lambda _record: {
            "status": "pending",
            "queue_id": 12,
        },
        load_record=lambda *_args: "inserted",
    )

    assert result.pending == 1
    assert result.pending_queue_ids == [12]
    assert calls == ["called"]
    assert result.parsed == result.inserted == result.failed == 0
    assert CrawlerState.load(state_path).is_pending("ssc", "10")
    assert CrawlerState.load(state_path).get_cached_parse([("ssc", "10")]) == _parsed()


def test_dry_run_never_calls_sonnet_or_mutates_state(tmp_path, monkeypatch):
    ssc_path, kupid_path = tmp_path / "ssc.json", tmp_path / "kupid.json"
    state_path = tmp_path / "state.json"
    ssc_path.write_text(json.dumps([_ssc("9", "2026-07-21")]), encoding="utf-8")
    kupid_path.write_text(json.dumps([_kupid("2026-07-21")]), encoding="utf-8")
    bootstrap_state(
        CrawlerState.load(state_path),
        json.loads(ssc_path.read_text()),
        json.loads(kupid_path.read_text()),
    )
    before = state_path.read_bytes()
    ssc_path.write_text(
        json.dumps([_ssc("9", "2026-07-21"), _ssc("10", "2026-07-22")]),
        encoding="utf-8",
    )

    monkeypatch.setattr(
        "crawler_pipeline.processor.parse_posting",
        lambda *_args, **_kwargs: (_ for _ in ()).throw(
            AssertionError("dry-run must not call Sonnet")
        ),
    )
    result = process_cached_new(
        state_path=state_path,
        ssc_path=ssc_path,
        kupid_path=kupid_path,
        anthropic_client=None,
        load_record=lambda *_args: (_ for _ in ()).throw(
            AssertionError("dry-run must not load records")
        ),
        dry_run=True,
    )

    assert result.candidates == 1
    assert result.parsed == result.inserted == result.failed == 0
    assert state_path.read_bytes() == before


def test_cached_parse_is_reused_after_loader_failure(tmp_path, monkeypatch):
    ssc_path, kupid_path = tmp_path / "ssc.json", tmp_path / "kupid.json"
    state_path = tmp_path / "state.json"
    ssc_path.write_text(json.dumps([_ssc("9", "2026-07-21")]), encoding="utf-8")
    kupid_path.write_text(json.dumps([_kupid("2026-07-21")]), encoding="utf-8")
    bootstrap_state(
        CrawlerState.load(state_path),
        json.loads(ssc_path.read_text()),
        json.loads(kupid_path.read_text()),
    )
    ssc_path.write_text(
        json.dumps([_ssc("9", "2026-07-21"), _ssc("10", "2026-07-22")]),
        encoding="utf-8",
    )

    parse_calls = []
    monkeypatch.setattr(
        "crawler_pipeline.processor.parse_posting",
        lambda *_args, **_kwargs: parse_calls.append("called") or _parsed(),
    )
    first = process_cached_new(
        state_path=state_path,
        ssc_path=ssc_path,
        kupid_path=kupid_path,
        anthropic_client=object(),
        load_record=lambda _row: (_ for _ in ()).throw(RuntimeError("db unavailable")),
    )
    assert first.failed == 1
    assert parse_calls == ["called"]

    state = CrawlerState.load(state_path)
    state.source("ssc")["failed_ids"]["10"]["next_retry_date"] = "2000-01-01"
    state.save()
    loaded = []
    second = process_cached_new(
        state_path=state_path,
        ssc_path=ssc_path,
        kupid_path=kupid_path,
        anthropic_client=object(),
        load_record=lambda row: loaded.append(row) or "inserted",
    )

    assert second.inserted == 1
    assert len(loaded) == 1
    assert parse_calls == ["called"]
    assert CrawlerState.load(state_path).data["parse_cache"] == {}


def test_ssc_worksite_inference_survives_legacy_parser_removal():
    assert infer_worksite_name({
        "company_name": "고려대학교",
        "title": "[중앙도서관] 학술정보개발팀 근로장학생 모집(휴학생)",
    }) == "학술정보개발팀"
    assert infer_worksite_name({
        "company_name": "고려대학교",
        "title": "[과학도서관] 학술정보큐레이션팀 근로장학생 모집",
    }) == "과학도서관 학술정보큐레이션팀"
    assert infer_worksite_name({
        "company_name": "고려대학교 중앙도서관",
        "title": "[중앙도서관] 학술정보개발팀 근로장학생 모집",
    }) == "학술정보개발팀"
    # 제목에 팀명이 없으면 대괄호 안을 쓰되, 정규화가 현행 근무지명으로 바꾼다.
    # 고려대 학교근장에는 평문 '중앙도서관' 근무지가 없다 — 20260804090000이
    # '중앙도서관 학술정보서비스팀'으로 rename했다. 평문으로 두면 어느 근무지에도
    # 매칭되지 않거나, 같은 이름인 서울대 교내 국가근로(id=6737)로 잘못 붙는다.
    assert infer_worksite_name({
        "company_name": "고려대학교 중앙도서관",
        "title": "[중앙도서관] 근로장학생 모집",
    }) == "중앙도서관 학술정보서비스팀"
    assert infer_worksite_name({
        "company_name": "고려대학교",
        "title": "[ONE-STOP서비스센터]의료공제 근로장학생 모집",
    }) == "ONE-STOP서비스센터"
    assert infer_worksite_name({
        "company_name": "고려대학교",
        "title": "재정팀 근로장학생 모집 (재학생, 휴학생)",
    }) == "재정팀"


class _RaisingClient:
    """messages.create가 항상 같은 예외를 던지는 Anthropic 클라이언트 대역."""

    def __init__(self, error):
        self.messages = self
        self.error = error
        self.calls = 0

    def create(self, **_kwargs):
        self.calls += 1
        raise self.error


def _credit_error():
    request = httpx.Request("POST", "https://api.anthropic.com/v1/messages")
    return anthropic.BadRequestError(
        "Your credit balance is too low to access the Anthropic API.",
        response=httpx.Response(400, request=request),
        body=None,
    )


def _fresh_ssc_candidates(tmp_path, seqs):
    """9번을 기준선으로 잡고, seqs를 신규 SSC 후보로 둔 상태를 만든다."""
    ssc_path, kupid_path = tmp_path / "ssc.json", tmp_path / "kupid.json"
    state_path = tmp_path / "state.json"
    ssc_path.write_text(json.dumps([_ssc("9", "2026-07-21")]), encoding="utf-8")
    kupid_path.write_text(json.dumps([_kupid("2026-07-21")]), encoding="utf-8")
    bootstrap_state(
        CrawlerState.load(state_path),
        json.loads(ssc_path.read_text()),
        json.loads(kupid_path.read_text()),
    )
    rows = [_ssc("9", "2026-07-21")] + [
        _ssc(seq, f"2026-07-{22 + index}") for index, seq in enumerate(seqs)
    ]
    ssc_path.write_text(json.dumps(rows), encoding="utf-8")
    return state_path, ssc_path, kupid_path


def test_budget_running_out_mid_retry_defers_instead_of_failing(tmp_path, monkeypatch):
    """실제 파서를 통과한 한도 초과는 보류여야 한다(실패 횟수 소모 금지).

    실제 사례(2026-10-08): 학부대학행정팀 공고가 '한도 초과'로 attempts를 잃었다.
    """
    monkeypatch.setattr("crawler_pipeline.llm.time.sleep", lambda _s: None)
    state_path, ssc_path, kupid_path = _fresh_ssc_candidates(tmp_path, ["10"])
    state = CrawlerState.load(state_path)
    for _ in range(4):  # 오늘 남은 호출은 1건
        assert state.reserve_llm_call()
    state.save()

    client = _RaisingClient(ValueError("model said no"))
    result = process_cached_new(
        state_path=state_path,
        ssc_path=ssc_path,
        kupid_path=kupid_path,
        anthropic_client=client,
        load_record=lambda *_args: "inserted",
    )

    assert client.calls == 1
    assert result.failed == 0
    assert result.deferred == 1
    state = CrawlerState.load(state_path)
    assert state.is_deferred("ssc", "10")
    assert not state.is_failed("ssc", "10")


def test_a_provider_outage_defers_and_stops_the_run(tmp_path, monkeypatch):
    """과금 오류는 공고 탓이 아니다. 횟수를 깎지 않고 보류하고, 남은 후보에
    한도를 더 쓰지 않으며, 상태 JSON에 이유를 남긴다.

    실제 사례(2026-10-07~08): 크레딧 소진 상태에서 공고 3건이 attempts를 2회씩
    잃고 하루 한도 5건이 전부 실패 호출에 쓰였다.
    """
    monkeypatch.setattr("crawler_pipeline.llm.time.sleep", lambda _s: None)
    state_path, ssc_path, kupid_path = _fresh_ssc_candidates(tmp_path, ["10", "11"])

    client = _RaisingClient(_credit_error())
    result = process_cached_new(
        state_path=state_path,
        ssc_path=ssc_path,
        kupid_path=kupid_path,
        anthropic_client=client,
        load_record=lambda *_args: "inserted",
    )

    assert client.calls == 1
    assert result.failed == 0
    assert result.deferred == 1
    assert result.ai_calls_used == 1
    assert "credit balance" in (result.unavailable or "")
    assert any("credit balance" in message for message in result.errors)
    state = CrawlerState.load(state_path)
    assert state.is_deferred("ssc", "10")
    assert not state.is_failed("ssc", "10")
    assert not state.is_failed("ssc", "11")
    assert not state.is_deferred("ssc", "11")
