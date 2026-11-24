# 교내근로(KUPID) 공고 적재 파이프라인 — 설계

- 날짜: 2026-07-17 · 담당: 배경록
- 상태: 설계 확정(브레인스토밍 합의), 구현 전
- 배경: 교내근로는 비정기·비일관이라 공고가 없는 시기가 길다. KUPID 포털 크롤러(2026-07-17 완성)가 모은
  공고를 카탈로그(`worksites`/`postings`)에 적재해, 공고가 안 나는 시기에도 근무지 정보를 보여준다.

## 합의된 결정

| 결정 | 선택 | 근거 |
|---|---|---|
| 파싱 수단 | Haiku LLM(`parse_kupid.py`) + Excel 사람 검수 | 프롬프트 이미 성숙. 자격 오판 등은 검수로 잡는다 |
| 적재 수단 | Excel → 마이그레이션 SQL 생성 → `db reset` 검증 → `db push` | 팀 규칙(마이그레이션 단일 경로)·이력·리뷰 가능 |
| 기존 school 25행 | 통째 삭제 후 재적재 | 리뷰 0 확인(2026-07-16). 리뷰 생기면 FK `on delete restrict`가 마이그레이션을 실패시키는 게 가드 |
| 모집 상태 | `recruit_until date` + 날짜 계산(아래) | `is_active` 정적 값은 낡아간다(교외 6,647건이 실례) |
| 마감 판정 정책 | **학교근장=공고별 캐스케이드 추정 / 국가근장=학기 공통 기간 직접 입력(추측 금지)** | 국가근장은 KOSAF 일괄 모집이라 근무지별 추측이 성립 안 함 |
| 마감 추정 TTL(학교근장) | 등록일 + 30일 | 학기 초 공고 사이클 기준 |

## 1. 파이프라인

```
kupid_portal_crawler.py (--full / --incremental) → data/*.json
  → parse_kupid.py (Haiku 파싱 + recruit_until 캐스케이드) → kupid_parsed_result.xlsx
  → [사람 검수 — 오판 수정·수동 행 추가]
  → generate_school_migration.py (Excel → migrations/*.sql 생성)
  → 로컬 supabase db reset 검증 → db push
```

- **Excel이 정본**: 검수에서 고친 값이 최종. SQL 생성기는 Excel만 읽는다(출처 무관).
- **수동 입력 경로 = Excel 행 추가**: SSC(고려대 학생지원시스템) 등 KUPID 밖 공고 중 안 겹치는
  것은 Excel에 수동으로 행을 넣으면 같은 파이프라인을 탄다. SSC 크롤러는 MVP 배포 이후 별건.
- 검수 체크리스트: ①자격 4종(학부/대학원/재학/휴학) 오판 ②마감일 추출 누락·오독 ③부서명 이상치
  (worksite 키가 되므로) ④교외 판정(`is_offcampus`)과 지역.

## 2. 모집 상태 — recruit_until (타입별 정책이 다름)

`postings`에 컬럼 2개 추가(별도 스키마 마이그레이션):

- `recruit_until date` — 이 날짜까지 접수 가능(추정 포함). NULL = 판정 불가(레거시 포함).
- `recruit_until_estimated boolean` — true면 추정값.

**⚠️ 학교근장과 국가근장은 채우는 방식이 다르다:**

**학교근장(KUPID, 이 파이프라인)** — 공고가 비정기·제각각이라 공고별 캐스케이드로 추정.
파이프라인(Python)이 우선순위로 확정:

1. 공고의 **명시 마감일**(서류접수 마감·모집기간 끝) → 그 날짜, estimated=false
2. 없으면 **근무시작일 전날** → estimated=true ("선발 시까지"여도 근무 시작 후엔 모집 종료가 확실)
3. 둘 다 없으면 **등록일 + 30일** → estimated=true

**국가근장** — KOSAF 학기 일괄 모집이라 **추측 금지**. 모집기간이 확정되면 학기마다
한 줄짜리 일괄 UPDATE 마이그레이션으로 직접 입력(estimated=false):

```sql
update postings p set recruit_until = '<학기 마감일>', recruit_until_estimated = false
  from worksites w where w.id = p.worksite_id and w.type = 'national' and p.deleted_at is null;
```

이 UPDATE가 교외 6,647건의 낡은 is_active 문제를 겸사겸사 해결한다(별도 소급 백필 불필요).

프론트 "모집중" 판정은 lib 순수 함수(테스트 포함):

