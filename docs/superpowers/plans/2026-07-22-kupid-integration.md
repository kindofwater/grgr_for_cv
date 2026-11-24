# KUPID 통합 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** KUPID 공지를 SSC와 함께 한 번의 중앙 SSO 로그인으로 매일 무인 크롤·파싱·적재하고, 기존 KUPID 408건에 `source/external_id/게시일자`를 부여해 멱등 적재 가능하게 한다.

**Architecture:** 두 크롤러(`ssc_job_crawler`·`kupid_portal_crawler`)는 이미 `session_from_cookies(cookies) → make_session_fetch → crawl(fetch)` 동일 구조 + 동일 중앙 SSO. 새 `crawl_both.py`가 SSC 로그인부(`_auto_login`)를 재사용해 1회 로그인 후 job·portal 쿠키를 모두 확보, 양쪽 크롤러에 주입. 백필은 별도 스크립트가 "삭제 대상 고정 → 삭제 → xlsx 재적재 → before/after 검증"을 한 세트로 수행.

**Tech Stack:** Python 3.13, pytest, Playwright(msedge), requests, supabase-py(service_role), openpyxl.

## Global Constraints
- **KUPID 크롤러(`kupid_portal_crawler.py`) 코드는 수정하지 않는다** — 오케스트레이션만. SSC 크롤러도 기존 `_auto_login` 재사용(로그인 로직 변경 없음).
- **백필은 `postings`만 삭제**하고 `worksites`는 절대 삭제하지 않는다(normalized_name 매칭 재사용). 삭제 대상은 실행 전 `SELECT`로 **id 목록을 고정**하고 그 목록만 삭제한다.
- **KUPID 식별 조건(불변)**: `source IS NULL` + 근무지 `type='school'` + `is_placeholder=False`. 이 조건으로 잡힌 수가 xlsx 행 수(408)와 크게 다르면 백필을 **중단**한다.
- **리뷰 불변**: 백필 before/after로 리뷰 수·근무지 수를 세어 동일함을 검증한다. 다르면 실패(비0 종료).
- **멱등**: 적재는 `(source, external_id)`·`normalized_name` 키. 재실행해도 행 수 불변.
- **비밀정보**는 `creds.py`(gitignore)에서만 읽는다. `service_role`은 git·프론트 반입 금지.
- **커밋**은 하되 push 안 함. 브랜치는 `main`(이 작업 스트림 확정). DB 변경은 `supabase migration new` + `db push`.

## File Structure
- `crawling_scripts/upsert_worksites.py` — MODIFY: KUPID row→canonical 순수함수 추출 + `posted_at`(게시일자) 추가.
- `crawling_scripts/crawl_both.py` — CREATE: 조합 SSO 로그인 + SSC·KUPID 크롤.
- `crawling_scripts/backfill_kupid.py` — CREATE: 삭제대상 고정·삭제·xlsx 재적재·before/after 검증.
- `crawling_scripts/run_daily.bat` — CREATE: 조합크롤 → 파싱2 → 적재2.
- `web/supabase/migrations/<ts>_grant_service_role_reviews_select.sql` — CREATE: 백필 검증용 service_role SELECT on reviews.
- `crawling_scripts/test_upsert_worksites.py` — CREATE: KUPID canonical(posted_at·external_id) 테스트.
- `crawling_scripts/test_backfill_kupid.py` — CREATE: 후보 필터·가드 순수로직 테스트.
- `crawling_scripts/README.md` — MODIFY: 새 스크립트·매일 파이프라인 갱신.

---

### Task 1: KUPID row→canonical 순수함수 + 게시일자(posted_at) 보존

**Files:**
- Modify: `crawling_scripts/upsert_worksites.py` (`kupid_rows_to_canonical` 내부 매핑을 `_kupid_row_to_canonical(row)`로 추출, `posted_at` 추가)
- Test: `crawling_scripts/test_upsert_worksites.py`

**Interfaces:**
- Produces: `_kupid_row_to_canonical(row: dict) -> dict | None` (부서명 없으면 None). canonical에 `posted_at`(등록일 ISO) 포함.
- Consumes: 기존 `kupid_external_id`, `_xlsx_cell`, `_flag`, `eligible_pair`, `_duration`.

- [ ] **Step 1: 실패 테스트 작성**

