# crawling_scripts — 공고 크롤러/파서/적재

근로고래 공고 데이터 파이프라인. 웹앱(`web/`)과 무관한 독립 배치 스크립트.

## 스크립트
- `kupid_portal_crawler.py` — ★현행★ 새 차세대 KUPID 포털 일반공지(BO06)에서 "근로장학" 공고와, 본문에 근로장학 표현이 있는 "조교" 공고를 수집 → `data/kupid_workstudy_notices.json`. 조교 검색 결과 중 제목에 근로장학이 있는 공고는 기존 검색과 중복되므로 제외. 조교 검색은 별도 상태 파일을 사용해 첫 증분 실행 시 2023년부터 백필한다. 하이브리드(Playwright 로그인+requests 크롤). `--full`/`--incremental`/`--limit N`.
- `crawler_pipeline/` — ★현행★ SSC/KUPID 신규 공고 선별, 교차 출처 중복 판정, Sonnet 통합 파싱, DB 적재와 로컬 상태 관리. 기본 모델은 `claude-sonnet-5-5`이며 `CRAWLER_PARSE_MODEL`로 변경.
  공고 한 건은 3번 실패하면 영구 제외(`exhausted`)되는데, **과금·인증·한도·서버·연결 오류는 공고 탓이 아니라**
  실패 횟수를 깎지 않고 보류(`deferred`)한 뒤 그 실행을 멈춰 하루 한도를 아낀다(상태 JSON `unavailable`에 이유, 종료 코드 1).
  2026-10-07~08 크레딧 소진 때 공고 3건이 횟수를 잃고 한도 5건이 전부 실패 호출에 쓰인 뒤 넣은 규칙.
- `ssc_job_crawler.py` — ★신규★ SSC(job.korea.ac.kr) 아르바이트 근로장학 크롤러(목록+상세). `--full`/`--incremental`/`--limit N`/`--auto`(무인 로그인).
- `crawl_both.py` — ★통합★ 한 브라우저에서 통합 아이디로 SSC·KUPID 각각 로그인 → 둘 다 크롤(매일 파이프라인 1단계). `--incremental`/`--auto`/`--limit N`. job=saml·portal=svc/tk 별도 SSO라 세션이 안 섞여 각 폼을 채운다(KUPID 크롤러 코드는 무수정 재사용).
- `upsert_worksites.py` — ★신규 적재 정본★ SSC/KUPID를 service_role로 무삭제 멱등 UPSERT. 모든 CLI 적재는 근무지 승인 게이트를 통과하며, 미확인 이름은 신규 근무지를 자동 생성하지 않고 검토 큐로 보낸다. `--source ssc|kupid|both` `--backfill`. `--source both --publish-notice`는 신규 insert가 있을 때 고려대 전용 자동 공지 한 건을 생성·갱신.
- `everytime_crawler.py` — ★신규★ 에브리타임 고려대 근장게시판(`/496548`) 모집공고 수집.
  **Aside 브라우저가 로그인 세션을 들고 있어 비밀번호를 다루지 않는다** — 브라우저 조작은
  `aside repl`의 결정론적 JS라 토큰이 들지 않는다. 목록 1회 + 신규 건만 상세(5~10초 간격).
  게시판 절반 이상이 잡담이라 제목에 `모집`과 `근로장학|근로학생`이 **함께** 있어야 통과한다.
  본문은 메모리에만 두고 디스크에 남기지 않는다. `--dry-run`/`--limit N`.
  **파싱 실패·호출 상한 초과 글은 seen에 넣지 않는다** — 다음 실행이 다시 가져온다(2026-10-08 크레딧 소진으로
  파싱이 실패한 글이 seen에 들어가 영영 재수집되지 않았던 사고 뒤 고침).
- `everytime_postings.py` — 에타 공고 정제·판별·변환 순수 함수. `clean_body`(이중 이스케이프
  해제), `is_recruitment`(모집공고 판별), `to_manual_record`(Sonnet 출력 → 로더 스키마).
  매핑에 본문 필드가 없어 **구조적으로** 본문이 저장될 수 없다.
- `everytime_parse.py` — 수집분을 기존 Sonnet 파서에 넘겨 구조화. 이미 파일에 있는 글은
  호출 없이 건너뛰고, 실행당 호출 상한(기본 5)을 둔다. 한 건 실패가 나머지를 막지 않는다.
- `worksite_norm.py` — 근무지명 정규화 순수 함수(소스 간 매칭 키).
- `review_worksite_queue.py` — 처음 보는 근무지·본문 조직 충돌 검토. 기존 근무지 선택 또는
  신규 생성 결정을 저장하고 보류 공고를 즉시 재처리하며, 같은 표기는 이후 토큰 없이 자동 매칭.
