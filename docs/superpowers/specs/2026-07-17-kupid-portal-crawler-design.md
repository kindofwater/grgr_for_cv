# 새 KUPID 포털 교내 근로장학 공지 크롤러 재작성 — 설계

- 날짜: 2026-07-17 · 담당: 배경록
- 상태: 설계 승인 대기
- 관련: `crawling_scripts/parse_kupid.py`, `crawling_scripts/import_to_supabase.py`, [[project-national-oncampus-worksite-seed]]

## 1. 배경 / 목표

고려대 학내 포털(KUPID)이 **차세대 포털**로 교체되면서 기존 크롤러
(`kupid_notice_crawler.py`, Playwright 클릭 순회 방식)가 동작하지 않는다.
새 포털 구조에 맞춰 **교내 근로장학 공지 수집 앞단(크롤러)만** 다시 짠다.

수집 대상: **일반공지(BO06) 게시판의 "근로장학" 공고** → 본문·부서·작성일·첨부.

### 이번 구현 범위 (사용자 확정 2026-07-17)
- ✅ **크롤러(①)만 구현** — 검색·순회·상세수집 → `data/kupid_workstudy_notices.json` 산출까지.
- ⏸ **파싱(②)·Supabase 적재(③)는 이번 사이클에서 제외**(나중에). 적재는 RLS 인증 이슈도 별도 해결 필요(9장).
- 산출 JSON은 기존 `parse_kupid.py` 입력 스키마를 그대로 맞춰, 나중에 파싱·적재를 이어붙일 때 크롤러를 손대지 않도록 한다.
- 검색어 = `근로장학` 단일(sc=all). 첫 실행 전량 + 이후 증분.

수집 범위 확정:
- **일반공지(BO06)만** 수집. 장학금공지(BO10)는 국가근로 안내 위주라 제외
  (국가근로 근무지는 KOSAF 명부 경로로 채운다 — [[project-national-oncampus-worksite-seed]]).

## 2. 확인된 새 포털 구조 (라이브 정찰로 검증됨, 2026-07-16)

로그인된 브라우저로 직접 확인한 사실이다. 추측 아님.

### 2.1 인증
- SSO(`sso.korea.ac.kr`) 로그인 → `portal.korea.ac.kr` 세션 쿠키(`JSESSIONID`).
- 세션 유효 **약 60분**(화면 우상단 연장 타이머).
- **검증 완료**: 브라우저 쿠키를 `requests.Session`에 주입 → 검색 URL GET →
  status 200, SSO 리다이렉트 없이 로그인된 목록 HTML(근로장학 공고 20행) 수신.
  즉 세션이 JS/User-Agent에 묶여 있지 않아 requests 재사용이 가능하다.

### 2.2 검색 (순수 GET)
```
GET https://portal.korea.ac.kr/p/BO06?encQS=<BO06_고정토큰>&px=&sc=all&sw=<키워드>&cuid=&cuname=&cudpname=
```
- `encQS` = BO06 검색 진입점 고정 토큰: `hMHVHi3u3QvCp8G06ziROMeGCw7SfX2Yy034BqtxecY%3D`
- `sc=all` = 제목+본문 전체 검색, `sw` = 검색어(URL 인코딩)
- "근로장학" 검색 → **2,296건**, 서버 렌더 HTML로 목록을 내려줌.
- 옛 포털의 일반공지/지난공지 구분이 사라지고 **과거 공고까지 한 게시판에 통합**.

### 2.3 목록 행 파싱
각 행:
```html
<div role="row" data-name="post_list" class="board_item ..." data-url="/p/BO06?encQS=<글별토큰>">
  <div class="col_title"><div class="txt_title"><a><span title="[학사팀] 근로장학생 모집">...</span></a></div></div>
  <div class="col_file_cnt">…</div>           <!-- 첨부 있으면 button 존재 -->
  <div class="col_cre_user_dept_name"><div title="학사팀">학사팀</div></div>
  <div class="col_cre_dt">2026.06.01</div>
  <div class="col_visit_cnt">663</div>
</div>
```
- `data-url` = **상세 URL**(글마다 고유 encQS). 별도 view() 함수 호출 불필요.
- **20건/페이지** (listSize 드롭다운은 10~60이나 평문 파라미터가 무시되어 기본 20 고정).

### 2.4 ⚠️ 페이지네이션 — 설계상 핵심 제약
- 페이지 링크(`.page_skip a`)가 전부 **암호화된 encQS**.
- 평문 페이지 파라미터(`cp`/`page`/`pageIndex`/`nowPage`/`pageNo`/`currPage`)는
  **전부 무시**됨(실측: 모두 1페이지 반환). **페이지 번호 랜덤 점프 불가.**
