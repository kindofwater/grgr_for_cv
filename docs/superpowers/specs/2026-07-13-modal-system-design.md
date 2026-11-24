# 모달 시스템 정비 — 설계

- 날짜: 2026-07-13 · 담당: 배경록
- 상태: 승인됨(브레인스토밍 완료) → 구현 계획 대기

## 1. 문제

모달 6종이 각자 껍데기(오버레이 + 카드 + 동작)를 따로 만들고 있다. 그 결과:

1. **폭 240px 병목** — 공용 `.modal { max-width: 240px }`이 확인 모달 하나 기준으로 잡혀 있다. 탈퇴 모달(안내 4줄 + 입력 + 버튼 2개)과 신고 모달(라디오 5개)이 이 폭에 갇혀 답답하다.
2. **모달 버튼이 네비바 버튼을 재활용** — `.btn-login` / `.btn-signup-nav`의 크기·모양은 `components/Navbar.css`에 정의돼 있고 `Modal.css`는 색만 덮어쓴다. 네비바 버튼을 바꾸면 전 모달이 같이 바뀐다.
3. **위험색 불일치** — 탈퇴만 빨강(`.mw-danger`)이고, 리뷰 삭제·포인트 회수 같은 파괴적 확인은 초록/파랑 primary다.
4. **오버레이 3종** — `rgba(0,0,0,0.4)` / `rgba(8,6,13,0.55)` / `rgba(8,6,13,0.62)`.
5. **접근성 부재** — Esc 닫기·포커스 트랩·배경 스크롤 잠금·포커스 복귀가 전 모달에 없다. `role="dialog"`는 AdModal에만 있다.
6. **ReportModal만 인라인 style + 네이티브 라디오** — CSS를 고쳐도 혼자 안 따라온다.
7. **`alert()` 10곳** — 모달을 다듬어도 브라우저 기본 경고창이 뜨면 디자인이 무너진다.

### 근본 원인: 모달이 페이지 DOM 안에 렌더된다

모달이 페이지의 후손이라 **페이지 CSS가 모달로 샌다.**

```css
/* pages/Home.css:14 */
.home-wrap input,
.home-wrap button { background: white; color: var(--text); }

/* pages/ReviewForm.css:15 */
.form-wrap button,
.form-wrap textarea { font-family: var(--sans); }
```

같은 `ConfirmModal`이 홈에서는 배경색이 강제되고, 리뷰 폼에서는 폰트가 강제된다. `Modal.css:63`의 주석("페이지 전역 버튼 리셋에 안 밀리게")은 이 싸움을 **특이도로 간신히 이기고 있다는 기록**이다.

이걸 안 막으면 개발용 갤러리(아래)는 **거짓말을 한다** — 갤러리에선 깨끗한데 실제 페이지에선 오염된 모달이 뜬다.

## 2. 대상 모달 6종

| 모달 | 파일 | 사용처 |
|---|---|---|
| ConfirmModal | `components/ConfirmModal.jsx` | 리뷰 삭제·익명 제출·로그아웃·열람권 교환/사용/환불 (5개 파일) |
| ReportModal | `components/ReportModal.jsx` | 리뷰 신고 |
| WithdrawModal | `components/WithdrawModal.jsx` | 회원 탈퇴 |
| AdModal | `components/AdModal.jsx` | 리워드 광고 |
| 광고 이탈 경고 | `AdModal.jsx` 내부 | 광고 5초 전 X |
| 로그인 유도 | `pages/Home.jsx` 인라인 | 홈 잠긴 카드 클릭 |

## 3. 결정

### 3.1 Radix Dialog 채택 (통합 `radix-ui` 패키지)

직접 셸을 만드는 안(A) 대신 **헤드리스 라이브러리(C)** 를 쓴다.

**채택 이유**
- **Portal이 CSS 유출을 원천 차단한다.** 모달을 `<body>` 직속으로 렌더 → 페이지의 후손이 아니게 됨 → `.home-wrap button` 같은 후손 선택자가 물리적으로 닿을 수 없다. 모달 모양이 오직 `Modal.css`로만 결정된다. **이것이 "갤러리 = 실제"의 구조적 보장이다.**
- 포커스 트랩·스크롤 잠금·Esc·포커스 복귀·중첩 모달이 검증된 상태로 온다. 직접 짜면 스크롤바 폭 보정, iOS 스크롤 잠금, 포커스 복귀 같은 지뢰를 밟는다.
- z-index 해킹(`AdModal.css:166`의 `.ad-leavewarn` 별도 오버레이, 999 vs 1000)이 사라진다.
- 헤드리스라 CSS는 여전히 우리 것 — 디자인 자유도 100%.

