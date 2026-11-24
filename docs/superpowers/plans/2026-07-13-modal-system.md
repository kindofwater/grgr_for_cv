# 모달 시스템 정비 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 모달 6종이 각자 만들던 껍데기(오버레이·카드·버튼·동작)를 Radix Dialog 기반 공용 셸 하나로 통합하고, 개발용 갤러리(`/dev/modals`)에서 전부 한자리에서 검증할 수 있게 한다.

**Architecture:** `radix-ui`의 Dialog가 포커스 트랩·스크롤 잠금·Esc·포커스 복귀·Portal을 담당하고, 그 위에 우리 셸 `components/Modal.jsx` 한 겹을 얹어 폭(`size`)·닫힘 정책(`dismissible`)·오버레이·카드·애니메이션을 소유한다. 기존 모달 6종은 셸 안에 내용물만 넣는다. **Portal이 모달을 `<body>` 직속으로 렌더하므로 페이지 CSS가 모달에 닿지 않고, 그 덕에 갤러리가 실제와 같음이 구조적으로 보장된다.**

**Tech Stack:** React 19.2 · Vite 8 · `radix-ui`(통합 패키지) · 순수 CSS(디자인 토큰은 `web/src/index.css`)

**설계 문서:** `docs/superpowers/specs/2026-07-13-modal-system-design.md`

## Global Constraints

- **작업 브랜치는 `feat/modal-system`** (이미 생성됨, 스펙 커밋 `91a4a98`). `main`·`prod`에 직접 커밋 금지.
- **DB 변경 없음.** 마이그레이션·`db push` 일절 없음.
- **`:root` 변수는 `web/src/index.css`에만 정의한다** (CLAUDE.md 규칙). 페이지·컴포넌트 CSS는 `var()`로 참조만.
- **컴포넌트 CSS는 컴포넌트가 소유한다** (`Modal.jsx` ↔ `Modal.css`). 페이지 CSS에 모달 스타일을 두지 않는다.
- **새 폴더를 만들지 않는다.** 새 파일은 기존 `web/src/components/` · `web/src/pages/`에 둔다.
- **의존성 방향:** `pages → components / data / lib`. 역방향 import 금지.
- ⚠️ **`npm run lint`는 이 브랜치를 파기 전부터 이미 실패한다 — 기준선은 `9 errors / 7 warnings`다.** (대부분 React 19의 새 규칙 `react-hooks/set-state-in-effect`. 이미 깨진 파일: `components/AdModal.jsx` · `components/Toast.jsx` · `components/Toast_example.js` · `components/WithdrawModal.jsx` · `lib/semesters.test.js` · `pages/Home.jsx` · `pages/Notice.jsx` · `pages/ReviewForm.jsx` · `pages/WorksiteDetail.jsx` — 공교롭게도 이 계획이 건드릴 파일과 많이 겹친다.)
  - **각 태스크의 "lint 성공" 문구는 이 규칙으로 대체된다:** 작업 전후로 `npm run lint`를 돌려 **에러·경고 개수가 늘지 않았는지**만 확인한다. 9/7 이하면 통과다.
  - **기존 lint 에러를 고치지 말 것.** 이 계획의 범위가 아니고, diff가 지저분해져 리뷰가 어려워진다. 남의 부채는 남겨둔다.
- **자동 테스트를 새로 붙이지 않는다.** 이 저장소의 vitest는 `web/src/lib/`의 순수 함수만 다룬다. 모달은 순수 함수가 아니라 테스트할 단위가 없고, 컴포넌트 테스트를 하려면 `@testing-library/react` + jsdom 인프라를 새로 깔아야 해서 범위가 번진다(스펙 5절 결정). **대신 매 태스크는 `npm run build` + `npm run lint` + 갤러리 육안 확인으로 검증한다.** `npm test`(기존 lib 테스트)는 깨지지 않아야 한다.
- **광고 모달은 Esc·배경클릭으로 닫히면 안 된다.** 이건 버그가 아니라 리워드 어뷰징 방지 사양이다.
- ⚠️ **유휴(idle) 경고 모달을 만들지 말 것.** 30분 유휴 자동 로그아웃(`components/IdleLogout.jsx`, main에 머지됨)은 **경고 모달 없이 바로 로그아웃하도록 일부러 그렇게 설계됐다.** "모달을 손보는 김에 유휴 경고도 넣자"는 유혹이 있는데, 의도된 부재이므로 추가하지 않는다. 유휴 로그아웃의 사용자 안내는 **Login 페이지의 토스트 하나로 끝난다**(Task 10).
- ⚠️ **`logout()` 호출 시 `{ scope: 'local' }`을 반드시 유지한다.** `logout({ scope: 'local' })`은 "이 브라우저만 로그아웃"이다. 인자를 빼면 auth-js 기본값이 `'global'`이라 **학교 PC에서 로그아웃했을 뿐인데 집의 폰 세션까지 끊긴다.** 최근 main에서 고쳐진 부분이니 되돌리지 말 것 (`AccountMenu.jsx`·`MyPage.jsx`).
- **`Login.jsx` / `Signup.jsx`는 현수(kindofwater) 담당 파일이다.** Task 10에서 건드리되 **`alert()` → `toast()` 치환으로만 엄격히 제한**한다. 인증 로직·상태·애니메이션은 손대지 않는다. **착수 전 디스코드 공유 필수.**
- 모든 명령은 `web/` 디렉터리에서 실행한다 (`cd web`).

## 확정된 디자인 값 (모든 태스크가 참조)

| 항목 | 값 |
|---|---|
| 폭 sm | `320px` — 확인 · 로그인 유도 · 광고 경고 |
| 폭 md | `400px` — 신고 · 탈퇴 |
| 폭 lg | `420px` — 광고 |
| 스크림 | `rgba(8, 6, 13, 0.5)` — **단 하나** |
| 취소 버튼 | 항상 **아웃라인**(회색 테두리·회색 글자). 색으로 경쟁하지 않음 |
| 확인 버튼 | 항상 **채움**. 색만 intent |
| intent `primary` | 파랑 `--primary` — 열람권 교환·사용, 익명 제출, "로그인하러 가기" |
| intent `neutral` | 짙은 회색 `--text-sub` — 로그아웃, 열람권 환불 |
| intent `danger` | 빨강 `--danger` — 리뷰 삭제, 회원 탈퇴 |

---

## Task 1: Radix 설치 + React 19 호환 확인 (게이트)

이 프로젝트는 React 19.2다. **Radix가 React 19에서 안 돌면 여기서 멈추고 스펙 6절의 탈출구(A안=직접 셸)로 되돌리는 판단을 한다.** 뒤 태스크를 전부 짜고 나서 발견하면 손해가 크므로 제일 먼저 확인한다.

**Files:**
- Modify: `web/package.json`

**Interfaces:**
- Consumes: 없음
- Produces: `import { Dialog } from 'radix-ui'` — 이후 모든 태스크가 이 import를 쓴다.

- [ ] **Step 1: 통합 패키지 설치**

```bash
cd web
npm install radix-ui
```

개별 `@radix-ui/react-dialog`가 아니라 **통합 `radix-ui`** 를 설치한다. 팀 방향이 "오버레이 UI는 Radix로 통일"이라, 나중에 Dropdown을 옮길 때 패키지가 여러 개로 번지지 않게 하기 위해서다.

- [ ] **Step 2: peer dependency 경고 확인**

설치 로그에 `ERESOLVE` 나 `peer react@"^16 || ^17 || ^18"` 같은 React 19 미지원 경고가 뜨는지 본다.

- 경고 없음 → Step 3으로.
- **경고가 뜨면 → 여기서 중단하고 사람에게 보고한다.** `--force`나 `--legacy-peer-deps`로 밀어붙이지 말 것. 스펙 6절에 따라 A안(직접 셸)으로 전환할지 판단해야 한다.

- [ ] **Step 3: 실제로 렌더되는지 최소 확인**

`web/src/main.jsx`나 아무 파일도 고치지 말고, import가 해석되는지만 빌드로 확인한다. 임시 파일을 만든다:

```bash
cd web
cat > src/__radix_check.jsx <<'EOF'
import { Dialog } from 'radix-ui'
export default function RadixCheck() {
  return (
    <Dialog.Root open>
      <Dialog.Portal>
        <Dialog.Overlay />
        <Dialog.Content>
          <Dialog.Title>ok</Dialog.Title>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  )
}
EOF
npx vite build
```

Expected: 빌드 성공. `radix-ui` 모듈을 못 찾는다는 에러가 없어야 한다.

- [ ] **Step 4: 임시 파일 삭제**

```bash
cd web
rm src/__radix_check.jsx
```

- [ ] **Step 5: 번들 기준선 기록**

```bash
cd web
npm run build
```

출력의 `dist/assets/index-*.js` 크기(gzip 포함)를 적어둔다. **Task 11에서 증가분을 재기 위한 기준선이다.** 계획 파일 하단 "번들 기록"에 적는다.

- [ ] **Step 6: 커밋**

```bash
cd "c:/새 폴더"
git add web/package.json web/package-lock.json
git commit -m "chore(deps): radix-ui 추가 — 모달 셸의 접근성·Portal 기반"
```

---

## Task 2: 디자인 토큰 추가

**Files:**
- Modify: `web/src/index.css` (`:root` 블록 안, `--card-radius` 정의 근처)

**Interfaces:**
- Consumes: 없음
- Produces: `--modal-w-sm` `--modal-w-md` `--modal-w-lg` `--scrim` — Task 3의 `Modal.css`가 쓴다.

- [ ] **Step 1: 토큰 4개 추가**

`web/src/index.css`의 `:root` 안, `--card-radius: 8px;` 줄 바로 아래에 넣는다:

```css
  /* 모달 — 폭 3종 + 스크림 단일 소스 (components/Modal.css가 참조).
     폭은 콘텐츠 성격으로 나눈다: 짧은 문답=sm, 리스트·입력이 있는 것=md, 광고=lg.
     스크림은 하나뿐 — 중첩 모달(광고 위 경고)은 같은 스크림이 두 겹 쌓여 저절로 더 어두워진다. */
  --modal-w-sm: 320px;   /* 확인 · 로그인 유도 · 광고 경고 */
  --modal-w-md: 400px;   /* 신고 · 탈퇴 */
  --modal-w-lg: 420px;   /* 광고 */
  --scrim: rgba(8, 6, 13, 0.5);   /* = --text-h(#08060d) 계열. 순검정보다 팔레트와 맞는다 */
```

- [ ] **Step 2: 빌드 확인**

```bash
cd web
npm run build
```

Expected: 성공.

- [ ] **Step 3: 커밋**

```bash
cd "c:/새 폴더"
git add web/src/index.css
git commit -m "feat(css): 모달 토큰 추가 — 폭 3종(sm/md/lg) + 스크림 단일 소스"
```

---

## Task 3: 공용 셸 `Modal.jsx` + `Modal.css` 전면 재작성

이 태스크가 문제 1·2·4를 한꺼번에 해결한다. 아직 아무 모달도 이걸 안 쓰므로 **화면은 안 변한다**(기존 `.modal-*` 클래스를 쓰는 모달들이 잠깐 깨진 채로 남는다). Task 4~9에서 하나씩 옮긴다.

⚠️ 기존 `Modal.css`의 `.modal-overlay` / `.modal` / `.modal-icon` / `.modal-actions` / `.btn-login` / `.btn-signup-nav` / `.modal-withdraw` 를 **전부 새 규칙으로 대체**한다. 옛 클래스를 남겨두면 두 체계가 공존해 다시 갈라진다.

**Files:**
- Create: `web/src/components/Modal.jsx`
- Rewrite: `web/src/components/Modal.css`

