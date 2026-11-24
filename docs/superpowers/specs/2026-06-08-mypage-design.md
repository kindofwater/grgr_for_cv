# 마이페이지 (MyPage) MVP 설계

작성일: 2026-06-08

## 1. 목적 / 범위

로그인 유저가 자기 정보를 보는 마이페이지. **MVP 범위 = 지갑 요약 + 포인트 내역 + 내가 쓴 리뷰(보기·삭제)**.
프로필 수정·리뷰 수정·회원 탈퇴·공지사항은 **범위 밖**(후속 스펙).

**시각 요구사항: 목업과 비슷하게.** `mockups/근로고래 mockup.html`의 `#screen-mypage`(2497~2573줄) 레이아웃·구성을 따른다. 목업 클래스 구조(`my-wrap`/`my-sidebar`/`my-profile`/`my-wallet`/`my-menu`/`my-main`/`my-sec`/`ph-item`/`rev-item` 등)를 참고하되, 색은 **앱 CSS 변수**(`--accent`/`--text`/`--text-h`/`--border`/`--good`/`--danger`/`--social-bg` 등, `index.css`)로 작성한다(목업의 `--primary` 등은 앱에 없음).

## 2. 결정사항 (브레인스토밍)

- **레이아웃: 탭** — 사이드바 메뉴로 `포인트 내역` / `내가 쓴 리뷰` 전환(한 번에 하나).
- **포인트 내역 잔액 칼럼: 포함** — 클라이언트에서 누적 계산.
- **사이드바 지갑: 사용 버튼 포함** — 7/30일 열람권 "사용"(activatePass 재사용).
- **새 SQL/RPC 없음** — 전부 SELECT 조회 + 기존 RPC 재사용.

## 3. 라우트 / 네비

- `App.jsx`에 `<Route path="/mypage" element={<MyPage />} />` 추가.
- **user-pill**(현재 동작 없음)을 `Home.jsx`·`WorksiteDetail.jsx`·`ExchangeCenter.jsx` 네비에서 `() => navigate('/mypage')`로 연결.
- 비로그인 시 `/login` 리다이렉트(다른 페이지와 동일 패턴).

## 4. 페이지 구조 — `pages/MyPage.jsx` (+ `MyPage.css`)

```
nav (기존 .navbar 재사용: 로고/근장찾기→/search/교환센터→/exchange/공지사항/내포인트/user-pill)
my-wrap (2열: sidebar + main)
├── my-sidebar
│   ├── my-profile : 아바타 + 닉네임
│   ├── my-wallet  : 열람기한 / 보유포인트 / 7일·30일 재고(+"사용" 버튼)
│   └── my-menu    : [포인트 내역] [내가 쓴 리뷰]  (활성 탭 .on)
└── my-main : 선택된 탭 렌더
```

- 마운트 시 `fetchWallet(user.id)`로 지갑 로드(교환센터와 동일). 비로그인 → `/login`.
- 지갑 "사용" 버튼: `ConfirmModal` → `activatePass(user.id, days)` → 반환 wallet으로 `setWallet` + `login({ ...user, ...wallet })`(AuthContext 동기화). 재고 0이면 비활성.
- 탭 상태: `const [tab, setTab] = useState('points')` (`'points'` | `'reviews'`).
- 에러/로딩 상태 분기(교환센터 패턴, 재시도 버튼 동일 적용).

## 5. 탭① 포인트 내역

**데이터** — `data/mypageQueries.js`의 `fetchPointHistory(userId)` (신규, SELECT, 새 RPC 아님):
```js
supabase.from('points')
  .select('amount, reason, created_at, review:reviews ( worksite:worksites ( organization_name, workplace_name ) )')
  .eq('user_id', userId)
  .order('created_at', { ascending: true })   // 오래된 순 → 누적 계산용
```
- `review_id`가 NULL(리뷰 삭제됨)이면 `review`도 null → 근장명 없이 표시.