`crawling_scripts/test_upsert_worksites.py`:
```python
import datetime
from upsert_worksites import _kupid_row_to_canonical, kupid_external_id


def _row(**over):
    r = {
        "제목": "[중앙도서관] 근로장학생 모집", "부서명": "중앙도서관",
        "등록일": datetime.date(2026, 5, 1), "모집마감일(계산)": datetime.date(2026, 5, 20),
        "시급": 10400, "모집인원": "2명", "마감추정": "X",
        "학부생가능": "O", "대학원생가능": "X", "재학생가능": "O", "휴학생가능": "O",
        "직무내용": "자료정리", "우대조건": "", "기타특이사항": "", "근무기간": "",
        "단기여부": "X", "지원마감일": "", "출처URL": "", "본문(원본)": "본문",
    }
    r.update(over)
    return r


def test_kupid_canonical_preserves_posted_at():
    c = _kupid_row_to_canonical(_row())
    assert c["posted_at"] == "2026-05-01"          # 등록일 → 게시일자
    assert c["source"] == "kupid"
    assert c["worksite_name"] == "중앙도서관"
    assert c["hourly_wage"] == 10400

def test_kupid_canonical_external_id_stable():
    a = _kupid_row_to_canonical(_row())
    b = _kupid_row_to_canonical(_row())
    assert a["external_id"] == b["external_id"]     # 같은 입력 = 같은 키
    assert a["external_id"] == kupid_external_id("[중앙도서관] 근로장학생 모집", "중앙도서관", "2026-05-01")

def test_kupid_canonical_blank_dept_returns_none():
    assert _kupid_row_to_canonical(_row(부서명="")) is None
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd crawling_scripts && python -m pytest test_upsert_worksites.py -q`
Expected: FAIL (`ImportError: cannot import name '_kupid_row_to_canonical'`)

- [ ] **Step 3: 최소 구현 — 매핑 추출 + posted_at**

`upsert_worksites.py`에서 기존 `kupid_rows_to_canonical` 루프 본문을 순수함수로 추출:
```python
def _kupid_row_to_canonical(row: dict) -> dict | None:
    """KUPID 파싱 row(dict) → 로더 canonical. 부서명 없으면 None."""
    dept = str(row.get("부서명") or "").strip()
    if not dept:
        return None
    ru = row.get("모집마감일(계산)")
    ru_iso = ru.isoformat()[:10] if hasattr(ru, "isoformat") else (str(ru)[:10] if ru else "")
    reg = row.get("등록일")
    reg_iso = reg.isoformat()[:10] if hasattr(reg, "isoformat") else str(reg or "")
    wage = row.get("시급")
    return {
        "source": "kupid",
        "external_id": kupid_external_id(str(row.get("제목") or ""), dept, reg_iso),
        "worksite_name": dept,
        "title": str(row.get("제목") or ""),
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
```
그리고 `kupid_rows_to_canonical`은 이 함수를 호출하도록 축약:
```python
def kupid_rows_to_canonical(xlsx_path) -> list[dict]:
    import openpyxl
    wb = openpyxl.load_workbook(xlsx_path, data_only=True)
    ws = wb["파싱결과"]
    headers = [c.value for c in ws[1]]
    out = []
    for r in ws.iter_rows(min_row=2, values_only=True):
        if not any(v not in (None, "") for v in r):
            continue
        canon = _kupid_row_to_canonical(dict(zip(headers, r)))
        if canon is not None:
            out.append(canon)
    return out
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd crawling_scripts && python -m pytest test_upsert_worksites.py -q`
Expected: PASS (3 passed)

- [ ] **Step 5: 커밋**
```bash
git add crawling_scripts/upsert_worksites.py crawling_scripts/test_upsert_worksites.py
git commit -m "feat(kupid): row→canonical 순수함수 추출 + 게시일자(posted_at) 보존"
```

---

### Task 2: 백필 검증용 service_role SELECT on reviews (마이그레이션)

**Files:**
- Create: `web/supabase/migrations/<ts>_grant_service_role_reviews_select.sql`
- Modify: `web/supabase/README.md` (마이그레이션 목록)

**Interfaces:** 없음(권한 grant). 백필 스크립트가 `service_role`로 `reviews` COUNT를 읽을 수 있게 함.

- [ ] **Step 1: 마이그레이션 파일 생성**

