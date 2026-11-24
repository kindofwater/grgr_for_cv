"""SSC/KUPID 공고를 Supabase에 무삭제 멱등 UPSERT(service_role).

- worksites: normalized_name 키로 없으면 insert, 있으면 유지.
- postings: (source, external_id) 키로 없으면 insert, 있으면 machine-owned(+content) 갱신.
- placeholder posting은 진짜 공고 첫 insert 시 삭제(예외).

실행: 사용자 환경변수 SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY 필요.
  python crawling_scripts/upsert_worksites.py            # ssc_parsed.json 적재
"""
from __future__ import annotations

import datetime
import hashlib
import json
import re
import sys
from pathlib import Path

from deadline_policy import decide_deadline
from source_metadata import title_without_closed_marker
from worksite_norm import (
    canonicalize_worksite_display_name,
    normalize_worksite_name,
    qualify_special_library_worksite,
    resolve_worksite_name,
    worksite_identity_key,
)

ROOT_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = ROOT_DIR / "data"
SSC_PARSED = DATA_DIR / "ssc_parsed.json"
KUPID_PARSED_CACHE = DATA_DIR / "kupid_parsed_cache.json"

CRAWL_NOTICE_TITLE = "근로장학 공고 업데이트"
_CRAWL_NOTICE_TOTAL_RE = re.compile(r"총\s+(\d+)건\s+업데이트")

UNIVERSITY_ID = 1                 # 고려대(본교)
ORG_NAME = "고려대학교(본교)"

# 크롤러가 매일 갱신해도 되는 컬럼(모집 판정계).
MACHINE_COLS = {
    "recruit_until", "recruit_until_estimated", "deadline_basis",
    "is_active", "recruitment_period_text", "source_closed_at",
    "source_closed_reason",
}
# 사람이 웹에서 고칠 수 있는 컬럼(manual_override면 크롤러가 건너뜀).
CONTENT_COLS = {"title", "hourly_wage", "recruit_count", "job_description", "preference_notes",
                "extra_notes", "work_period_text", "work_duration_type", "work_time_text",
                "eligible_degree", "eligible_status", "source_department",
                "work_department", "work_location", "office_phone", "attachment_names"}

_DATE_TOKEN_RE = re.compile(
    r"(20\d{2})\s*(?:[.\-/년]\s*)?(\d{1,2})\s*(?:[.\-/월]\s*)?(\d{1,2})"
)
_RECRUITMENT_PERIOD_WORD_RE = re.compile(r"(모집|신청|지원|접수)\s*(기간|기한|마감|마감일|일자)")
_WS_RE = re.compile(r"\s+")


def _date_token_set(text) -> set[str]:
    """텍스트 안의 날짜를 YYYY-MM-DD set으로 추출한다(비교용, 시각 무시)."""
    out = set()
    for m in _DATE_TOKEN_RE.finditer(str(text or "")):
        try:
            d = datetime.date(int(m[1]), int(m[2]), int(m[3]))
        except ValueError:
            continue
        out.add(d.isoformat())
    return out


def looks_like_copied_recruitment_period(work_period_text, recruitment_period_text) -> bool:
    """근로기간 칸에 모집/신청기간이 복사된 흔한 LLM 오판이면 True."""
    work_text = str(work_period_text or "").strip()
    if not work_text:
        return False
    if _RECRUITMENT_PERIOD_WORD_RE.search(work_text):
        return True
    work_dates = _date_token_set(work_text)
    recruit_dates = _date_token_set(recruitment_period_text)
    return bool(recruit_dates and len(work_dates) >= 2 and work_dates.issubset(recruit_dates))


def sanitize_canonical_record(canonical: dict) -> dict:
    """적재 직전 공고 품질 보정. 원본 dict는 건드리지 않는다."""
    out = dict(canonical)
    if looks_like_copied_recruitment_period(out.get("work_period_text"), out.get("period_text")):
        out["work_period_text"] = None
        out["work_duration_type"] = "unknown"
    return out


