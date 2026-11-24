# web/ — 근로고래 프론트엔드 (React + Vite)

근로고래 웹앱의 프론트엔드. **React + Vite**로 만들고, 별도 백엔드 서버 없이 **Supabase**와 직접 통신한다.
실행·환경설정(`npm install`/`run dev`, `.env.local`)은 [docs/README_supabase.md](../docs/README_supabase.md) 참고.

---

## 폴더 구조 한눈에

```
web/
├── index.html        브라우저가 처음 읽는 껍데기(#root만 있음, 거의 안 건드림)
├── package.json      패키지·실행 명령 목록
├── vite.config.js    Vite 설정 · eslint.config.js  코드 검사 규칙 (거의 안 건드림)
├── public/           코드 변환 없이 그대로 쓰이는 정적 파일(favicon·아이콘 등)
├── scripts/          빌드 보조 스크립트(sitemap 자동 생성)  → scripts/README.md
│
├── src/              ★ 실제 작업하는 소스 ★   → src/README.md
│   ├── App.jsx       라우터: URL → 페이지 연결. 새 페이지는 여기 <Route> 등록
│   ├── main.jsx      앱 진입점 (거의 안 건드림)
│   ├── supabase.js   Supabase 클라이언트 싱글톤
│   ├── index.css     전역 스타일 + 디자인 토큰(색·폰트 변수) 단일 소스
│   ├── pages/        라우트 단위 화면        → pages/README.md
│   ├── components/   재사용 UI 조각          → components/README.md
│   ├── data/         Supabase 쿼리·RPC (DB 통신은 여기서만)  → data/README.md
│   ├── lib/          순수 함수 + 단위테스트   → lib/README.md
│   └── auth/         로그인 상태 공유         → auth/README.md
│
├── supabase/         DB 마이그레이션(스키마·RPC 정본)  → supabase/README.md
└── node_modules/     npm 패키지 (gitignore, 직접 수정·커밋 ❌)
```

---

## 어디서 뭘 하나

| 하려는 것 | 위치 / 문서 |
|-----------|-------------|
| 새 화면(라우트) 추가 | `src/pages/`에 만들고 `src/App.jsx`에 `<Route>` 추가 |
| 여러 화면이 쓰는 UI 조각 | `src/components/` |
| DB에서 읽기/쓰기 (앱 코드) | `src/data/`의 함수 사용 — 페이지가 supabase 직접 호출 ❌ |
| DB 스키마·RPC **변경** | `web/supabase/migrations/` → [supabase/README.md](supabase/README.md) |
| 순수 계산·포맷 함수 | `src/lib/` (+ `.test.js`) |
| Supabase 연결·키 설정 | [docs/README_supabase.md](../docs/README_supabase.md) |
| 전체 작업 규칙 | 루트 [CLAUDE.md](../CLAUDE.md) |