Run: `cd web && npx supabase migration new grant_service_role_reviews_select`
(생성된 파일이 최신 timestamp보다 앞서면 최신 뒤 timestamp로 파일명 조정 — SSC widen 때와 동일 이슈.)

- [ ] **Step 2: SQL 작성**

파일 내용:
```sql
-- 목적: 백필 before/after 검증에서 service_role이 reviews 개수를 읽을 수 있게 SELECT grant
-- 날짜: 2026-07-22 · 담당: 배경록
-- 비고: 읽기전용(SELECT만). 로더/백필은 reviews를 절대 쓰지 않음 — 검증 카운트 용도.

begin;
grant select on public.reviews to service_role;
commit;
```

- [ ] **Step 3: prod push**

Run: `cd web && npx supabase db push`
Expected: `Applying migration ..._grant_service_role_reviews_select.sql... Finished`
검증: `python -c "import sys;sys.path.insert(0,'crawling_scripts');import creds;from supabase import create_client;c=create_client(creds.SUPABASE_URL,creds.SUPABASE_SERVICE_ROLE_KEY);print(c.table('reviews').select('id',count='exact').execute().count)"` → 정수(에러 없음).

- [ ] **Step 4: README 갱신 + 커밋**

`web/supabase/README.md` 마이그레이션 목록에 한 줄 추가 후:
```bash
git add web/supabase/migrations/*_grant_service_role_reviews_select.sql web/supabase/README.md
git commit -m "feat(db): service_role reviews SELECT grant (백필 검증용, 읽기전용)"
```
> ⚠️ push 후 디스코드 공유(순서 꼬임 방지).

---

### Task 3: KUPID 백필 스크립트 (삭제대상 고정 → 삭제 → 재적재 → 검증)

**Files:**
- Create: `crawling_scripts/backfill_kupid.py`
- Test: `crawling_scripts/test_backfill_kupid.py`

**Interfaces:**
- Consumes: `upsert_worksites.kupid_rows_to_canonical`·`load`, `creds`.
- Produces: `filter_kupid_ids(posts, school_ids) -> list[int]` (순수), `main()` (`--apply` 없으면 dry-run).

- [ ] **Step 1: 순수 필터 실패 테스트 작성**

`crawling_scripts/test_backfill_kupid.py`:
```python
from backfill_kupid import filter_kupid_ids


def test_filter_only_school_nonplaceholder():
    posts = [
        {"id": 1, "worksite_id": 10, "is_placeholder": False},   # school, real → 포함
        {"id": 2, "worksite_id": 10, "is_placeholder": True},    # school, placeholder → 제외
        {"id": 3, "worksite_id": 99, "is_placeholder": False},   # national → 제외
    ]
    assert filter_kupid_ids(posts, {10}) == [1]

def test_filter_empty():
    assert filter_kupid_ids([], {10}) == []
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd crawling_scripts && python -m pytest test_backfill_kupid.py -q`
Expected: FAIL (`ImportError`)

- [ ] **Step 3: 백필 스크립트 구현**

