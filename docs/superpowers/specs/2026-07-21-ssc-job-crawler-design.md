# SSC(job.korea.ac.kr) 근로장학 공고 — 완전 무인 크롤·파싱·적재 파이프라인 설계

- 날짜: 2026-07-21
- 담당: 배경록
- 관련: [[2026-07-17-kupid-portal-crawler-design]], [[2026-07-17-kupid-school-postings-design]], `crawling_scripts/README.md`
- 상태: 설계 확정(v3.1) — 코덱스 리뷰 반영(스키마 보강·수정값 보호·정규화키 영속화·gitignore·placeholder 예외) + Fable 검토(KUPID external_id=stable_key 해시·soft-delete 유니크 조건·NULL 유니크 보강)

## 1. 배경 / 목적

고려대 취업지원(Student Success Center, **SSC**) 사이트 `https://job.korea.ac.kr`
의 **채용정보 › 아르바이트** 게시판을 `근로장학`으로 검색하면 교내/교외
근로장학 공고 목록이 나온다. 기존 KUPID 포털 일반공지 크롤러와 **보완 관계**
(같은 공고가 양쪽에 뜰 수도, SSC에만 있을 수도 있음).

**목표:**
1. **새 근무지 발굴** — 기존 명부(교내 57개 + KUPID)에 없는 근무지 확장.
2. **과거 공고 이력 확보** — 게시판 과거 공고까지 긁어 근무지별 공고 이력 축적.
3. **완전 무인 파이프라인** — 크롤 → 파싱 → 적재를 **매일 사람 없이** 실행.

**설계 방침(v2 전환):** 초기엔 "목록만·수동 적재"였으나, 사용자가 (a) PC 꺼져도
도는 상시 자동화, (b) 상세+Opus 파싱, (c) 눈검수 게이트 제거(오류는 사후 웹에서
수정)를 요구 → **완전 무인 아키텍처**로 확대. 이 결정이 적재 메커니즘과 KUPID
파이프라인까지 바꾼다(§5·§6).

**v3 보강(코덱스 리뷰):** 무삭제 UPSERT를 실제 스키마 위에서 안전하게 돌리려면
DB에 "열쇠 구멍" 두 개가 선행돼야 한다 — ① `postings` 공고 외부키
(`source`+`external_id`+unique), ② `worksites` 정규화 이름키(`normalized_name`
+unique). 여기에 ③ **사람 수정값 보호**(machine-owned 컬럼만 갱신), ④ SSC 산출물
gitignore, ⑤ **placeholder 공고 삭제 예외**를 스펙에 못박는다. ①②는 **스키마
변경이라 마이그레이션 선행**(CLAUDE.md §3) — 구현 순서 맨 앞(§8-0).

## 2. 소스 데이터 구조

로그인 후 목록 URL(예):
```
https://job.korea.ac.kr/ptfol/ncEm/job/rcrt/arb/index.do
  ?tabType=tot&currentPageNo=1&placeSh=0000&searchType=1
  &frDtSh=&toDtSh=&searchValue=근로장학
```
HTML 테이블(서버렌더, AJAX 아님). 페이지네이션 `currentPageNo`.

**목록 컬럼**

| 컬럼 | 예시 | 용도 |
|------|------|------|
| 번호 | 71 | **natural key**(게시 순번) |
| 구분 | 교내 / 교외 | 참고(교내는 DB region=NULL, §4) |
| 지역 | 서울 | 참고 |
| 회사명 | `학생처 Student Success Center`, `고려대학교 물리학과` | **근무지명(=부서명)** |
| 공고명 | `[Student Success Center] 근로장학생 모집` | 공고 제목 |
| 모집기간 | `2026.07.20 00:00~2026.07.24 12:00` | 시작일·마감일(recruit_until 직접 확보) |
| 조회수 | 41 | 참고 |

**상세 페이지**: 공고 본문(시급·모집인원·근무시간·직무내용·우대조건 등 자유
서술). Opus 파싱 대상(§3-②).

**KUPID 대비 차이:**
- 등록일 없음 → **모집기간(시작~끝)** 사용. `recruit_until`은 모집기간 끝에서
  직접(캐스케이드 `recruit_until.py` 불필요).
- dedup 키 = **번호(또는 상세 seq)**.
- 로그인·상세 모두 SSO 뒤. 비로그인 시 로그인 페이지 리다이렉트.
- 2차 인증(2FA) 없음 → id/pw 자동로그인 가능.

## 3. 파이프라인 개요 (매일 무인)

