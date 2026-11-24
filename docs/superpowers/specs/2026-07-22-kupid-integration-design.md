# KUPID 통합 — 조합 SSO 로그인 + 백필 + 매일 무인 파이프라인 (설계)

- **작성**: 2026-07-22 · 담당: 배경록
- **상태**: 설계 승인(사용자). spec 확정 리뷰 대기 → 이후 writing-plans.
- **관련**: [[project-ssc-job-crawler]] · [[project-kupid-portal-crawler]] · SSC spec `2026-07-21-ssc-job-crawler-design.md`

## 목표 (한 문장)
KUPID(portal.korea.ac.kr 일반공지 "근로장학")를 SSC와 함께 **한 번의 중앙 SSO 로그인**으로 매일 무인 크롤·파싱·적재하고, 기존 KUPID 408건에 키를 부여해 **멱등 적재**가 가능하게 한다.

## 배경 / 현재 상태 (조사 완료)
- **SSC**: 크롤(`--auto` 중앙 SSO 자동로그인)·파싱(Sonnet)·적재 전부 무인 동작 검증됨. prod `source='ssc'` 72건 LIVE.
- **KUPID**: 2026-07-20 408건 적재 LIVE지만 스키마(`source`/`external_id`) 도입(07-21) *전*에 들어와 **`source=NULL`**. 지금 `--source kupid` 재적재 시 (source,external_id) 매칭이 안 돼 **408건 전부 중복 삽입** → 로더가 `--allow-kupid` 가드로 막고 있음.
- 두 크롤러는 **동일 구조**: `session_from_cookies(cookies) → make_session_fetch(session) → crawl(fetch, ...)`. 둘 다 `korea.ac.kr` 쿠키만 필터. 둘 다 **동일 중앙 SSO**(`sso.korea.ac.kr/saml/Auth.eps`, `#user_id`·`#ipt_password`·`doLogin()`).
- **KUPID 식별 (확정)**: 기존 KUPID 공고 = `source NULL` + 근무지 `type='school'` + `is_placeholder=False` = **408건 / 근무지 107개**. (국가근로는 `type='national'`이라 안 섞이고, 교내 시드 껍데기는 `is_placeholder=True`로 제외.) `data/kupid_parsed_result.xlsx`에 그 **408행 원본** 존재 → 재크롤 없이 무손실 재적재 가능.
- **리뷰 안전 (확정)**: `reviews.worksite_id`로 근무지에만 연결. `postings`를 FK로 참조하는 테이블 **0개**(grep 확인). `reviews→worksites`는 `ON DELETE RESTRICT`. 로더의 service_role은 reviews **SELECT 권한조차 없음**(42501). → 공고 삭제가 리뷰에 닿을 경로가 구조적으로 없음.

## 설계

### 파트 1 — 조합 SSO 로그인 오케스트레이터
새 스크립트 `crawling_scripts/crawl_both.py`가 **로그인 1회**로 두 사이트 세션을 확보한다:
1. Playwright 컨텍스트 1개에서 **중앙 SSO 자동로그인**(SSC의 `_auto_login` 재사용): SSC 목록(job) → `login.do` → `oauthFrm` → `sso.korea.ac.kr` → `#user_id`/`#ipt_password` 채우고 로그인 버튼(`doLogin`) → SAML로 job 복귀 = **SSC(job) 세션 확보**.
2. 같은 컨텍스트에서 **KUPID 방문**: `portal.korea.ac.kr/p/BO06` goto. 중앙 SSO 세션이 살아있어 **silent SAML** → **KUPID(portal) 세션 확보**. (검증: 목록/공고 링크가 보이는지 = 로그인 리다이렉트 아님.)
3. `cookies = ctx.cookies()`(전 도메인) → **SSC·KUPID 각각의 `session_from_cookies(cookies)`에 주입**(각자 도메인 쿠키를 씀).
4. SSC·KUPID **각각 crawl(fetch, incremental)** 실행 → `data/ssc_workstudy_raw.json` · `data/kupid_workstudy_notices.json` 갱신.
- **KUPID 크롤러 코드 무변경**(이미 `crawl(fetch)` 받음). SSC 크롤 함수도 재사용. 필요한 리팩터는 SSC의 로그인부를 "쿠키 반환" 형태로 소폭 분리하는 정도.
- **실패 처리**: 로그인 실패(비번/2FA/캡차)·KUPID 세션 미확보 시 명확한 RuntimeError로 중단(부분 저장). 한 소스가 실패해도 다른 소스는 이어가되 종료코드로 표시.
- **미검증 지점**: KUPID **headless** 로그인. SSC는 headless 검증됨(동일 SSO라 될 전망이나 파트1에서 실측 확인).