def _norm_duplicate_text(value) -> str:
    return _WS_RE.sub(" ", str(value or "").strip()).lower()


def is_same_posting_for_dedupe(existing: dict, fields: dict) -> bool:
    """같은 근무지 안에서 직무내용+마감일이 같으면 소스가 달라도 같은 공고로 본다."""
    if existing.get("is_placeholder"):
        return False
    desc = _norm_duplicate_text(fields.get("job_description"))
    existing_desc = _norm_duplicate_text(existing.get("job_description"))
    deadline = fields.get("recruit_until")
    return bool(desc and deadline and existing_desc == desc
                and str(existing.get("recruit_until") or "") == str(deadline))


def find_duplicate_posting(client, worksite_id: int, fields: dict) -> dict | None:
    if not fields.get("job_description") or not fields.get("recruit_until"):
        return None
    rows = (client.table("postings")
            .select("id, source, external_id, job_description, recruit_until, is_placeholder")
            .eq("worksite_id", worksite_id)
            .eq("recruit_until", fields["recruit_until"])
            .eq("is_placeholder", False)
            .execute()).data
    for row in rows or []:
        if is_same_posting_for_dedupe(row, fields):
            return row
    return None


def decide_posting_update(existing: dict, parsed: dict) -> dict:
    """기존 posting 갱신 시 쓸 필드만 골라 반환. None 값은 제외."""
    protected = bool(existing.get("manual_override"))
    deadline_protected = (
        protected or existing.get("deadline_basis") == "human_confirmed"
    )
    protected_deadline_cols = {
        "recruit_until", "recruit_until_estimated", "deadline_basis",
        "is_active",
    }
    upd = {}
    if not protected:
        upd = {
            c: parsed[c] for c in MACHINE_COLS
            if parsed.get(c) is not None
            and not (deadline_protected and c in protected_deadline_cols)
        }
    if not protected:
        upd.update({c: parsed[c] for c in CONTENT_COLS if parsed.get(c) is not None})
    return upd


def _or3(v):
    """eligible 값 None(파싱 미상) → 3(미상). 0(학부만/재학만)은 falsy라 `or 3` 금지."""
    return 3 if v is None else v


def _elig(v):
    """eligible 값을 0/1/2/3로 강제(_or3 후 범위 밖이면 3=미상)."""
    v = _or3(v)
    return v if v in (0, 1, 2, 3) else 3


def kupid_external_id(title: str, dept: str, reg_date: str) -> str:
    """KUPID 공고 자연키 = stable_key(제목·부서·등록일) 해시.
    detail_url(encQS)은 세션마다 바뀌어 불안정하므로 stable_key를 쓴다(spec §4.5)."""
    raw = (
        f"{title_without_closed_marker(title)}|"
        f"{str(dept or '').strip()}|{str(reg_date or '')[:10]}"
    )
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:16]


def _xlsx_cell(row: dict, key: str):
    v = row.get(key)
    return None if v in (None, "") else v


def _flag(v):
    """Excel 'O'/'X'/공백 → True/False/None (generate_school_migration와 동일 규칙)."""
    s = str(v or "").strip().upper()
    return True if s == "O" else False if s == "X" else None


def eligible_pair(a_ok, b_ok):
    """둘 다=2, 앞만=0, 뒤만=1, 그 외(미상)=3. (a=학부/재학, b=대학원/휴학.)"""
    a, b = _flag(a_ok), _flag(b_ok)
    if a and b:
        return 2
    if a and b is False:
        return 0
    if b and a is False:
        return 1
    return 3


def _duration(v):
    """Excel 단기여부 O/X/공백 → short/long/unknown."""
    f = _flag(v)
    return "short" if f is True else "long" if f is False else "unknown"


