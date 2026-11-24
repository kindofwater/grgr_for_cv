# components/ — 재사용 UI 조각

## (a) 역할
여러 페이지/위치에서 **재사용하는 UI 부품**. JSX를 반환하는 작은 컴포넌트.
한 화면 전체가 아니라 그 안에 들어가는 조각(카드, 모달, 리스트 등).

## (b) 무엇이 들어가나
- 2곳 이상에서 쓰이거나, 페이지에서 떼어내면 깔끔해지는 UI 조각.
- 모달, 카드, 리스트 아이템 같은 **표현(presentational) 컴포넌트**.
- 한 페이지에서만 쓰고 재사용 가능성 없으면 → 그 페이지 파일 안에 두는 게 나을 수도.

## (c) 무엇을 참조(import)하나
- `../lib/*` — 순수 계산/포맷 (예: `InfoCard` → `../lib/scores`의 `formatWage` 등)
- 같은 폴더 내부 — 예: `ReviewList` → `./ReviewCard`
- 데이터는 **직접 안 가져옴**. 페이지가 `data/`에서 받아 props로 내려줌 (권장).

> **CSS는 컴포넌트가 자체 보유하는 게 원칙.** 같은 이름 `.css`를 옆에 두고 import한다
> (예: `Navbar.jsx` + `Navbar.css`, `ArrowButton.jsx` + `ArrowButton.css`). 그래야 어느 페이지에서
> 재사용해도 **동일하게** 보인다. (페이지 css에 스타일을 두면 페이지마다 다르게 보이는 문제 발생 — navbar가 그랬음.)
>
> ⚠️ **레거시 부채:** 일부 오래된 컴포넌트(`InfoCard`/`ScoreSummary`/`ReviewList`/`ReviewCard`)는
> 아직 자체 css 없이 페이지 css(특히 `../pages/WorksiteDetail.css`의 `sum-row`, `fill-blue` 등)에 의존한다.
> 다른 페이지에서 재사용하려면 그 스타일 로드 여부를 확인하고, 가능하면 자체 css로 옮길 것.

