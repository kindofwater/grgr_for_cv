# scripts/ — 빌드 보조 스크립트

## (a) 역할
`npm run build` 과정에서 실행되는 **Node 스크립트**. 앱 런타임 코드가 아니다
(브라우저 번들에 포함되지 않음). 현재는 sitemap 자동 생성 하나.

## (b) 무엇이 들어가나
- 빌드 시점에 한 번 실행되는 생성기·후처리 스크립트.
- 순수 로직은 별도 모듈로 분리하고 옆에 `*.test.mjs` 단위테스트를 둔다(`npm test`가 수행).

## (c) 무엇을 참조하나
- 같은 폴더 내부 모듈, Node 내장(`node:fs` 등), 빌드 env(`VITE_SUPABASE_URL`/`VITE_SUPABASE_ANON_KEY`, 로컬은 `.env.local` 폴백).
- Supabase는 **anon 키 + 공개 RPC**로만 읽는다(service key 금지 — 시크릿을 빌드에 넣지 않는다).
- ❌ `src/` 앱 코드 import 금지(브라우저 전용 모듈이 섞여 있음). 필요한 로직은 여기에 순수 모듈로 둔다.

## (d) 현재 파일
| 파일 | 역할 |
|------|------|
| `generate-sitemap.mjs` | 빌드 후 `dist/sitemap.xml` 생성 엔트리. anon 키로 `search_worksite_cards`를 호출해 **품질 셋만** 담음: 학교근장 전부 + 교내 국가근장 전부 + 리뷰 있는 교외(레거시 교외 6,700여 빈 페이지는 제외 — 애드센스 품질 역효과 방지, 2026-08-19 결정). **실패 시 soft-fail**(경고만, `public/sitemap.xml` 정적본이 배포됨). ⚠️ 검색 RPC는 p_limit 서버 캡 50 — 페이징은 실수신 개수로 전진(1,750 버그 회귀 방지). ⚠️ `PUBLIC_BROWSE`(src/config.js) 닫으면 함께 무력화 — sitemap 전략 재검토 필요 |
| `sitemap.mjs` | 순수 함수: `STATIC_PATHS`(공개 라우트 6개), `worksitePaths`(RPC 행→경로, dedupe·정렬), `buildSitemapXml`(경로→XML), `collectRows`(페이징 수집 — 실수신 개수만큼 offset 전진·stopWhen 조기종료·maxPages 가드), `filterReviewed`(리뷰 1개 이상 행만) |
| `sitemap.test.mjs` | `sitemap.mjs` 단위테스트 |