def _kupid_notice_key(title, source_dept, registered_date) -> tuple[str, str, str]:
    """KUPID 파싱 캐시와 Excel 행을 연결하는 목록 원본 기준 키."""
    date = (registered_date.isoformat()[:10] if hasattr(registered_date, "isoformat")
            else str(registered_date or "")[:10])
    return str(title or ""), str(source_dept or ""), date


def load_kupid_work_departments() -> dict[tuple[str, str, str], str]:
    """Sonnet이 추출한 실제 근무부서를 파싱 캐시에서 읽는다.

    기존 Excel에는 근무부서 열이 없을 수 있으므로, 다음 재생성 전에도 캐시 값을
    사용한다. Excel에 근무부서를 직접 입력한 경우에는 그 값이 이 캐시보다 우선한다.
    """
    if not KUPID_PARSED_CACHE.exists():
        return {}
    try:
        records = json.loads(KUPID_PARSED_CACHE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}

    departments = {}
    for record in records:
        department = str((record.get("ai") or {}).get("department") or "").strip()
        if department:
            departments[_kupid_notice_key(
                record.get("title"), record.get("department"), record.get("registered_date")
            )] = department
    return departments


def resolve_kupid_worksite_name(title: str, parsed_department: str, source_department: str) -> str:
    """Sonnet의 실제 근무부서를 우선해 KUPID 근무지명을 결정한다.

    과거 캐시는 제목을 모델에 주기 전 생성됐다. 물리학과처럼 제목에 실제 부서가
    명시된 대리 게시 공고는 그 캐시가 게시 부서를 되돌려줘도 실제 부서를 보존한다.
    """
    if "물리학과" in title:
        candidate = "물리학과"
    else:
        candidate = parsed_department or source_department
    return qualify_special_library_worksite(candidate, title)


def _kupid_row_to_canonical(row: dict) -> dict | None:
    """KUPID 파싱 row(dict) → 로더 canonical.

    부서명은 KUPID 목록의 게시 부서라 자연키에만 유지한다. 실제 근무지명은
    Sonnet이 제목·본문에서 추출한 근무부서를 우선하고, 빈 경우에만 게시 부서로 폴백한다.
    """
    source_dept = str(row.get("부서명") or "").strip()
    if not source_dept:
        return None
    parsed_dept = str(row.get("근무부서") or "").strip()
    ru = row.get("모집마감일(계산)")
    ru_iso = ru.isoformat()[:10] if hasattr(ru, "isoformat") else (str(ru)[:10] if ru else "")
    # 등록일도 날짜 정규화 후 해시(엑셀 셀이 datetime이면 str()에 '...00:00:00'이 섞여
    # 재export 시 external_id가 흔들려 중복 공고 발생). ru_iso와 동일 가드.
    reg = row.get("등록일")
    reg_iso = reg.isoformat()[:10] if hasattr(reg, "isoformat") else str(reg or "")
    wage = row.get("시급")
    title = str(row.get("제목") or "")
    worksite_name = resolve_kupid_worksite_name(title, parsed_dept, source_dept)
    return {
        "source": "kupid",
        "external_id": kupid_external_id(title, source_dept, reg_iso),
        "worksite_name": worksite_name,
        "source_department": source_dept,
        "work_department": parsed_dept or None,
        "title": title,
        "recruit_until": ru_iso,
        "recruit_until_estimated": bool(_flag(row.get("마감추정"))),
        "period_text": _xlsx_cell(row, "지원마감일"),
        "posted_at": reg_iso,                       # 게시일자 보존(SSC와 동일하게 created_at으로)
        "source_url": _xlsx_cell(row, "출처URL"),
        "raw_text": _xlsx_cell(row, "본문(원본)"),
        "hourly_wage": int(wage) if isinstance(wage, (int, float)) else None,
        "recruit_count": _xlsx_cell(row, "모집인원"),
        "eligible_degree": eligible_pair(row.get("학부생가능"), row.get("대학원생가능")),
        "eligible_status": eligible_pair(row.get("재학생가능"), row.get("휴학생가능")),
        "job_description": _xlsx_cell(row, "직무내용"),
        "preference_notes": _xlsx_cell(row, "우대조건"),
        "extra_notes": _xlsx_cell(row, "기타특이사항"),
        "work_period_text": _xlsx_cell(row, "근무기간"),
        "work_duration_type": _duration(row.get("단기여부")),
        "work_time_text": _xlsx_cell(row, "근무시간"),
    }