`crawling_scripts/backfill_kupid.py`:
```python
"""KUPID 백필: source=NULL 기존 KUPID 공고를 고정·삭제하고 xlsx에서 source/external_id/게시일자를
부여해 재적재. before/after 검증. 기본 dry-run, --apply로 실제 실행.

실행: python crawling_scripts/backfill_kupid.py            # dry-run(삭제 안 함)
      python crawling_scripts/backfill_kupid.py --apply    # 실제 백필
"""
from __future__ import annotations
import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "crawling_scripts"))
import creds
from supabase import create_client
import upsert_worksites as U


def filter_kupid_ids(posts: list[dict], school_ids: set[int]) -> list[int]:
    """source=NULL posting 중 school 근무지·非placeholder만 = 기존 KUPID 공고."""
    return sorted(p["id"] for p in posts
                  if p["worksite_id"] in school_ids and not p["is_placeholder"])


def _fetch_all(client, table, cols, **eq):
    rows, start = [], 0
    while True:
        q = client.table(table).select(cols)
        for k, v in eq.items():
            q = q.is_(k, "null") if v is None else q.eq(k, v)
        r = q.range(start, start + 999).execute().data
        rows.extend(r)
        if len(r) < 1000:
            return rows
        start += 1000


def kupid_ids(client) -> list[int]:
    ws = _fetch_all(client, "worksites", "id, type", deleted_at=None)
    school = {w["id"] for w in ws if w["type"] == "school"}
    posts = _fetch_all(client, "postings", "id, worksite_id, is_placeholder", source=None)
    return filter_kupid_ids(posts, school)


def snapshot(client) -> dict:
    def cnt(tbl, **eq):
        q = client.table(tbl).select("id", count="exact")
        for k, v in eq.items():
            q = q.is_(k, "null") if v is None else q.eq(k, v)
        return q.execute().count
    return {
        "reviews": cnt("reviews"),
        "worksites": cnt("worksites", deleted_at=None),
        "source_kupid": cnt("postings", source="kupid"),
        "candidate": len(kupid_ids(client)),
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="KUPID 백필(고정·삭제·재적재·검증)")
    ap.add_argument("--apply", action="store_true", help="실제 삭제·재적재(없으면 dry-run)")
    args = ap.parse_args()
    c = create_client(creds.SUPABASE_URL, creds.SUPABASE_SERVICE_ROLE_KEY)

    ids = kupid_ids(c)                                   # 삭제 대상 고정
    records = U.kupid_rows_to_canonical(U.DATA_DIR / "kupid_parsed_result.xlsx")
    before = snapshot(c)
    print(f"[고정] 삭제 대상 KUPID 공고: {len(ids)}건 | xlsx 원본: {len(records)}건")
    print("[BEFORE]", before)

    if not args.apply:
        print("[dry-run] 삭제/적재 안 함. 값 확인 후 --apply로 실행.")
        return 0

    # 안전 가드: 삭제 대상이 xlsx 원본과 크게 다르면 중단
    if not (0 < len(ids) <= int(len(records) * 1.1) + 5):
        print(f"[중단] 삭제 대상 {len(ids)}이 예상(xlsx {len(records)}) 밖 — 안전상 중단.")
        return 2

    for i in range(0, len(ids), 100):                    # 고정된 id만 삭제
        c.table("postings").delete().in_("id", ids[i:i + 100]).execute()
    print(f"[삭제] {len(ids)}건 완료")

    stats = U.load(c, records)                            # xlsx 재적재(source/external_id/게시일자)
    print("[재적재]", stats)

    after = snapshot(c)
    print("[AFTER]", after)
    checks = {
        "리뷰 불변": after["reviews"] == before["reviews"],
        "근무지 불변": after["worksites"] == before["worksites"],
        "source=kupid == xlsx": after["source_kupid"] == len(records),
        "잔여 candidate 0": after["candidate"] == 0,
    }
    print("[검증]", checks)
    return 0 if all(checks.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: 순수 테스트 통과 확인**

Run: `cd crawling_scripts && python -m pytest test_backfill_kupid.py -q`
Expected: PASS (2 passed)

- [ ] **Step 5: dry-run 실측(prod 읽기전용)**

Run: `PYTHONIOENCODING=utf-8 python crawling_scripts/backfill_kupid.py`
Expected: `[고정] 삭제 대상 KUPID 공고: 408건 | xlsx 원본: 408건` + BEFORE 스냅샷. **삭제/적재 안 함.**
> ⚠️ 삭제 대상이 408이 아니면 여기서 멈추고 조건을 재점검(사고 방지).

- [ ] **Step 6: 커밋(백필 --apply는 별도 인간 게이트)**
```bash
git add crawling_scripts/backfill_kupid.py crawling_scripts/test_backfill_kupid.py
git commit -m "feat(kupid): 백필 스크립트 — 삭제대상 고정·삭제·xlsx 재적재·before/after 검증"
```
> 🔴 `--apply` 실제 실행은 dry-run 값(408=408) 확인 후, 사람이 직접. 검증 4개 전부 통과해야 성공.

---

### Task 4: 조합 SSO 로그인 크롤러 (crawl_both.py)

**Files:**
- Create: `crawling_scripts/crawl_both.py`

**Interfaces:**
- Consumes: `ssc_job_crawler`(`_auto_login`·`build_list_url`·`session_from_cookies`·`make_session_fetch`·`crawl`·`save_rows`·`load_skip_ids`·`PROFILE_DIR`·`OUTPUT_FILE`·`DEFAULT_OLDEST_DATE`), `kupid_portal_crawler`(`BASE_URL`·`BOARD_PATH`·`session_from_cookies`·`make_session_fetch`·`crawl`·`save_rows`·`load_cutoff`·`load_existing_keys`·`OUTPUT_FILE`·`STATE_FILE`·`DEFAULT_OLDEST_DATE`).

- [ ] **Step 1: 구현**

`crawling_scripts/crawl_both.py`:
```python
"""조합: 중앙 SSO 1회 로그인 → SSC·KUPID 둘 다 크롤. 매일 무인 파이프라인 1단계.

실행: python crawling_scripts/crawl_both.py --incremental --auto
      python crawling_scripts/crawl_both.py --auto --limit 3   # 스모크
"""
from __future__ import annotations
import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "crawling_scripts"))
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