**Interfaces:**
- Consumes: `radix-ui`(Task 1), 토큰 4개(Task 2)
- Produces:
  - `<Modal open onOpenChange size dismissible title titleHidden className>` — 기본 export
  - CSS 클래스: `.modal-overlay` `.modal` `.modal-sm|md|lg` `.modal-title` `.modal-sr-only` `.modal-icon` `.modal-text` `.modal-actions` `.modal-btn` `.modal-btn-cancel` `.is-primary` `.is-neutral` `.is-danger`
  - Task 4~9가 전부 이 인터페이스를 쓴다.

- [ ] **Step 1: `web/src/components/Modal.jsx` 생성**

```jsx
import { Dialog } from 'radix-ui'
import './Modal.css'

// 앱의 모든 모달이 통과하는 공용 셸 — 모달을 새로 만들 땐 반드시 이걸 쓴다.
//
// Radix Dialog가 담당(우리가 안 짬): 포커스 트랩 · 배경 스크롤 잠금 · Esc · 닫을 때 포커스 복귀 ·
//   role/aria-modal · Portal.
// 이 파일이 담당: 오버레이(스크림) · 카드 · 폭 · 애니메이션 · 닫힘 정책.
//
// ⚠️ Portal이 모달을 <body> 직속으로 렌더한다 = 모달이 페이지 DOM의 후손이 아니다.
//    그래서 `.home-wrap button`, `.form-wrap button` 같은 페이지 CSS가 모달에 닿지 않는다.
//    모달의 모양은 오직 Modal.css로만 결정된다 → /dev/modals 갤러리 = 실제 화면.
//    (역으로: 페이지 CSS에 기대던 것도 안 닿는다. 폰트 등은 Modal.css가 직접 박아야 한다.)
//
// props:
//   open, onOpenChange  — Radix 제어 (열림 상태는 부모가 소유)
//   size        'sm'(320) | 'md'(400) | 'lg'(420·광고)
//   dismissible false면 Esc·배경클릭으로 안 닫힘. 광고 모달 전용 —
//               리워드 어뷰징 방지 사양이라 버그가 아니다. 기본 true.
//   title       스크린리더용 제목(필수 — Radix가 없으면 경고). 화면에 보이려면 titleHidden={false}
//   className   같은 components/ 안의 모달이 카드 모양을 덧칠할 때만 (예: 'ad-modal').
//               ⚠️ pages가 모달에 className을 주입하는 통로로 쓰지 말 것 — 그게 갈라짐의 시작이다.
export default function Modal({
  open,
  onOpenChange,
  size = 'sm',
  dismissible = true,
  title,
  titleHidden = true,
  className = '',
  children,
}) {
  // dismissible=false면 Radix의 닫기 트리거를 전부 막는다
  const block = (e) => { if (!dismissible) e.preventDefault() }

  // aria-describedby={undefined}: 설명 요소를 안 쓴다고 Radix에 명시(안 하면 콘솔 경고)
  return (
    <Dialog.Root open={open} onOpenChange={onOpenChange}>
      <Dialog.Portal>
        <Dialog.Overlay className="modal-overlay" />
        <Dialog.Content
          className={`modal modal-${size}${className ? ' ' + className : ''}`}
          onEscapeKeyDown={block}
          onPointerDownOutside={block}
          onInteractOutside={block}
          aria-describedby={undefined}
        >
          <Dialog.Title className={titleHidden ? 'modal-sr-only' : 'modal-title'}>
            {title}
          </Dialog.Title>
          {children}
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  )
}
```

- [ ] **Step 2: `web/src/components/Modal.css` 전면 재작성**

파일 전체를 아래 내용으로 **교체**한다(기존 내용 전부 삭제):

```css
/* 공용 모달 스타일 단일 소스 — components/Modal.jsx가 소유.
   ⚠️ 모달은 Radix Portal로 <body> 직속에 렌더된다 = 페이지 CSS가 안 닿는다.
      따라서 폰트처럼 예전에 페이지에서 흘러들어오던 값도 여기서 직접 박아야 한다.
      (구 .btn-login/.btn-signup-nav 재활용 및 .home-wrap 특이도 싸움은 이 파일에서 제거됨) */

/* ── 오버레이(스크림) ── */
.modal-overlay {
  position: fixed;
  inset: 0;
  z-index: 999;
  background: var(--scrim);
  animation: modal-fade 0.18s ease;
}
@keyframes modal-fade {
  from { opacity: 0; }
  to   { opacity: 1; }
}

/* ── 카드 ── */
.modal {
  position: fixed;
  left: 50%;
  top: 50%;
  transform: translate(-50%, -50%);
  z-index: 1000;

  box-sizing: border-box;
  max-width: calc(100vw - 40px);          /* 좁은 화면에서 가장자리에 안 붙게 */
  max-height: calc(100svh - 40px);
  overflow-y: auto;

  padding: 24px 22px;
  border-radius: 16px;
  background: var(--card);
  box-shadow: 0 20px 40px rgba(0, 0, 0, 0.15);

  font-family: var(--sans);               /* ⚠️ Portal 이후 페이지 폰트 규칙이 안 닿음 — 필수 */
  color: var(--text);
  text-align: center;

  animation: modal-rise 0.22s ease;
  outline: none;
}
@keyframes modal-rise {
  from { opacity: 0; transform: translate(-50%, calc(-50% + 16px)); }
  to   { opacity: 1; transform: translate(-50%, -50%); }
}

/* 폭 3종 — 값은 index.css 토큰 */
.modal-sm { width: var(--modal-w-sm); }
.modal-md { width: var(--modal-w-md); }
.modal-lg { width: var(--modal-w-lg); }

/* 모션 저감 선호 존중 (전정장애 등) */
@media (prefers-reduced-motion: reduce) {
  .modal, .modal-overlay { animation: none; }
}

/* ── 제목 ── */
/* 스크린리더 전용(화면엔 안 보임). Radix는 Dialog.Title이 없으면 경고한다 */
.modal-sr-only {
  position: absolute;
  width: 1px; height: 1px;
  padding: 0; margin: -1px;
  overflow: hidden;
  clip-path: inset(50%);
  white-space: nowrap;
}
/* 화면에 보이는 제목 (titleHidden={false}) */
.modal-title {
  margin: 0 0 10px;
  font-size: 16px;
  font-weight: 700;
  color: var(--text-h);
}

/* ── 아이콘(원형 배지) — 로그인 유도 모달 등 ── */
.modal-icon {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 56px;
  height: 56px;
  border-radius: 50%;
  background: var(--primary-light);
  color: var(--primary-dark);
  margin-bottom: 16px;
}

/* ── 본문 ── */
.modal-text {
  font-size: 15px;
  font-weight: 600;
  margin: 0 0 20px;
  color: var(--text);
  line-height: 1.55;
}
/* 제목+설명 패턴: <strong>제목</strong> 뒤에 설명문을 주면 제목이 한 줄 차지 */
.modal-text strong {
  display: block;
  margin-bottom: 8px;
}

/* ── 버튼 ──
   위계는 색이 아니라 '채움 여부'로 잡는다:
     취소 = 항상 아웃라인 · 확인 = 항상 채움(색만 intent).
   이래야 확인이 회색(neutral)일 때도 취소와 안 헷갈린다. */
.modal-actions {
  display: flex;
  gap: 8px;
  justify-content: flex-end;
}

.modal-btn {
  padding: 10px 18px;
  border: 1px solid transparent;
  border-radius: 8px;
  font-family: var(--sans);     /* ⚠️ 필수 — Portal 이후 .form-wrap button의 폰트가 안 닿는다 */
  font-size: 14px;
  font-weight: 600;
  line-height: 1.2;
  cursor: pointer;
  transition: filter 0.15s, background 0.15s;
}
.modal-btn:disabled { opacity: 0.45; cursor: default; }

/* 취소 — 아웃라인. 색으로 경쟁하지 않는다 */
.modal-btn-cancel {
  background: transparent;
  border-color: var(--border-strong);
  color: var(--text-sub);
}
.modal-btn-cancel:not(:disabled):hover { background: var(--surface); }

/* 확인 — 채움. 색만 intent에 따라 */
.modal-btn.is-primary { background: var(--primary);  color: #fff; }
.modal-btn.is-neutral { background: var(--text-sub); color: #fff; }
.modal-btn.is-danger  { background: var(--danger);   color: #fff; }
.modal-btn.is-primary:not(:disabled):hover,
.modal-btn.is-neutral:not(:disabled):hover,
.modal-btn.is-danger:not(:disabled):hover { filter: brightness(1.06); }
```

- [ ] **Step 3: 빌드·린트**

```bash
cd web
npm run build && npm run lint
```

Expected: 둘 다 성공. (`Modal.jsx`를 아직 아무도 import하지 않으므로 화면 변화 없음. 기존 모달들은 이 시점에 스타일이 깨져 있다 — Task 4~9에서 해소된다.)

- [ ] **Step 4: 커밋**

```bash
cd "c:/새 폴더"
git add web/src/components/Modal.jsx web/src/components/Modal.css
git commit -m "feat(modal): Radix 기반 공용 셸 Modal.jsx + Modal.css 재작성

Portal로 <body> 직속 렌더 → 페이지 CSS 유출 차단.
폭 3종·스크림 1종·버튼 3종(취소=아웃라인/확인=채움).
네비바 버튼(.btn-login/.btn-signup-nav) 의존 제거."
```

---

## Task 4: `ConfirmModal` 전환 + 호출부 5곳 intent 지정

문제 3(위험색)이 여기서 해결된다. `className` 탈출구도 여기서 없앤다(현재 넘기는 호출부가 없음을 확인했다 — 죽은 prop).

**Files:**
- Rewrite: `web/src/components/ConfirmModal.jsx`
- Modify: `web/src/components/AccountMenu.jsx` (로그아웃 → `neutral`)
- Modify: `web/src/components/AccountMenu.css` (빨간 '로그아웃' 글자 → 중립)
- Modify: `web/src/pages/MyPage.jsx` (리뷰 삭제 → `danger`, 열람권 사용 → `primary`, 로그아웃 → `neutral`)
- Modify: `web/src/pages/ExchangeCenter.jsx` (교환·사용 → `primary`, 환불 → `neutral`)
- Modify: `web/src/pages/WorksiteDetail.jsx` (리뷰 삭제 → `danger`)
- Modify: `web/src/pages/ReviewForm.jsx` (익명 제출/수정 → `primary`)

**Interfaces:**
- Consumes: `Modal`(Task 3)
- Produces: `<ConfirmModal message confirmText intent onConfirm onCancel />` — `intent`: `'primary' | 'neutral' | 'danger'`, 기본 `'primary'`. **`className` prop 없음.**

- [ ] **Step 1: `ConfirmModal.jsx` 전면 교체**

```jsx
import Modal from './Modal'

// 확인/취소 모달 — 리뷰 삭제·로그아웃·열람권 교환/사용/환불·익명 제출에 재사용.
//
// intent = 확인 버튼의 성격. 취소 버튼은 언제나 아웃라인이라 색으로 안 싸운다.
//   primary(파랑)  되돌릴 수 있거나 권장되는 진행 — 교환·사용·익명 제출
//   neutral(회색)  권장하지도 위험하지도 않은 것 — 로그아웃·환불
//   danger(빨강)   되돌릴 수 없는 상실 — 리뷰 삭제·회원 탈퇴
//
// ⚠️ className prop을 다시 만들지 말 것. 페이지별 스타일 주입 통로가 되는 순간 모달이 다시 갈라진다.
//    변형이 필요하면 intent처럼 '정해진 값'으로만 늘린다.
export default function ConfirmModal({
  message,
  confirmText = '확인',
  intent = 'primary',
  onConfirm,
  onCancel,
}) {
  return (
    <Modal
      open
      onOpenChange={(next) => { if (!next) onCancel() }}
      size="sm"
      title={confirmText}
    >
      <p className="modal-text">{message}</p>
      <div className="modal-actions">
        <button className="modal-btn modal-btn-cancel" onClick={onCancel}>취소</button>
        <button className={`modal-btn is-${intent}`} onClick={onConfirm}>{confirmText}</button>
      </div>
    </Modal>
  )
}
```