**개별 `@radix-ui/react-dialog`가 아니라 통합 `radix-ui` 패키지**를 쓴다. 팀 방향이 "오버레이 UI는 Radix로 통일"이라, 나중에 Dropdown을 옮길 때 패키지가 번지지 않는다.

**감수하는 비용**: 의존성 +1(gzip 약 15~20KB), Portal·asChild 등 Radix 개념 학습.

**기각한 대안**
- A안(직접 셸): 의존성 0이지만 포커스 트랩을 직접 구현해야 하고, 무엇보다 **CSS 유출을 못 막는다**(Portal 없이는 모달이 페이지 후손으로 남음). 갤러리 신뢰성이 깨진다.
- B안(CSS만 통일 + 훅): 오버레이 div를 6곳이 계속 각자 소유 → 새 모달을 만드는 사람이 또 빠뜨린다. 지금 문제가 정확히 이렇게 생겼다.

### 3.2 구조 — 2층

```
radix-ui (Dialog)          동작: 포커스 트랩 · 스크롤 잠금 · Esc · Portal · aria
      ↓ 감쌈
components/Modal.jsx       우리 셸: size · dismissible · 오버레이 · 카드 · 애니메이션
      ↓ 내용물만 넣음
ConfirmModal · ReportModal · WithdrawModal · AdModal · LoginPromptModal · 광고 경고
```

가운데 `Modal.jsx` 한 겹을 두어 **페이지·컴포넌트가 Radix를 직접 알지 않게** 한다. 라이브러리를 갈아도 이 파일만 고치면 되고, 팀원은 `<Modal size="md">`만 알면 된다.

`Modal.jsx` props:
- `size`: `"sm" | "md" | "lg"`
- `dismissible`: 기본 `true`. `false`면 Esc·배경클릭으로 안 닫힘 (Radix의 `onEscapeKeyDown` / `onPointerDownOutside`에서 `preventDefault`).
- `open` / `onOpenChange`

### 3.3 디자인 토큰 (`web/src/index.css`에 추가)

`:root`는 `index.css`만 정의한다(CLAUDE.md 규칙).

```css
--modal-w-sm: 320px;   /* 확인 · 로그인 유도 · 광고 경고 */
--modal-w-md: 400px;   /* 신고 · 탈퇴 */
--modal-w-lg: 420px;   /* 광고 (기존 폭 유지) */
--scrim: rgba(8, 6, 13, 0.5);   /* 오버레이 단일 소스 */
```

