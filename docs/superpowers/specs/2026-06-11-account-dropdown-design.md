# 계정 드롭다운 (AccountMenu) 설계

작성일: 2026-06-11 · 담당: 배경록 (최현수 제안, PM 보류 → 착수)

## 1. 목적 / 범위

상단 우측 닉네임 pill(`Navbar`의 `user-pill`)은 지금 클릭 시 바로 `/mypage`로 간다. 이를 **계정 드롭다운**으로 바꿔, 자주 쓰는 정보·이동을 pill 한 번으로 펼친다.

- ✅ 범위: 새 `AccountMenu` 컴포넌트 + Navbar 연결 + MyPage `?tab=` 초기탭 지원. **DB 변경 0**(기존 `fetchWallet`/`activatePass` 재사용).
- ❌ 범위 밖: "회원정보 수정" 전용 페이지, "포인트샵"(=교환센터, 중복이라 미채택), 로그인 디자인 전면 통일, 포커스 트랩.

> 배경: 최현수 제안 → PM(배경록) 보류(2026-06-10) → 지금 착수. 보류 메모의 합의사항은 이번 간소화 목록으로 대부분 해소(포인트샵 제외 = 명칭충돌 해소, "프로필 수정" 단일화, 모바일은 pill이 `nav-right`라 계속 보임).

## 2. 결정사항 (브레인스토밍)

- **아키텍처: 새 `AccountMenu` 컴포넌트.** Navbar(공용·민감)를 비대화하지 않게 복잡도 격리. `useAuth`/`useNavigate` + `data`의 `fetchWallet`/`activatePass`를 직접 쓰는 **"연결형 예외"**(Navbar와 동일 성격). 지갑을 전 페이지 prop으로 흘리지 않기 위한 의도적 예외.
- **탭 항목 이동:** 내가 쓴 리뷰/포인트 내역/프로필 수정은 MyPage 탭 → **`/mypage?tab=` 이동 + 해당 탭 자동 선택**.
- **"열람권한 없음"(재고0):** 단순 표시가 아니라 **교환센터(`/exchange`)행 CTA 버튼**.
- **사용(activate) 버튼:** 비활성 + 재고>0이면 **보유 종류마다**(7일권/30일권, `PASS_DAYS` 중 재고>0).
- **로그아웃:** **`ConfirmModal` 한 번** 확인 후 실행.
- **지갑 데이터:** 드롭다운 **열 때 lazy fetch**(항상 최신).

## 3. 컴포넌트 — `components/AccountMenu.jsx` (+ `AccountMenu.css`)

로그인 사용자의 pill + 드롭다운을 담당하는 자족 컴포넌트.

**의존:** `useAuth`(user, logout), `useNavigate`(react-router), `data/exchangeQueries`의 `fetchWallet`·`activatePass`, `lib/passes`의 `PASS_DAYS`, `components/ConfirmModal`.

**상태:**
- `open`(bool) — 드롭다운 열림
- `wallet`(obj|null) — 열 때 fetch, `null`=로딩 중
- `confirm`(obj|null) — ConfirmModal용 `{ message, confirmText, action }`
- `busy`(bool) — activate/logout 진행 중

**동작:**
- pill 클릭 → `open` 토글. 열릴 때 `wallet===null`이면 `fetchWallet(user.id)`.
- 바깥 클릭(document mousedown, 메뉴 ref 밖) / `Esc` → 닫힘.
- 항목 선택(이동·CTA) → 닫고 `navigate(...)`.
- pill은 `open`일 때 강조(active 클래스).
- **user 없음 가드:** `user`가 없으면(비정상 진입) 드롭다운 대신 클릭 시 `/login` 이동(기존 pill이 null user에도 떴던 것과 호환).

## 4. Navbar 연결 — `components/Navbar.jsx`

`nav-right`의 비게스트 분기에서 기존:
```jsx
<button className="user-pill" onClick={() => navigate('/mypage')}> … {nickname}님 </button>
```
→ `<AccountMenu />` 로 교체. 게스트 분기(로그인/회원가입 버튼)는 그대로. (Navbar는 pill 마크업·navigate를 더는 직접 들지 않음.)

