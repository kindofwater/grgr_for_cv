"""One shared Sonnet parser for SSC and KUPID."""
from __future__ import annotations

import json
import os
import re
import time

MODEL = os.environ.get("CRAWLER_PARSE_MODEL", "claude-sonnet-5-5")
MAX_ATTEMPTS_PER_RUN = 2
PROMPT_SCHEMA_VERSION = 2

_EMAIL_RE = re.compile(r"[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}")
_MOBILE_RE = re.compile(r"(?<!\d)01[016789][-. ]?\d{3,4}[-. ]?\d{4}(?!\d)")
_CONTACT_NAME_RE = re.compile(
    r"((?:담당자|문의자|담당)\s*[:：]\s*)[가-힣]{2,4}(?=\s|,|/|$)"
)


class LLMBudgetExceeded(RuntimeError):
    """Raised before an API request when the persisted daily allowance is spent."""


class LLMUnavailable(RuntimeError):
    """Raised when the provider, not the posting, is the problem.

    Billing, authentication, rate limiting, server faults and lost connections
    cannot be fixed by retrying the posting, so they must never count against
    its retry budget. 2026-10-07~08: a drained credit balance was wrapped as an
    ordinary parse failure, three postings each lost two attempts, and the daily
    allowance was spent on calls that could not succeed.
    """


_OUTAGE_STATUS = frozenset({401, 402, 403, 429})


def is_provider_outage(exc: BaseException) -> bool:
    """True for errors that say nothing about the posting being parsed."""
    try:
        import anthropic
    except ImportError:
        return False
    if isinstance(exc, anthropic.APITimeoutError):
        # A timeout may be this one oversized posting; let it retry and fail.
        return False
    if isinstance(exc, anthropic.APIConnectionError):
        return True
    if isinstance(exc, anthropic.APIStatusError):
        status = int(getattr(exc, "status_code", 0) or 0)
        if status in _OUTAGE_STATUS or status >= 500:
            return True
        return status == 400 and "credit balance" in str(exc).lower()
    return False


def redact_for_model(value: str | None) -> str:
    """Remove contact PII while retaining office landlines for identity evidence."""
    text = str(value or "")
    text = _EMAIL_RE.sub("[이메일]", text)
    text = _MOBILE_RE.sub("[휴대전화]", text)
    return _CONTACT_NAME_RE.sub(r"\1[담당자]", text)

SYSTEM = """고려대학교 근로장학생 공고를 구조화한다.
반드시 설명이나 코드펜스 없이 JSON 객체 하나만 출력한다.
대표 본문을 기준으로 추출하고, 대표 본문에 값이 없을 때만 보충 본문을 사용한다.
두 본문의 명시적 값이 충돌하면 conflict_fields에 필드명을 넣는다.
모르는 값은 null로 둔다.

필드:
hourly_wage(integer|null), recruit_count(string|null),
eligible_degree(0=학부만,1=대학원만,2=모두,3=미정),
eligible_status(0=재학만,1=휴학만,2=모두,3=미정),
job_description, preference_notes, extra_notes,
work_period_text, work_period_days(integer|null),
work_duration_type(short|long|unknown),
work_time_text, recruitment_period_text,
recruit_until(YYYY-MM-DD|null), work_start_date(YYYY-MM-DD|null),
posting_department(string|null), work_department(string|null),
work_location(string|null), worksite_evidence(string|null),
office_phone(string|null),
conflict_fields(array of strings).

근무지 추출 기준:
- posting_department는 공고를 게시한 부서다.
- work_department는 학생이 실제로 근무할 조직이다. 제목·본문에 명시된 실제
  근무부서를 우선하고, 알 수 없으면 null로 둔다.
- work_location은 건물·층·호실 등 물리적 장소다.
- worksite_evidence는 위 판단의 가장 직접적인 원문 한 문장이다.
- office_phone은 사무실 유선번호만 출력하고 휴대전화는 null로 둔다.

근무기간 분류 기준:
- 실제 근무기간이 42일(6주) 미만이면 short, 42일 이상이면 long이다.
- 기간 선택지가 여러 개면 가장 긴 선택지의 일수를 work_period_days로 출력하고 그 값을 기준으로 분류한다.
- 시작일과 종료일이 명확하면 양 끝 날짜를 포함한 달력 일수로 계산한다.
- 일수를 계산할 수 없으면 work_period_days는 null로 두고, 공고가 명시한 단기/장기 표현만 따른다.
- 기간과 명시 표현이 모두 불명확하면 unknown으로 둔다.
"""


def response_text(response) -> str:
    return "\n".join(
        block.text
        for block in response.content
        if getattr(block, "type", None) == "text" and hasattr(block, "text")
    ).strip()


def parse_json(raw: str) -> dict:
    cleaned = re.sub(r"^```(?:json)?\s*", "", (raw or "").strip())
    cleaned = re.sub(r"\s*```$", "", cleaned)
    match = re.search(r"\{.*\}", cleaned, re.DOTALL)
    if not match:
        raise ValueError("Sonnet response did not contain a JSON object")
    value = json.loads(match.group(0), strict=False)
    if not isinstance(value, dict):
        raise ValueError("Sonnet response must be a JSON object")
    return value


def parse_posting(client, representative: dict, supplement: dict | None = None,
                  max_attempts: int = MAX_ATTEMPTS_PER_RUN,
                  before_request=None) -> dict:
    representative_body = redact_for_model(
        representative.get("body") or representative.get("raw_text") or ""
    )
    user = (
        f"[대표 출처] {representative['source']}\n"
        f"[대표 제목] {representative.get('title', '')}\n"
        f"[대표 게시일] {representative.get('posted_at', '')}\n"
        f"[대표 게시 부서] {representative.get('source_department', '')}\n"
        f"[대표 본문]\n{representative_body}"
    )
    if supplement:
        supplement_body = redact_for_model(
            supplement.get("body") or supplement.get("raw_text") or ""
        )
        user += (
            f"\n\n[보충 출처] {supplement['source']}\n"
            f"[보충 제목] {supplement.get('title', '')}\n"
            f"[보충 게시일] {supplement.get('posted_at', '')}\n"
            f"[보충 게시 부서] {supplement.get('source_department', '')}\n"
            f"[보충 본문]\n{supplement_body}"
        )
    error = None
    for attempt in range(1, max_attempts + 1):
        try:
            if before_request:
                before_request()
            response = client.messages.create(
                model=MODEL,
                max_tokens=1800,
                system=SYSTEM,
                messages=[{"role": "user", "content": user}],
                timeout=45.0,
            )
            parsed = parse_json(response_text(response))
            if not any(parsed.get(key) not in (None, "", [], {})
                       for key in ("job_description", "work_time_text", "recruit_count")):
                raise ValueError("Sonnet response has no meaningful posting fields")
            return parsed
        except LLMBudgetExceeded:
            raise
        except Exception as exc:
            if is_provider_outage(exc):
                raise LLMUnavailable(f"Anthropic API unavailable: {exc}") from exc
            error = exc
            if attempt < max_attempts:
                time.sleep(2 ** (attempt - 1))
    raise RuntimeError(f"Sonnet parsing failed after {max_attempts} attempts: {error}") from error