from playwright.sync_api import sync_playwright
import ssc_job_crawler as ssc
import kupid_portal_crawler as kupid


def login_both_cookies(auto: bool) -> list[dict]:
    """중앙 SSO 로그인 → job·portal 세션을 한 브라우저에서 확보 → 전체 쿠키 반환."""
    with sync_playwright() as p:
        try:
            ctx = p.chromium.launch_persistent_context(
                str(ssc.PROFILE_DIR), channel="msedge", headless=auto,
                viewport={"width": 1400, "height": 900})
        except Exception:
            ctx = p.chromium.launch_persistent_context(
                str(ssc.PROFILE_DIR), headless=auto,
                viewport={"width": 1400, "height": 900})
        page = ctx.pages[0] if ctx.pages else ctx.new_page()
        # 1) SSC(job) 로그인 — 중앙 SSO
        page.goto(ssc.build_list_url(1), wait_until="domcontentloaded")
        if auto:
            ssc._auto_login(page)
        else:
            print("[로그인] 브라우저에서 로그인 후 목록 보이면 Enter.")
            input("> ")
        # 2) KUPID(portal) 방문 — SSO 세션 공유로 silent SAML
        page.goto(kupid.BASE_URL + kupid.BOARD_PATH, wait_until="domcontentloaded")
        try:
            page.wait_for_load_state("networkidle", timeout=8000)
        except Exception:
            pass
        cookies = ctx.cookies()
        ctx.close()
    return cookies


def main() -> int:
    ap = argparse.ArgumentParser(description="SSC+KUPID 조합 크롤(1회 SSO 로그인)")
    ap.add_argument("--auto", action="store_true", help="무인 자동로그인")
    ap.add_argument("--incremental", action="store_true", help="증분")
    ap.add_argument("--limit", type=int, default=None, help="각 소스 N건(스모크)")
    args = ap.parse_args()

    cookies = login_both_cookies(auto=args.auto)
    fail = 0

    # SSC
    try:
        s = ssc.make_session_fetch(ssc.session_from_cookies(cookies))
        rows: list[dict] = []
        ssc.crawl(s, oldest_date=ssc.DEFAULT_OLDEST_DATE, limit=args.limit,
                  skip_ids=ssc.load_skip_ids(ssc.OUTPUT_FILE) if args.incremental else set(),
                  results=rows, on_progress=lambda n, r: print(f"  [SSC {n}] {r['title'][:34]}"))
        ssc.save_rows(ssc.OUTPUT_FILE, rows)
        print(f"[SSC] {len(rows)}건 수집")
    except Exception as e:
        print(f"[SSC 실패] {e}")
        fail |= 1

    # KUPID
    try:
        k = kupid.make_session_fetch(kupid.session_from_cookies(cookies))
        rows = []
        kupid.crawl(k, oldest_date=kupid.DEFAULT_OLDEST_DATE, limit=args.limit,
                    cutoff_date=kupid.load_cutoff(kupid.STATE_FILE) if args.incremental else None,
                    skip_keys=kupid.load_existing_keys(kupid.OUTPUT_FILE) if args.incremental else set(),
                    results=rows, on_progress=lambda n, r: print(f"  [KUPID {n}] {r['title'][:34]}"))
        kupid.save_rows(kupid.OUTPUT_FILE, rows)
        print(f"[KUPID] {len(rows)}건 수집")
    except Exception as e:
        print(f"[KUPID 실패] {e}")
        fail |= 2

    return fail


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 2: 스모크 테스트 — KUPID headless 로그인 실측 (핵심 미검증 지점)**