⚠️ `confirmText`의 기본값을 `'삭제'` → `'확인'`으로 바꿨다. 옛 기본값은 위험했다(intent를 안 주면 아무 확인 모달이나 "삭제"라고 뜸). **`WorksiteDetail`은 `confirmText`를 안 넘기고 있었으므로 Step 5에서 명시적으로 넘겨야 한다.**

- [ ] **Step 2: `AccountMenu.jsx` — 로그아웃을 neutral로**

`web/src/components/AccountMenu.jsx`의 `askLogout` 안 `setConfirm({...})`에 `intent`를 추가한다:

```jsx
  function askLogout() {
    setOpen(false)
    setConfirm({
      message: '로그아웃하시겠습니까?',
      confirmText: '로그아웃',
      intent: 'neutral',          // 되돌릴 수 있는 행동 — 빨강 아님
      // scope:'local' — 이 브라우저만 로그아웃. 인자를 안 주면 auth-js 기본이 'global'이라
      // 학교 PC에서 로그아웃했을 뿐인데 집의 폰 세션까지 끊긴다.
      action: () => { logout({ scope: 'local' }); navigate('/login') },
    })
  }
```

그리고 아래쪽 `<ConfirmModal ... />`에 `intent`를 전달한다:

```jsx
      {confirm && (
        <ConfirmModal
          message={confirm.message}
          confirmText={confirm.confirmText}
          intent={confirm.intent}
          onConfirm={runConfirm}
          onCancel={() => setConfirm(null)}
        />
      )}
```

- [ ] **Step 2b: `AccountMenu.css` — 빨간 '로그아웃' 글자를 중립으로**

드롭다운의 로그아웃 메뉴 글자가 빨강(`--danger`)인데, 확인 모달의 로그아웃 버튼은 이제 neutral이다. **앞뒤가 안 맞으므로 글자도 중립으로 내린다.** 빨강은 리뷰 삭제·회원 탈퇴에만 남긴다(그래야 진짜 위험할 때 눈에 띈다).

`web/src/components/AccountMenu.css:47`을 바꾼다:

```css
/* 로그아웃 — 되돌릴 수 있는 행동이라 위험색(빨강)을 쓰지 않는다.
   빨강은 리뷰 삭제·회원 탈퇴처럼 '되돌릴 수 없는 상실'에만. (모달 intent 규칙과 일치) */
.acct-logout { color: var(--text-sub); }
```

- [ ] **Step 3: `MyPage.jsx` — ask()에 intent 추가**

`ask` 시그니처에 `intent`를 넣는다 (`web/src/pages/MyPage.jsx:279`):

```jsx
  function ask(message, confirmText, intent, action) {
    setConfirm({ message, confirmText, intent, action })
  }
```

호출부 3곳을 고친다:

```jsx
  function handleUseTicket(days) {
    ask(`${days}일 열람권을 지금 사용할까요? 사용하면 기존 만료에 ${days}일이 더해져요.`, '사용', 'primary', async () => {
```

```jsx
  function removeReview(reviewId) {
    ask('이 리뷰를 삭제할까요? (적립한 포인트가 회수됩니다)', '삭제', 'danger', async () => {
```

```jsx
          {/* scope:'local' — 이 브라우저만. 기본값 'global'은 다른 기기 세션까지 끊는다 */}
          <button className="my-logout" onClick={() => ask('로그아웃하시겠습니까?', '로그아웃', 'neutral', () => { logout({ scope: 'local' }); navigate('/login') })}>로그아웃</button>
```

⚠️ **`{ scope: 'local' }`을 빼지 말 것.** 최근 main에서 고쳐진 부분이라, 인자를 빼면 "학교 PC에서 로그아웃 → 집 폰 세션도 끊김" 버그가 되살아난다.

그리고 렌더부(`MyPage.jsx:386`)에 `intent`를 전달한다:

```jsx
        <ConfirmModal
          message={confirm.message}
          confirmText={confirm.confirmText}
          intent={confirm.intent}
          onConfirm={() => { const a = confirm.action; setConfirm(null); runAction(a) }}
          onCancel={() => setConfirm(null)}
        />
```

- [ ] **Step 4: `ExchangeCenter.jsx` — ask()에 intent 추가**

`ask` 시그니처 (`web/src/pages/ExchangeCenter.jsx:88`):

```jsx
  // 확인 모달을 띄우고, 확인 시 run(action) 실행
  function ask(message, confirmText, intent, action) {
    setConfirm({ message, confirmText, intent, action })
  }
```

호출부 3곳 (`ExchangeCenter.jsx:136-140`):

```jsx
                    <button className="tk-btn" disabled={busy || stock < 1} onClick={() => ask(`${d}일 열람권을 지금 사용할까요? 사용하면 지금부터 ${d}일간 열람할 수 있어요.`, '사용', 'primary', () => activatePass(d))}>사용하기</button>
                    <button className="tk-btn tk-btn-buy" disabled={busy} onClick={() => ask(`${d}일 열람권을 ${passPrice(d)}P로 교환할까요?`, '교환', 'primary', () => purchasePass(d))}>교환하기</button>
```

```jsx
                    <button className="tk-refund" disabled={busy} onClick={() => ask(`미사용 ${d}일 열람권 1장을 환불할까요? ${passPrice(d)}P가 환급돼요.`, '환불', 'neutral', () => refundPass(d))}>
```

렌더부(`ExchangeCenter.jsx:173`)에 `intent` 전달:

```jsx
        <ConfirmModal
          message={confirm.message}
          confirmText={confirm.confirmText}
          intent={confirm.intent}
          onConfirm={() => { const a = confirm.action; setConfirm(null); run(a) }}
          onCancel={() => setConfirm(null)}
        />
```

- [ ] **Step 5: `WorksiteDetail.jsx` — 리뷰 삭제를 danger로**

`web/src/pages/WorksiteDetail.jsx:155`. **`confirmText`가 없었으므로 반드시 명시한다**(ConfirmModal 기본값이 '확인'으로 바뀌었기 때문):

```jsx
      {confirm && (
        <ConfirmModal
          message="이 리뷰를 삭제할까요? (적립한 15P가 회수됩니다)"
          confirmText="삭제"
          intent="danger"
          onConfirm={doDelete}
          onCancel={() => setConfirm(null)}
        />
      )}
```

- [ ] **Step 6: `ReviewForm.jsx` — 익명 제출을 primary로**

`web/src/pages/ReviewForm.jsx:428`에 `intent="primary"`를 추가한다(나머지는 그대로):

```jsx
        <ConfirmModal
          confirmText="제출"
          intent="primary"
          message={
```

- [ ] **Step 7: 빌드·린트·기존 테스트**

```bash
cd web
npm run build && npm run lint && npm test
```

Expected: 전부 통과. `npm test`는 `lib/` 순수 함수 테스트 — 이 태스크와 무관하므로 그대로 통과해야 한다.

- [ ] **Step 8: 손으로 확인**

```bash
cd web
npm run dev
```

로그인 후 교환센터에서 '교환하기'를 눌러 확인 모달이 뜨는지 본다. 확인할 것:
- 확인 버튼이 **파랑(채움)**, 취소가 **회색 아웃라인**
- **Esc로 닫힌다**
- 배경이 스크롤 안 된다
- 닫으면 원래 눌렀던 '교환하기' 버튼으로 **포커스가 돌아온다**

- [ ] **Step 9: 커밋**

```bash
cd "c:/새 폴더"
git add web/src/components/ConfirmModal.jsx web/src/components/AccountMenu.jsx web/src/components/AccountMenu.css web/src/pages/MyPage.jsx web/src/pages/ExchangeCenter.jsx web/src/pages/WorksiteDetail.jsx web/src/pages/ReviewForm.jsx
git commit -m "feat(modal): ConfirmModal을 공용 셸로 + intent 3종(primary/neutral/danger)

리뷰 삭제·회원 탈퇴만 danger, 로그아웃·환불은 neutral, 나머지 primary.
계정 드롭다운의 빨간 '로그아웃' 글자도 중립으로 — 모달 intent 규칙과 일치.
className 탈출구 제거(죽은 prop) — 페이지별 스타일 주입 통로 차단."
```

---

## Task 5: 갤러리 `/dev/modals` 초판

여기서 갤러리를 세우면 **이후 태스크를 전부 갤러리로 검증**할 수 있다. 그래서 모달을 다 옮기기 전에 만든다.

**Files:**
- Create: `web/src/pages/DevModals.jsx`
- Create: `web/src/pages/DevModals.css`
- Modify: `web/src/App.jsx` (DEV 전용 라우트)

**Interfaces:**
- Consumes: `ConfirmModal`(Task 4)
- Produces: `/dev/modals` 라우트. Task 6~9가 이 파일에 항목을 추가한다.

- [ ] **Step 1: `web/src/pages/DevModals.jsx` 생성**

```jsx
import { useState } from 'react'
import ConfirmModal from '../components/ConfirmModal'
import './DevModals.css'

// 개발용 모달 갤러리 — 모달 전종을 한자리에서 띄워보고 디자인을 비교한다.
// ⚠️ DEV 전용. App.jsx가 import.meta.env.DEV로 감싸 실서비스 빌드에서 제거한다.
//
// 이 갤러리가 '실제와 같다'고 믿을 수 있는 이유:
//   모달이 Radix Portal로 <body> 직속에 렌더 → 페이지 CSS(.home-wrap button 등)가 안 닿는다.
//   즉 어느 페이지에서 띄우든 모양이 같다. (Portal 이전엔 페이지마다 달랐다.)
// Portal로도 안 막히는 것 3개는 여기서 직접 막는다:
//   ① className 주입 → 모달 컴포넌트에서 prop 자체를 없앰
//   ② 콘텐츠 길이 → 아래 LONG_MSG·JSX 메시지로 최악 케이스를 기본 노출
//   ③ 뷰포트 → 폭 전환 버튼(360/768/데스크톱)

// 최악 케이스 텍스트 — 짧은 더미만 보면 실제에서 깨지는 걸 놓친다
const LONG_MSG =
  '고려대학교 세종캠퍼스 과학기술대학 컴퓨터정보학과 행정실 근로장학생 리뷰를 삭제할까요? ' +
  '(적립한 15P가 회수됩니다)'

const JSX_MSG = (
  <>
    <strong>익명으로 수정할까요?</strong>
    적립된 10P가 회수돼요.
  </>
)

const WIDTHS = [
  { label: '360 (모바일)', value: 360 },
  { label: '768 (태블릿)', value: 768 },
  { label: '데스크톱', value: 0 },   // 0 = 제한 없음
]

export default function DevModals() {
  const [open, setOpen] = useState(null)   // 열린 항목의 id
  const [width, setWidth] = useState(0)

  const close = () => setOpen(null)

  // 갤러리 항목 — { id, label, render }
  const ITEMS = [
    {
      id: 'confirm-primary',
      label: '확인 — primary (열람권 교환)',
      render: () => (
        <ConfirmModal
          message="30일 열람권을 300P로 교환할까요?"
          confirmText="교환"
          intent="primary"
          onConfirm={close}
          onCancel={close}
        />
      ),
    },
    {
      id: 'confirm-neutral',
      label: '확인 — neutral (로그아웃)',
      render: () => (
        <ConfirmModal
          message="로그아웃하시겠습니까?"
          confirmText="로그아웃"
          intent="neutral"
          onConfirm={close}
          onCancel={close}
        />
      ),
    },
    {
      id: 'confirm-danger',
      label: '확인 — danger (리뷰 삭제)',
      render: () => (
        <ConfirmModal
          message="이 리뷰를 삭제할까요? (적립한 15P가 회수됩니다)"
          confirmText="삭제"
          intent="danger"
          onConfirm={close}
          onCancel={close}
        />
      ),
    },
    {
      id: 'confirm-long',
      label: '확인 — 긴 텍스트 (최악 케이스)',
      render: () => (
        <ConfirmModal
          message={LONG_MSG}
          confirmText="삭제"
          intent="danger"
          onConfirm={close}
          onCancel={close}
        />
      ),
    },
    {
      id: 'confirm-jsx',
      label: '확인 — JSX 메시지 (제목+설명)',
      render: () => (
        <ConfirmModal
          message={JSX_MSG}
          confirmText="제출"
          intent="primary"
          onConfirm={close}
          onCancel={close}
        />
      ),
    },
  ]

  const active = ITEMS.find((i) => i.id === open)

  return (
    <div className="dev-wrap">
      <header className="dev-head">
        <h1>모달 갤러리</h1>
        <p className="dev-sub">
          DEV 전용. 실제 컴포넌트를 그대로 렌더한다 — Modal.css를 고치면 여기에 즉시 반영된다.
        </p>
        <div className="dev-widths">
          {WIDTHS.map((w) => (
            <button
              key={w.value}
              className={`dev-width${width === w.value ? ' is-on' : ''}`}
              onClick={() => setWidth(w.value)}
            >
              {w.label}
            </button>
          ))}
        </div>
      </header>

      <div
        className="dev-stage"
        style={width ? { maxWidth: `${width}px` } : undefined}
      >
        <ul className="dev-list">
          {ITEMS.map((item) => (
            <li key={item.id}>
              <button className="dev-item" onClick={() => setOpen(item.id)}>
                {item.label}
              </button>
            </li>
          ))}
        </ul>
      </div>

      {active?.render()}
    </div>
  )
}
```

