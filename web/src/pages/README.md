# pages/ — 라우트 단위 페이지

## (a) 역할
URL 하나에 대응하는 **한 화면 전체**. `components` + `data` + `lib`를 **조합(조립)**해
완성된 페이지를 만든다. 앱에서 제일 위 계층(조립자).

## (b) 무엇이 들어가나
- `App.jsx`의 `<Route path=... element={<여기 컴포넌트/>} />`에 연결되는 컴포넌트.
- 페이지 전용 스타일은 같은 이름 `.css`로 **나란히** 둔다 (예: `Home.jsx` + `Home.css`).
- 새 페이지 추가 = 이 폴더에 `Xxx.jsx`(+`Xxx.css`) 만들고 → `App.jsx`에 `<Route>` 한 줄 등록.

## (c) 무엇을 참조(import)하나
- `../components/*` — UI 조각
- `../data/*` — 데이터 가져오기 (예: `worksiteQueries`)
- `../lib/*` — 순수 계산 (예: `scores`, `semesters`)
- `react-router-dom` — `useNavigate`, `useParams` 등

> css import는 같은 폴더라 `./Xxx.css` 그대로.
> ❌ `../supabase` 직접 import 금지. **DB 통신은 전부 `../data/*` 함수를 통해서만** 한다 (CLAUDE.md 규칙).