def kupid_rows_to_canonical(xlsx_path) -> list[dict]:
    import openpyxl
    wb = openpyxl.load_workbook(xlsx_path, data_only=True)
    ws = wb["파싱결과"]
    headers = [c.value for c in ws[1]]
    cached_work_departments = load_kupid_work_departments()
    out = []
    for r in ws.iter_rows(min_row=2, values_only=True):
        if not any(v not in (None, "") for v in r):
            continue
        row = dict(zip(headers, r))
        if not str(row.get("근무부서") or "").strip():
            row["근무부서"] = cached_work_departments.get(_kupid_notice_key(
                row.get("제목"), row.get("부서명"), row.get("등록일")
            ), "")
        canon = _kupid_row_to_canonical(row)
        if canon is not None:
            out.append(canon)
    return out


def backfill_normalized_names(client) -> int:
    """normalized_name이 빈 school worksites를 Python 정규화로 채움(정본 동기화)."""
    rows = (client.table("worksites").select("id, workplace_name")
            .eq("type", "school").is_("normalized_name", "null")
            .is_("deleted_at", "null").execute()).data
    n = 0
    for r in rows:
        norm = normalize_worksite_name(r["workplace_name"])
        client.table("worksites").update({"normalized_name": norm}).eq("id", r["id"]).execute()
        n += 1
    return n


def _posting_fields(canonical: dict, today: datetime.date, *,
                    first_seen_at=None) -> dict:
    """canonical → postings 컬럼 dict(파싱 None은 그대로 둠)."""
    canonical = sanitize_canonical_record(canonical)
    supplied_estimate = bool(canonical.get("recruit_until_estimated", False))
    deadline = decide_deadline(
        source=canonical.get("source"),
        explicit_until=(
            None if supplied_estimate else canonical.get("recruit_until")
        ),
        posted_at=canonical.get("posted_at"),
        first_seen_at=first_seen_at,
        work_start_date=canonical.get("work_start_date"),
    )
    ru = deadline.recruit_until
    # 마감일 당일까지 포함하고 다음 날부터 비활성으로 본다.
    active = (
        not canonical.get("source_closed_at")
        and (ru is None or ru >= today.isoformat())
    )
    return {
        "source": canonical["source"],
        "external_id": canonical["external_id"],
        "title": canonical.get("title"),
        "source_url": canonical.get("source_url"),
        "recruit_until": ru,
        "recruit_until_estimated": deadline.estimated,
        "deadline_basis": deadline.basis,
        "is_active": active,
        "recruitment_period_text": canonical.get("period_text"),
        "raw_text": canonical.get("raw_text"),
        "hourly_wage": canonical.get("hourly_wage"),
        "recruit_count": canonical.get("recruit_count"),
        "eligible_degree": _elig(canonical.get("eligible_degree")),
        "eligible_status": _elig(canonical.get("eligible_status")),
        "job_description": canonical.get("job_description"),
        "preference_notes": canonical.get("preference_notes"),
        "extra_notes": canonical.get("extra_notes"),
        "work_period_text": canonical.get("work_period_text"),
        "work_duration_type": (canonical.get("work_duration_type")
                               if canonical.get("work_duration_type") in ("short", "long", "unknown")
                               else "unknown"),
        "work_time_text": canonical.get("work_time_text"),
        "source_department": canonical.get("source_department"),
        "work_department": canonical.get("work_department"),
        "work_location": canonical.get("work_location"),
        "office_phone": canonical.get("office_phone"),
        "source_closed_at": canonical.get("source_closed_at"),
        "source_closed_reason": canonical.get("source_closed_reason"),
        "attachment_names": canonical.get("attachment_names") or [],
        "is_placeholder": False,
    }