- 따라서 **각 페이지 HTML에 박혀오는 다음 페이지 링크를 순차적으로 따라가야** 한다.
- `.page_skip`은 10페이지 블록 단위 표시 → 10페이지 초과분은 블록 이동(다음 블록) 링크로 넘어간다.
- 2,296건 = 약 115페이지.

### 2.5 상세 파싱
- 컨테이너 `.view_board` 안에 제목·작성자·작성일(YYYY-MM-DD HH:MM:SS)·승인자·조회수·
  게시형태·**본문 전체**·`파일 첨부`·이전글/다음글이 모두 렌더됨.
- 첨부 다운로드 링크: `/ctt/bb/bulletin?encQS=<토큰>&fs=1` (파일명·크기 텍스트 포함).
- 본문 구조가 기존 `parse_kupid.py`의 Haiku 필드(모집인원/근무장소/시급/이메일/기타사항 등)와
  **그대로 호환**된다.

### 2.6 인코딩
- 응답 본문은 UTF-8(정찰 시 `r.text`에서 "근로장학" 정규식 매칭 성공). 크롤러는
  `r.encoding` 명시 고정 + 파일 출력 시 `encoding="utf-8"`로 저장한다.

## 3. 채택 아키텍처 — 하이브리드 (사용자 승인: 방식 C)

**Playwright로 로그인+쿠키 캡처만, requests로 빠른 순차 크롤.**

```
[Playwright: 수동 SSO 로그인] → 쿠키 캡처
        │
        ▼
[requests.Session + 쿠키] ──GET──► BO06 검색(키워드)
        │                              │
        │                     목록 HTML 파싱(행 추출)
        │                              │
        │              다음 페이지 암호화 링크 따라가기(순차) ──반복──▶ 목록 소진
        │                              │
        │                     각 행 detail_url ──GET──► 상세 HTML → 본문·첨부 추출
        ▼
[data/kupid_workstudy_notices.json]  ← 기존 parse_kupid.py 입력 스키마와 동일
```

- A(Playwright 전체)의 로그인 편의 + B(requests 단독)의 속도를 결합.
- 첫 실행만 전량(~2,296건, 약 15~20분), 이후 **증분 모드**로 신규만.

## 4. 모듈 구성 (단일 신규 파일 `crawling_scripts/kupid_portal_crawler.py`)

| 함수 | 역할 | 입력 → 출력 |
|------|------|------------|
| `capture_session()` | Playwright로 Edge 실행(기존 `.kupid_playwright_profile` 재사용) → 수동 로그인 대기 → `context.cookies()` → 쿠키 주입된 `requests.Session` 반환 | 없음 → Session |
| `iter_list_rows(session, keyword)` | 검색 GET → 목록 파싱 → 다음 페이지 암호화 링크 추적하며 **행을 yield** | Session, 키워드 → 행 제너레이터 |
| `parse_list_page(html)` | `.board_item` 행에서 `{title, department, registered_date, views, has_file, detail_url}` 추출 | HTML → 행 리스트 |
| `find_next_page_url(html)` | `.page_skip`에서 현재 다음 페이지(및 블록 이동) 링크 추출, 없으면 None | HTML → URL 또는 None |
| `fetch_detail(session, url)` | 상세 GET → `.view_board`에서 `detail_text` + `attachments`(label/url) 추출 | Session, URL → dict |
| `main()` | 오케스트레이션: 증분 컷오프, 딜레이, 세션 만료 감지, JSON 저장 | CLI |

- **역방향/외부 import 없음**: `crawling_scripts/` 안에서 완결. 웹 코드와 무관.
- 기존 `kupid_notice_crawler.py`(구 포털용)는 **레거시로 남겨두고**, 신규 검증 완료 후 삭제.
  실행 배치 `run_kupid_*.bat`는 새 파일을 가리키도록 갱신.

## 5. 출력 스키마 (기존 파서 호환)

`data/kupid_workstudy_notices.json` — **기존 `parse_kupid.py`가 읽는 파일명·필드 유지**하여
파싱·적재 단계를 손대지 않는다. 공고당:

```json
{
  "board": "일반공지",
  "title": "[학사팀] 근로장학생 모집",
  "department": "학사팀",
  "registered_date": "2026-06-01",
  "due_date": "",
  "views": "663",
  "detail_url": "https://portal.korea.ac.kr/p/BO06?encQS=...",
  "detail_text": "제목 ...\n(본문 전체)\n첨부파일 ...",
  "attachments_json": "[{\"label\": \"근로장학지원_학번_성명.docx\", \"url\": \"/ctt/bb/bulletin?encQS=...&fs=1\"}]",
  "matched_keyword": "근로장학"
}
```

- `registered_date`: 목록 `YYYY.MM.DD` → `YYYY-MM-DD` 정규화. `get_year()` 등 파서 로직과 호환.
- `due_date`: 새 포털 목록에 게시기한 컬럼 없음 → 빈 문자열. 마감 판정은 파서의
  `is_closed()`가 **제목 `[마감]` 태그**로 처리(기존 로직 그대로).