- `run_daily.bat` — ★현행 실행 정본★: 증분 수집 → `crawler_pipeline/cli.py` → 감사 →
  에타 수집·적재 → Windows 알림. 에타는 보조 출처라 **실패해도 핵심 파이프라인을 되돌리지
  않지만**, 조용히 죽지 않도록 `[EVERYTIME-FAIL]` 표식을 로그에 남긴다.
- `run_daily_if_needed.ps1` — 인터넷 연결과 당일 성공 여부를 확인하고 중복 실행을 막는 가드.
  KUPID 연결을 **60초 간격으로 두 번** 확인해, 절전 복귀 이벤트로 떴다가 몇 초 뒤 다시 잠드는 경우(2026-10-04·05)는
  실패 대신 `skip`으로 넘기고 다음 트리거를 기다린다. 테스트는 Pester: `Invoke-Pester -Script crawling_scripts\run_daily_if_needed.Tests.ps1`.
- `install_crawler_task.ps1` — 로그인·잠금해제·절전복귀·네트워크 연결 트리거 등록. 검증 전에는 `-EnableAfterValidation`을 주지 않아 비활성으로 등록.
  작업은 스크립트 위치 기준 경로로 등록되므로 **저장소를 옮기면 새 위치에서 다시 실행**해야 한다.
  PowerShell을 `conhost.exe --headless`로 감싸 띄운다 — Windows 11 기본 터미널이 Windows Terminal이면
  작업 스케줄러의 콘솔이 OpenConsole로 위임되다 멈춰, 가드가 로그 한 줄 없이 30분 뒤 강제 종료된다.
- `configure_crawler_env.py` — 크롤러 설정을 Windows 사용자 환경변수로 저장. 기존 `creds.py` 이전(`--from-creds`) 또는 숨김 입력(`--interactive`)을 지원하며 값은 출력하거나 명령행 인자로 넘기지 않음.
- `kosaf_crawler.py` — 한국장학재단(KOSAF) 희망근로지 크롤러.
- `import_to_supabase.py` — 국가근로 데이터용 레거시 임포터. 학교근로 자동 파이프라인에서는 사용하지 않음.
- `fixtures/` — 크롤러 파서 단위테스트용 실제 서버 HTML.

## 테스트
```bash
cd crawling_scripts && python -m pytest            # 전체
cd crawling_scripts && python -m pytest test_kupid_portal_crawler.py -v
```
```powershell
Invoke-Pester -Script crawling_scripts\run_daily_if_needed.Tests.ps1   # 가드 스크립트(Pester 3, Windows 기본 탑재)
```

## 크롤러 실행
```bash
python crawling_scripts/kupid_portal_crawler.py --limit 3   # 스모크
python crawling_scripts/kupid_portal_crawler.py --full      # 기본: 2023-01-01까지 포함
python crawling_scripts/kupid_portal_crawler.py --full --until-year 2023
python crawling_scripts/kupid_portal_crawler.py --full --until-year 2023 --resume-existing
python crawling_scripts/kupid_portal_crawler.py --full --all-history  # 전체 과거
python crawling_scripts/kupid_portal_crawler.py --incremental
```
`kupid_portal_crawler.py`는 기본적으로 `--oldest-date 2023-01-01`을 적용합니다. 즉 2023년 공고는 포함하고, 2022년 이하 공고를 만나면 저장 후 종료합니다.
중간에 멈춘 뒤 이어 돌릴 때는 `--resume-existing`을 붙이면 기존 JSON에 저장된 공고는 건너뜁니다.

**증분(`--incremental`) 동작**: `data/kupid_last_crawl.json`에 마지막 최대 등록일을 저장해두고,
다음 실행 때 그 날짜를 컷오프로 삼아 목록(최신순)을 훑다 컷오프보다 과거 글을 만나면 즉시 중단합니다.
⚠️ 단, 컷오프는 **`INCREMENTAL_LOOKBACK_DAYS`(기본 7일)만큼 뒤로 물려서** 적용합니다 —
학교가 과거 날짜로 글을 올리거나 기존 글을 수정해 등록일이 바뀌면 컷오프보다 과거가 되어
영영 수집되지 않기 때문입니다. 며칠 겹쳐 훑어도 중복은 `stable_key`(제목·부서·등록일)가 걸러냅니다.
Edge 창이 열리면 KUPID 로그인 후 일반공지 목록이 보일 때 콘솔에서 Enter.

