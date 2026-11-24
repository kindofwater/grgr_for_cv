# 근로고래(Geunrogorae) 프로젝트 작업 규칙

근로장학생을 위한 근무지 리뷰·추천 웹앱.

> 작업 시작 전 이 파일을 먼저 읽고, 만지는 폴더의 `README.md`도 함께 읽는다.
> 이 파일은 "항상 지킬 규칙"만 담는다. 세부 구조 규칙은 각 폴더 README에 있다.

## 기술 스택
- 프론트엔드: **React + Vite** (`web/`)
- 백엔드·DB: **Supabase**(Postgres). 별도 서버 없음 — `web/src/data/`에서 직접 통신한다.

## 폴더 구조 (세부 규칙은 각 폴더 README 참고)
- `web/src/` — 웹앱 소스. 관심사별 분리(화면/UI/데이터/계산). → `web/src/README.md`
  - `pages/` 라우트 단위 화면 · `components/` 재사용 UI · `data/` Supabase 쿼리·RPC · `lib/` 순수 함수 + 테스트
- `web/supabase/` — Supabase CLI 설정·마이그레이션. **DB 스키마·RPC의 정본**(baseline 확보 완료 — Docker 없이 수동 baseline). → `web/supabase/README.md`
- `DB/` — (레거시) 예전 수동 복붙용 SQL 보관소. 기록·참고용 — 새 변경은 `web/supabase/migrations/`로.
- `docs/` — 문서(`db-schema.md`, `README_supabase.md`, `frontend.md`). 옛 문서는 `docs/legacy/`

## 핵심 규칙

### 1. 의존성 방향 / 참조
- 의존성은 한 방향으로만 흐른다: `pages → components / data / lib`. **역방향 import 금지.**
- 웹 코드는 `web/` 안의 코드만 참조한다. **외부 폴더 파일을 직접 import하지 않는다.**
- 자세한 건 `web/src/README.md`와 각 폴더 README.

### 2. 데이터·백엔드 (Supabase)
- DB 통신은 **`web/src/data/`에서만** 한다. 페이지·컴포넌트는 data의 함수만 부른다.
- 일반 쿼리(`.from()`)와 RPC(`.rpc()`) 중 무엇을 쓸지는 작업자가 판단한다.
- RPC 함수 본체는 `web/supabase/migrations/`의 SQL에 있다(레거시는 `DB/`). `.rpc('이름', 인자)`는 그 시그니처와 **정확히 일치**해야 한다.
- 보안은 **RLS(Row Level Security)** 로 보장하는 게 원칙.

### 3. ⚠️ DB·RPC 변경 규칙 (Supabase CLI 마이그레이션)
DB 스키마/RPC 변경은 되돌리기 어렵고 모두가 같은 인스턴스를 공유한다. 그래서 **`web/supabase/migrations/` 마이그레이션으로만** 바꾼다 — SQL 에디터 **수동 편집 금지**(옛/새 방식 혼용 = 드리프트 → 사고).
1. **변경 전 팀에 공유**(디스코드)한다.
2. `cd web && npx supabase migration new <주제>` → SQL 작성(파일 맨 위 헤더 2줄 필수: `-- 목적:` / `-- 날짜: YYYY-MM-DD · 담당:`) → **로컬 `supabase db reset`로 검증**(맨바닥 재구축이 안 깨지는지).
3. **prod 반영은 `supabase db push`** — 변경한 사람이 직접 올린다(특히 RPC). push 전 디스코드에 한 마디(순서 꼬임 방지).
4. 함수 **시그니처(인자·리턴 타입) 변경 시 `DROP FUNCTION IF EXISTS …` 먼저**(안 그러면 옛 함수가 남아 RPC가 꼬임).
- 자세한 워크플로우는 `web/supabase/README.md`. 기존 `DB/` SQL은 레거시 기록.
> live DB 스키마는 `migrations/20260609000000_baseline.sql`로 baseline 확보 완료(Docker 없이 수동). 이후 변경은 `migration new` + `db push`.

### 4. 보안
- 사용자 입력값(리뷰 등)은 **반드시 필터링·검증**한다 (XSS·인젝션 등 시큐어 코딩).
- DB 키 등 민감정보가 프론트 코드로 노출되지 않게 한다.

### 5. 폴더·문서
- **새 폴더는 함부로 만들지 않는다.** 꼭 필요하면 사용자 허락 + 합당한 근거가 있을 때만 만든다.
- 폴더를 새로 만들면 그 폴더의 `README.md`에 역할(무엇이 들어가고 무엇을 참조하는지)을 적는다.
- 스키마·구조를 바꾸면 관련 README와 `docs/db-schema.md`를 **같이 갱신**한다.

## Git / 브랜치
- 작업이 완료되면 **항상 커밋**한다. 푸시는 하지 않는다.
- 커밋 전, 새 브랜치를 팔지 현재 브랜치(main)에 그대로 커밋할지 **반드시 먼저 물어본다**.
- 기능은 각자 브랜치를 파서 작업하고, **브랜치를 파면 PM(배경록)에게 알린다.**

### ⚠️ 배포 브랜치 모델 (2026-07-12~)
- **`main` = 개발 브랜치**, **`prod` = 배포 브랜치.** grgr.kr 실서비스는 `prod`에서 나간다.
- Cloudflare Pages(honeyjang) **Production branch = `prod`**. 따라서:
  - `prod` push → **grgr.kr 실서비스 자동배포**
  - `main`(및 기타 브랜치) push → **Preview 배포**(별도 URL, 실서비스 영향 없음)
- **실서비스 반영 흐름:** `main`에서 개발 → 검증 → **`prod`로 머지 → `git push origin prod`**. `prod`에 직접 커밋하지 말 것(main 경유).
- ⚠️ **DB 스키마/RPC는 자동배포에 안 실린다** — 여전히 `web/supabase`에서 `supabase db push` 수동. 프론트 배포와 순서 조율(스키마 먼저).
