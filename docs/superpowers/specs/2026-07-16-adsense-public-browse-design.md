# 비로그인 공개(soft-wall) + AdSense 연결 — 설계

- 날짜: 2026-07-16
- 담당: 배경록 (프론트·AdSense·백엔드 RPC·스펙 전부). DB 변경은 CLAUDE.md §3(마이그레이션·db reset 검증·db push) 준수.
- 관련: 광고 수익화 계획, 리뷰 열람권 모델

## 1. 배경 & 목적

근로고래는 현재 **비로그인 시 콘텐츠가 전혀 안 보인다**(근무지 상세·검색이 `/login`으로 리다이렉트). 그래서:
- **Google AdSense 승인 불가** — 심사봇이 볼 공개 콘텐츠가 홈·법적 페이지뿐.
- **SEO 유입 0** — 크롤러가 근무지·리뷰를 색인 못 함.

이번 학기는 **고려대 단일 학교** 대상이라 "다른 학교 노출" 문제가 없다. 이 창을 이용해 **비로그인에게 일부 콘텐츠를 공개**하여 AdSense 승인 + SEO를 확보한다. 다학교 확장 시점에 **피처 플래그 + anon 권한 회수로 다시 닫는다**(닫힌 커뮤니티 모델로 복귀).

## 2. 결정 — B안

**비로그인/크롤러에게 "근무지 정보 + 리뷰 개수 + 추천율"까지만 공개.** 세부 별점과 리뷰 본문은 로그인/열람권 뒤에 그대로 둔다.

| 요소 | 비로그인/크롤러 | 로그인·무열람권 | 로그인·열람권 |
|---|---|---|---|
| 근무지 정보(InfoCard) | ✅ | ✅ | ✅ |
| "리뷰 N개 · X% 추천" | ✅ | ✅ (현행 유지) | ✅ |
| 세부 별점(평균·항목별) | ❌ 렌더 안 함 | 🔒 마스킹(현행) | ✅ |
| 리뷰 본문 | ❌ "로그인하고 보기" | 🔒 블러 티저(현행) | ✅ |

**근거:** 근무지 정보 + 자체 집계 추천율은 "오리지널 콘텐츠" 신호가 되어 AdSense 승인에 유리하면서, 리뷰 본문·세부 별점은 노출 안 되어 열람권을 보호한다. 리뷰 본문 RPC(`list_worksite_reviews`)가 이미 `anon` 차단이라 비로그인은 원천적으로 리뷰를 못 받는다.

## 3. 범위

**포함**
- 프론트: 비로그인 접근 허용(피처 플래그) + 비로그인 렌더링 분기 + auth 호출 가드
- AdSense 사이트 연결: `index.html` script/meta + `public/ads.txt` (+ `lang="ko"` 완료)
- 백엔드: **anon용 화이트리스트 RPC 추가 + 권한 grant** (배경록 직접, 마이그레이션)
- SEO 경량 기본: `robots.txt`·`sitemap.xml`·canonical (이번 포함)

**제외 (범위 밖)**
- **debt #3** (무열람권 **로그인** 유저의 리뷰 본문 DOM·네트워크 유출) — 별개 이슈로 추적(§8)
- 프리렌더/SSR — 불필요(비로그인 렌더가 리다이렉트 없이 콘텐츠를 그리므로 Googlebot JS 렌더로 충분). 승인·색인 부진 시 재검토
- per-page 동적 meta(react-helmet 등) — 가벼운 후속, 리뷰 티저, 다학교 스코핑

## 4. 상세 설계

### 4.1 피처 플래그
- `web/src/config.js`에 `export const PUBLIC_BROWSE = true` (상수). 닫을 때 `false` 한 줄.

### 4.2 프론트엔드
- **리다이렉트 우회:** [WorksiteDetail.jsx:33](../../web/src/pages/WorksiteDetail.jsx), [Search.jsx:164](../../web/src/pages/Search.jsx)의 `if (!authUser) navigate('/login')` → `if (!authUser && !PUBLIC_BROWSE)`.
- **비로그인 렌더 분기(WorksiteDetail):**
  - 근무지 정보: 비로그인은 신설 **`get_worksite_public_detail(id)`**(화이트리스트 RPC, §4.4)로 받아 표시. 로그인은 기존 경로 유지.
  - 점수: **`get_worksite_score_cards([id])`**(이미 anon 허용)에서 **개수 + 추천율만** 렌더. 세부 별점(overall·항목별)·리뷰 목록은 **렌더 안 함** → DOM에 안 들어감(크롤러도 못 봄).
  - "로그인하고 리뷰 보기" 안내 + 로그인 유도.
- **auth 호출 가드:** `incrementViewCount` 등 `auth.uid()` 기반 호출은 `authUser` 있을 때만.
- **액션 가드:** 리뷰 쓰기·도움돼요·신고는 비로그인이면 로그인 유도.
- **Search:** 비로그인도 검색 가능. `search_worksite_cards`는 이미 **화이트리스트 RPC**라 anon grant만 하면 됨(§4.4).
- **카드 점수 표시 일관성:** 홈·검색 카드의 점수 노출은 페이지 인라인 렌더다. 비로그인에게 **세부 별점(항목별)은 미노출, 개수+추천율(또는 단일 평균)까지만** 보이도록 상세 페이지 정책과 일관되게 맞춘다(구현 시 홈·검색 카드 렌더 확인).