```
effectiveActive(posting) =
  posting.recruit_until != null ? (recruit_until >= today) : posting.is_active
```

- ⚠️ **레거시 호환 필수**: 기존 교외 6,647건은 recruit_until=NULL → 기존 `is_active` 폴백.
  폴백 없으면 교외 전체가 '모집완료'로 뒤집힌다.
- 새 적재 데이터에도 `is_active` 스냅숏(적재 시점 recruit_until ≥ 오늘)을 같이 넣는다 —
  검색 RPC(`search_worksite_cards`)의 active 롤업·정렬이 아직 `is_active`를 보기 때문.
- 라벨 세부 문구(확정 "~M/D 접수" vs 추정 표시 방식)는 구현 때 확정. 교외 6,647건에
  recruit_until 소급은 별건(같은 원리로 가능).

## 3. 데이터 매핑

**worksites** (부서 단위 dedup — 크롤 내 같은 부서 공고 여러 건이면 worksite 1개에 postings 여러 건):

| 컬럼 | 값 |
|---|---|
| university_id | 1 (고려대 서울) |
| type | 'school' |
| location_type | 파서 `is_offcampus`: false→'on_campus', true→'off_campus' |
| organization_name | `'고려대학교(본교)'` — 국가근로 시드는 `'고려대학교(본교) 학부'`지만 그건 명부가 학부 한정이라서. 교내근로는 대학원생 공고도 있어 '학부'를 뺀다 |
| workplace_name | 파서 `department`(부서명) |
| region | 교내=NULL(계약: 교내 region=NULL 정상). 교외 판정 시 근무장소에서 추출, 실패 시 검수 단계 수기 |
| address | 파서 `work_location` |

**postings**:

| 컬럼 | 값 |
|---|---|
| eligible_degree | undergrad_ok/grad_ok: 둘 다=2, 학부만=0, 대학원만=1, 둘 다 false=3(미정) |
| eligible_status | enrolled_ok/leave_ok: 동일 방식 |
| work_duration_type | is_short_term: true='short', false='long', null='unknown' |
| hourly_wage | `WAGE_BY_YEAR[등록연도]` (2026=10,400) |
| recruit_until / _estimated | §2 캐스케이드 |
| is_active | 적재 시점 스냅숏(recruit_until ≥ 생성일) |
| is_placeholder | false (실공고) |
| raw_text | 공지 원문(`detail_text`) 보관 |
| source_url | KUPID 상세 링크(`detail_url`) — 로그인 필요 링크지만 출처 기록용 |
| job_description / work_period_text / work_time_text / recruitment_period_text / contact_* / preference_notes / extra_notes | 파서 대응 필드 그대로 |

## 4. 기존 school 데이터 처리

적재 마이그레이션 서두에서 `type='school'` worksites delete(postings는 cascade).
리뷰가 붙어 있으면 `reviews.worksite_id`의 `on delete restrict`로 마이그레이션이 실패한다 —
그때는 해당 근무지만 유지로 전환 판단(현재 리뷰 0이라 통과 예상). 조회수는 리셋을 감수(합의).

## 5. 구현 단위(계획 수립 시 상세화)

1. 스키마 마이그레이션: `postings.recruit_until`/`recruit_until_estimated` + `docs/db-schema.md` 갱신
2. `parse_kupid.py` 보강: recruit_until 캐스케이드(순수 함수 + pytest), Excel에 새 컬럼
3. `generate_school_migration.py` 신규: Excel → wipe+재적재 SQL 생성(멱등·헤더 규칙 준수)
4. 프론트: lib `effectiveActive`(+테스트), Home/Search 카드가 이를 사용, 셀렉트에 recruit_until 추가
5. 국가근장 학기 UPDATE 마이그레이션: 2026-2학기 모집기간 확정값 입수 시(§2) — 확정 전이면 뼈대만 문서화
6. 실데이터: 크롤 full 실행(로그인 필요—사용자) → 파싱 → 검수 → SQL 생성 → db reset → push

## 스코프 밖

- SSC 크롤러(MVP 배포 이후)
- 검색 RPC의 active 롤업을 recruit_until 기반으로 전환
- 서울대/타대학(현수 담당 — 선행: 검색 대학 스코프)

> (정정 2026-07-17) "교외 6,647건 recruit_until 소급"은 스코프 밖 항목이었으나,
> 국가근장 학기 일괄 UPDATE(§2)가 그 역할을 하므로 별도 백필이 불필요해졌다.
