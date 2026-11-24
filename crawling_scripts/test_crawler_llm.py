import anthropic
import httpx
import pytest

from crawler_pipeline.llm import LLMBudgetExceeded, parse_posting, redact_for_model


class _Response:
    class _Block:
        type = "text"
        text = (
            '{"job_description":"행정보조","work_time_text":"09:00~17:30",'
            '"recruit_count":"1명","work_department":"학생지원팀"}'
        )

    content = [_Block()]


class _Messages:
    def __init__(self):
        self.kwargs = None

    def create(self, **kwargs):
        self.kwargs = kwargs
        return _Response()


class _Client:
    def __init__(self):
        self.messages = _Messages()


def test_redact_for_model_keeps_office_phone_only():
    value = (
        "담당자: 홍길동, 02-3290-1403, 010-1234-5678, "
        "person@korea.ac.kr"
    )
    redacted = redact_for_model(value)
    assert "홍길동" not in redacted
    assert "010-1234-5678" not in redacted
    assert "person@korea.ac.kr" not in redacted
    assert "02-3290-1403" in redacted


def test_parse_posting_adds_source_department_without_extra_call():
    client = _Client()
    parsed = parse_posting(client, {
        "source": "kupid",
        "title": "근로장학생 모집",
        "posted_at": "2026-07-31",
        "source_department": "학생지원팀",
        "body": "문의 person@korea.ac.kr / 02-3290-1403",
    })
    assert parsed["work_department"] == "학생지원팀"
    assert client.messages.kwargs is not None
    prompt = client.messages.kwargs["messages"][0]["content"]
    assert "[대표 게시일] 2026-07-31" in prompt
    assert "[대표 게시 부서] 학생지원팀" in prompt
    assert "person@korea.ac.kr" not in prompt
    assert "02-3290-1403" in prompt


REPRESENTATIVE = {
    "source": "ssc",
    "title": "[중앙도서관] 제2자료실 근로장학생 모집",
    "posted_at": "2026-10-06",
    "source_department": "중앙도서관",
    "body": "중앙도서관(3F) 제2자료실에서 근무할 근로장학생을 모집합니다.",
}


def _status_error(cls, status, message):
    request = httpx.Request("POST", "https://api.anthropic.com/v1/messages")
    return cls(message, response=httpx.Response(status, request=request), body=None)


def _connection_error():
    return anthropic.APIConnectionError(
        request=httpx.Request("POST", "https://api.anthropic.com/v1/messages")
    )


class _RaisingMessages:
    def __init__(self, error):
        self.error = error
        self.calls = 0

    def create(self, **_kwargs):
        self.calls += 1
        raise self.error


def _client_raising(error):
    client = _Client()
    client.messages = _RaisingMessages(error)
    return client


def test_budget_exhaustion_before_a_retry_is_not_a_parse_failure(monkeypatch):
    """첫 시도가 실패하고 두 번째 시도 직전에 한도가 끝나면 공고 실패가 아니다.

    실제 사례(2026-10-08): 한도 초과가 'Sonnet parsing failed after 2 attempts'로
    감싸여 failed로 집계됐고, 공고가 재시도 횟수 하나를 잃었다.
    """
    monkeypatch.setattr("crawler_pipeline.llm.time.sleep", lambda _s: None)
    reserved = []

    def reserve():
        reserved.append(1)
        if len(reserved) > 1:
            raise LLMBudgetExceeded("daily AI call limit reached")

    client = _client_raising(ValueError("model said no"))
    with pytest.raises(LLMBudgetExceeded):
        parse_posting(client, REPRESENTATIVE, before_request=reserve)
    assert client.messages.calls == 1


@pytest.mark.parametrize("error", [
    _status_error(anthropic.BadRequestError, 400,
                  "Your credit balance is too low to access the Anthropic API."),
    _status_error(anthropic.AuthenticationError, 401, "invalid x-api-key"),
    _status_error(anthropic.RateLimitError, 429, "rate limited"),
    _status_error(anthropic.InternalServerError, 500, "overloaded"),
    _connection_error(),
], ids=["credit", "auth", "rate-limit", "server", "network"])
def test_a_provider_problem_is_an_outage_not_a_posting_failure(monkeypatch, error):
    """과금·인증·한도·서버·연결 오류는 공고와 무관하고 재시도로 풀리지 않는다.

    실제 사례(2026-10-07~08): 크레딧 소진 400이 공고 실패로 집계돼 공고 3건이
    재시도 횟수를 2회씩 잃었고, 하루 한도 5건이 실패 재시도로 소진됐다.
    """
    from crawler_pipeline.llm import LLMUnavailable

    monkeypatch.setattr("crawler_pipeline.llm.time.sleep", lambda _s: None)
    client = _client_raising(error)
    with pytest.raises(LLMUnavailable):
        parse_posting(client, REPRESENTATIVE)
    assert client.messages.calls == 1  # 재시도 없이 바로 멈춘다


def test_an_ordinary_bad_request_still_counts_against_the_posting(monkeypatch):
    """입력 쪽 문제의 400은 공고 실패라 기존처럼 재시도 뒤 RuntimeError."""
    monkeypatch.setattr("crawler_pipeline.llm.time.sleep", lambda _s: None)
    client = _client_raising(_status_error(
        anthropic.BadRequestError, 400,
        "messages.0.content: text content blocks must be non-empty",
    ))
    with pytest.raises(RuntimeError, match="after 2 attempts"):
        parse_posting(client, REPRESENTATIVE)
    assert client.messages.calls == 2