## 5. 드롭다운 내용 / 열람 상태 로직

```
포인트  {wallet.point_balance}P
열람 상태 (아래 셋 중 하나):
  · 활성( pass_expires_at 있고 > now )      → "열람 가능 · {날짜}까지"
  · 비활성 + Σ재고>0                         → PASS_DAYS 중 재고>0인 d마다 "[{d}일권 사용]" 버튼
  · 비활성 + Σ재고0                          → "열람권한 없음" + "[교환센터]" 버튼(→/exchange)
─────────
내가 쓴 리뷰   → navigate('/mypage?tab=reviews')
포인트 내역    → navigate('/mypage?tab=points')
프로필 수정    → navigate('/mypage?tab=profile')
─────────
로그아웃       → ConfirmModal('로그아웃하시겠습니까?') → logout() + navigate('/login')
```

- **활성 판정:** `pass_expires_at && new Date(pass_expires_at) > new Date()`.
- **재고:** `Number(wallet.pass_balances?.[String(d)] ?? 0)` (MyPage `stockOf`와 동일 규칙).
- **사용 버튼:** 클릭 → ConfirmModal(`'{d}일권을 지금 사용할까요? …'`) → `activatePass(user.id, d)` → 반환 wallet으로 `setWallet` + `login({...user, ...w})` 동기화. (MyPage `handleUseTicket`과 동일 패턴 재현)
- 날짜 표기는 `lib/dates.formatDate`(있음) 재사용 가능 — 활성 만료일 표시에.

## 6. MyPage `?tab=` 초기탭 — `pages/MyPage.jsx`

현재 `const [tab, setTab] = useState('points')` → 쿼리파라미터로 초기화:
```jsx
import { useSearchParams } from 'react-router-dom'
const [searchParams] = useSearchParams()
const initialTab = ['points', 'reviews', 'profile'].includes(searchParams.get('tab'))
  ? searchParams.get('tab') : 'points'
const [tab, setTab] = useState(initialTab)
```
- 그 외/없음 → `points`(기존 기본값 유지). 탭 클릭 동작은 그대로(URL은 안 바꿔도 됨 — 범위 최소화).

## 7. 보안 / 접근성

- 닉네임·포인트 등은 텍스트 렌더(React 자동 escape). `dangerouslySetInnerHTML` 미사용.
- `Esc`로 닫기, 바깥 클릭으로 닫기. (전체 포커스 트랩·aria 메뉴 역할은 범위 밖 — 후속.)
- 사용/로그아웃은 `busy` 가드로 중복 실행 방지.

## 8. 스타일 — `AccountMenu.css` (자체 보유)

- 스크린샷 톤: 흰 카드(`--card`) · 1px 테두리(`--border`) · 라운드 · 그림자(`--shadow-md`) · 항목 hover. **앱 토큰만**(hex 금지, `:root` 재정의 금지).
- pill은 기존 `.user-pill` 재사용 + 열림 시 강조.
- 드롭다운은 pill 아래 우측 정렬, `position: absolute`(부모 `nav-right` 기준) · 적당한 `z-index`(navbar 위).

## 9. 변경 파일 요약

- **신규:** `web/src/components/AccountMenu.jsx` (+ `AccountMenu.css`)
- **수정:** `web/src/components/Navbar.jsx`(pill→AccountMenu), `web/src/pages/MyPage.jsx`(`?tab=` 초기탭)
- **README:** `components/README.md`(AccountMenu 추가 + "연결형 예외" 명시), `pages/README.md`(MyPage 비고에 `?tab=` 한 줄)
- **재사용:** `ConfirmModal`, `fetchWallet`/`activatePass`(`exchangeQueries`), `PASS_DAYS`(`lib/passes`), `formatDate`(`lib/dates`), `useAuth`

## 10. 범위 밖 (YAGNI)

회원정보 수정 전용 페이지, 포인트샵(교환센터 중복), 데스크톱/모바일 별도 메뉴(현재 pill이 양쪽 다 보임), 포커스 트랩·full aria, 로그인 디자인 전면 통일, 탭 변경 시 URL 동기화(드롭다운 진입만 `?tab=` 사용).