## (d) 현재 파일
| 파일 | 역할 |
|------|------|
| `PageMeta.jsx` | 라우트별 `document.title`·meta description 반영(`return null` 마운트 전용, `lib/seo` 사용). **모든 라우트 페이지가 각자 렌더하는 게 전제**(title 생략=기본 타이틀) — 새 페이지를 만들면 PageMeta도 함께 넣을 것. SEO(색인 품질) 목적 — Googlebot은 JS 렌더 후 title을 색인 |
| `InfoCard.jsx` | 근무지 기본정보 카드. `../lib/scores` 사용 |
| `ScoreSummary.jsx` | 점수 막대 요약. `locked`면 CSS 마스킹(무열람권), `publicOnly`면 "리뷰 N개·X% 추천"만 렌더(비로그인 공개 — 세부 별점 DOM에 없음) |
| `ReviewList.jsx` | 리뷰 목록. `ReviewCard`를 반복 렌더 |
| `ReviewCard.jsx` | 리뷰 1건 카드 |
| `ReviewFormFields.jsx` | 리뷰 작성·수정 폼의 입력 필드 묶음(별점 `StarRating`·세부점수·내용 등). `ReviewForm` 페이지에서 사용 |
| `Modal.jsx` | **공용 모달 셸(Radix `Dialog` 기반) — 모든 모달의 단일 진입점.** `Dialog.Portal`로 `<body>` 직속에 렌더되어 페이지 CSS가 안 닿는다(포커스 트랩·스크롤 잠금·Esc·포커스 복귀·`role`/`aria`는 Radix가 담당). props: `open`·`onOpenChange`·`size`(`sm`320/`md`400/`lg`420)·`dismissible`(false=Esc·배경클릭 무시 — 광고 모달·탈퇴 처리 중 전용, 리워드 어뷰징 방지·처리 중 혼란 방지)·`title`(스크린리더용, 필수)·`titleHidden`(기본 true)·`className`(같은 폴더 모달이 카드 모양만 덧칠할 때, 페이지가 주입하는 통로 아님). 스타일은 `Modal.css`. **2026-07-14 도입 — `ConfirmModal`·`LoginPromptModal`·`ReportModal`·`WithdrawModal` 마이그레이션 완료** |
| `Modal.css` | **공용 모달 스타일 단일 소스 — `Modal.jsx` 전용.** 클래스: `.modal-overlay`(스크림, `--scrim`)·`.modal`+`.modal-sm|md|lg`(폭 토큰 `--modal-w-*`)·`.modal-title`/`.modal-sr-only`·`.modal-icon`·`.modal-text`·`.modal-actions`·`.modal-btn`(+`.modal-btn-cancel`=아웃라인, `.is-primary`/`.is-neutral`/`.is-danger`=채움)·`.rp-list`/`.rp-option`/`.rp-radio`(`ReportModal` 사유 라디오 — 행 전체가 클릭 타깃, 네이티브 radio는 `appearance:none`으로 커스텀)·`.modal-withdraw`+`.mw-list`/`.mw-label`/`.mw-input`/`.mw-err`(`WithdrawModal` 안내 리스트+문구 입력, 버튼은 공용 `.modal-btn.is-danger` 재사용). Portal로 페이지 CSS가 안 닿으므로 폰트(`--sans`) 등을 직접 지정. `ConfirmModal`·`LoginPromptModal`·`ReportModal`·`WithdrawModal` 모두 이 클래스로 마이그레이션 완료 |
| `ConfirmModal.jsx` | 확인/취소 모달 (리뷰 삭제·로그아웃·열람권 교환/사용/환불 확인에 재사용). **`Modal.jsx`로 마이그레이션 완료**(`size="sm"`). props: `intent`(`'primary'`\|`'neutral'`\|`'danger'`, 기본 `'primary'`)·`confirmText`(기본 `'확인'`)·`cancelText`(기본 `'취소'`). `className` prop 제거됨(페이지별 스타일 주입 통로였던 탈출구 — 모달 파편화 재발 방지를 위해 되살리지 말 것) |
| `LoginPromptModal.jsx` | 비로그인 사용자가 잠긴 기능을 눌렀을 때 뜨는 로그인 유도 모달(자물쇠 아이콘). **`Modal.jsx`로 마이그레이션 완료**(`size="sm"`). props: `onClose`. "로그인하러 가기" 클릭 시 컴포넌트가 직접 `/login`으로 이동(`useNavigate`). **전역 `LoginPromptContext`가 렌더** — 잠긴 기능(교환센터·리뷰보기/쓰기·검색잠금) 시도 시 `promptLogin()`으로 표시. (⚠️ 명시적 "로그인/회원가입" 버튼은 이거 대신 `navigate('/login')` 직접) |
| `LoginPromptContext.jsx` | 앱 전역 로그인 프롬프트 통로(`ToastContext`와 동형) — `LoginPromptProvider`+`useLoginPrompt()`. `promptLogin()` 호출 시 `LoginPromptModal`을 띄운다. **정책: 잠긴 기능 시도=모달(`promptLogin`) / 명시적 로그인 버튼=리다이렉트(`navigate('/login')`)**. ⚠️ 모달이 `useNavigate`를 쓰므로 `App.jsx`에서 **`BrowserRouter` 안**에 Provider를 둔다 |
| `ReportModal.jsx` | 리뷰 신고 모달. **`Modal.jsx`로 마이그레이션 완료**(`size="md"`, `titleHidden={false}`). 사유 5개(`.rp-list`/`.rp-option`/`.rp-radio`, 네이티브 radio라 방향키 이동 유지) 선택 + 상세 내용 textarea(`.rp-opinion`/`.rp-textarea`, **필수** — 비면 라벨 옆 `.rp-field-error` 인라인 에러로 제출 차단, max 500자). 제출 버튼은 `is-danger`(남의 리뷰에 조치가 들어가는 되돌리기 어려운 행동). props: `onSubmit(reason, opinion)`·`onCancel`, `WorksiteDetail.jsx`에서 사용 |
| `WithdrawModal.jsx` | 회원 탈퇴 확인 모달. **`Modal.jsx`로 마이그레이션 완료**(`size="md"`, `titleHidden={false}`). **"탈퇴합니다" 문구 정확 입력 시에만** 실행 활성 + 사라지는 것 안내(리뷰 익명·포인트/열람권 소멸·30일 재가입 제한). 처리 중엔 `dismissible={!loading}`으로 Esc·배경클릭 차단(RPC 도중 모달만 사라지는 혼란 방지), 실패 시 `.mw-err` 빨간 문구. props: `onConfirm(()=>Promise)`·`onCancel` — 시그니처 불변, `MyPage.jsx` 프로필 탭에서 사용 |
| `AdModal.jsx` (+`.css`) | 리워드 광고 모달(교환센터 '광고 시청하기'에서 띄움 — 구 `/ad` 페이지 AdView 대체). 5초 강제시청(우상단 원형 카운트다운) → '포인트 받기 →'(시청 보상), 이미지 클릭=가게 이동(**시작부터 가능** — 새 탭만 열고 모달 유지·카운트 계속, 클릭 로그는 뷰당 1회, 적립은 포인트받기/X가 담당). 미디어 프리로드(로딩 화면 없이 준비되면 바로 표시)→onLoad 시 5초 카운트, X링→사라짐, X=5초후 받고나가기 / 5초 전엔 **리워드 상실 경고 모달**(계속 시청=카운트 멈췄다 재개 / 그냥 나가기=미지급), TOO_SOON 자동재시도, 이미지 1px 오버필+배경 투명으로 라운드 흰선 방지. **닫기는 X·포인트받기 2가지만**(배경/Esc로는 안 닫힘). props: `onClose`·`onClaimed(지갑)`(부모가 지갑·전역 머지). **예외: data(`adQueries`)·`useAuth` 직접 사용** — 상호작용 플로우 위젯이라 AuthContext 소비자처럼 둠 |
| `Toast.jsx` (+`.css`) | **상단 중앙**에 메시지 하나를 표시하고 자동 종료되는 비차단 안내 토스트(위에서 내려오며 등장). props: `message`·`onClose`·`duration`(기본 1500)·`variant`(`'info'`\|`'error'` → `.toast-info`/`.toast-error`). 직접 렌더하지 않고 `ToastContext`가 렌더한다 |
| `ToastContext.jsx` | 앱 전역 토스트 통로(Context) — `ToastProvider`+`useToast()`. `App.jsx`가 `<AuthProvider>` 안·`<AppRoutes/>` 밖에서 감싸 최상단에서 `<Toast>`를 렌더하므로, 페이지뿐 아니라 `AdModal` 같은 컴포넌트도 토스트를 띄울 수 있다. `useToast()` → `toast(message, variant='info', duration=1500)`. **2026-07 도입 — 페이지별 로컬 `notice`/`alert()` 전부 대체** |
| `SkeletonSearch.jsx` | 근장찾기(검색) 로딩 스켈레톤 (검색바 + 결과 카드) |
| `AdvancedSearch.jsx` (+`.css`) | 근장찾기 고급검색 필터 패널. 7그룹(모집상태·유형·교내외·지역·기간·학위·학적) 모두 복수선택 칩 + 검색/초기화 + 지역·기간 안내 말풍선. 기간은 학교근장 6주(42일) 미만=단기·이상=장기, 복수 기간은 최장 기준, 국가근장은 장기로 안내한다. 옵션은 `lib/profileOptions`(REGIONS). 선택 변경은 `onChange`로 즉시 알리고 실제 결과에는 검색 시 반영한다. (우대 필터는 2026-07 제거 — 카드 태그에는 유지) props: `initial`·`onChange`·`onApply`·`onReset`(부모가 `key`로 리마운트해 pending 동기화) |
| `SearchSuggest.jsx` (+`.css`) | 검색어 입력 → 근무지 제안 드롭다운(부분일치·입력어 매칭 강조·클릭 시 상세 이동). **홈·근장찾기 공용**. 디바운스(200ms) fetch·바깥클릭/포커스복귀·'붙는 모양'(검색바와 한 덩어리) 자체 보유. 검색바 래퍼(position:relative)에 absolute 자식이라 스크롤/리사이즈에 함께 움직임(분리 없음). props: `query`(입력값)·`containerRef`(검색바 래퍼)·`enabled`(false면 비활성, 예: 홈 비로그인)·`onOpenChange(open)`(부모가 래퍼에 `is-suggest-open` 토글). **예외: data(`searchWorksiteSuggestions`) 직접 사용** — 입력 중 fetch하는 연결형 위젯(AdModal과 동일). 검색창 input 쪽 모서리 변화는 래퍼 클래스가 페이지마다 달라 각 페이지 css가 담당 |
| `CardTags.jsx` (+`.css`) | 근무지 카드 태그 목록 — `max`개까지 개별 칩, 넘치면 `+N` 칩(hover 시 **브라우저 기본 툴팁 `title`**으로 숨은 태그명 콤마표시 — Floating UI 안 씀). props: `tags`([{label, cls}])·`max`(기본 Infinity=전부. **홈은 `max={3}`, 근장찾기는 미지정=전부**). 표시할 태그 필터(교외만·학위/학적 0·1만·장기단기 제외 등)는 부모가 결정. 색 클래스(`tag-national`/`tag-loc`/`tag-gray` 등)는 `Home.css` 전역 정의 사용. 부모 flex 컨테이너(`.tag-row`/`.hf-tags`) 안에 조각(fragment)으로 렌더 |
| `ArrowButton.jsx` (+`.css`) | 오른쪽 화살표(→) 진행 버튼. 로그인/회원가입 등 "다음" 액션에 재사용 |
| `Pagination.jsx` (+`.css`) | 공용 윈도우식 페이지네이션(1 … 현재±1 … 마지막). props: `page`·`totalPages`·`onPage`. 근장찾기·공지 목록에서 공유 |
| `PinIcon.jsx` (+`.css`) | 고정(공지) 표시용 압정 SVG(단색, 빨강 X). 공지 목록·홈 공지 위젯에서 `is_pinned`일 때 표시. 색은 `.pin-icon` 한 곳에서 관리 |
| `AppLayout.jsx` | 공용 레이아웃. `App.jsx`의 레이아웃 라우트(`<Route element={<AppLayout/>}>`)로 쓰여 `<Navbar/>`+`<Footer/>`를 **한 번만 마운트**하고 자식 페이지를 `<Outlet/>`에 렌더 → 페이지 이동 시 navbar/footer 깜빡임 방지. Login은 이 레이아웃 밖(별도 라우트). 지갑 prefetch는 C4 AuthContext(`fetchMe`)가 세션 하이드레이션 때 담당 — AppLayout은 순수 레이아웃만. |
| `Footer.jsx` (+`.css`) | 전역 푸터. AppLayout 하단에 1회 마운트(Login 제외 전 페이지). **왼쪽: 링크 3개(`/privacy`·`/terms`·`/contact`, `·`구분). 오른쪽: `© 2026 근로고래`**(모바일은 가운데 정렬). 1:1 문의 창구는 `/contact`(문의사항) 페이지로 분리. `react-router-dom`의 `Link`만 의존. `#root`(flex column) 마지막 자식이라 `margin-top:auto`로 짧은 페이지에서도 하단 고정 |
| `Navbar.jsx` (+`.css`) | 공용 상단 네비 **+ 모바일 하단 탭바**(≤768px에서 상단 링크 숨김→하단 `.bottom-nav` 표시, 현재 경로 강조). **AppLayout이 1회 마운트해 유지**(페이지가 직접 렌더하지 않음). **연결형(예외)**: 내부에서 `useAuth`·`useLocation`·`useNavigate` 사용. **비로그인도 근장찾기·공지는 통과(PUBLIC_BROWSE), 교환센터·마이페이지만 `/login` 유도**(`GUEST_LOGIN_REQUIRED` set). 우측엔 로그인 시 `AccountMenu`, 비로그인 시 **파란 "로그인 / 회원가입" 버튼**(→ `/login`) |
| `AccountMenu.jsx` (+`.css`) | 닉네임 pill + 계정 드롭다운(포인트·열람가능기한 표시·마이페이지 탭·로그아웃). 포인트·열람기한은 **컨텍스트(user)에서 즉시** 읽음(조회 없음 → 깜빡임 X; 최신화는 AuthContext/fetchMe가 세션 하이드레이션 시 담당). 열람권 *사용*은 교환센터/마이페이지에서만. `useAuth`·`useNavigate` 사용, Navbar가 로그인 시 렌더 |
| `Dropdown.jsx` (+`.css`) | 재사용 드롭다운(네이티브 `select` 대체) — **앱 드롭다운 단일 소스**. 계정 드롭다운 룩 + 살짝 올라오는 애니메이션. props: `value`·`onChange(value)`·`options`([{value,label,`dotClass?`}] 또는 문자열 배열)·`ariaLabel`·`hasError`·`disabled`·`size`("sm"=컴팩트 15px)·`label`(라벨:값 인라인). 옵션에 `dotClass`면 색 점(dd-dot) 표시. 바깥클릭/Esc로 닫힘. **회원가입(18px 기본, 별도 진행)·리뷰 폼·근장찾기(개수·정렬)·마이페이지(프로필)·홈 모바일 필터는 `size="sm"`로 통일** |
| `AuthContext.jsx` | 로그인 유저 전역 상태(Context + `useAuth`). **supabase + `data/profileQueries` 의존**(UI 부품 아님, 상태 공급자). `supabase.auth.getSession()`으로 초기 세션 로드, `onAuthStateChange`로 변화 감지 → `fetchMe()`+`_wallet()` RPC로 프로필·지갑 하이드레이션. 노출 인터페이스: `{ user, isLoading, mergeUser, logout }`. `AuthProvider`는 `App.jsx`가 감쌈, pages·components가 `useAuth()`로 읽음. ⚠️ `onAuthStateChange` 콜백 안에서 supabase 직접 호출 금지 — GoTrue lock 데드락 발생(무한 로딩). `setTimeout(0)`으로 다음 틱에 실행할 것. *여기 둔 이유: pages·components 양쪽이 쓰므로 역방향 의존 없이 둘 수 있는 유일한 기존 폴더* |
| `IdleLogout.jsx` | 유휴 로그아웃(30분). `return null` 마운트 전용 — `App.jsx`의 `<BrowserRouter>` 직속·`<ProfileGate>` 밖에 마운트(다른 위치에 두면 `useNavigate()` throw로 앱 백지). `useAuth()`의 `user`·`logout()`만 소비하고 `AuthContext` 내부는 안 건드림. 판정은 `lib/idle`(벽시계), I/O는 `idleStorage` |
| `idleStorage.js` / `.test.js` | `IdleLogout`의 `lastActive` localStorage I/O. `storage`를 주입받아 node 환경 테스트 가능. **삭제 함수 없음**(로그아웃 시에도 지우지 않는 게 설계) |