**스크림 1종으로 통일.** `8,6,13`은 `--text-h`(#08060d)와 같은 색이라 팔레트와 맞는다(순검정보다 자연스러움). **중첩 모달은 저절로 해결된다** — 광고 위에 경고가 뜨면 같은 스크림이 두 겹 쌓여 자동으로 더 어두워진다(체감 0.75). 경고용 스크림을 따로 정의할 필요가 없다.

### 3.4 버튼 — 채움 여부로 위계, 색으로 intent

3단계 색을 쓸 때 함정: 확인 버튼이 회색이면 **취소 버튼도 회색이라 둘이 똑같아 보인다.** 그래서 색이 아니라 **채움 여부**로 위계를 잡는다.

```
취소 = 항상 아웃라인 (회색 테두리 · 회색 글자) — 색으로 경쟁하지 않음
확인 = 항상 채워진 버튼, 색만 intent에 따라:
```

| intent | 색 | 적용 |
|---|---|---|
| `primary` | 파랑 `--primary` | 열람권 교환 · 사용 · 익명 제출 · "로그인하러 가기" |
| `neutral` | 짙은 회색 | 로그아웃 · 열람권 환불 |
| `danger` | 빨강 `--danger` | 리뷰 삭제 · 회원 탈퇴 |

클래스는 `.modal-btn` + `.is-primary` / `.is-neutral` / `.is-danger`. **크기·모양·폰트를 `Modal.css`가 소유**한다 → 네비바 의존(문제 2) 해소.

⚠️ **`font-family`를 `.modal-btn`에 명시적으로 박을 것.** Portal 이후 `.form-wrap button { font-family: var(--sans) }`가 더 이상 안 닿으므로, 안 박으면 폰트가 빠진다.

`components/AccountMenu.css:47`의 빨간 '로그아웃' 글자도 중립으로 내린다 — 그래야 "로그아웃 = neutral" 규칙과 앞뒤가 맞는다.

### 3.5 모달 6종 정리

| 모달 | 변화 |
|---|---|
| ConfirmModal | 셸 사용 + `intent` prop 추가. **`className` prop 삭제**(3.7 참조) |
| ReportModal | 셸 사용 + 인라인 style 제거, 라디오를 CSS 클래스로 (문제 6) |
| WithdrawModal | 셸 사용. `.mw-danger` → 공용 `.modal-btn.is-danger`로 흡수 |
| AdModal | 셸 사용 + `dismissible={false}`. **Esc·배경클릭으로 안 닫히는 건 지켜야 할 사양**(리워드 어뷰징 방지) |
| 광고 경고 | 중첩 Dialog로 정식화 → `.ad-leavewarn` z-index 해킹 삭제 |
| 로그인 유도 | `Home.jsx`에서 떼어내 `components/LoginPromptModal.jsx`로 승격 |

로그인 유도 모달을 컴포넌트로 빼야 **갤러리에 올릴 수 있고**, 나중에 다른 페이지에서도 재사용된다.

### 3.6 갤러리 `/dev/modals`

`pages/DevModals.jsx` (+`.css`). 새 폴더 없이 기존 `pages/`에 둔다.

**DEV 전용.** 라우트를 `import.meta.env.DEV`로 감싸 실서비스 빌드에서 제거한다(Vite가 `false`로 치환 → dead code elimination). grgr.kr에서 `/dev/modals`는 존재하지 않는다.

왼쪽 목록에서 클릭하면 **진짜 컴포넌트**가 그대로 뜬다. `Modal.css`를 고치면 즉시 반영된다.

포함 항목:
- 확인 모달 — **3가지 intent 각각**(primary/neutral/danger). 파랑·회색·빨강이 나란히 있을 때 위계가 사는지 확인.
- 로그인 유도 / 신고 / 탈퇴(기본·에러·로딩 상태) / 광고 / 광고 경고
- 탈퇴의 에러·로딩은 실제로 재현하기 까다로운 상태라 갤러리의 큰 이득이다.

AdModal도 **실물 그대로** 넣는다. 갤러리에서 포인트가 실제 적립되지만, 현재 테스트 기간이고 실유저가 없어 무시 가능(PM 판단). `daily_cap` 디버그값 복구는 별개의 런칭 체크리스트 항목.

### 3.7 갤러리가 거짓말하지 않게 하는 장치

Portal이 **CSS 유출(가장 큰 구멍)** 을 막는다. Portal로도 안 막히는 유출 3개는 따로 막는다.

1. **`className` 탈출구 제거.** `ConfirmModal`이 `className` prop을 받는다. 현재 넘기는 호출부는 **없다**(죽은 prop). 남겨두면 언젠가 페이지별 스타일이 주입돼 다시 갈라진다. → **prop 삭제.** 변형이 필요하면 `intent`처럼 정해진 값으로만.
2. **최악 케이스 콘텐츠.** 짧은 더미만 넣으면 긴 근무지명이나 `ReviewForm`의 JSX 메시지(`<strong>` 포함)에서 깨지는 걸 못 본다. → 갤러리에 **긴 텍스트·JSX 메시지**를 기본으로 넣는다.
3. **뷰포트 전환.** 데스크톱에서만 보면 모바일 깨짐을 놓친다. → 갤러리에 **폭 전환 버튼(360 / 768 / 데스크톱)**.

### 3.8 alert() → Toast (10곳 전부)

`Toast` 컴포넌트에 **오류용 빨강 변형** `variant="error"`를 추가한다.

**`ToastContext.jsx` + `useToast()` 훅**을 만든다. 현재는 `ReviewForm`이 `notice` 로컬 상태로 `<Toast>`를 직접 렌더하는데, 이 패턴을 6곳에 복사하면 지저분하고, 특히 **AdModal은 페이지가 아니라 컴포넌트라** 자기가 토스트를 띄울 방법이 없다. `AuthContext.jsx`가 이미 같은 자리(`components/`)에 같은 방식으로 있으므로 새 패턴이 아니다.

```js
const toast = useToast()
toast('신고가 접수되었어요')
toast('포인트가 부족해요', 'error')
```

| 파일 | alert 수 |
|---|---|
| `pages/WorksiteDetail.jsx` | 3 (신고 접수·신고 오류·포인트 부족) |
| `pages/MyPage.jsx` | 1 |
| `pages/ExchangeCenter.jsx` | 1 |
| `components/AdModal.jsx` | 1 (적립 오류) |
| `pages/Login.jsx` | 2 |
| `pages/Signup.jsx` | 2 |

⚠️ **`Login.jsx` / `Signup.jsx`는 현수(kindofwater) 담당 파일이다.** PM 판단으로 이번에 함께 처리하되:
- 변경을 **`alert()` → `toast()` 한 줄 치환으로만 엄격히 제한**한다. 인증 로직은 손대지 않는다.
- **착수 전 디스코드에 공유**한다(현수가 동시에 만지면 충돌).

`ReviewForm`의 기존 `notice` 로컬 상태도 `useToast()`로 통일한다.

## 4. 파일 변경

**신규 (4)**

| 파일 | 역할 |
|---|---|
| `web/src/components/Modal.jsx` | Radix Dialog를 감싼 공용 셸 |
| `web/src/components/LoginPromptModal.jsx` | Home 인라인 모달 승격 |
| `web/src/components/ToastContext.jsx` | `useToast()` 훅 |
| `web/src/pages/DevModals.jsx` (+`.css`) | 갤러리 |

**수정**

- `web/package.json` — `radix-ui` 추가
- `web/src/index.css` — 토큰 4개(`--modal-w-sm/md/lg`, `--scrim`)
- `web/src/components/Modal.css` — 전면 재작성(셸 · 버튼 3종 · 신고 라디오 · 탈퇴)
- `web/src/components/ConfirmModal.jsx` — 셸 + `intent`, `className` 삭제
- `web/src/components/ReportModal.jsx` — 셸 + 인라인 style 제거
- `web/src/components/WithdrawModal.jsx` — 셸 + 공용 danger 버튼
- `web/src/components/AdModal.jsx` / `.css` — 셸 + `dismissible={false}` + 중첩 Dialog, `.ad-leavewarn` 제거
- `web/src/components/Toast.jsx` / `.css` — `variant="error"`
- `web/src/components/AccountMenu.jsx` / `.css` — `intent="neutral"`, 빨간 로그아웃 글자 중립화
- `web/src/App.jsx` — `ToastProvider` + DEV 라우트
- `web/src/pages/Home.jsx` — 인라인 모달 제거 → `LoginPromptModal`
- `web/src/pages/MyPage.jsx` · `ExchangeCenter.jsx` · `WorksiteDetail.jsx` · `ReviewForm.jsx` — `intent` 지정 + `alert` → `toast`
- `web/src/pages/Login.jsx` · `Signup.jsx` — `alert` → `toast` (현수 공유 후)
- `web/src/components/README.md` · `web/src/pages/README.md` — 갱신

**DB 변경 없음.**

## 5. 검증

갤러리에서 6종을 육안 확인하고, **접근성 4가지를 손으로 확인**한다:

1. Esc로 닫히는가
2. Tab이 모달 안에서만 도는가
3. 뒤 페이지가 스크롤 안 되는가
4. 닫으면 원래 눌렀던 버튼으로 포커스가 돌아오는가

**단, 광고 모달만은 Esc·배경클릭으로 안 닫혀야 정상이다** (리워드 어뷰징 방지 사양).

**자동 테스트는 이번에 붙이지 않는다.** 이 프로젝트의 vitest는 `lib/`의 순수 함수만 다루고, 컴포넌트를 테스트하려면 `@testing-library/react` + jsdom 설정을 새로 깔아야 한다. 모달 정비하러 와서 테스트 인프라를 까는 건 범위가 번진다. 대신 **`npm test`로 기존 테스트가 안 깨졌는지 반드시 확인**한다. 컴포넌트 테스트 도입은 후속 TODO.

## 6. 위험

1. **Radix × React 19 호환** — 이 프로젝트는 React 19.2다. **설치 직후 제일 먼저 확인한다.** 문제가 있으면 여기서 A안(직접 셸)으로 되돌리는 판단을 한다.
2. **번들 크기** — 빌드 후 증가분을 실제로 재서 기록한다.
3. **Login·Signup 충돌** — 현수와 공유 후 착수.

## 7. 범위 밖 (후속)

- **Dropdown → Radix 이관.** 팀 방향은 "오버레이 UI는 Radix로 통일"이다. 이번엔 모달만. 이관 전까지는 자체 `Dropdown.jsx`와 Radix가 공존하는 과도기다.
- 컴포넌트 테스트 인프라(`@testing-library/react`).
- 모달 세부 디자인(여백·폰트 크기 등) 미세 조정 — 갤러리를 보며 별도로.