Run: `PYTHONIOENCODING=utf-8 python crawling_scripts/crawl_both.py --auto --limit 3`
Expected: `[SSC N건 수집]` **그리고** `[KUPID N건 수집]` 둘 다.
- ✅ 둘 다 수집 → 조합 로그인·KUPID headless 통과 확인.
- ❌ KUPID만 `세션 만료(로그인 필요)` → headless에서 portal SAML 미완. 대응: (a) portal 방문 후 로그인 대기/재시도 추가, 또는 (b) `--auto`를 headful로 두는 옵션. 이 경우 실패 로그를 사람에게 보고 후 조정.
> ⚠️ 실패 로그인 반복 최소화 — 한 번 돌려보고 결과에 따라 판단.

- [ ] **Step 3: 커밋**
```bash
git add crawling_scripts/crawl_both.py
git commit -m "feat(kupid): 조합 SSO 로그인 크롤러 crawl_both.py — 1회 로그인으로 SSC+KUPID"
```

---

### Task 5: 매일 파이프라인 (run_daily.bat) + 스케줄러 문서

**Files:**
- Create: `crawling_scripts/run_daily.bat`
- Modify: `crawling_scripts/README.md`

- [ ] **Step 1: run_daily.bat 작성**

`crawling_scripts/run_daily.bat`:
```bat
@echo off
REM 매일 무인: 조합크롤(SSC+KUPID)->파싱2->적재2. 단계 실패 시 중단.
cd /d %~dp0\..
set PYTHONIOENCODING=utf-8
set SSC_PARSE_MODEL=claude-sonnet-5

python crawling_scripts\crawl_both.py --incremental --auto
if errorlevel 1 goto :fail

python crawling_scripts\parse_ssc.py
if errorlevel 1 goto :fail
python crawling_scripts\parse_kupid.py
if errorlevel 1 goto :fail

python crawling_scripts\upsert_worksites.py --source ssc
if errorlevel 1 goto :fail
python crawling_scripts\upsert_worksites.py --source kupid --allow-kupid
if errorlevel 1 goto :fail

echo [OK] daily pipeline done %date% %time%
exit /b 0
:fail
echo [FAIL] daily pipeline aborted %date% %time%
exit /b 1
```
> `run_ssc_pipeline.bat`은 SSC 전용으로 남겨두거나 삭제 — 이 태스크에서는 `run_daily.bat` 추가만(사람이 스케줄러를 새 .bat로 교체).

- [ ] **Step 2: parse_kupid 실행 인터페이스 확인**

`parse_kupid.py`가 인자 없이 `data/kupid_workstudy_notices.json` → `data/kupid_parsed_result.xlsx`를 만드는지 확인(아니면 .bat의 해당 줄을 실제 사용법으로 교체). Run: `python crawling_scripts/parse_kupid.py --help` 또는 소스 확인.

- [ ] **Step 3: README 갱신**

`crawling_scripts/README.md`에 `crawl_both.py`·`backfill_kupid.py`·`run_daily.bat`를 스크립트 목록·"매일 무인" 섹션에 추가.

- [ ] **Step 4: 커밋**
```bash
git add crawling_scripts/run_daily.bat crawling_scripts/README.md
git commit -m "feat(kupid): 매일 조합 파이프라인 run_daily.bat + README"
```

---

## 인간 게이트 (구현 후, 코드와 별개)
1. 🔴 **백필 `--apply` 실행** — dry-run 값(삭제408=xlsx408) 확인 후 사람이 `python crawling_scripts/backfill_kupid.py --apply`. 검증 4개 전부 통과 확인.
2. **정식 ANTHROPIC_API_KEY**(크레딧) `creds.py` 반영 — throwaway 대체.
3. **Windows 작업 스케줄러**에 `run_daily.bat` 등록(놓친 작업 다음 부팅 실행 옵션 켜기).
4. Task 2 push 후 **디스코드 공유**.

## Verification (성공 기준)
- `pytest crawling_scripts/ -q` 전부 통과(Task 1·3 신규 테스트 포함).
- 백필 후: `source='kupid'` 408 · `source NULL·school·非placeholder` 0 · **리뷰 수 before=after** · 근무지 수 불변.
- `backfill_kupid.py`(재실행) 또는 `--source kupid` 재실행 시 postings 행 수 불변(멱등).
- `crawl_both.py --auto --limit 3` → SSC·KUPID 둘 다 수집.
- `run_daily.bat` 수동 1회 완주.