⚠️ 폭 전환은 **갤러리 스테이지의 `max-width`만 줄인다.** 모달 자체는 Portal로 `<body>`에 붙어 있어 스테이지 밖에 뜬다 — 즉 이 버튼으로는 모달의 반응형을 못 본다. **모달의 모바일 폭은 브라우저 창을 실제로 줄이거나 devtools의 기기 모드로 확인해야 한다.** (Step 4에서 그렇게 확인한다.)

- [ ] **Step 2: `web/src/pages/DevModals.css` 생성**

```css
/* 개발용 모달 갤러리 (DEV 전용) — 실서비스 빌드에 안 실림 */

.dev-wrap {
  max-width: var(--container);
  margin: 0 auto;
  padding: 32px var(--container-pad) 80px;
  font-family: var(--sans);
}

.dev-head h1 {
  margin: 0 0 6px;
  font-size: 24px;
  color: var(--text-h);
}
.dev-sub {
  margin: 0 0 18px;
  color: var(--text-sub);
  font-size: 14px;
  line-height: 1.6;
}

.dev-widths { display: flex; gap: 8px; margin-bottom: 24px; }
.dev-width {
  padding: 7px 14px;
  border: 1px solid var(--border);
  border-radius: 999px;
  background: var(--card);
  color: var(--text-sub);
  font-family: var(--sans);
  font-size: 13px;
  font-weight: 600;
  cursor: pointer;
}
.dev-width.is-on {
  border-color: var(--primary);
  background: var(--primary-light);
  color: var(--primary-dark);
}

.dev-stage {
  border: 1px dashed var(--border-strong);
  border-radius: 12px;
  padding: 20px;
  background: var(--card);
}

.dev-list { list-style: none; margin: 0; padding: 0; display: grid; gap: 8px; }

.dev-item {
  width: 100%;
  text-align: left;
  padding: 12px 14px;
  border: 1px solid var(--border);
  border-radius: var(--card-radius);
  background: var(--bg);
  color: var(--text);
  font-family: var(--sans);
  font-size: 14px;
  font-weight: 600;
  cursor: pointer;
}
.dev-item:hover { border-color: var(--primary-mid); background: var(--primary-light); }
```

- [ ] **Step 3: `App.jsx`에 DEV 전용 라우트 등록**

`web/src/App.jsx` 상단 import에 추가:

```jsx
import Terms from './pages/Terms'
import DevModals from './pages/DevModals'
import './App.css'
```

그리고 `AppLayout` 레이아웃 라우트 블록 안, `/terms` 줄 아래에 추가:

```jsx
          <Route path="/terms" element={<Terms />} />
          {/* 개발용 모달 갤러리 — import.meta.env.DEV가 false면 Vite가 통째로 제거(실서비스 빌드에 없음) */}
          {import.meta.env.DEV && <Route path="/dev/modals" element={<DevModals />} />}
```

- [ ] **Step 4: 갤러리 확인**

```bash
cd web
npm run dev
```

브라우저에서 `http://localhost:5173/dev/modals` 를 연다. 확인할 것:
- 항목 5개가 뜨고, 클릭하면 각 모달이 뜬다
- **파랑·회색·빨강이 나란히 있을 때 위계가 사는가** (확인 버튼이 채워져 있고 취소가 아웃라인이라 구분되는가)
- 긴 텍스트 항목에서 카드가 안 깨지는가
- JSX 메시지 항목에서 제목이 한 줄 차지하는가
- **브라우저 창을 360px까지 줄여** 모달이 화면 밖으로 안 넘치는지 본다 (`max-width: calc(100vw - 40px)`가 먹는지)

- [ ] **Step 5: 실서비스 빌드에서 제거되는지 확인**

```bash
cd web
npm run build
grep -r "모달 갤러리" dist/assets/ || echo "OK: 갤러리가 프로덕션 번들에 없음"
```

Expected: `OK: 갤러리가 프로덕션 번들에 없음`

- [ ] **Step 6: 커밋**

```bash
cd "c:/새 폴더"
git add web/src/pages/DevModals.jsx web/src/pages/DevModals.css web/src/App.jsx
git commit -m "feat(dev): 모달 갤러리 /dev/modals (DEV 전용)

실제 컴포넌트를 그대로 렌더 — Portal 덕에 갤러리=실제가 보장됨.
최악 케이스(긴 텍스트·JSX 메시지)를 기본 노출."
```

---

## Task 6: 홈 로그인 유도 모달을 `LoginPromptModal`로 승격

지금은 `Home.jsx`에 인라인으로 박혀 있어 **갤러리에 올릴 수가 없다.** 컴포넌트로 빼야 갤러리에 올라가고 재사용도 된다.

**Files:**
- Create: `web/src/components/LoginPromptModal.jsx`
- Modify: `web/src/pages/Home.jsx` (인라인 모달 제거, `import '../components/Modal.css'` 제거)
- Modify: `web/src/pages/DevModals.jsx` (갤러리 항목 추가)

**Interfaces:**
- Consumes: `Modal`(Task 3)
- Produces: `<LoginPromptModal onClose />` — "로그인하러 가기"는 컴포넌트가 직접 `/login`으로 이동한다.

- [ ] **Step 1: `web/src/components/LoginPromptModal.jsx` 생성**

```jsx
import { useNavigate } from 'react-router-dom'
import Modal from './Modal'

// 비로그인 사용자가 잠긴 기능을 눌렀을 때 뜨는 로그인 유도 모달.
// 홈의 잠긴 카드에서 사용. (구 Home.jsx 인라인 모달 — 갤러리에 올리고 재사용하려고 승격)
export default function LoginPromptModal({ onClose }) {
  const navigate = useNavigate()

  return (
    <Modal
      open
      onOpenChange={(next) => { if (!next) onClose() }}
      size="sm"
      title="로그인이 필요한 기능이에요"
    >
      <div className="modal-icon">
        <svg viewBox="0 0 24 24" width="32" height="32" fill="none" stroke="currentColor"
             strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
          <rect x="5" y="11" width="14" height="9" rx="2"></rect>
          <path d="M8.5 11V8a3.5 3.5 0 0 1 7 0v3"></path>
        </svg>
      </div>
      <p className="modal-text">로그인이 필요한 기능이에요</p>
      <div className="modal-actions">
        <button className="modal-btn modal-btn-cancel" onClick={onClose}>닫기</button>
        <button className="modal-btn is-primary" onClick={() => navigate('/login')}>
          로그인하러 가기
        </button>
      </div>
    </Modal>
  )
}
```

- [ ] **Step 2: `Home.jsx`에서 인라인 모달 제거**

`web/src/pages/Home.jsx:10`의 `import '../components/Modal.css'` 줄을 **삭제**하고, 대신 컴포넌트를 import한다:

```jsx
import LoginPromptModal from '../components/LoginPromptModal'
```

그리고 `Home.jsx:658-674`의 인라인 모달 블록 전체를 아래로 **교체**한다:

```jsx
      {showLoginModal && (
        <LoginPromptModal onClose={() => setShowLoginModal(false)} />
      )}
```

- [ ] **Step 3: 갤러리에 항목 추가**

`web/src/pages/DevModals.jsx` 상단 import에 추가:

```jsx
import LoginPromptModal from '../components/LoginPromptModal'
```

`ITEMS` 배열 끝(`confirm-jsx` 항목 뒤)에 추가:

```jsx
    {
      id: 'login-prompt',
      label: '로그인 유도',
      render: () => <LoginPromptModal onClose={close} />,
    },
```

- [ ] **Step 4: 빌드·린트·확인**

```bash
cd web
npm run build && npm run lint && npm run dev
```

확인할 것:
- `/dev/modals`에서 '로그인 유도' 항목이 뜨고, 자물쇠 아이콘 배지가 보인다
- **로그아웃 상태로 홈(`/home`)** 에서 잠긴 카드를 눌러 같은 모달이 뜨는지 본다
- **갤러리와 홈에서 모양이 같은가** — 이게 Portal이 CSS 유출을 막았다는 증거다. (Portal 이전이라면 `.home-wrap button { background: white }`가 버튼을 덮쳤을 것이다.)

- [ ] **Step 5: 커밋**

```bash
cd "c:/새 폴더"
git add web/src/components/LoginPromptModal.jsx web/src/pages/Home.jsx web/src/pages/DevModals.jsx
git commit -m "refactor(modal): 홈 로그인 유도 모달을 LoginPromptModal 컴포넌트로 승격

인라인이라 갤러리에 못 올리던 것 → 컴포넌트화 + 갤러리 등록."
```

---

## Task 7: `ReportModal` 전환 (인라인 style 제거 + 라디오 스타일)

문제 6이 여기서 해결된다.

**Files:**
- Rewrite: `web/src/components/ReportModal.jsx`
- Modify: `web/src/components/Modal.css` (신고 라디오 스타일 추가)
- Modify: `web/src/pages/DevModals.jsx` (갤러리 항목 추가)

**Interfaces:**
- Consumes: `Modal`(Task 3)
- Produces: `<ReportModal onSubmit={(reason) => void} onCancel />` — 시그니처 변화 없음(호출부 `WorksiteDetail.jsx:162` 그대로).

- [ ] **Step 1: `ReportModal.jsx` 전면 교체**

