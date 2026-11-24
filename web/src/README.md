# src/ — 소스 코드 구조 안내

근로고래 웹앱의 소스 전체. **관심사별로 폴더를 나눠** 둠.
바뀌는 이유가 다른 코드(화면 / 데이터 / 계산)를 한곳에 섞지 않는 게 원칙.

## 폴더 지도

```
src/
├── main.jsx        앱 진입점. #root에 <App/> 렌더. (건드릴 일 거의 없음)
├── App.jsx         라우터. URL → 페이지 연결 (<Route>). 새 페이지는 여기 등록.
├── App.css         App 관련 스타일
├── index.css       전역 스타일 + 디자인 토큰 단일 소스 (색·폰트·레이아웃 변수: --container·--nav-h 등, body, #root)
├── supabase.js     Supabase 클라이언트 싱글톤. data/와 일부 페이지가 import.
├── config.js       앱 전역 피처 플래그 (PUBLIC_BROWSE: 비로그인 공개 on/off · REVIEWS_OPEN_UNTIL: 리뷰 한시 전면 공개 종료시각 — 서버 RPC와 동일 값)
│
├── pages/          라우트 단위 화면. 아래 셋을 "조합"해 한 페이지 완성.
├── components/     재사용 UI 조각 + AuthContext(로그인 상태 Context+useAuth)
├── data/           데이터 접근 계층 (Supabase 쿼리/RPC)
└── lib/            순수 함수 유틸 + 단위테스트 (의존성 0)
```

## 의존성 방향 (위 → 아래로만 흐름)

```
pages  ──→ components   (UI 그리기)
       ──→ data ──→ supabase.js   (데이터 가져오기)
       ──→ lib          (순수 계산)
```

규칙:
- **pages**는 components/data/lib를 모두 import해 조립한다. (제일 위 조립자)
- **data**는 supabase만 의존한다. UI(JSX) 금지.
- **lib**는 아무것도 의존하지 않는다. (React/DOM/네트워크 import 금지 → 그래서 테스트가 쉬움)
- **AuthContext**(`components/`)는 react만 의존(Context). pages·components가 `useAuth()`로 가져다 씀.
- 거꾸로 흐르면 안 됨 (lib가 components를 import 하는 식 ❌).

## 새 작업 어디에?

| 하려는 것 | 위치 |
|-----------|------|
| 새 화면(라우트) 추가 | `pages/`에 만들고 `App.jsx`에 `<Route>` 추가 |
| 여러 화면이 쓰는 UI 조각 | `components/` |
| DB에서 읽고/쓰기 | `data/` |
| 순수 계산·포맷 함수 | `lib/` (+ `.test.js`) |
| 로그인 유저 읽기/쓰기 | `components/AuthContext` (`useAuth()`) |
| 색·폰트·레이아웃 토큰 | `index.css` **단일 소스**. 페이지/컴포넌트 css는 `:root` 재정의 금지, `var(--…)`만 참조 |

각 폴더 안 README에 세부 규칙 있음.