## 에브리타임 근장게시판 (Aside 경유)

학과가 KUPID·SSC에 안 올리고 에타에만 올리는 공고를 메우는 경로다.

```bash
python crawling_scripts/everytime_crawler.py --dry-run --limit 3   # 수집만, 토큰 0
python crawling_scripts/everytime_crawler.py                        # 수집 → 파싱 → JSON
python crawling_scripts/manual_postings.py data/manual_everytime_postings.json
```

### 인간 게이트(1회)
Aside 브라우저에서 **에브리타임에 직접 로그인**해 둔다. 세션이 유지되므로 그 뒤로는
자동이며, 비밀번호는 어디에도 저장하지 않는다. CLI 경로는 `ASIDE_CLI`로 덮어쓸 수 있다.

- `aside repl`은 **Aside 브라우저가 켜져 있어야** 응답한다(꺼져 있으면 `Aside isn't running`).
  자동 실행 때는 대개 꺼져 있어 9/28~10/2에 5일 중 4일 실패했다. 그래서 크롤러가 응답이
  없으면 `C:\Program Files\Aside\Application\Aside.exe`를 직접 띄우고 최대 60초 기다린다
  (경로는 `ASIDE_BROWSER`로 덮어쓰기). 실행 중 Aside 창이 뜨는 건 정상이며, 띄운 창은 닫지 않는다.
  ⚠️ `--no-startup-window`로 띄우면 Aside가 바로 종료돼 데몬이 안 뜬다 — 창 있는 일반 실행만 된다.

- 목록은 `api.everytime.kr/v2/find/board/article/list`(`mode=board`)를 한 번 부른다.
  이 응답의 본문은 **160자에서 잘리므로** 상세는 `find/board/comment/list`에
  `articleInfo=true`로 따로 가져온다(댓글은 쓰지 않고 버린다).
- 제목 필터는 `모집` **그리고** `근로장학|근로학생`을 함께 요구한다. 실제 표본 20건에서
  모집공고 8건을 모두 잡고 잡담 12건(교외 알바 "헬스장 근로 모집" 포함)을 모두 걸렀다.
  `근로`만 있는 교외 알바가 새어도 근무지 승인 게이트가 2차 방어선이다.
- 본 글 ID는 `data/everytime_seen.json`에 남겨 다시 열지 않는다. 적재 중복은
  `source_url`로 한 번 더 막는다.
- ⚠️ PowerShell에서 `aside repl`에 코드를 넘기면 **큰따옴표가 사라진다.** 크롤러는
  파이썬 `subprocess`로 인자를 넘기므로 영향이 없지만, 손으로 시험할 때는
  `String.fromCharCode(34)`를 쓸 것.

## 무인 파이프라인 (SSC + KUPID 통합)

고정 시각 대신 로그인·잠금해제·절전복귀·네트워크 연결 때 가드를 실행한다. 오늘 정상 완료했으면 조용히 종료한다.

내부 흐름:
```bash
python crawling_scripts/crawl_both.py --incremental --auto
python crawling_scripts/crawler_pipeline/cli.py
python crawling_scripts/audit_worksite_norm.py
```
- 최초 전환 때 `python crawling_scripts/crawler_pipeline/cli.py --initialize`로 현재 캐시를 과거 처리 완료 기준선으로 기록한다.
- 등록일/작성일이 기준일 이상(`>=`)이면서 처리하지 않은 공고만 Sonnet을 호출한다.
  `--dry-run`은 후보 수만 계산하며 API 키를 읽거나 Sonnet을 호출하지 않는다.
- 한 실행의 Sonnet 호출은 공고 그룹당 최대 2회다. 실패한 공고는 1일 뒤, 다시 실패하면
  3일 뒤에만 재시도하고 총 3회 실패하면 자동 재시도를 중단한다.
- Sonnet 파싱이 끝난 뒤 DB 적재만 실패한 경우 파싱 결과를 로컬 상태에 보관한다. 다음
  재시도에서는 저장된 결과를 사용하므로 같은 공고에 토큰을 다시 쓰지 않는다.
- 근무지 정규화는 Sonnet보다 먼저 실행한다. 정확한 정본명·사람이 승인한 별칭만 자동
  통과하며, 처음 보는 이름이나 본문 조직 충돌은 `worksite_resolution_queue`에 보류한다.
  보류 건은 Sonnet을 호출하지 않으므로 검토 전까지 토큰이 들지 않는다.