## (d) 현재 파일
| 파일 | 라우트 | 비고 |
|------|--------|------|
| `Login.jsx` / `.css` | `/login` | 로그인 화면(이메일 먼저 → 비밀번호 단계, choi 애니메이션). `signIn`(Supabase Auth) 사용 — 성공 시 `/home`(세션은 AuthContext onAuthStateChange가 하이드레이션). 가입여부 자동감지는 불가(Auth가 이메일 존재 숨김)라 **로그인-먼저**: 실패/신규는 비번단계 '회원가입' 링크 → 입력 비번 들고 `Signup` 마운트. 인증은 `data/authQueries`. |
| `Signup.jsx` | `/login`(2단계) | 회원가입 프로필 입력(3단계 wizard·진척도바·뒤로가기). Login 비번단계에서 분기 후 마운트(email/password props, 스타일 Login.css 공유). `signUpUser`(Supabase Auth signUp+metadata, handle_new_user 트리거와 짝). 단과대/학과/계열 드롭다운 + 필수선택 검증(빨간 테두리·인라인) — **학과는 단과대 선택 종속(계단식)**: 미선택 시 비활성+"단과대학을 먼저 선택해주세요", 단과대 변경 시 학과 초기화. 성공 시 이메일 확인 인터스티셜(자동 로그인 없음). 드롭다운 옵션은 `lib/profileOptions` 공용(`colleges`/`departments`/`PREFFEREDTRACK` 포함) |
| `ResetPassword.jsx` | `/reset-password` | 비밀번호 재설정 착지(메일 recovery 링크의 redirectTo, 스타일 Login.css 공유). 링크 유효 시 세션이 이미 있음 → 새 비번 2회 입력 → `updatePassword`(auth.updateUser). 만료/무효(해시 error_code·세션 없음)는 안내 + /login 유도. 프로필 없는 계정은 변경 후 ProfileGate가 프로필 단계로 보냄. ⚠️ Supabase 대시보드 Redirect URLs에 이 경로 등록 필요 |
| `Home.jsx` / `.css` | `/home` | 근무지 목록(랜딩). DB는 `data/worksiteQueries`(`fetchHomePostings`·`getReviewStats`)로 호출. 개인화 프로필은 AuthContext(fetchMe)에서 읽되, **값 기준 문자열 키로 메모**해 넘긴다(mergeUser로 객체만 바뀔 때 재요청·재계산 방지). **맞춤 추천 1곳 후보 = 추천점수 평균 4.0 이상**, 정렬 = ①모집중 ②자격부합(`isEligible`) ③개인화 매칭(`matchScore`: 학과3·단대2·계열2·지역1) ④리뷰 추천점수 — ③이 ④보다 앞이어야 "내 학과 맞춤"이 실제 순위를 만든다(2026-07-20 이전엔 ④가 앞이라 리뷰 있는 곳이 항상 이겼고, 메모 의존성도 `[postings]`뿐이라 프로필이 늦게 오면 개인화가 아예 반영 안 됐음). **비로그인(PUBLIC_BROWSE)도 카드 클릭→상세·검색창·공지·점수(단일 평균) 개방.** 검색 Enter/버튼은 `/search?q=`로 이동(제안 드롭다운은 로그인 시만 — suggestions RPC 미개방). **개인화만 로그인 전용**: 맞춤 추천 자리는 `GuestRecCard`(로그인 유도), 필터바도 로그인 시만 |
| `WorksiteDetail.jsx` / `.css` | `/worksite/:id` | 상세. components·data·lib 전부 조립. **비로그인(PUBLIC_BROWSE)은 공개 경로**: `fetchWorksitePublicDetail`(화이트리스트 RPC)+`fetchWorksiteScoreCard`로 근무지 정보+"리뷰 N개·X% 추천"만, 세부 별점·리뷰 본문 미노출('로그인하고 리뷰 보기'). 리뷰 RPC·auth 호출(조회수 등) 안 탐. **한시 전면 공개 기간(`config.REVIEWS_OPEN_UNTIL` 전, 애드센스 재심사 — 2026-11-09 종료, 지금은 잠금)엔 비로그인·무열람권도 열림 경로** — 판정은 `lib/passes.canViewReviews`(열람권 ∪ 공개기간). 비로그인 열림 경로는 정보카드만 공개 RPC로 받고 리뷰는 `list_worksite_reviews`(기간 중 anon 허용)로 받으며, 내 리뷰·도움됨은 빈 집합, 도움됨·신고·리뷰쓰기는 로그인 유도 모달 |
| `ReviewForm.jsx` / `.css` | `/worksite/:id/review` · `/worksite/:id/review/:reviewId/edit` | 리뷰 작성·수정 폼. 수정 시 리뷰 ID와 로그인 유저를 검증해 기존 값을 불러오고 업데이트 |
| `ExchangeCenter.jsx` / `.css` | `/exchange` | 교환센터(열람권 교환/사용/환불 · 포인트 적립 — '광고 시청하기'는 `components/AdModal` 모달을 띄움) |
| `MyPage.jsx` / `.css` | `/mypage` | 마이페이지: 포인트 내역 · 내 리뷰(수정→edit 라우트/삭제) · **프로필 수정**(진입 게이트: 탭 진입 시 비밀번호 확인 — `verifyCurrentPassword`=세션 이메일 재인증, 통과 전엔 흰 박스+가운데 입력만·탈퇴 버튼도 숨김. 확인 박스 밖의 독립 **비밀번호 변경** 아웃라인 버튼은 `sendPasswordResetToCurrentUser`로 세션 이메일에 재설정 링크 발송 + 60초 재발송 쿨다운 · 단과대/학과(계단식, Signup과 동일)·계열·거주지역·입학연도·학위·학년·학적상태 — 컨텍스트로 초기화→`update_profile` rpc 저장(단과대/학과 이름→id 엄격 매칭)→컨텍스트 머지(college/department {name} 재구성), 소속학교는 읽기전용) · **회원 탈퇴**(`WithdrawModal` "탈퇴합니다" 문구 타이핑 확인 → `deleteAccount`=`delete_account` rpc → signOut→`/login`) · 계정 드롭다운에서 ?tab=points|reviews|profile로 진입 시 해당 탭 선택 |
| `Notice.jsx` / `Notice.css` | `/notice` | 공지 목록(아코디언 펼침·10개 페이지네이션·본문 prefetch). `?open=:id`로 진입 시 해당 공지 펼침(홈 위젯에서 사용). `data/noticeQueries` |
| `Search.jsx` / `.css` | `/search` | 근장찾기 목록. **검색·정렬·페이징·dedup 전부 서버**(`data/worksiteQueries`의 `searchWorksiteCards`·`searchWorksiteSuggestions` rpc) — 프론트 재정렬 없음. **대학 스코프(서버)**: 로그인 유저는 자기 university_id + 공용(0)만, 비로그인은 전체(소속 없음). 검색창 입력→제안 드롭다운은 **`components/SearchSuggest`(홈과 공용)** — 기관명+근무지명 한 줄·입력어 매칭 강조, 클릭 시 상세 이동. **Enter/검색버튼**에만 카드 검색 실행. 정렬 2종(추천순/리뷰많은순, 잠금 시 추천순 고정). 열람권 없으면 점수 더미+블러(리뷰 없는 카드도 블러)+잠금 배너, 있으면 실점수. **비로그인(PUBLIC_BROWSE)은 검색 공개 — 잠금 취급(세부점수 더미·블러 + 개수·추천율 clear), 배너는 로그인 유도로 분기.** 잠금 판정은 `lib/passes.canViewReviews`(열람권 ∪ `config.REVIEWS_OPEN_UNTIL` 공개기간) — 한시 공개 기간엔 비로그인도 실점수·정렬 2종. **고급검색 패널**(`components/AdvancedSearch`): 유형·교내외·지역·기간·우대·학위·학적 필터를 "반영하여 검색"으로 적용(검색어와 AND), 초기화로 전체 리셋. 필터는 대표공고 기준, 학위/학적은 지원가능 의미, 지역은 국가근장 자동한정 |
| `Privacy.jsx` / `Legal.css` | `/privacy` | 개인정보처리방침(정적 문서). 푸터에서 링크. DB·data 의존 없음(순수 텍스트). 수집항목은 실제 스키마 기준 작성, 운영주체/위탁 리전 등은 가칭·placeholder(출시 전 확정). `Terms.jsx`와 `Legal.css` 공유 |
| `Terms.jsx` / `Legal.css` | `/terms` | 이용약관(정적 문서). 푸터에서 링크. 포인트·열람권·리뷰 정책 + 비공식 서비스 고지 반영. 2026-07-15 정식화(가칭·초안 표기 제거, 관할=관계 법령·운영주체 별도 미표기·시행일=서비스 출시일). **제6조에 지원 대학을 하드코딩하지 말 것** — 정본은 `universities.signup_enabled`다(2026-08-20 '(현재 @korea.ac.kr)' 드리프트 정정, `TermsConsentModal` 문구에 맞춤). `Privacy.jsx`와 `Legal.css` 공유 |
| `Contact.jsx` / `Legal.css` | `/contact` | 문의사항(정적 문서). 푸터 "문의사항" 링크. 1:1 문의 창구(인스타 `@grgr_review_official`·이메일 `bgl0819@korea.ac.kr`) + 개인정보 문의는 개인정보처리방침 안내. `Privacy`/`Terms`와 `Legal.css` 공유 |
