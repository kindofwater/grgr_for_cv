# lib/ — 순수 함수 유틸 (library)

## (a) 역할
앱 어디서나 꺼내 쓰는 **순수 함수 창고**(library). 특정 화면/DB에 묶이지 않은
범용 계산·포맷·변환 로직. 입력 → 출력만 있고 부작용(side effect)이 없다.
그래서 **제일 밑바닥 계층**이며 단위테스트가 쉽다.

## (b) 무엇이 들어가나
- 점수 계산, 임금 포맷, 학기 정렬 같은 **순수 함수**.
- 같은 입력이면 항상 같은 출력. 외부 상태·시간·랜덤·네트워크에 의존하지 않음.
- 각 모듈 옆에 `*.test.js` 단위테스트를 둔다 (`npm run test`로 실행).

## (c) 무엇을 참조(import)하나
- **아무것도 안 한다.** 의존성 0이 핵심.
- ❌ React/DOM, ❌ `../supabase`/네트워크, ❌ components/pages/data.
- (이 규칙을 지켜야 DB·브라우저 없이 테스트가 가능)

## (d) 현재 파일
| 파일 | 역할 |
|------|------|
| `scores.js` | 점수 요약(`computeScoreSummary`), 임금 포맷(`formatWage`), 라벨 변환 등 |
| `scores.test.js` | `scores.js` 단위테스트 |
| `semesters.js` | 학기 순서(`SEMESTER_ORDER`), 리뷰 폼 올해부터 5년 전까지 옵션(`reviewFormYearOptions`, 오래된 수정 리뷰 원래 연도 예외), 연도·국가근로 유형별 가능 학기(`reviewFormSemesterOptions`) |
| `semesters.test.js` | `semesters.js` 단위테스트 |
| `passes.js` | 열람권 가격·표기·만료 계산 (`passPrice`, `passLabel`, `passDuration`, `nextExpiry`, `PASS_DAYS`). 최소 상품(0)의 지속시간은 대학마다 다르므로 `minutes` 인자로 받는다(기본 60) |
| `passes.test.js` | `passes.js` 단위테스트 |
| `points.js` | 리뷰 적립 포인트 상수·계산(`PUBLIC_REVIEW_POINTS`=30·`ANONYMOUS_REVIEW_POINTS`=20·`reviewPoints(isAnonymous)`) + 포인트 내역 누적 잔액 계산 (`computeRunningBalance`) |
| `points.test.js` | `points.js` 단위테스트 |
| `dates.js` | 서버 timestamp 파싱·포맷 (KST 고정). `parseServerDate`(offset 없으면 UTC로 간주), `formatDate`("YYYY.MM.DD"), `formatDateTime`("YYYY.MM.DD HH:mm"), `formatRelativeDate`(상대표기 "N일/주/달 전", KST 달력일 기준·now 주입가능) |
| `dates.test.js` | `dates.js` 단위테스트 |
| `profileOptions.js` | 프로필/회원가입 공용 드롭다운 옵션 상수(`REGIONS`·`DEGREE_PROGRAMS`·`ACADEMIC_STATUSES`·`GRADES`) + `admissionYears()` + 단과대↔학과 매핑(`colleges`·`departments` **대학별 이중 배열** — 1차 index는 `UNIV_EMAIL_KEYS`(korea=0·snu=1)와 병렬, `univIndexFromEmail(email)`이 @ 뒤 라벨로 index 결정(미매칭→0). 2차는 단과대↔학과 index 병렬, 단독 학부는 1:1. 원본 텍스트는 파일 하단 주석 보존. ⚠️ DB colleges/departments 시드는 고려대만 완비 — 서울대는 '미분류' 1쌍뿐이라 서울대 학과 선택은 가입 시 미분류 fallback·프로필 수정 저장은 NO_COLLEGE). ProfileTab·Signup 공용 |
| `authValidation.js` | 로그인·회원가입 입력 검증(이메일 형식·비밀번호 규칙·닉네임 규칙) 순수 함수. 각 함수가 에러 메시지(string)/`null` 반환 → Login·Signup의 inline 필드 에러에 사용. **닉네임 규칙**(`nicknameError`): 한글·영문·숫자만 / 2자 이상·가중길이(한글2·영숫자1) 16 이하=한글8·영문16 / 예약어(익명·운영자·admin·grgr 등) 부분일치 차단 + `nicknameFromEmail`(미입력 폴백 — 이메일 @앞부분을 같은 규칙으로 정제, 통과 불가면 `null`=직접 입력 요구). ⚠️ 서버 `validate_nickname`(migration 20260721071224)과 이중 소스 — 규칙·예약어 변경 시 양쪽 함께 |
| `authValidation.test.js` | `authValidation.js` 단위테스트 |
| `recruit.js` | 모집 상태 판정. `kstToday`(KST 달력일 'YYYY-MM-DD'), `effectiveActive`(recruit_until 우선, NULL이면 is_active 폴백 — 레거시 교외 6,647건) |
| `recruit.test.js` | `recruit.js` 단위테스트 |
| `seo.js` | 페이지 title·meta description 문자열 조립(`DEFAULT_TITLE`/`DEFAULT_DESCRIPTION`·`pageTitle`·`worksiteTitle`·`worksiteDescription`). DOM 반영은 `components/PageMeta`가 담당. ⚠️ `DEFAULT_DESCRIPTION`은 `index.html` 정적 meta와 같은 문구 유지 |
| `seo.test.js` | `seo.js` 단위테스트 |
| `idle.js` | 유휴 자동 로그아웃 만료 판정. `IDLE_TIMEOUT_MS`(30분)·`POLL_INTERVAL_MS`(15초)·`SKEW_MS`(60초) 상수, `parseLastActive`(localStorage 원문 파싱: `{uid,ts}` \| `null`(부재) \| `'invalid'`(가비지)), `isExpired`(벽시계 기준 만료 판정, fail-closed, `now` 인자 주입) |
| `idle.test.js` | `idle.js` 단위테스트 |