```jsx
import { useState } from 'react'
import Modal from './Modal'

const REASONS = ['허위/과장 후기', '욕설/비방', '광고/스팸', '개인정보 노출', '기타']

// 리뷰 신고 모달. 사유 하나를 골라 제출.
// (구버전은 인라인 style + 네이티브 라디오라 CSS를 고쳐도 혼자 안 따라왔다 → 전부 클래스로)
export default function ReportModal({ onSubmit, onCancel }) {
  const [reason, setReason] = useState(REASONS[0])

  return (
    <Modal
      open
      onOpenChange={(next) => { if (!next) onCancel() }}
      size="md"
      title="신고 사유를 선택해주세요"
      titleHidden={false}
    >
      <div className="rp-list" role="radiogroup" aria-label="신고 사유">
        {REASONS.map((r) => (
          <label key={r} className={`rp-option${reason === r ? ' is-on' : ''}`}>
            <input
              type="radio"
              name="report-reason"
              className="rp-radio"
              checked={reason === r}
              onChange={() => setReason(r)}
            />
            <span>{r}</span>
          </label>
        ))}
      </div>

      <div className="modal-actions">
        <button className="modal-btn modal-btn-cancel" onClick={onCancel}>취소</button>
        <button className="modal-btn is-danger" onClick={() => onSubmit(reason)}>신고</button>
      </div>
    </Modal>
  )
}
```

⚠️ 신고 버튼은 `danger`다 — 남의 리뷰에 조치가 들어가는 되돌리기 어려운 행동이라 스펙의 danger 정의("되돌릴 수 없는 상실")에 맞는다.

- [ ] **Step 2: `Modal.css` 끝에 신고 라디오 스타일 추가**

`web/src/components/Modal.css` 맨 아래에 덧붙인다:

```css
/* ── 신고 모달 (ReportModal) — 사유 라디오 목록 ──
   네이티브 라디오 대신 행 전체가 선택 타깃. 카드는 가운데 정렬이지만 목록은 왼쪽. */
.rp-list {
  display: grid;
  gap: 6px;
  margin: 0 0 20px;
  text-align: left;
}

.rp-option {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px 12px;
  border: 1px solid var(--border);
  border-radius: var(--card-radius);
  font-size: 14px;
  color: var(--text);
  cursor: pointer;
  transition: border-color 0.15s, background 0.15s;
}
.rp-option:hover { border-color: var(--border-strong); }
.rp-option.is-on {
  border-color: var(--primary);
  background: var(--primary-light);
  color: var(--primary-deep);
  font-weight: 600;
}

.rp-radio {
  appearance: none;
  flex: none;
  width: 16px;
  height: 16px;
  margin: 0;
  border: 1.5px solid var(--border-strong);
  border-radius: 50%;
  cursor: pointer;
}
.rp-radio:checked {
  border-color: var(--primary);
  border-width: 5px;   /* 가운데가 점처럼 보이게 */
}
.rp-radio:focus-visible {
  outline: 2px solid var(--primary);
  outline-offset: 2px;
}
```

- [ ] **Step 3: 갤러리에 항목 추가**

`web/src/pages/DevModals.jsx` import에 추가:

```jsx
import ReportModal from '../components/ReportModal'
```

`ITEMS` 배열 끝에 추가:

```jsx
    {
      id: 'report',
      label: '신고 (md · 라디오 5개)',
      render: () => <ReportModal onSubmit={close} onCancel={close} />,
    },
```

- [ ] **Step 4: 빌드·린트·확인**

```bash
cd web
npm run build && npm run lint && npm run dev
```

`/dev/modals`에서 '신고' 항목을 열어 확인:
- 카드가 **md(400px)** 라 라디오 5개가 답답하지 않다
- 행을 클릭하면 선택된다(행 전체가 타깃)
- **키보드 방향키로 라디오를 옮길 수 있다**(네이티브 radio 동작 유지)
- Tab 포커스 링이 보인다

- [ ] **Step 5: 커밋**

```bash
cd "c:/새 폴더"
git add web/src/components/ReportModal.jsx web/src/components/Modal.css web/src/pages/DevModals.jsx
git commit -m "feat(modal): ReportModal 공용 셸 전환 — 인라인 style 제거, 라디오 CSS 클래스화

혼자 CSS를 안 따라오던 문제 해소. 폭 md(400)로 라디오 5개 여유."
```

---

## Task 8: `WithdrawModal` 전환

**Files:**
- Rewrite: `web/src/components/WithdrawModal.jsx`
- Modify: `web/src/components/Modal.css` (`.modal-withdraw` 블록을 새 셸에 맞게 재작성 — Task 3에서 옛 블록은 이미 삭제됨)
- Modify: `web/src/pages/DevModals.jsx` (기본·에러·로딩 3상태 등록)

**Interfaces:**
- Consumes: `Modal`(Task 3)
- Produces: `<WithdrawModal onConfirm={() => Promise} onCancel />` — 시그니처 변화 없음(호출부 `MyPage.jsx:193` 그대로).

- [ ] **Step 1: `WithdrawModal.jsx` 전면 교체**

```jsx
import { useState } from 'react'
import Modal from './Modal'

const CONFIRM_PHRASE = '탈퇴합니다'

// 회원 탈퇴 확인 모달 — 되돌릴 수 없어(유예 없음) 문구 타이핑으로 이중 확인.
// 사라지는 것 안내 + "탈퇴합니다" 정확 입력 시에만 버튼 활성. onConfirm: 부모가 deleteAccount 실행.
export default function WithdrawModal({ onConfirm, onCancel }) {
  const [phrase, setPhrase] = useState('')
  const [loading, setLoading] = useState(false)
  const [err, setErr] = useState('')

  const canConfirm = phrase.trim() === CONFIRM_PHRASE && !loading

  async function handleConfirm() {
    if (!canConfirm) return
    setLoading(true); setErr('')
    try {
      await onConfirm()   // 성공 시 부모가 리다이렉트 → 이 모달은 언마운트됨
    } catch {
      setErr('탈퇴 처리 중 오류가 났어요. 잠시 후 다시 시도해 주세요.')
      setLoading(false)
    }
  }

  return (
    <Modal
      open
      // 탈퇴 처리 중엔 Esc·배경클릭으로 못 닫는다 (RPC가 도는 중에 모달만 사라지면 사용자가 혼란)
      dismissible={!loading}
      onOpenChange={(next) => { if (!next && !loading) onCancel() }}
      size="md"
      title="정말 탈퇴하시겠어요?"
      titleHidden={false}
      className="modal-withdraw"
    >
      <ul className="mw-list">
        <li>작성한 리뷰는 <b>&quot;탈퇴한 사용자&quot;</b>로 익명 처리돼요(내용은 남아요).</li>
        <li>보유 <b>포인트·열람권은 모두 소멸</b>돼요.</li>
        <li>같은 이메일로는 <b>30일간 재가입할 수 없어요</b>.</li>
        <li><b>되돌릴 수 없어요.</b></li>
      </ul>

      <label className="mw-label" htmlFor="mw-phrase">
        확인을 위해 <b>{CONFIRM_PHRASE}</b> 를 입력해 주세요
      </label>
      <input
        id="mw-phrase"
        className="mw-input"
        value={phrase}
        onChange={(e) => setPhrase(e.target.value)}
        placeholder={CONFIRM_PHRASE}
        disabled={loading}
        autoFocus
      />
      {err && <p className="mw-err">{err}</p>}

      <div className="modal-actions">
        <button className="modal-btn modal-btn-cancel" onClick={onCancel} disabled={loading}>
          취소
        </button>
        <button className="modal-btn is-danger" onClick={handleConfirm} disabled={!canConfirm}>
          {loading ? '탈퇴 중…' : '탈퇴하기'}
        </button>
      </div>
    </Modal>
  )
}
```

- [ ] **Step 2: `Modal.css` 끝에 탈퇴 모달 스타일 추가**

```css
/* ── 회원 탈퇴 모달 (WithdrawModal) — 안내 리스트 + 문구 입력 ──
   버튼은 공용 .modal-btn.is-danger를 쓴다(옛 .mw-danger는 제거됨). */
.modal-withdraw { text-align: left; }

.modal-withdraw .mw-list {
  margin: 0 0 14px;
  padding-left: 18px;
  font-size: 13px;
  color: var(--text-sub);
  line-height: 1.6;
}
.modal-withdraw .mw-list b { color: var(--text); }

.modal-withdraw .mw-label {
  display: block;
  font-size: 13px;
  color: var(--text-sub);
  margin-bottom: 6px;
}

.modal-withdraw .mw-input {
  width: 100%;
  box-sizing: border-box;
  padding: 9px 11px;
  border: 1px solid var(--border);
  border-radius: var(--card-radius);
  font-family: var(--sans);   /* ⚠️ Portal 이후 페이지 폰트가 안 닿음 */
  font-size: 14px;
  margin-bottom: 4px;
}
.modal-withdraw .mw-input:focus {
  outline: none;
  border-color: var(--danger);
}

.modal-withdraw .mw-err {
  font-size: 12px;
  color: var(--danger);
  margin: 6px 0 0;
}

.modal-withdraw .modal-actions { margin-top: 18px; }
```

- [ ] **Step 3: 갤러리에 3상태 등록**

갤러리에서 **에러·로딩 상태를 재현**하는 게 이 태스크의 핵심 이득이다(실제로는 만들기 까다로운 상태들).

`web/src/pages/DevModals.jsx` import에 추가:

```jsx
import WithdrawModal from '../components/WithdrawModal'
```

`ITEMS` 배열 끝에 추가:

```jsx
    {
      id: 'withdraw',
      label: '탈퇴 — 기본',
      render: () => (
        <WithdrawModal onConfirm={async () => close()} onCancel={close} />
      ),
    },
    {
      id: 'withdraw-error',
      label: '탈퇴 — 에러 상태 (onConfirm이 throw)',
      render: () => (
        <WithdrawModal
          onConfirm={async () => { throw new Error('dev: 강제 실패') }}
          onCancel={close}
        />
      ),
    },
    {
      id: 'withdraw-loading',
      label: '탈퇴 — 로딩 상태 (영원히 pending)',
      render: () => (
        <WithdrawModal
          onConfirm={() => new Promise(() => {})}
          onCancel={close}
        />
      ),
    },
```

⚠️ 에러·로딩 항목은 **"탈퇴합니다"를 직접 타이핑해야** 버튼이 활성화된다(그게 사양이다). 타이핑 후 '탈퇴하기'를 눌러야 상태가 보인다.

- [ ] **Step 4: 빌드·린트·확인**

```bash
cd web
npm run build && npm run lint && npm run dev
```

`/dev/modals`에서 확인:
- '탈퇴 — 기본': 제목이 **보이고**(titleHidden={false}), 리스트가 왼쪽 정렬, 입력창이 md(400px) 안에 여유 있게 들어간다
- 입력이 틀리면 '탈퇴하기'가 비활성(흐림)
- '탈퇴 — 에러': `탈퇴합니다` 타이핑 → '탈퇴하기' → 빨간 에러 문구가 뜬다
- '탈퇴 — 로딩': 타이핑 → '탈퇴하기' → 버튼이 '탈퇴 중…'으로 바뀌고 **Esc·배경클릭으로 안 닫힌다**(`dismissible={!loading}`)

- [ ] **Step 5: 실제 마이페이지에서도 확인**

`/mypage?tab=profile`의 '회원 탈퇴' 버튼으로 같은 모달이 뜨는지, 갤러리와 모양이 같은지 본다. **⚠️ 실제로 탈퇴하지 말 것** — 모달만 띄우고 취소한다.

- [ ] **Step 6: 커밋**

```bash
cd "c:/새 폴더"
git add web/src/components/WithdrawModal.jsx web/src/components/Modal.css web/src/pages/DevModals.jsx
git commit -m "feat(modal): WithdrawModal 공용 셸 전환 — .mw-danger를 공용 danger 버튼으로 흡수

폭 md(400)로 안내 리스트+입력 여유. 처리 중엔 dismissible=false.
갤러리에 에러·로딩 상태 등록(실제로는 재현이 까다로운 상태들)."
```

---

## Task 9: `AdModal` 전환 + 중첩 경고 모달 정식화

여기서 z-index 해킹(`.ad-leavewarn`, 999 vs 1000)이 사라진다.