집 상시 머신에서 매일 스케줄러가 아래를 순서대로 실행한다. **중간 사람 개입 0.**

```
SSC 자동 로그인(학번/비번)
   │
① 크롤: 목록(--incremental) + 각 공고 상세 페이지
   │
② 파싱: Opus가 상세 본문 → 구조화 필드(시급·시간·자격 등)
   │
③ 적재: service_role로 prod DB에 UPSERT (삭제 없음)
   │
④ KUPID도 같은 upsert 로더 공유 (wipe+reload 은퇴)
   │
⑤ 눈검수 게이트 없음 — 오류는 사후 웹에서 수정
```

### ③-① 크롤러 `crawling_scripts/ssc_job_crawler.py`
`kupid_portal_crawler.py` 패턴 미러링.
- `capture_session()`: Playwright(Edge). **수동 모드** = 사람이 로그인 후 Enter.
  **자동 모드(headless)** = SSO 폼에 id/pw 자동입력·제출 → 쿠키를
  `requests.Session`에 주입.
- 목록 GET → `parse_list_page(html)`(BeautifulSoup), `currentPageNo` 순회.
- 각 행의 `detail_url` GET → 상세 HTML 확보(본문 텍스트 추출).
- 컷오프: `period_start < 2023-01-01` 만나면 중단. `--all-history`로 해제.
- dedup: `stable_key = board_no`. `--incremental`은 `data/ssc_last_crawl.json`의
  마지막 최대 번호 이후만.
- 출력(중간 산출): `data/ssc_workstudy_raw.json` — 목록 필드 + 상세 본문 원문.

**행 레코드(크롤 직후)**
```
board_no, category(구분), region_raw(지역), company_name(회사명),
title(공고명), period_start, recruit_until, period_text,
views, detail_url, detail_text(상세 본문 원문), source="ssc"
```

### ③-② 파서 `crawling_scripts/parse_ssc.py` (Opus)
- 입력: 크롤 raw JSON의 `detail_text`.
- **Opus** API로 본문 → 구조화 필드 추출(시급·모집인원·근무시간·직무내용·
  우대조건·기타·학부/대학원·재학/휴학 가능 등). 기존 `parse_kupid.py`(Haiku)와
  같은 목표, 모델만 Opus·프롬프트 SSC 맞춤.
- 목록에서 이미 확정된 필드(회사명·모집기간·구분)는 **파싱으로 덮어쓰지 않음**
  (구조화가 확실한 건 목록 우선).
- 출력: `data/ssc_parsed.json` — 적재기가 먹는 정규 스키마.
- ⚠️ 파싱 정확도는 프롬프트 반복으로 개선. 초기 오류는 감수(사후 웹 수정).

### ③-③ 적재기 `crawling_scripts/upsert_worksites.py` (신규, 공유 로더)
- **마이그레이션 아님.** 매일 도는 데이터 적재라 마이그레이션 파일 누적을
  피하려 **service_role 클라이언트(supabase-py)로 직접 UPSERT**.
- anon 키는 RLS로 INSERT 불가(레거시 `import_to_supabase.py` 사망 원인) →
  **service_role 필수**(§7 보안).
- 상세 동작은 §5.

## 4. 근무지 정규화·매칭

SSC 회사명과 KUPID 부서명 표기 차이(`고려대학교 물리학과` vs `물리학과`)로
그냥 합치면 근무지 중복 생성. 정규화(`normalize_worksite_name`):
- 접두어 제거: `고려대학교`, `고려대`, `(본교)`.
- `[대괄호]` 태그 제거.
- 공백 축약·대소문자·전각/반각 정리·양끝 트림.
- 정규화 키 동일 → 동일 근무지. 매칭 안 되는 SSC 회사명 = **새 근무지 발굴**.