- `python crawling_scripts/review_worksite_queue.py`로 후보를 확인하고
  `--resolve ID --worksite-id 근무지ID`, `--new-name "이름"`, `--skip` 중 하나를 선택한다.
  검토 결정은 근무지 생성·별칭 학습·큐 완료를 하나의 DB 트랜잭션으로 저장하므로 일부만
  반영되지 않는다. 결정 저장 직후 보류 공고를 자동으로 재처리해 DB에 반영한다.
- 자동 실행 결과에 검토 대기 건이 있으면 Windows 알림에 `검토하기`와 `나중에` 버튼이
  표시된다. `검토하기`는 `review_worksite_queue.py --interactive`를 새 창으로 열어
  기존 후보 번호, 신규 등록, 제외, 나중에 검토 중 하나를 선택하게 한다. 검토 창은
  자동으로 닫히지 않으며, 별도 프로세스로 실행되어 크롤러 완료를 막지 않는다.
- 같은 근무지, 게시일 차이 3일 이내, 제목 80% 이상, 정규화 본문 3-gram cosine 90% 이상이며 핵심 값 충돌이 없을 때만 합친다. 애매하면 두 공고로 유지한다.
- 같은 날은 SSC, 날짜가 다르면 더 최근 출처가 대표다. 대표에 없는 명확한 값만 다른 출처에서 보충한다.
- 마감일은 `명시 마감일`이 있으면 그대로 쓰고, 없으면 **추정 후보 중 가장 빠른 날**을 쓴다:
  `등록일 포함 21일`(등록일이 없으면 최초 관측일 기준) 과 `근무시작일 전날`. 근무가 이미
  시작한 공고가 모집 중으로 보이면 안 되므로 21일 창이 근무시작일을 넘기지 못한다.
  `deadline_basis`에 어느 후보가 채택됐는지(`explicit`·`posted_window`·`first_seen_window`·`work_start`) 남는다.
- 상세 요청은 순차적으로 5~10초 간격을 두며, 403/429/차단 페이지를 감지하면 해당 출처는 다음 날까지 재요청하지 않는다.
- KUPID 상세 응답은 드물게 내용 없는 껍데기 HTML로 온다(같은 encQS URL이 다른 실행에서는
  정상 본문을 준 사례로 확인). 제목·본문·첨부가 **모두** 비면 깨진 응답으로 보고 저장하지
  않는다 → 다음 실행에서 자연히 재시도된다. 저장해버리면 빈 본문이 Sonnet까지 흘러가
  '의미 있는 필드 없음'으로 실패하고 3회 재시도 후 그 공고가 영구 누락된다.
  ⚠️ 본문만 비고 제목·첨부가 있으면 **첨부에만 내용이 있는 정상 공고**이므로 그대로 수집한다.
- 신규 insert가 있을 때만 고려대 전용 공지를 갱신한다. 공지 실패는 핵심 적재를 되돌리지 않고 부분 실패로 알린다.
- 실행 로그는 `crawling_scripts/logs/`에 7일간 보관한다.
- 학교근장 근무기간은 **6주(42일) 미만=단기, 6주 이상=장기**다. 선택지가 여러 개면 가장 긴 기간을
  기준으로 한다. 파서가 계산한 `work_period_days`를 로더가 다시 판정하므로 모델이 라벨을 잘못
  출력해도 일수 값이 있으면 42일 기준이 우선한다. 일수 계산과 명시적 단기·장기 표현이 모두
  불가능할 때만 `unknown`으로 적재한다. 국가근장은 별도 임포터 정책으로 항상 장기다.

### 인간 게이트(스케줄러 등록 전 1회)
1. 기존 `creds.py`가 있다면 `python crawling_scripts/configure_crawler_env.py --from-creds`로 다음 Windows 사용자 환경변수를 만든다: `ANTHROPIC_API_KEY`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `KOREA_PORTAL_ID`, `KOREA_PORTAL_PASSWORD`.
   새 키를 직접 넣거나 회전할 때는 `python crawling_scripts/configure_crawler_env.py --interactive`를 사용한다.
2. `SUPABASE_SERVICE_ROLE_KEY`는 백엔드 마스터키다. **`web/.env*`, `VITE_*`, Git, 프론트 번들에 절대 넣지 않는다.**
3. `creds.py` 폴백은 이전 기간에만 사용한다. 환경변수 검증 후 로컬 파일을 삭제한다.
4. `install_crawler_task.ps1 -ValidateOnly`로 작업 XML을 검사한다.
5. 수동 크롤·드라이런·DB 적재 검증 후에만 `install_crawler_task.ps1 -EnableAfterValidation`로 활성화한다.