**Files:**
- Modify: `web/src/components/AdModal.jsx` (셸 사용 + 중첩 Dialog)
- Modify: `web/src/components/AdModal.css` (`.ad-overlay` · `.ad-modal` · `.ad-leavewarn` 제거·정리)
- Modify: `web/src/pages/DevModals.jsx` (광고 + 광고 경고 등록)

**Interfaces:**
- Consumes: `Modal`(Task 3)
- Produces: `<AdModal onClose onClaimed />` — 시그니처 변화 없음(호출부 `ExchangeCenter.jsx:182` 그대로).

- [ ] **Step 1: `AdModal.jsx` — import 교체**

`web/src/components/AdModal.jsx:1-5`를 아래로 바꾼다:

```jsx
import { useEffect, useRef, useState } from 'react'
import { useAuth } from './AuthContext'
import { startAdView, claimAdReward, logAdClick, adMediaUrl } from '../data/adQueries'
import Modal from './Modal'
import './AdModal.css'
```

(구 `import './Modal.css'` 줄은 삭제 — `Modal.jsx`가 자기 CSS를 들고 온다.)

- [ ] **Step 2: `AdModal.jsx` — 포커스 수동 관리 코드 제거**

Radix가 포커스를 관리하므로 `modalRef` + 수동 focus는 필요 없다.

`AdModal.jsx:25`의 `const modalRef = useRef(null)` 줄을 **삭제**한다.

`AdModal.jsx:29-30`의 아래 두 줄을 **삭제**한다:

```jsx
  // 콘텐츠가 뜨면 모달에 포커스 (접근성) — loading 중엔 모달 자체가 안 떠 있음
  useEffect(() => { if (status !== 'loading') modalRef.current?.focus() }, [status])
```

- [ ] **Step 3: `AdModal.jsx` — 렌더부 교체**

`AdModal.jsx:219-239`(`return ( <div className="ad-overlay"> ... )` 전체)를 아래로 **교체**한다:

```jsx
  return (
    <>
      <Modal
        open
        // 닫기는 X · '포인트 받기' · 이미지(가게 이동) 3가지로만.
        // Esc·배경클릭으로 안 닫히는 건 리워드 어뷰징 방지 사양 — 버그가 아니다.
        dismissible={false}
        onOpenChange={() => {}}
        size="lg"
        title="리워드 광고"
        className="ad-modal"
      >
        {inner}
      </Modal>

      {/* 5초 전 X → 리워드 상실 경고. 광고 모달 위에 뜨는 중첩 Dialog.
          Portal 덕에 DOM 순서로 자연스럽게 위에 쌓이고, 같은 스크림이 두 겹 겹쳐 광고가 어두워진다.
          (구버전은 z-index 999 vs 1000 때문에 .ad-leavewarn 오버레이를 따로 만들어야 했다) */}
      {warnOpen && (
        <Modal
          open
          onOpenChange={(next) => { if (!next) resumeWatching() }}
          size="sm"
          title="나가기 확인"
        >
          <p className="modal-text">잠깐! 지금 나가면 포인트를 못 받아요</p>
          <div className="modal-actions">
            <button className="modal-btn modal-btn-cancel" onClick={leaveNow}>그냥 나가기</button>
            <button className="modal-btn is-primary" onClick={resumeWatching}>계속 시청</button>
          </div>
        </Modal>
      )}
    </>
  )
}
```

⚠️ 경고 모달은 **`dismissible` 기본값(true)** 이다 — Esc를 누르면 `resumeWatching()`(계속 시청)으로 돌아간다. 광고 본체는 못 닫지만 경고창은 취소할 수 있어야 자연스럽다.

- [ ] **Step 4: `AdModal.css` — 셸이 가져간 부분 삭제**

`web/src/components/AdModal.css`에서:

1. **`.ad-overlay` 블록 전체 삭제**(4~14행). 오버레이는 이제 공용 `.modal-overlay`가 담당한다.
2. **`.ad-leavewarn` 블록 전체 삭제**(166~180행, 주석 포함). 중첩 Dialog가 대체한다.
3. **`.ad-modal` 블록을 아래로 교체**(공용 `.modal` 위에 덧칠하는 형태):

```css
/* 광고 카드 — 공용 .modal 위에 덧칠. 이미지가 카드를 꽉 채우므로 패딩·배경을 없앤다.
   (폭·중앙정렬·애니메이션·스크림은 공용 셸이 담당) */
.modal.ad-modal {
  display: flex;
  flex-direction: column;
  overflow: hidden;
  padding: 0;
  background: transparent;  /* 이미지 뒤 밝은 배경 제거 → 라운드 모서리 흰선(AA) 차단. 흰색은 .ad-foot/.ad-state에만 */
  text-align: left;
}
```

4. 파일 맨 위 주석(1~2행)을 갱신:

```css
/* 리워드 광고 모달 (components/AdModal) — 교환센터 '광고 시청하기'에서 띄움.
   껍데기(오버레이·폭·중앙정렬)는 공용 Modal.jsx 셸이 담당하고, 이 파일은 광고 내용물만 소유한다.
   닫기는 X · '포인트 받기' · 이미지(가게 보러가기) 3가지로만 (배경/Esc로는 안 닫힘 — dismissible={false}). */
```

- [ ] **Step 5: 갤러리에 등록**

`web/src/pages/DevModals.jsx` import에 추가:

```jsx
import AdModal from '../components/AdModal'
```

`ITEMS` 배열 끝에 추가:

```jsx
    {
      id: 'ad',
      label: '광고 (lg) — ⚠️ 실제 광고 fetch, 실제 포인트 적립됨',
      render: () => <AdModal onClose={close} onClaimed={close} />,
    },
```

⚠️ 갤러리에서 광고를 열면 **실제 Supabase에서 광고를 가져오고, '포인트 받기'를 누르면 실제로 적립된다.** 현재 테스트 기간·실유저 없음이라 허용된 트레이드오프다(스펙 3.6). 광고 **경고 모달**은 광고를 열고 5초 전에 X를 눌러 확인한다.

- [ ] **Step 6: 빌드·린트·확인**

```bash
cd web
npm run build && npm run lint && npm run dev
```

`/dev/modals`에서 '광고' 항목을 열어 확인:
- 광고 카드가 뜨고 이미지가 모서리까지 꽉 찬다(흰 테두리선 없음)
- **Esc를 눌러도 안 닫힌다** · **배경을 클릭해도 안 닫힌다** ← 사양대로
- 5초 카운트다운 링이 돈다
- **5초 전에 X를 누르면** 경고 모달이 광고 위에 뜨고, **광고가 더 어두워진다**(스크림 두 겹) · 카운트다운이 멈춘다
- '계속 시청' → 멈춘 지점부터 재개 / '그냥 나가기' → 미지급 퇴장
- 경고 모달에서 **Esc를 누르면 '계속 시청'과 같게 동작**한다

교환센터(`/exchange`)의 '광고 시청하기'에서도 같은지 확인한다.

- [ ] **Step 7: 커밋**

```bash
cd "c:/새 폴더"
git add web/src/components/AdModal.jsx web/src/components/AdModal.css web/src/pages/DevModals.jsx
git commit -m "feat(modal): AdModal 공용 셸 전환 + 경고를 중첩 Dialog로 정식화

.ad-overlay/.ad-leavewarn과 z-index 999vs1000 해킹 제거.
중첩 스크림이 겹쳐 광고가 저절로 어두워짐. dismissible=false로 어뷰징 방지 사양 유지."
```

---

## Task 10: `alert()` 10곳 → Toast

**Files:**
- Create: `web/src/components/ToastContext.jsx`
- Modify: `web/src/components/Toast.jsx` (`variant` 추가)
- Modify: `web/src/components/Toast.css` (error 변형)
- Modify: `web/src/App.jsx` (`ToastProvider`)
- Modify: `web/src/pages/WorksiteDetail.jsx` (alert 3)
- Modify: `web/src/pages/MyPage.jsx` (alert 1)
- Modify: `web/src/pages/ExchangeCenter.jsx` (alert 1)
- Modify: `web/src/components/AdModal.jsx` (alert 1)
- Modify: `web/src/pages/ReviewForm.jsx` (로컬 `notice` → `useToast`)
- Modify: `web/src/pages/Login.jsx` (alert 2, `setToast` 3, **+ 유휴 로그아웃 안내 토스트 신규**) — **현수 담당 파일**
- Modify: `web/src/pages/Signup.jsx` (alert 2, `onToast` prop 제거) — **현수 담당 파일**

**Interfaces:**
- Consumes: 없음(Toast는 독립)
- Produces: `useToast()` → `toast(message, variant = 'info', duration = 2800)`. `variant`: `'info' | 'error'`.

- [ ] **Step 0: 디스코드 공유 (사람이 한다)**

`Login.jsx`·`Signup.jsx`를 건드리므로 **착수 전 디스코드에 알린다.** 현수가 그 파일을 동시에 만지고 있으면 충돌한다. 변경은 `alert()` → `toast()` 치환으로만 제한하고 인증 로직은 손대지 않는다.

- [ ] **Step 1: `Toast.jsx`에 variant 추가**

`web/src/components/Toast.jsx`를 아래로 교체:

```jsx
import { useEffect, useRef } from "react";
import "./Toast.css";

// 우측 하단 비차단 안내. variant: 'info'(기본·파랑) | 'error'(빨강)
export default function Toast({ message, onClose, duration = 2800, variant = "info" }) {
  const onCloseRef = useRef(onClose);
  onCloseRef.current = onClose;

  useEffect(() => {
    const timerId = window.setTimeout(() => {
      onCloseRef.current?.();
    }, duration);

    return () => window.clearTimeout(timerId);
  }, [duration, message]);

  return (
    <div className="toast-region" aria-live="polite" aria-atomic="true">
      <div
        className={`toast-message toast-${variant}`}
        role="status"
        style={{ "--toast-duration": `${duration}ms` }}
      >
        {message}
      </div>
    </div>
  );
}
```

- [ ] **Step 2: `Toast.css` — 색을 변형으로 분리**

`web/src/components/Toast.css`의 `.toast-message` 블록에서 색 3줄(`border`·`background`·`color`)을 빼고, 변형 규칙을 추가한다.

`.toast-message`를 아래로 바꾼다:

```css
.toast-message {
  border: 1px solid transparent;
  border-radius: 8px;
  padding: 12px 14px;
  box-shadow: var(--shadow-md);
  font-size: 13px;
  font-weight: 600;
  line-height: 1.5;
  animation: toast-lifecycle var(--toast-duration) ease both;
}

/* 안내(기본) */
.toast-info {
  border-color: var(--primary-mid);
  background: var(--primary-light);
  color: var(--primary-deep);
}

/* 오류 */
.toast-error {
  border-color: var(--danger-mid);
  background: var(--danger-light);
  color: #C53847;   /* --danger(#FF6978)는 연분홍 배경 위에서 대비가 모자람 */
}
```

- [ ] **Step 3: `web/src/components/ToastContext.jsx` 생성**