**표시 로직**:
- reason → 한글 문구 매핑: `review_write`="리뷰 작성", `review_delete`="리뷰 삭제(롤백)", `ad_view`="광고 시청", `signup_bonus`="가입 보너스", `pass_purchase`="열람권 교환", `pass_refund`="열람권 환불". 그 외는 reason 원문.
  - `review_write`/`review_delete` + 근장명 있으면 `"리뷰 작성 — {근장명}"` 형태(`organization_name - workplace_name`).
- **잔액(누적)**: 순수 헬퍼 `lib/points.js`의 `computeRunningBalance(rowsAsc)` — 오래된 순으로 `running += amount`, 각 행에 `balance` 부여. UI는 **최신순(역순)** 표시.
- 변동 부호: `amount > 0` → `+{amount}P`(`.plus`/`--good`), `< 0` → `{amount}P`(`.minus`/`--danger`).
- 빈 상태: "아직 포인트 내역이 없어요."

## 6. 탭② 내가 쓴 리뷰

**데이터** — `data/mypageQueries.js`의 `fetchMyReviews(userId)` (신규, SELECT):
```js
supabase.from('reviews')
  .select('id, worksite_id, work_year, work_semester, opinion, work_content, created_at, worksite:worksites ( organization_name, workplace_name )')
  .eq('user_id', userId).is('deleted_at', null)
  .order('created_at', { ascending: false })
```

**표시**:
- 항목: 근장명(`organization_name - workplace_name`) · `{work_year}년 {work_semester} · {created_at} 작성` · 미리보기(`opinion` 앞부분, 없으면 `work_content`).
- **삭제 버튼**: `ConfirmModal`("이 리뷰를 삭제할까요? (적립한 15P가 회수됩니다)") → `deleteReview(user.id, reviewId)`(기존 RPC 재사용) → 목록에서 제거 + `fetchWallet` 재조회로 지갑·포인트 갱신 + AuthContext 동기화.
  - `INSUFFICIENT_POINTS` 예외 시 친절 문구(교환센터 `errorText`와 동일 매핑 재사용 가능).
- **수정 버튼: 범위 밖**(리뷰 edit 모드 미구현) — 이번엔 넣지 않음.
- 빈 상태: "아직 작성한 리뷰가 없어요." + "근장 찾기" 버튼(`navigate('/search')`).

## 7. 데이터 계층

- 신규 파일 `web/src/data/mypageQueries.js`: `fetchPointHistory`, `fetchMyReviews` (둘 다 supabase SELECT 래퍼, `../supabase`만 의존).
- 재사용: `fetchWallet`·`activatePass`(`exchangeQueries`), `deleteReview`(`worksiteQueries`).
- data 폴더 README "현재 파일" 표 갱신.

## 8. 순수 헬퍼 / 테스트

- `web/src/lib/points.js`: `computeRunningBalance(rowsAsc)` — `[{amount,...}]`(오래된 순) → 각 항목에 누적 `balance` 추가한 새 배열. 순수 함수.
- `web/src/lib/points.test.js`: vitest. (빈 배열, +/- 혼합, 잔액 정확성)
- lib 폴더 README 표 갱신.

## 9. 상태 동기화 / 에러 처리

- 지갑 "사용", 리뷰 "삭제" 후 → 갱신된 지갑으로 `login({ ...user, ...wallet })` → 네비 "내 포인트" + 상세 `hasPass`(`pass_expires_at`) 전역 일치.
- 친절 에러: `INSUFFICIENT_POINTS`/`NO_PASS_STOCK` → 사용자 문구. 로딩 실패 → "다시 시도" 버튼(교환센터 패턴).

## 10. 변경 파일 요약

- 신규: `web/src/pages/MyPage.jsx`(+`.css`), `web/src/data/mypageQueries.js`, `web/src/lib/points.js`(+`.test.js`)
- 수정: `web/src/App.jsx`(라우트), `Home.jsx`·`WorksiteDetail.jsx`·`ExchangeCenter.jsx`(user-pill → /mypage), 각 폴더 README 표
- 문서: 이 스펙

## 11. 범위 밖 (YAGNI)

프로필 수정(단과대/학과/계열 데이터·학년 팝업·updateProfile), 리뷰 수정(ReviewForm edit 모드), 회원 탈퇴(소프트삭제), 공지사항.