def upsert_worksite(client, canonical: dict) -> int:
    resolved_name = resolve_worksite_name(
        canonical["worksite_name"],
        canonical.get("title"),
        canonical.get("raw_text"),
        canonical.get("job_description"),
        canonical.get("extra_notes"),
    )
    norm = normalize_worksite_name(resolved_name)
    if not norm:
        raise ValueError(f"empty normalized worksite name: {canonical.get('worksite_name')!r}")
    q = (client.table("worksites").select("id, workplace_name")
         .eq("university_id", UNIVERSITY_ID).eq("type", "school")
         .eq("normalized_name", norm).is_("deleted_at", "null").execute())
    if q.data:
        existing = q.data[0]
        canonical_existing = canonicalize_worksite_display_name(
            existing.get("workplace_name")
        )
        if canonical_existing and canonical_existing != existing.get("workplace_name"):
            client.table("worksites").update({
                "workplace_name": canonical_existing,
            }).eq("id", existing["id"]).execute()
        return existing["id"]
    identity = worksite_identity_key(resolved_name)
    candidates = (
        client.table("worksites")
        .select("id, workplace_name, normalized_name")
        .eq("university_id", UNIVERSITY_ID)
        .eq("type", "school")
        .is_("deleted_at", "null")
        .execute()
        .data
    ) or []
    existing = next((
        row for row in candidates
        if worksite_identity_key(row.get("normalized_name") or row.get("workplace_name"))
        == identity
    ), None)
    if existing:
        return existing["id"]
    ins = client.table("worksites").insert({
        "university_id": UNIVERSITY_ID, "type": "school", "location_type": "on_campus",
        "organization_name": ORG_NAME, "workplace_name": resolved_name,
        "region": None, "normalized_name": norm,
    }).execute()
    return ins.data[0]["id"]


def upsert_posting(client, worksite_id: int, canonical: dict, today: datetime.date,
                   *, check_legacy_duplicate: bool = True) -> str:
    source = canonical["source"]
    external_id = canonical["external_id"]
    q = (client.table("postings").select(
            "id, manual_override, worksite_id, created_at, deadline_basis"
         )
         .eq("source", source).eq("external_id", external_id)
         .limit(1).execute())
    if q.data:
        existing = q.data[0]
        fields = _posting_fields(
            canonical, today, first_seen_at=existing.get("created_at")
        )
        upd = decide_posting_update(existing, fields)
        if existing.get("worksite_id") != worksite_id and not existing.get("manual_override"):
            upd["worksite_id"] = worksite_id
        if upd:
            client.table("postings").update(upd).eq("id", existing["id"]).execute()
        return "updated"
    fields = _posting_fields(canonical, today, first_seen_at=today)
    if check_legacy_duplicate and find_duplicate_posting(client, worksite_id, fields):
        return "skipped_duplicate"
    # 진짜 공고 첫 삽입 — 이 근무지의 껍데기 posting 제거(예외적 삭제).
    client.table("postings").delete().eq("worksite_id", worksite_id)\
        .eq("is_placeholder", True).execute()
    fields["worksite_id"] = worksite_id
    if canonical.get("posted_at"):
        fields["created_at"] = canonical["posted_at"]   # SSC 게시일자 보존. 없으면 키 생략→DB default now()
    client.table("postings").insert(fields).execute()
    return "inserted"