**⚠️ 정규화 키는 DB에 영속화(코덱스 #3).** 파이썬 함수 결과를 조회에만 쓰면
코드 변경·동시 실행 시 중복 근무지가 생긴다(DB가 못 막음). → `worksites`에
**`normalized_name` 컬럼 + `unique(university_id, type, normalized_name)`** 를
추가(§4.5). 적재기는 이 컬럼으로 조회/insert하고, DB unique가 중복을 원천 차단.
정규화 규칙이 나중에 바뀌면 `normalized_name`을 **재계산하는 일회성 백필
마이그레이션**으로 갱신(코드-DB 동기화).

**교내/교외(계약 준수):** school 근무지는 전부 `location_type=on_campus`·
`region=NULL`(2026-07 결정). SSC `구분=교외`·`지역`은 raw JSON에만 참고로 남기고
DB region에 반영하지 않음.

**정규화 튜닝:** 규칙 실효성은 실물로 확인. 최초 크롤 후 **KUPID↔SSC 회사명
대조표**를 뽑아 규칙 조정(구현 순서 §8-2).

## 4.5. 스키마 보강 (마이그레이션 선행 — 코덱스 #1·#3)

무삭제 UPSERT를 안전히 돌리려면 현재 스키마에 없는 "열쇠 구멍"을 먼저 뚫는다.
**이 둘은 스키마 변경이라 마이그레이션 + 수동 `db push`** 로 선반영(§8-0).

**`postings` — 공고 외부키(코덱스 #1):** 현재 `source`·`board_no`·`external_id`
컬럼이 없어 재실행 시 "같은 공고"를 못 알아본다(URL 문자열 비교는 불안정).
추가:
```sql
alter table postings add column source      varchar(20);   -- 'ssc' | 'kupid'
alter table postings add column external_id  varchar(100);   -- SSC seq(없으면 board_no), KUPID=stable_key 해시(아래)
create unique index postings_source_extid_uq
  on postings (source, external_id)
  where source is not null and external_id is not null;  -- 부분 유니크(레거시 행 NULL 허용)
```
`source`가 NULL인 기존 행(수동/레거시)은 유니크에서 제외 → 기존 데이터 무영향.
NULL끼리는 unique가 안 막으므로(Postgres) **로더는 source·external_id를 항상
둘 다 채운다**(빠뜨리면 중복 방치).

**⚠️ KUPID external_id는 detail_url 해시 불가(Fable 검토):** KUPID 상세 URL은
`/p/BO06?encQS=<암호화 토큰>` — encQS가 세션/시점에 따라 달라질 수 있어 기존
크롤러도 dedup에 detail_url이 아닌 `stable_key(제목·부서·등록일)`를 쓴다.
→ **KUPID `external_id` = stable_key 튜플의 sha256 해시(앞 16자)**. SSC는 seq
(없으면 board_no) 그대로.

**`worksites` — 정규화 이름키(코덱스 #3):**
```sql
alter table worksites add column normalized_name varchar(200);
create unique index worksites_norm_uq
  on worksites (university_id, type, normalized_name)
  where normalized_name is not null and deleted_at is null;
```
`deleted_at is null` 조건(Fable 검토): 관리자가 근무지를 소프트 삭제하면 행이
남아 키를 점유 → 조건 없으면 다음날 크롤러의 동명 insert가 unique 위반으로
실패한다. 삭제 행은 키를 반납하고, **로더 조회도 같은 조건**(`deleted_at is
null`)으로 산 근무지만 본다.
기존 school 근무지는 백필(파이썬 정규화 규칙으로 1회 계산해 채움).

**`postings` — 수동수정 보호(코덱스 #2, §5 참고):**
```sql
alter table postings add column manual_override boolean not null default false;
```

## 5. 적재 모델 — 삭제 없는 멱등 UPSERT

기존 `generate_school_migration.py`는 `delete from worksites where type='school'`
후 재적재(wipe+reload). 매일 무인엔 부적합:
- 리뷰 붙은 근무지 delete가 on-delete-restrict로 실패 → 그날 적재 통째 실패.
- 삭제 순간 데이터 공백.
- KUPID가 wipe하면 SSC가 넣은 근무지 삭제(클로버링).

→ **무삭제 UPSERT**로 전환. `upsert_worksites.py`가 매일:

**worksites** — 키: `normalized_name`(§4.5)
- `(university_id, type, normalized_name)`로 조회 → 없으면 insert(type='school'·
  location_type='on_campus'·region=null·workplace_name·organization_name·
  normalized_name), 있으면 유지.
- **삭제 없음**(리뷰 보존·클로버링 회피의 핵심).

**postings** — 키: `unique(source, external_id)`(§4.5, 코덱스 #1)
- `external_id` = SSC 공고 고유 seq(없으면 board_no; KUPID는 detail_url 해시, §10).
- 조회 → **없으면 insert**(source·external_id·recruit_until·
  recruitment_period_text·source_url·파싱 필드), **있으면 갱신 규칙(아래) 적용**.
- ⚠️ `(worksite_id, source, board_no)`는 v2 아이디어였으나 **DB에 그 컬럼이
  없어 폐기** — `(source, external_id)`로 확정. worksite 매칭이 나중에 바뀌어도
  "같은 외부 공고" 사실은 유지된다.

**갱신 규칙 — 사람 수정값 보호(코덱스 #2):** "오류는 사후 웹에서 수정"
방침(§1)과 매일 update가 충돌한다 → 사람이 웹에서 고친 값을 다음날 Opus가
덮어쓰면 안 됨. 컬럼을 두 갈래로 나눈다:
- **machine-owned(크롤러가 매일 갱신 허용):** `recruit_until`·`is_active`·
  `recruitment_period_text`. `is_active` = `recruit_until >= today` 스냅숏 —
  매일 갱신돼 마감 지난 공고는 자동 비활성.
- **content(사람이 고칠 수 있음, 조건부 갱신):** `hourly_wage`·`job_description`·
  `preference_notes`·`work_time_text` 등 파싱 필드. **`manual_override=true`면
  크롤러가 이 컬럼들을 건너뜀**(사람 수정 우선). false면 파싱값으로 갱신.
- 웹 관리자 수정 UI는 저장 시 `manual_override=true`로 표식(구현은 별건, §10).

**placeholder 삭제 예외(코덱스 #5):** §5의 "삭제 없음"은 **worksites 삭제 금지**가
핵심이다. 진짜 공고가 처음 들어오는 근무지에 껍데기 posting(`is_placeholder=true`)이
있으면 **그 placeholder posting은 삭제 허용**(db-schema.md:439 규칙). 리뷰는
worksite에 붙으므로 placeholder posting 하나 지워도 무손상. 절차: 해당 worksite에
비-placeholder 공고를 처음 insert할 때 `delete from postings where
worksite_id=X and is_placeholder=true` 실행.

**KUPID 흡수(④):** KUPID 파싱 결과(Excel/JSON)도 같은 `upsert_worksites.py`로
적재하도록 어댑터 추가(`source='kupid'`, `external_id`=**stable_key(제목·부서·
등록일) sha256 해시** — detail_url은 encQS 암호화라 불안정, §4.5).
`generate_school_migration.py`의 wipe+reload는 **은퇴**(레거시 보존, README에
deprecated). 두 소스가 같은 테이블을 삭제 충돌 없이 공유.

**멱등성:** 같은 입력 재실행 시 결과 동일 — `unique(source, external_id)` +
`unique(normalized_name)`가 DB 레벨에서 보장. 구현 검증: 같은 입력 2회 실행 후
row 수 불변 확인(§8-3).

## 6. 상시 실행 환경 / 스케줄

- **실행 주체**: **집 상시 PC 또는 저전력 미니PC**. 가정 IP라 SSO 로그인 가장
  안정(데이터센터/해외 IP 차단 회피). 클라우드·GitHub Actions 대비 로그인 신뢰성 ↑.
- **스케줄**: 매일 1회. Windows면 **작업 스케줄러**(`run_ssc_pipeline.bat`),
  Linux 미니PC면 cron. 기존 `run_kupid_*.bat` 패턴.
- **파이프라인 배치**: 한 배치가 크롤→파싱→적재를 순차 실행. 단계 실패 시 즉시
  중단·로그 파일 기록(다음날 재시도, 데이터 손상 없음 — upsert 멱등).
- **모드**: 자동 실행은 크롤 `--incremental`(신규만).
- **경계 유지**: 데이터 적재만 자동. **스키마/RPC 변경은 여전히 마이그레이션 +
  수동 `db push`**(CLAUDE.md §3). 바뀌는 건 "데이터 적재 방법"뿐.

## 7. 보안 — service_role 키

- 크롤러의 worksites/postings INSERT는 RLS를 넘어야 하므로 **service_role 키**
  (RLS 우회) 사용. Supabase 대시보드 Settings→API에서 복사.
- 보관: 집 머신의 **gitignore 파일**(`crawling_scripts/creds.py`, 이미 .gitignore)
  또는 OS 환경변수. `SUPABASE_URL`·`SUPABASE_SERVICE_ROLE_KEY`·`SSC_ID`·`SSC_PW`.
- ⚠️ service_role은 전 DB 마스터키(모든 유저 데이터 read/write/delete). 규칙:
  1. **git 커밋 금지**(gitignore 파일에만). 실수 커밋 시 대시보드에서 키 재발급.
  2. **프론트엔드·브라우저 절대 반입 금지**(웹앱은 계속 anon 키만).
  3. 실행 머신 접근통제.
- 이 키를 제외한 나머지(파싱 정확도 등)는 "완벽 안전 불요" 방침 적용.

## 8. 구현 순서

0. **스키마 보강 마이그레이션(§4.5)** — `postings`(source·external_id·
   manual_override + 부분 유니크), `worksites`(normalized_name + 유니크),
   기존 school 근무지 `normalized_name` 백필. 로컬 검증 후 수동 `db push`.
   ⚠️ **상세 URL seq 확인(§10)이 이 단계 전에 선행** — external_id 정체가 결정돼야 함.
1. **크롤러 + 파서(목록/상세) + fixtures 테스트** — 실물 HTML로 파싱 검증.
   board_no·회사명·모집기간·상세본문·seq를 안정적으로 뽑는지.
2. **최초 `--full` 크롤 → KUPID↔SSC 회사명 대조표** — §4 정규화 규칙 튜닝.
   여기서 대충 넘기면 중복 근무지가 쌓임.
3. **`upsert_worksites.py`(service_role UPSERT)** — SSC + KUPID 어댑터 둘 다.
   **멱등성 필수 검증: 같은 입력 2회 실행 후 row 수 불변**(100→100, 200되면 키 오류).
4. **wipe+reload 은퇴** — 3 검증 후에만. `generate_school_migration.py`
   deprecated 표기(바로 죽이면 복구 경로 소멸), README 갱신.
5. **자동 로그인(headless) + 배치 + 스케줄러** — 마지막(SSO·세션·창없는실행 변수
   많음). 크롤/파싱/적재 확정 후 붙임. 무인 증분 end-to-end 확인.

## 9. 산출물 / 파일

| 파일 | 내용 |
|------|------|
| `web/supabase/migrations/<ts>_ssc_posting_keys.sql` | **스키마 보강(§4.5)**: postings source·external_id·manual_override + worksites normalized_name + 유니크 + 백필(신규 마이그레이션) |
| `crawling_scripts/ssc_job_crawler.py` | 크롤러(목록+상세, 신규) |
| `crawling_scripts/parse_ssc.py` | Opus 파서(신규) |
| `crawling_scripts/upsert_worksites.py` | service_role UPSERT 공유 로더(신규) |
| `crawling_scripts/test_ssc_job_crawler.py` | 파서 단위테스트(신규) |
| `crawling_scripts/fixtures/ssc_list_page1.html`, `ssc_detail_sample.html` | fixture(신규) |
| `crawling_scripts/run_ssc_pipeline.bat` | 스케줄러용 배치(신규) |
| `crawling_scripts/creds.py` | `SUPABASE_*`·`SSC_ID`·`SSC_PW` 추가(gitignore) |
| `crawling_scripts/generate_school_migration.py` | deprecated 표기 |
| `crawling_scripts/README.md` | SSC 파이프라인 + 적재 방식 변경 반영 |
| `.gitignore` | **`ssc_*.json` 추가**(코덱스 #4 — raw에 연락처·개인명 포함 가능, 커밋 금지) |
| `data/ssc_workstudy_raw.json`, `ssc_parsed.json`, `ssc_last_crawl.json` | 산출/상태(gitignore) |
| `docs/db-schema.md` | postings/worksites 신규 컬럼·유니크 반영(스키마 변경 동반 갱신) |

## 10. 미해결 / 확인 필요

- 상세 URL의 안정적 **seq 파라미터** 존재 여부 → **§8-0 스키마 전 선행 확인**.
  있으면 `external_id`=seq, 없으면 board_no(게시판 종류 포함해 충돌 방지).
- **supabase-py** 의존성 추가(적재기). `requirements.txt`/설치 스크립트 — 스케줄러
  머신에 빠지면 파이프라인 즉사. 로컬 파이썬 환경에 설치.
- Opus 파싱 **프롬프트 초안** — JSON 스키마·unknown 처리·목록 필드 덮어쓰기 금지·
  날짜/시급 파싱 규칙을 프롬프트에 명시. 구현 시 작성·반복 튜닝.
- **웹 관리자 수정 UI의 `manual_override` 세팅**(코덱스 #2) — **결정(2026-07-21):
  UI는 나중에.** 컬럼만 지금 추가(기본 false, 마이그레이션 재작업 방지). UI 생기기
  전까진 content 컬럼도 파싱이 갱신함(수정값 보호 미작동) — 감수하기로 함.
- KUPID 어댑터: 기존 파싱 산출(Excel)을 `upsert_worksites.py` 입력으로 변환.
  `external_id`=stable_key(제목·부서·등록일) sha256 해시로 **확정**(§4.5 — detail_url은
  encQS 암호화라 불안정).
- SSC fixture(`ssc_detail_sample.html`) 커밋 전 **담당자 연락처·이름 등 개인정보
  마스킹**(fixtures는 git에 올라감).