```jsx
import { createContext, useCallback, useContext, useRef, useState } from 'react'
import Toast from './Toast'

// 앱 어디서나 토스트를 띄우는 통로. App.jsx가 <ToastProvider>로 감싼다.
//
// 왜 컨텍스트인가: 예전엔 페이지가 각자 notice 상태를 들고 <Toast>를 렌더했는데,
// AdModal 같은 '컴포넌트'는 토스트를 띄울 방법이 없었다(페이지가 아니라서).
// AuthContext와 같은 자리·같은 방식이라 새 패턴이 아니다.
//
// 쓰는 법:
//   const toast = useToast()
//   toast('신고가 접수되었어요')
//   toast('포인트가 부족해요', 'error')
//   toast('기존에 작성한 리뷰를 불러왔어요.', 'info', 5000)
const ToastContext = createContext(null)

export function ToastProvider({ children }) {
  const [current, setCurrent] = useState(null)   // { message, variant, duration, key }
  const seq = useRef(0)

  const toast = useCallback((message, variant = 'info', duration = 2800) => {
    // key를 매번 새로 줘서 리마운트 → 같은 메시지를 연속으로 띄워도 애니메이션이 다시 돈다.
    // (Symbol은 React key로 못 쓴다 — 문자열/숫자만 허용)
    seq.current += 1
    setCurrent({ message, variant, duration, key: seq.current })
  }, [])

  return (
    <ToastContext.Provider value={toast}>
      {children}
      {current && (
        <Toast
          key={current.key}
          message={current.message}
          variant={current.variant}
          duration={current.duration}
          onClose={() => setCurrent(null)}
        />
      )}
    </ToastContext.Provider>
  )
}

export function useToast() {
  const toast = useContext(ToastContext)
  if (!toast) throw new Error('useToast는 <ToastProvider> 안에서만 쓸 수 있어요')
  return toast
}
```

- [ ] **Step 4: `App.jsx`에 ToastProvider 연결**

`web/src/App.jsx`의 import에 추가:

```jsx
import { AuthProvider, useAuth } from './components/AuthContext'
import { ToastProvider } from './components/ToastContext'
```

그리고 `App` 컴포넌트를 아래로 바꾼다:

```jsx
function App() {
  return (
    <AuthProvider>
      <ToastProvider>
        <AppRoutes />
      </ToastProvider>
    </AuthProvider>
  )
}
```

- [ ] **Step 5: `WorksiteDetail.jsx` — alert 3곳**

import에 추가:

```jsx
import { useToast } from '../components/ToastContext'
```

컴포넌트 안 상단(다른 훅들 옆)에 추가:

```jsx
  const toast = useToast()
```

`doReport`(101~110행)와 `doDelete`(112~127행)의 `alert`를 바꾼다:

```jsx
  async function doReport(reason) {
    try {
      await reportReview(report.reviewId, reason)
      setReport(null)
      toast('신고가 접수되었어요. 검토 후 조치됩니다.')
    } catch (e) {
      setReport(null)
      toast('신고 중 오류: ' + e.message, 'error')
    }
  }

  async function doDelete() {
    const targetId = confirm.reviewId
    try {
      await deleteReview(targetId)
      setConfirm(null)
      // 낙관적 제거 — 네트워크 재조회 없이 로컬에서 바로 제거 (C5)
      setState((s) => ({ ...s, reviews: s.reviews.filter((r) => r.id !== targetId) }))
      // 회수된 포인트를 컨텍스트에 반영 → AccountMenu(드롭다운) 잔액 즉시 갱신
      await refreshProfile()
    } catch (e) {
      setConfirm(null)
      toast(
        e.message?.includes('INSUFFICIENT_POINTS')
          ? '포인트가 부족해 삭제할 수 없어요. (광고 시청 등으로 충전 후 삭제 가능)'
          : '삭제 중 오류: ' + e.message,
        'error',
      )
    }
  }
```

- [ ] **Step 6: `MyPage.jsx` — alert 1곳**

import에 추가:

```jsx
import { useToast } from '../components/ToastContext'
```

컴포넌트 안에 `const toast = useToast()` 추가 후, `runAction`(283~293행):

```jsx
  async function runAction(action) {
    if (busy) return
    setBusy(true)
    try {
      await action()
    } catch (e) {
      toast(errorText(e), 'error')
    } finally {
      setBusy(false)
    }
  }
```

- [ ] **Step 7: `ExchangeCenter.jsx` — alert 1곳**

import에 추가:

```jsx
import { useToast } from '../components/ToastContext'
```

컴포넌트 안에 `const toast = useToast()` 추가 후, `run`(73~85행):

```jsx
  async function run(action) {
    if (busy) return
    setBusy(true)
    try {
      const w = await action()
      setWallet(w)
      mergeUser(w)
    } catch (e) {
      toast(errorText(e), 'error')
    } finally {
      setBusy(false)
    }
  }
```

- [ ] **Step 8: `AdModal.jsx` — alert 1곳**

import에 추가:

```jsx
import { useToast } from './ToastContext'
```

컴포넌트 안 `const { user } = useAuth()` 아래에 추가:

```jsx
  const toast = useToast()
```

`claim()`의 catch(113~117행):

```jsx
    } catch (e) {
      setClaiming(false)
      if ((e.message || '').includes('INVALID_TOKEN')) { claimed.current = true; finish() }
      else if (!closed.current) toast('포인트 적립 중 오류가 발생했어요: ' + e.message, 'error')
    }
```

- [ ] **Step 9: `ReviewForm.jsx` — 로컬 notice를 useToast로**

`import Toast from "../components/Toast";`(6행)를 **삭제**하고 추가:

```jsx
import { useToast } from "../components/ToastContext";
```

컴포넌트 안에 `const toast = useToast()`를 추가한다.

`const [notice, setNotice] = useState(null);`(95행)를 **삭제**하고, `setNotice(...)` 호출 8곳을 전부 `toast(...)`로 바꾼다. 오류성 메시지는 `'error'`를 붙인다:

| 기존 (행) | 새 코드 |
|---|---|
| `setNotice("사용자 입학연도 정보가 없습니다.")` (148) | `toast("사용자 입학연도 정보가 없습니다.", "error")` |
| `setNotice("수정할 리뷰가 없습니다.")` (173) | `toast("수정할 리뷰가 없습니다.", "error")` |
| `setNotice(\`정보를 불러오지 못했습니다: ${error.message}\`)` (196) | `toast(\`정보를 불러오지 못했습니다: ${error.message}\`, "error")` |
| `setNotice(toastMessage)` (254) | `toast(toastMessage, "info", toastMessage === "기존에 작성한 리뷰를 불러왔어요." ? 5000 : 2800)` |
| `setNotice("필수 정보를 확인할 수 없어 리뷰를 저장할 수 없습니다.")` (268) | `toast("필수 정보를 확인할 수 없어 리뷰를 저장할 수 없습니다.", "error")` |
| `setNotice("모든 별점을 선택해 주세요.")` (279) | `toast("모든 별점을 선택해 주세요.", "error")` |
| `setNotice("실제 업무 내용은 30자 이상 작성해 주세요.")` (284) | `toast("실제 업무 내용은 30자 이상 작성해 주세요.", "error")` |
| `setNotice("자유 의견은 50자 이상 작성해 주세요.")` (289) | `toast("자유 의견은 50자 이상 작성해 주세요.", "error")` |
| `setNotice("이미 해당 학기에 작성한 리뷰가 있어요.")` (353) | `toast("이미 해당 학기에 작성한 리뷰가 있어요.", "error")` |
| `setNotice(reviewSaveErrorMessage(error))` (358) | `toast(reviewSaveErrorMessage(error), "error")` |

그리고 렌더부(418~426행)의 `<Toast>` 블록을 **통째로 삭제**한다(이제 Provider가 렌더한다):

```jsx
      {notice && (
        <Toast ... />
      )}
```

- [ ] **Step 10: `Login.jsx` — alert 2곳 + 로컬 toast 제거 + 유휴 로그아웃 토스트 (현수 담당 파일)**

⚠️ **줄번호를 믿지 말고 문자열로 찾을 것.** main이 최근 움직여(비밀번호 재설정·유휴 로그아웃) 이 파일이 커졌다.

**(a) import 교체** — `import Toast from '../components/Toast'`를 **삭제**하고, `react-router-dom` import에 `useLocation`을 추가한 뒤 훅을 들여온다:

```jsx
import { useNavigate, useLocation } from 'react-router-dom'
import { useToast } from '../components/ToastContext'
```

(`useNavigate`는 이미 import돼 있다 — `useLocation`만 보태면 된다.)

**(b) 로컬 토스트 상태 제거** — `const [toast, setToast] = useState(null)` 줄(주석 포함)을 **삭제**하고 대신:

```jsx
  const toast = useToast()
  const location = useLocation()
```

**(c) `setToast(...)` 3곳을 `toast(...)`로.** 비밀번호 재설정 재전송(`handleResendReset`)에 있다:

```jsx
    try { await sendPasswordReset(email); toast('재설정 메일을 다시 보냈어요.', 'info', 5000) }
    catch (err) {
      console.error('재설정 메일 재전송 실패:', err)
      toast(isRateLimited(err)
        ? '재전송이 너무 잦아요. 잠시 후 다시 시도해주세요.'
        : '재설정 메일 재전송에 실패했어요. 연결을 확인하고 다시 시도해주세요.', 'error', 5000)
    }
```

(원래 `<Toast duration={5000}>`이었으므로 5000을 유지한다.)

**(d) `alert()` 2곳을 `toast(...)`로:**

```jsx
      toast('확인 중 오류가 발생했어요. 잠시 후 다시 시도해주세요.', 'error')
```

```jsx
                    onClick={() => toast('아직 불가능! 조금만 기다려!')}
```

**(e) `<Signup>`의 `onToast={setToast}` prop을 삭제**한다(Signup이 직접 `useToast`를 쓴다 — Step 11). 나머지 props(`email`·`password`·`notice`·`onBack`)는 그대로 둔다.

**(f) 파일 하단의 `{toast && <Toast ... />}` 줄을 삭제**한다(이제 Provider가 렌더한다).

⚠️ 원래 주석("Signup 쪽 안내도 여기서 렌더 — logout 등으로 Signup이 언마운트돼도 살아남게")이 걱정하던 문제는 **Provider가 App 최상단에 있으므로 자동 해결된다.**

**(g) 유휴 로그아웃 안내 토스트를 추가한다.**

30분 유휴 자동 로그아웃(`components/IdleLogout.jsx`, main에 머지됨)은 `navigate('/login', { replace: true, state: { reason: 'idle' } })`로 이 페이지에 온다. **payload는 이미 도착하는데 Login이 안 읽고 있어서, 사용자는 영문도 모르고 로그인 화면에 튕긴다.** 여기서 읽어 토스트만 띄우면 끝난다.

다른 `useEffect`들 옆에 추가한다:

```jsx
  // 30분 유휴 자동 로그아웃(IdleLogout)이 state.reason='idle'로 보낸다 → 왜 튕겼는지 알려준다.
  // ⚠️ 유휴 '경고 모달'은 일부러 안 만든다(의도된 부재). 안내는 이 토스트 하나로 끝.
  // 뒤로가기·새로고침으로 같은 토스트가 다시 뜨지 않게 state를 1회 소비하고 지운다.
  useEffect(() => {
    if (location.state?.reason !== 'idle') return
    toast('30분 동안 활동이 없어 자동으로 로그아웃했어요.', 'info', 5000)
    navigate(location.pathname, { replace: true, state: null })
  }, [location.state, location.pathname, navigate, toast])
```

⚠️ **마지막 줄(state 소비)을 빠뜨리지 말 것.** 안 지우면 사용자가 로그인 화면에서 새로고침할 때마다 "자동 로그아웃했어요" 토스트가 계속 뜬다.

- [ ] **Step 11: `Signup.jsx` — alert 2곳 + onToast prop 제거 (현수 담당 파일 — 치환만)**

import에 추가:

```jsx
import { useToast } from '../components/ToastContext'
```

컴포넌트 시그니처(26행)에서 `onToast`를 뺀다:

```jsx
function Signup({ email: emailProp, password, notice, onBack }) {
```

컴포넌트 안에 추가:

```jsx
  const toast = useToast()
```

25행의 `onToast` 설명 주석을 삭제한다.

169·172·176행:

```jsx
      } else if (m.includes('NO_COLLEGE') || m.includes('NO_DEPARTMENT')) {
        toast('학과 정보를 다시 확인해 주세요.', 'error')
      } else if (isStaleSessionError(err)) {
        // 유령 세션(계정 삭제 후 남은 토큰): 이 세션으론 영영 저장 불가 → 비우고 처음부터
        toast(`탭 종료 후 다시 시도해 보세요. (오류 ${err?.code ?? '23503'})`, 'error', 5000)
        await logout()
        onBack?.()   // Login의 profileStep 잔재 정리(needsProfile 경로면 no-op)
      } else {
        toast('회원가입 중 오류가 발생했어요. 잠시 후 다시 시도해주세요.', 'error')
      }
```

- [ ] **Step 12: alert가 다 사라졌는지 확인**

```bash
cd web
grep -rn "alert(" src/ || echo "OK: alert() 없음"
```

Expected: `OK: alert() 없음`

- [ ] **Step 13: 빌드·린트·테스트**

```bash
cd web
npm run build && npm run lint && npm test
```

Expected: 전부 통과.

- [ ] **Step 14: 손으로 확인**

```bash
cd web
npm run dev
```

- 상세 페이지에서 리뷰 **신고** → 우측 하단에 파란 토스트("신고가 접수되었어요")
- 교환센터에서 포인트가 모자란 상태로 **교환** → 빨간 토스트
- **회원가입 화면**에서 SSO 버튼 → "아직 불가능!" 토스트 (파랑)
- 리뷰 폼에서 별점을 안 채우고 제출 → 빨간 토스트

- [ ] **Step 15: 커밋**

```bash
cd "c:/새 폴더"
git add web/src/components/Toast.jsx web/src/components/Toast.css web/src/components/ToastContext.jsx web/src/components/AdModal.jsx web/src/App.jsx web/src/pages/WorksiteDetail.jsx web/src/pages/MyPage.jsx web/src/pages/ExchangeCenter.jsx web/src/pages/ReviewForm.jsx web/src/pages/Login.jsx web/src/pages/Signup.jsx
git commit -m "feat(toast): alert() 10곳을 Toast로 + useToast() 훅 도입

Toast에 error 변형 추가. ToastProvider가 App 최상단에서 렌더하므로
컴포넌트(AdModal)도 토스트를 띄울 수 있고, Login이 Signup에 onToast를
내려주던 우회도 사라짐.

⚠️ Login/Signup은 현수 담당 파일 — alert→toast 치환만, 인증 로직 무변경."
```

---

## Task 11: 마무리 — README 갱신 · 번들 측정 · 최종 검증

**Files:**
- Modify: `web/src/components/README.md`
- Modify: `web/src/pages/README.md`
- Modify: `docs/superpowers/plans/2026-07-13-modal-system.md` (번들 기록)

**Interfaces:**
- Consumes: Task 1~10 전부
- Produces: 없음(마무리)

- [ ] **Step 1: `web/src/components/README.md` 갱신**

`(d) 현재 파일` 표에서 **`Modal.css` 행을 아래로 교체**한다:

```markdown
| `Modal.jsx` (+`Modal.css`) | **모든 모달의 공용 셸 — 새 모달은 반드시 이걸 통해 만든다.** `radix-ui`의 Dialog를 감싸 포커스 트랩·배경 스크롤 잠금·Esc·포커스 복귀·`role/aria`·**Portal**을 위임하고, 우리 껍데기(오버레이·카드·폭·애니메이션·닫힘정책)만 소유. props: `open`·`onOpenChange`·`size`(`sm`320/`md`400/`lg`420)·`dismissible`(false=Esc·배경클릭 안 닫힘, 광고 전용)·`title`·`titleHidden`·`className`(같은 components/ 안 모달의 카드 덧칠용 — **pages가 주입하는 통로로 쓰지 말 것**). ⚠️ **Portal로 `<body>` 직속 렌더 → 페이지 CSS(`.home-wrap button` 등)가 모달에 안 닿는다.** 모달 모양은 오직 `Modal.css`로만 결정 → `/dev/modals` 갤러리 = 실제 화면. 역으로 페이지에서 흘러오던 폰트도 안 닿으므로 `font-family: var(--sans)`를 직접 박아둠. 버튼은 `.modal-btn` + `.modal-btn-cancel`(취소=항상 아웃라인) / `.is-primary`·`.is-neutral`·`.is-danger`(확인=항상 채움, 색만 intent). 폭·스크림 값은 `index.css` 토큰(`--modal-w-*`·`--scrim`) |
```

`ConfirmModal.jsx` 행을 교체:

```markdown
| `ConfirmModal.jsx` | 확인/취소 모달 (리뷰 삭제·로그아웃·열람권 교환/사용/환불·익명 제출에 재사용). `Modal` 셸 사용. props: `message`(문자열 또는 JSX)·`confirmText`·`intent`(`primary` 교환/사용/익명제출 · `neutral` 로그아웃/환불 · `danger` 리뷰삭제)·`onConfirm`·`onCancel`. ⚠️ **`className` prop 없음 — 다시 만들지 말 것**(페이지별 스타일 주입 통로가 되는 순간 모달이 갈라진다). 변형은 `intent`처럼 정해진 값으로만 |
```

`ReportModal.jsx` 행을 교체:

```markdown
| `ReportModal.jsx` | 리뷰 신고 모달(사유 라디오 5개). `Modal` 셸(`size="md"`) 사용. 라디오는 `.rp-*` 클래스(`Modal.css`) — 행 전체가 선택 타깃. 신고 버튼은 `is-danger` |
```

`WithdrawModal.jsx` 행을 교체:

```markdown
| `WithdrawModal.jsx` | 회원 탈퇴 확인 모달. **"탈퇴합니다" 문구 정확 입력 시에만** 실행 활성 + 사라지는 것 안내(리뷰 익명·포인트/열람권 소멸·30일 재가입 제한). `Modal` 셸(`size="md"`, 처리 중엔 `dismissible=false`) 사용. 스타일은 `Modal.css`의 `.modal-withdraw`. props: `onConfirm(()=>Promise)`·`onCancel`. MyPage 프로필 탭에서 사용 |
```

`AdModal.jsx` 행의 끝에 덧붙인다:

```markdown
 **껍데기는 공용 `Modal` 셸(`size="lg"`·`dismissible={false}`)이 담당**하고 이 파일은 광고 내용물만 소유. 5초 전 X의 리워드 상실 경고는 **중첩 `Modal`**(구 `.ad-leavewarn`·z-index 999vs1000 해킹은 제거됨 — 스크림이 두 겹 겹쳐 저절로 어두워짐).
```

`Toast.jsx` 행을 교체하고 `ToastContext.jsx`·`LoginPromptModal.jsx` 행을 추가한다:

```markdown
| `Toast.jsx` (+`.css`) | 우측 하단 비차단 안내(자동 종료). props: `message`·`variant`(`info` 파랑 / `error` 빨강)·`duration`·`onClose`. **직접 렌더하지 말고 `useToast()`를 쓸 것** — 렌더는 `ToastProvider`가 한다 |
| `ToastContext.jsx` | 앱 어디서나 토스트를 띄우는 통로(`ToastProvider` + `useToast`). `App.jsx`가 `AuthProvider` 안에서 감싼다. `const toast = useToast(); toast('메시지', 'error', 5000)`. **앱의 `alert()`를 전부 대체했다** — 새 코드에서 `alert()`를 쓰지 말 것. 컴포넌트(AdModal 등)도 토스트를 띄울 수 있게 하려고 컨텍스트로 만듦(AuthContext와 같은 자리·같은 방식) |
| `LoginPromptModal.jsx` | 비로그인 사용자가 잠긴 기능을 눌렀을 때의 로그인 유도 모달(자물쇠 배지 + "로그인하러 가기"). `Modal` 셸 사용. 홈의 잠긴 카드에서 사용. props: `onClose` |
```

- [ ] **Step 2: `web/src/pages/README.md` 갱신**

`(d) 현재 파일` 표 맨 아래에 행을 추가한다:

```markdown
| `DevModals.jsx` / `.css` | `/dev/modals` | **개발용 모달 갤러리 (DEV 전용).** 모달 전종을 한자리에서 띄워 디자인을 비교·검증. `App.jsx`가 `import.meta.env.DEV`로 감싸 **실서비스 빌드에 안 실린다**. Portal 덕에 갤러리 모양 = 실제 화면 모양(페이지 CSS가 모달에 안 닿음). 최악 케이스(긴 텍스트·JSX 메시지)와 재현이 까다로운 상태(탈퇴 에러·로딩)를 기본 노출. ⚠️ 광고 항목은 **실제 광고를 fetch하고 실제 포인트가 적립**된다 |
```

- [ ] **Step 3: 번들 증가분 측정**

```bash
cd web
npm run build
```

Task 1 Step 5에서 적어둔 기준선과 `dist/assets/index-*.js` 크기를 비교해, 이 계획 파일 맨 아래 "번들 기록" 절에 적는다.

- [ ] **Step 4: 최종 전체 검증**

```bash
cd web
npm run build && npm run lint && npm test
grep -rn "alert(" src/ || echo "OK: alert() 없음"
grep -rn "btn-signup-nav\|btn-login" src/components/Modal.css src/components/*Modal.jsx || echo "OK: 모달이 네비바 버튼을 안 씀"
```

Expected: 빌드·린트·테스트 통과, 두 grep 모두 `OK`.

⚠️ `btn-login` / `btn-signup-nav`는 **Navbar에서는 계속 쓰인다**(그게 원래 자리다). 위 grep은 **모달 쪽에서만** 안 쓰는지 확인하는 것이다.

- [ ] **Step 5: 갤러리에서 접근성 4종 최종 확인**

```bash
cd web
npm run dev
```

`/dev/modals`의 **모든 항목**에 대해:

1. **Esc로 닫히는가** (광고 본체만 예외 — 안 닫혀야 정상)
2. **Tab이 모달 안에서만 도는가** (뒤 페이지 버튼으로 안 새는가)
3. **뒤 페이지가 스크롤 안 되는가**
4. **닫으면 원래 눌렀던 항목 버튼으로 포커스가 돌아오는가**

그리고 **브라우저 창을 360px로 줄여** 모든 모달이 화면 밖으로 안 넘치는지 본다.

- [ ] **Step 6: 커밋**

```bash
cd "c:/새 폴더"
git add web/src/components/README.md web/src/pages/README.md docs/superpowers/plans/2026-07-13-modal-system.md
git commit -m "docs(modal): components·pages README 갱신 + 번들 증가분 기록"
```

---

## 번들 기록

Task 1 Step 5 / Task 11 Step 3에서 채운다.

| 시점 | `dist/assets/index-*.js` | gzip | CSS gzip |
|---|---|---|---|
| 기준선 (radix 설치 전) | 622.48 kB | 178.98 kB | 14.41 kB |
| 최종 (전 태스크 완료) | 657.39 kB | 190.27 kB | 14.99 kB |
| 증가분 | **+34.91 kB** | **+11.29 kB** | +0.58 kB |

→ Radix Dialog(포커스 트랩·스크롤 잠금·포털·aria)로 gzip +11.3 KB. 접근성 프리미티브 값으로 적정.
  Dropdown까지 Radix로 옮기면(후속) 이 다이얼로그 코어를 공유하므로 추가 증가는 미미할 전망.

## 범위 밖 (후속)

- **Dropdown → Radix 이관.** 팀 방향은 "오버레이 UI는 Radix로 통일". 이번엔 모달만 — 그때까지 자체 `Dropdown.jsx`와 Radix가 공존하는 과도기다.
- 컴포넌트 테스트 인프라(`@testing-library/react` + jsdom).
- 모달 세부 디자인(여백·폰트 크기) 미세 조정 — 갤러리를 보며 별도로.