def apply_source_closures(client, records: list[dict]) -> int:
    """Close already-known postings from strong source-list metadata only."""
    changed = 0
    for record in records:
        closed_at = record.get("source_closed_at")
        if not closed_at:
            continue
        rows = (
            client.table("postings")
            .select("id, manual_override, source_closed_at")
            .eq("source", record.get("source"))
            .eq("external_id", record.get("external_id"))
            .limit(1)
            .execute()
            .data
        ) or []
        if not rows or rows[0].get("manual_override") or rows[0].get("source_closed_at"):
            continue
        client.table("postings").update({
            "source_closed_at": closed_at,
            "source_closed_reason": (
                record.get("source_closed_reason") or "source_metadata"
            ),
            "is_active": False,
        }).eq("id", rows[0]["id"]).execute()
        changed += 1
    return changed


def load(client, records: list[dict], today: datetime.date | None = None) -> dict:
    """Low-level legacy loader that may create worksites.

    Interactive and scheduled entry points must use ``load_reviewed`` so an
    unknown worksite cannot bypass the human review queue.
    """
    today = today or datetime.date.today()
    stats = {"worksites_seen": 0, "postings_inserted": 0,
             "postings_updated": 0, "postings_skipped_duplicate": 0,
             "updated_worksites": [], "updated_posting_titles": []}
    for rec in records:
        wid = upsert_worksite(client, rec)
        stats["worksites_seen"] += 1
        result = upsert_posting(client, wid, rec, today)
        stats["postings_" + result] += 1
        if result == "inserted":
            name = str(rec.get("worksite_name") or "").strip()
            if name and name not in stats["updated_worksites"]:
                stats["updated_worksites"].append(name)
            title = str(rec.get("title") or "").strip()
            if title and title not in stats["updated_posting_titles"]:
                stats["updated_posting_titles"].append(title)
    return stats


def load_reviewed(client, records: list[dict], today: datetime.date | None = None,
                  *, resolver=None) -> dict:
    """Load records only after deterministic or human-approved resolution."""
    if resolver is None:
        from worksite_resolution import resolve_worksite_record
        resolver = resolve_worksite_record

    today = today or datetime.date.today()
    stats = {
        "worksites_seen": 0,
        "postings_inserted": 0,
        "postings_updated": 0,
        "postings_skipped_duplicate": 0,
        "pending": 0,
        "skipped": 0,
        "pending_queue_ids": [],
        "updated_worksites": [],
        "updated_posting_titles": [],
    }
    for rec in records:
        resolution = resolver(client, rec)
        if resolution["status"] == "pending":
            stats["pending"] += 1
            queue_id = resolution.get("queue_id")
            if queue_id is not None and queue_id not in stats["pending_queue_ids"]:
                stats["pending_queue_ids"].append(queue_id)
            continue
        if resolution["status"] == "skipped":
            stats["skipped"] += 1
            continue

        stats["worksites_seen"] += 1
        result = upsert_posting(client, resolution["worksite_id"], rec, today)
        stats["postings_" + result] += 1
        if result == "inserted":
            name = str(
                resolution.get("resolved_name") or rec.get("worksite_name") or ""
            ).strip()
            if name and name not in stats["updated_worksites"]:
                stats["updated_worksites"].append(name)
            title = str(rec.get("title") or "").strip()
            if title and title not in stats["updated_posting_titles"]:
                stats["updated_posting_titles"].append(title)
    return stats


def crawl_notice_week(today: datetime.date) -> tuple[datetime.date, datetime.date]:
    """Return the Monday-Sunday range containing ``today``."""
    week_start = today - datetime.timedelta(days=today.weekday())
    return week_start, week_start + datetime.timedelta(days=6)


def _notice_week_label(today: datetime.date, *, include_year: bool) -> str:
    week_start, week_end = crawl_notice_week(today)
    prefix = f"{week_start.year}년 " if include_year else ""
    if week_start.month == week_end.month:
        return f"{prefix}{week_start.month}월 {week_start.day}일~{week_end.day}일"
    return (
        f"{prefix}{week_start.month}월 {week_start.day}일~"
        f"{week_end.month}월 {week_end.day}일"
    )


