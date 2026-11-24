# public/ — 정적 파일 폴더

Vite가 **가공하지 않고 그대로** 서빙/배포하는 정적 파일을 두는 곳입니다.
빌드하면 이 폴더의 내용물이 `dist/` **루트로 그대로 복사**됩니다
(파일명 변경·압축·해시 없음).

## 핵심 규칙

- **경로:** 이 폴더의 파일은 사이트 루트 `/`에서 접근합니다.
  `public/favicon.svg` → 코드에서는 `/favicon.svg` 로 참조.
  (`public/` 라는 폴더명은 경로에 **안** 붙습니다.)
- **참조 방법:** 절대경로 문자열로만. `<img src="/logo.png">`, `href="/favicon.svg"`.
  `import` 하지 않습니다.
- **파일명 유지:** 해시가 안 붙으므로 이름이 그대로 보존됩니다.
  (이름이 고정돼야 하는 파일에 적합)

## 여기에 넣어야 하는 것 ✅

- `favicon.svg` / `favicon.ico` — 브라우저 탭 아이콘 (현재 사용 중)
- `robots.txt`, `sitemap.xml` — 검색엔진용, 루트에 이름 그대로 있어야 함
- `manifest.json`, 앱 아이콘 (PWA 쓸 경우)
- 외부에서 고정 URL로 접근해야 하는 파일 (`/og-image.png` 같은 공유 미리보기 이미지 등)
- JS로 import하지 않고 `/경로`로 직접 부르는 이미지·폰트·svg

## 여기에 넣으면 안 되는 것 ❌

- **컴포넌트에서 `import` 하는 이미지/svg** → `src/assets/`에 두세요.
  (그래야 Vite가 최적화·해시 처리하고, 안 쓰면 번들에서 빠짐)
- 빌드 산출물(`dist/`), 소스코드(`src/`)
- **비밀값** (`.env`, API 키 등) — public은 그대로 공개 배포됩니다. 절대 금지.

## 판단 기준 (한 줄)

> 코드에서 `import`로 가져오면 → `src/assets/`
> `/경로` 문자열로 직접 부르거나, 이름이 고정돼야 하면 → `public/`

## 현재 폴더 상태

| 파일 | 상태 |
|------|------|
| `favicon.svg` | ✅ 사용 중 — `index.html`의 `<link rel="icon" href="/favicon.svg">` |
| `icons.svg` | ⚠️ 미사용 — Vite 기본 템플릿 잔재(소셜 아이콘 스프라이트). 코드에서 참조 없음. 필요 없으면 삭제 가능 |
| `_redirects` | ✅ 사용 중 — 알려진 BrowserRouter 경로만 루트 앱으로 rewrite. 임의 경로를 200으로 만들지 않음 |
| `404.html` | ✅ 사용 중 — Cloudflare Pages가 미등록 경로에 HTTP 404로 제공하는 검색 제외 안내 화면 |
| `ads.txt` | ✅ 사용 중 — Google AdSense 사이트 인증(`pub-2107047521899823`). 루트 `/ads.txt`로 서빙 |
| `robots.txt` | ✅ 사용 중 — 전체 크롤 허용 + sitemap 위치 안내 |
| `sitemap.xml` | ✅ 사용 중 — **정적 폴백**(공개 라우트 6개). 빌드 시 `scripts/generate-sitemap.mjs`가 dist 사본을 근무지 URL 포함본으로 덮어씀 — 이 파일이 그대로 배포됐다면 생성 실패(빌드 로그 `[sitemap]` 확인) |
