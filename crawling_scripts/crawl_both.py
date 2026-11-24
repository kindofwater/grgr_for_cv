"""조합: 한 브라우저에서 통합 아이디로 SSC·KUPID 각각 로그인 → 둘 다 크롤. 매일 무인 파이프라인 1단계.

SSC(job)와 KUPID(portal)는 같은 통합 아이디를 쓰지만 SSO 엔드포인트가 다르다
— job=sso.korea.ac.kr/saml, portal=sso.korea.ac.kr/svc/tk(exsignon). 세션이 공유되지 않아
'한 번 로그인=양쪽 silent'는 안 되고, 한 브라우저에서 각각 폼을 채운다:
  1) SSC : _auto_login (oauth→saml 폼: #user_id/#ipt_password)
  2) KUPID: portal BO06 방문 → doLogin() → svc/tk 폼(#ipt_id/#ipt_password) 채워 제출
그 뒤 전체 쿠키를 양쪽 크롤러에 주입해 각자의 수집 흐름(cookies→fetch→crawl)을 실행한다.

실행: python crawling_scripts/crawl_both.py --incremental --auto
      python crawling_scripts/crawl_both.py --auto --limit 3   # 스모크
"""
from __future__ import annotations
import argparse
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "crawling_scripts"))
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

from playwright.sync_api import sync_playwright
import ssc_job_crawler as ssc
import kupid_portal_crawler as kupid
from crawler_pipeline.network import SourceBlockedError
from crawler_pipeline.state import CrawlerState

PIPELINE_STATE = ROOT / "data" / "crawler_state.json"


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
        # 2) KUPID(portal) 방문 — 로그인 페이지면 portal 자체 SSO 폼(svc/tk)을 채워 로그인(SSC와 별도 세션)
        page.goto(kupid.BASE_URL + kupid.BOARD_PATH, wait_until="domcontentloaded")
        try:
            page.wait_for_load_state("networkidle", timeout=8000)
        except Exception:
            pass
        if page.locator("div.board_item").count() == 0:      # 게시판 아님 = 로그인 페이지
            from crawler_config import get_portal_credentials
            portal_id, portal_password = get_portal_credentials()
            try:
                page.evaluate("doLogin && doLogin()")                 # portal 로그인 트리거(전역함수 직접 호출: off-viewport 스킵링크 클릭 회피)
                page.wait_for_selector("#ipt_id", state="visible", timeout=15000)   # svc/tk/Auth.eps 통합 SSO 폼(보이는 아이디칸=#ipt_id, #user_id는 hidden)
                page.fill("#ipt_id", portal_id)
                page.fill("#ipt_password", portal_password)
                page.click("button.btn_primary", timeout=5000)        # doLogin(): #ipt_id→#user_id 복사·비번 RSA 암호화·제출
                page.wait_for_load_state("networkidle", timeout=20000)
            except Exception as e:
                print(f"[KUPID 로그인 경고] {e}")
            time.sleep(3)
            page.goto(kupid.BASE_URL + kupid.BOARD_PATH, wait_until="domcontentloaded")   # 로그인 후 게시판 재방문
            try:
                page.wait_for_selector("div.board_item", timeout=15000)
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

    state = CrawlerState.load(PIPELINE_STATE)
    ssc_blocked = state.is_blocked("ssc")
    kupid_blocked = state.is_blocked("kupid")
    if ssc_blocked and kupid_blocked:
        print("[skip] SSC와 KUPID 모두 오늘 재시도 금지 상태")
        return 0

    cookies = login_both_cookies(auto=args.auto)
    fail = 0

    # SSC
    try:
        if ssc_blocked:
            print("[SSC skip] 오늘 재시도 금지 상태")
            raise StopIteration
        s = ssc.make_session_fetch(ssc.session_from_cookies(cookies))
        rows: list[dict] = []
        ssc.crawl(s, oldest_date=ssc.DEFAULT_OLDEST_DATE, limit=args.limit,
                  skip_ids=ssc.load_skip_ids(ssc.OUTPUT_FILE) if args.incremental else set(),
                  results=rows, on_progress=lambda n, r: print(f"  [SSC {n}] {r['title'][:34]}"))
        ssc.save_rows(ssc.OUTPUT_FILE, rows)
        print(f"[SSC] {len(rows)}건 수집")
    except StopIteration:
        pass
    except SourceBlockedError as e:
        blocked_until = state.block_until_tomorrow("ssc")
        state.save()
        print(f"[SSC 차단 감지] {e}; {blocked_until}부터 재시도")
        fail |= 1
    except Exception as e:
        print(f"[SSC 실패] {e}")
        fail |= 1

    # KUPID
    try:
        if kupid_blocked:
            print("[KUPID skip] 오늘 재시도 금지 상태")
            raise StopIteration
        k = kupid.make_session_fetch(kupid.session_from_cookies(cookies))
        rows = []
        list_metadata_updates = []
        kupid.crawl_workstudy_notices(
            k, oldest_date=kupid.DEFAULT_OLDEST_DATE, limit=args.limit,
            cutoff_date=kupid.load_cutoff(kupid.STATE_FILE) if args.incremental else None,
            assistant_cutoff_date=(kupid.load_cutoff(kupid.ASSISTANT_STATE_FILE)
                                   if args.incremental else None),
            skip_keys=kupid.load_existing_keys(kupid.OUTPUT_FILE) if args.incremental else set(),
            results=rows,
            on_skip=lambda row: (
                list_metadata_updates.append(row)
                if kupid.title_has_strong_closed_marker(row.get("title"))
                else None
            ),
            on_progress=lambda n, r: print(f"  [KUPID {n}] {r['title'][:34]}"))
        kupid.apply_list_metadata_updates(
            kupid.OUTPUT_FILE, list_metadata_updates
        )
        merged = kupid.save_rows(kupid.OUTPUT_FILE, rows)
        # --limit은 스모크 테스트이므로 조교 3개년 백필 완료 상태를 기록하지 않는다.
        if args.limit is None:
            kupid.save_cutoff(kupid.ASSISTANT_STATE_FILE, merged)
        print(f"[KUPID] {len(rows)}건 수집")
    except StopIteration:
        pass
    except SourceBlockedError as e:
        blocked_until = state.block_until_tomorrow("kupid")
        state.save()
        print(f"[KUPID 차단 감지] {e}; {blocked_until}부터 재시도")
        fail |= 2
    except Exception as e:
        print(f"[KUPID 실패] {e}")
        fail |= 2

    return fail


if __name__ == "__main__":
    sys.exit(main())