def crawl_notice_title(today: datetime.date) -> str:
    return f"{CRAWL_NOTICE_TITLE} ({_notice_week_label(today, include_year=False)})"


def _notice_labels(content: str | None) -> list[str]:
    """Read labels from the weekly bullet format and the previous one-line format."""
    lines = [line.strip() for line in str(content or "").splitlines() if line.strip()]
    labels = [line[2:].strip() for line in lines if line.startswith("• ")]
    if labels:
        return list(dict.fromkeys(label for label in labels if label))
    if len(lines) >= 3:
        return list(dict.fromkeys(
            label.strip() for label in lines[1].split(" · ") if label.strip()
        ))
    return []


def _notice_total(content: str | None) -> int:
    match = _CRAWL_NOTICE_TOTAL_RE.search(str(content or ""))
    return int(match.group(1)) if match else 0


def crawl_notice_content(today: datetime.date, postings_inserted: int,
                         worksite_names: list[str] | None = None,
                         *, posting_titles: list[str] | None = None) -> str:
    """월요일~일요일 단위로 누적할 고려대 전용 공지 본문."""
    labels = []
    for raw_title in posting_titles or []:
        title = str(raw_title or "").strip()
        label = title if title.startswith("[") else f"[{title}]"
        if label and label not in labels:
            labels.append(label)
    if not labels:
        for raw_name in worksite_names or []:
            name = str(raw_name or "").strip()
            label = f"[{name}]" if name else ""
            if label and label not in labels:
                labels.append(label)
    lines = [_notice_week_label(today, include_year=True)]
    lines.extend(f"• {label}" for label in labels)
    lines.append(f"총 {postings_inserted}건 업데이트 완료되었습니다.")
    return "\n".join(lines)