### 파트 2 — KUPID 백필 (삭제 후 재적재 · 무손실 · A안)
1. **게시일자 보존 추가**(개선): `upsert_worksites.kupid_rows_to_canonical`에 `posted_at`(xlsx 등록일 `reg_iso`)를 넣어, SSC처럼 **`created_at`에 게시일자 보존**(현재 KUPID는 미보존 → 적재일로 들어감). `_posting_fields`/`upsert_posting`의 posted_at→created_at 경로는 이미 있음(SSC용) — 재사용.
2. **백필 절차 (1회, 전용 스크립트 또는 문서화된 수동 단계)**:
   - **before 검증**: 리뷰 개수 기록(리뷰 읽을 수 있는 anon/authenticated 키로), KUPID 후보 408·근무지 107 재확인.
   - **삭제**: `source IS NULL` + 근무지 `type='school'` + `is_placeholder=False` 인 postings **408건 삭제**(service_role). worksites·reviews 무손상.
   - **재적재**: `python upsert_worksites.py --source kupid --allow-kupid` → xlsx 408행에 `source='kupid'`·`external_id`·게시일자 부여해 삽입. 근무지는 `normalized_name` 매칭으로 **재사용**(신규 생성 최소).
   - **after 검증**: `source='kupid'` 408건 · `source NULL·school·非placeholder` **0건** · **리뷰 개수 before=after** · 근무지 수 불변.
3. **멱등성**: 이후 `--source kupid` 재실행은 `(source,external_id)` 매칭으로 UPDATE(중복 0).

### 파트 3 — 조합 매일 파이프라인 + 스케줄러
- `crawling_scripts/run_daily.bat`(기존 `run_ssc_pipeline.bat` 확장/대체):
  1. `crawl_both.py`(조합 로그인 + SSC·KUPID 증분 크롤)
  2. `parse_ssc.py`(Sonnet) · `parse_kupid.py`
  3. `upsert_worksites.py --source ssc` · `upsert_worksites.py --source kupid --allow-kupid`
- 단계 실패 시 `errorlevel`로 중단. `SSC_PARSE_MODEL=claude-sonnet-5` 유지.
- **Windows 작업 스케줄러** 등록(놓친 작업 다음 부팅 실행 옵션 켬).
- **선행조건**: 정식 `ANTHROPIC_API_KEY`(크레딧 충전) — 현재 throwaway 대체 필요.

## YAGNI / 범위 밖 (이번에 안 함)
- KUPID **부서명=게시부서≠실근무처**(B안 통합·실근무처 필드) — 별도 과제.
- KUPID **본문-only 근로장학** 재현율 갭(제목필터 한계) — 별도 과제.
- SSC/KUPID **중복 공고 교차 dedup**(같은 공고가 양쪽에 뜰 때) — 현재는 소스별 독립 적재, 이번 범위 아님.

## 검증 (성공 기준)
1. `crawl_both.py` **1회 로그인**으로 SSC·KUPID 둘 다 크롤(headless, 각 N건 수집).
2. 백필 후: `source='kupid'` 408 · `school·NULL·非placeholder` 0 · **리뷰 개수 불변** · 근무지 수 불변.
3. `--source kupid` 재실행 **멱등**(postings 행 수 불변).
4. `run_daily.bat` 수동 1회 완주(3소스 크롤·파싱·적재 stats 정상).

## 위험 / 완화
- **로그인 자동화 = 학교 보안 리스크**(계정 잠금 소지): 하루 1회, 실패 시도 최소화(파트1에서 실측 후 확정). 캡차 등장 시 무인 실패로 중단(자동 우회 안 함).
- **삭제 백필**: 리뷰 삼중 보호(근무지 유지·postings FK 참조 0·RESTRICT·service_role 접근불가) + before/after 리뷰 개수 검증 게이트.
- **KUPID headless 로그인 미검증**: 파트1 첫 단계에서 `--limit 3` 스모크로 실측.
- **prod 삭제**: 되돌리기 대비 — 삭제 전 xlsx(408 원본)가 재적재 소스이므로 즉시 복구 가능.