- `detail_text`: 파서 `extract_body()`가 `제목 ` 줄 이후 ~ `첨부파일` 이전을 본문으로 자름 →
  상세 텍스트 앞에 `제목 <title>` 한 줄을 붙이고 첨부 섹션 앞에 `첨부파일` 마커를 넣어
  기존 파서 계약을 만족시킨다.

## 6. 증분 모드 & 중복 제거

- **안정 키** = `(title, department, registered_date)` 튜플.
  - 상세 encQS 토큰은 세션마다 바뀔 수 있어 크로스런 키로 부적합 → 위 튜플 사용
    (구 크롤러 `stable_key` 폴백과 동일 사상).
- **증분 컷오프**: `data/kupid_last_crawl.json`에 지난 실행의 최신 `registered_date` 저장.
  - `--full`(기본 첫 실행): 전량 수집.
  - `--incremental`(정기 실행): 목록을 최신→과거 순으로 훑다가 **컷오프 날짜 이전 행이 나오면
    상세 요청을 멈추고 종료**(목록은 날짜 내림차순이라 조기 종료 가능).
- 같은 실행 내 중복은 안정 키로 스킵.

## 7. 에러 처리 / 견고성

- **세션 만료(60분)**: 크롤 도중 응답이 `sso.korea.ac.kr`로 리다이렉트되거나 로그인 폼이
  감지되면 → "재로그인 필요" 안내 후 `capture_session()` 재호출 → **마지막 위치부터 재개**.
  (증분 모드에서는 사실상 발생 안 함.)
- **요청 딜레이**: 요청 간 0.3~0.5초(서버 예의, `kosaf_crawler.DELAY` 관례).
- **상세 실패**: 개별 상세 파싱 실패 시 `detail_text=""`, `error` 필드 기록하고 계속(구 크롤러와 동일).
- **페이지 루프 방지**: 직전 페이지와 행 시그니처가 동일하면 종료(무한 루프 차단).
- **민감정보**: 쿠키·자격증명은 파일·로그·git에 저장하지 않는다. 쿠키는 메모리 내 Session에만.
  `.gitignore`에 `*.har`, `creds_curl.txt` 추가 완료.

## 8. 테스트 계획

- `parse_list_page` / `find_next_page_url` / `fetch_detail`은 **저장한 실제 HTML 픽스처**로
  단위 테스트(로그인·네트워크 없이). 정찰 때 확보한 목록·상세 HTML을 픽스처로 사용.
- 통합 스모크: `--limit 3`으로 상세 3건만 수집 → JSON 스키마·한글 인코딩 확인.
- 회귀: 수집 JSON을 기존 `parse_kupid.py`(TEST_MODE)에 통과시켜 필드 추출이 깨지지 않는지 확인.

## 9. 재사용 범위 요약

| 단계 | 파일 | 조치 |
|------|------|------|
| ① 크롤 | `kupid_portal_crawler.py` | **신규 작성** (이 설계) |
| ② 파싱 | `parse_kupid.py` | **그대로** (입력 파일명·스키마 유지) |
| ③ 적재 | `import_to_supabase.py` | 스키마는 그대로지만 ⚠️ **인증 수단 교체 필요**(아래) |

⚠️ **적재 단계 선행 이슈(이 설계 범위 밖, 별건)**: `import_to_supabase.py`는
`VITE_SUPABASE_ANON_KEY`로 접속하는데, Auth+RLS 컷오버([[project-auth-rls-cutover]]) 이후
anon 키로는 INSERT가 RLS에 막혀 **현재 그대로는 실행 안 됨**. 이 크롤러 설계와 독립적으로
적재 수단(service_role 키 사용 등)을 결정해야 함 —
[[project-national-oncampus-worksite-seed]]에서도 지적된 미해결 항목.
이 크롤러의 산출물(JSON→파싱 Excel)까지는 영향 없음.

## 10. 미해결 / 기본값 (스펙 리뷰에서 조정 가능)

- **검색어**: 기본 `["근로장학"]` + `sc=all`. `sc=all`이 제목+본문을 훑어 "국가근로장학생",
  "교내근로장학" 등을 포함하므로 단일 키워드로 충분(2,296건). 필요 시 config 리스트로 확장.
- **크롤 주기**: 정기 자동화(cron 등)는 이 설계 범위 밖. 우선 수동 실행 → 추후 논의.
- **교외 여부/지역**: 상세 파싱은 파서가 담당. 크롤러는 원문 텍스트만 충실히 전달.
  ⚠️ 교내 근무지 `region`은 NULL이 정상(지역 필터 계약 — [[project-national-oncampus-worksite-seed]]).