def upsert_crawl_notice(client, postings_inserted: int,
                        today: datetime.date | None = None,
                        worksite_names: list[str] | None = None,
                        *, posting_titles: list[str] | None = None) -> str | None:
    """신규 공고가 있을 때만 고려대 전용 자동 공지 한 건을 생성·갱신한다."""
    if postings_inserted <= 0:
        return None

    today = today or datetime.date.today()
    title = crawl_notice_title(today)
    rows = (client.table("notices").select("id, content")
            .eq("university_id", UNIVERSITY_ID)
            .eq("title", title)
            .limit(1).execute()).data or []
    if rows:
        previous_labels = _notice_labels(rows[0].get("content"))
        new_labels = _notice_labels(crawl_notice_content(
            today, postings_inserted, worksite_names, posting_titles=posting_titles,
        ))
        labels = list(dict.fromkeys([*previous_labels, *new_labels]))
        content = crawl_notice_content(
            today,
            _notice_total(rows[0].get("content")) + postings_inserted,
            posting_titles=labels,
        )
        # notices.updated_at has a DEFAULT but no automatic update trigger.
        client.table("notices").update({
            "content": content,
            "updated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        }).eq("id", rows[0]["id"]).execute()
        return "updated"

    content = crawl_notice_content(
        today, postings_inserted, worksite_names, posting_titles=posting_titles,
    )
    client.table("notices").insert({
        "title": title,
        "content": content,
        "university_id": UNIVERSITY_ID,
    }).execute()
    return "inserted"


def load_sources(client, source_records: dict[str, list[dict]],
                 today: datetime.date | None = None) -> dict:
    """두 소스를 한 실행에서 적재하고, 소스별·합계 통계를 함께 반환한다."""
    today = today or datetime.date.today()
    by_source = {source: load(client, records, today) for source, records in source_records.items()}
    totals = {key: sum(stats[key] for stats in by_source.values())
              for key in ("worksites_seen", "postings_inserted", "postings_updated",
                          "postings_skipped_duplicate")}
    totals["updated_worksites"] = list(dict.fromkeys(
        name
        for stats in by_source.values()
        for name in stats["updated_worksites"]
    ))
    totals["updated_posting_titles"] = list(dict.fromkeys(
        title
        for stats in by_source.values()
        for title in stats["updated_posting_titles"]
    ))
    return {"by_source": by_source, "totals": totals}


def load_sources_reviewed(client, source_records: dict[str, list[dict]],
                          today: datetime.date | None = None) -> dict:
    """Load multiple sources while enforcing the worksite review gate."""
    today = today or datetime.date.today()
    by_source = {
        source: load_reviewed(client, records, today)
        for source, records in source_records.items()
    }
    totals = {
        key: sum(stats[key] for stats in by_source.values())
        for key in (
            "worksites_seen",
            "postings_inserted",
            "postings_updated",
            "postings_skipped_duplicate",
            "pending",
            "skipped",
        )
    }
    totals["pending_queue_ids"] = [
        queue_id
        for stats in by_source.values()
        for queue_id in stats["pending_queue_ids"]
    ]
    totals["updated_worksites"] = list(dict.fromkeys(
        name
        for stats in by_source.values()
        for name in stats["updated_worksites"]
    ))
    return {"by_source": by_source, "totals": totals}


def _make_client():
    from crawler_config import get_supabase_credentials
    from supabase import create_client
    url, key = get_supabase_credentials()
    return create_client(url, key)


def main() -> int:
    import argparse
    ap = argparse.ArgumentParser(description="SSC/KUPID 공고 UPSERT 로더")
    ap.add_argument("--source", choices=["ssc", "kupid", "both"], default="ssc")
    ap.add_argument("--backfill", action="store_true", help="적재 전 normalized_name 백필")
    ap.add_argument("--allow-kupid", action="store_true",
                    help="기존 KUPID postings에 source/external_id 백필을 끝낸 뒤에만 사용")
    ap.add_argument("--publish-notice", action="store_true",
                    help="--source both 성공 후 신규 insert 합계가 있으면 고려대 전용 공지를 생성·갱신")
    args = ap.parse_args()
    if args.source in ("kupid", "both") and not args.allow_kupid:
        print("[중단] --source kupid는 기존 KUPID 공고(source=NULL)와 매칭되지 않아 중복 삽입합니다.\n"
              "  먼저 기존 postings에 source='kupid'·external_id 백필을 하세요(별도 작업).\n"
              "  백필 완료 후 --allow-kupid로 재실행하세요.")
        return 2
    if args.publish_notice and args.source != "both":
        ap.error("--publish-notice는 --source both와 함께만 사용할 수 있습니다")
    client = _make_client()
    if args.backfill:
        print(f"[backfill] normalized_name 채움: {backfill_normalized_names(client)}건")
    if args.source == "ssc":
        records = json.loads(SSC_PARSED.read_text(encoding="utf-8"))
        stats = load_reviewed(client, records)
    elif args.source == "kupid":
        records = kupid_rows_to_canonical(DATA_DIR / "kupid_parsed_result.xlsx")
        stats = load_reviewed(client, records)
    else:
        stats = load_sources_reviewed(client, {
            "ssc": json.loads(SSC_PARSED.read_text(encoding="utf-8")),
            "kupid": kupid_rows_to_canonical(DATA_DIR / "kupid_parsed_result.xlsx"),
        })
        if args.publish_notice:
            stats["notice"] = upsert_crawl_notice(
                client,
                stats["totals"]["postings_inserted"],
                posting_titles=stats["totals"]["updated_posting_titles"],
            )
    print(f"[done] source={args.source} {stats}")
    pending = stats["totals"]["pending"] if args.source == "both" else stats["pending"]
    if pending:
        print(
            "[review] 신규/충돌 근무지는 적재하지 않았습니다: "
            "python crawling_scripts/review_worksite_queue.py"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