### 4.3 AdSense 연결 & SEO 기본
- `index.html <head>`: adsbygoogle 스크립트 + `<meta name="google-adsense-account" content="ca-pub-2107047521899823">`.
- `web/public/ads.txt`: `google.com, pub-2107047521899823, DIRECT, f08c47fec0942fa0`.
- `web/public/robots.txt`(크롤 허용 + sitemap 위치), `web/public/sitemap.xml`(주요 근무지 URL), 상세 페이지 canonical.
- 광고 유닛은 **콘텐츠 페이지에서만** 렌더(로그인 화면·빈 상태엔 광고 금지 — "No content" 위반 회피). ※ 실제 광고 배치는 승인 후 별도.

### 4.4 백엔드 — anon 화이트리스트 RPC (테이블 grant 금지)
**원칙: anon에게 테이블 SELECT를 열지 않는다.** 필요한 필드만 주는 `security definer` RPC로만 노출한다 → 나중에 민감 컬럼이 추가돼도 자동 노출되지 않음(whitelist).
- **신설 `get_worksite_public_detail(p_worksite_id int)`** — [InfoCard](../../web/src/components/InfoCard.jsx)가 쓰는 필드만 리턴: 기관·근무지명, region, address, type, location_type, is_active, 시급, 근로기간·시간, 직무내용, 우대조건, 기타, 모집인원, 자격(학위·학적), 선호계열/학년, 모집기간, source_url. **리뷰·내부 관리 컬럼 제외.** `grant execute … to anon, authenticated`.
- `search_worksite_cards`: **anon grant**(이미 화이트리스트 RPC).
- `get_worksite_score_cards`·`get_review_stats`: 이미 anon → 변경 없음.
- `list_worksite_reviews`: **변경 없음**(authenticated 전용 유지 = 리뷰 본문 보호).
- **`worksites`·`postings` 테이블 anon SELECT: 열지 않음.**
- 마이그레이션 헤더 2줄 + 시그니처 변경 시 `DROP FUNCTION` 선행. db reset 검증 → db push(배경록).

## 5. 닫기 런북 (다학교 확장 시 — 두 단계 반드시 함께)
프론트만 닫으면 화면은 닫혀도 **API(anon RPC)는 열린 채로 남는다.** 반드시 같이 움직인다:
1. **프론트:** `PUBLIC_BROWSE = false`
2. **백엔드:** anon RPC 권한 회수 — `revoke execute on get_worksite_public_detail, search_worksite_cards, get_worksite_score_cards, get_review_stats from anon` (공개용으로 연 것만).
3. 로그인/빈 화면에 광고 코드 잔존 없나 확인.
> RPC 방식이라 회수 표면이 "함수 몇 개 revoke" 한 곳으로 좁다(테이블 RLS 정책을 여기저기 되돌리는 것보다 안전).

## 6. 실행 순서 & 검증
1. 프론트 변경 + AdSense/SEO 파일 + anon RPC 마이그레이션 (이 브랜치).
2. 마이그레이션 db reset 검증 → db push → 배포.
3. **grgr.kr 크롤 확인**: 비로그인으로 근무지 정보 + "N개·X% 추천"이 보이고 콘솔 에러 없음.
4. 콘텐츠 확인되면 → AdSense 리뷰 요청.

## 7. 테스트
- 비로그인: 근무지 상세·검색 진입 시 정보 + 개수/추천율 보임, 세부 별점·리뷰 본문 미노출, 콘솔 에러 없음.
- 비로그인: 리뷰 쓰기/도움돼요/신고 클릭 → 로그인 유도.
- 로그인·무열람권 / 로그인·열람권: 기존 동작 100% 유지.
- `get_worksite_public_detail` 응답에 리뷰·내부 컬럼 없음(필드 화이트리스트 확인).
- `PUBLIC_BROWSE = false` + anon 권한 회수: 기존 로그인 벽 원복.

## 8. 후속 / 미해결
- **debt #3 (별도 추적 이슈):** 무열람권 **로그인** 유저에게 `list_worksite_reviews`가 pass 무관하게 리뷰 본문(work_content·opinion)을 반환 → DOM·네트워크에 실림(클라 CSS 마스킹만). 열람권 신뢰의 핵심이므로 서버 게이팅으로 정리 필요. 이번 범위 밖(비로그인은 anon RPC라 무관)이나 "언젠가"가 아니라 별도 이슈로 관리. → 메모 `project-debt3-review-body-gating`.
- **thin content 대비:** 정보 빈약한 근무지는 `noindex`로 크롤 제외. 공개 정보(설명·업종·근무형태·위치·공고 요약) 최대한 충실히.
- **SEO 후속:** per-page 동적 title/meta, 색인 부진 시 SSR 재검토.
- AdSense가 "thin content"로 거절 시 → 공개 범위 상향(세부 별점 또는 리뷰 티저) 재검토.
