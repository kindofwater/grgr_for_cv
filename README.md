# 근로고래 (honeyjang)

> ### ⚠️ 이 저장소에 대해
>
> 포트폴리오 공개를 위한 **사본**입니다. 원본은 비공개 팀 저장소이고, 추적 가능한 개인정보가
> 포함된 파일은 필드 마스킹이 아닌 완전 삭제를 진행했습니다.
>
>
> 따라서 **마이그레이션 체인이 맨바닥에서 재현되지 않습니다. 이 사본은 그대로 구동할 수 없습니다.**
> 설계와 구현 방식을 보여주기 위한 읽기 전용 사본으로 보시기 바랍니다.
>
> 코드는 3인 팀의 공동 산출물이며, 기능별 담당은 각 마이그레이션·문서 헤더의 `담당:` 표기를 따릅니다.

대학 근로장학생들의 **근무지 리뷰 서비스**. 프론트엔드는 React(Vite), 백엔드는 Supabase(Postgres).

## 폴더 구조

```
honeyjang/
├── CLAUDE.md                # 작업 규칙 (커밋·DB·RPC 규칙)
├── README.md                # (이 파일) 프로젝트 개요·구조
├── assets/                  # 아이콘·로고
├── crawling_scripts/        # KOSAF·KUPID 공고 크롤러/파서 + Supabase 적재 스크립트
├── docs/                    # 문서
│   ├── db-schema.md         #   DB 스키마 정의
│   ├── frontend.md          #   프론트 구조
│   ├── api-spec.md          #   API/RPC 명세
│   ├── README_supabase.md   #   Supabase 연결 가이드
│   ├── 회의록-YYYY-MM-DD.md  #   팀 회의록 (예: 회의록-2026-06-12.md)
│   ├── legacy/              #   구버전 기획·정책
│   └── superpowers/         #   기능별 설계 문서 (plans/, specs/)
├── mockups/                 # HTML 목업 (근로고래 mockup.html)
└── web/                     # 프론트엔드 (React + Vite)
    ├── package.json
    ├── public/
    ├── src/
    │   ├── App.jsx · main.jsx · index.css
    │   ├── components/      #   공용 컴포넌트 + AuthContext(로그인 상태)
    │   ├── data/            #   Supabase 쿼리·RPC 래퍼 (authQueries 등)
    │   ├── lib/             #   순수 로직 (scores·semesters·passes·points·dates·profileOptions·authValidation — lib/README.md 참고)
    │   └── pages/           #   라우트 페이지 (Login·Home·WorksiteDetail 등)
    └── supabase/           # ★ DB 정본 (Supabase CLI) — 스키마·RPC 마이그레이션 ★
        ├── config.toml
        ├── migrations/      #   스키마·RPC 마이그레이션 (단일 소스)
        │   ├── 20260609000000_baseline.sql          # 스키마 + review/points/exchange RPC
        │   ├── 20260612065535_login.sql             # auth: verify_login·register_user 등 (컷오버로 제거됨)
        │   ├── 20260624025109_auth_rls_cutover.sql  # 적용됨(2026-06-24 LIVE) — Supabase Auth·전테이블 RLS·uuid 신원
        │   ├── 20260624160000_grant_authenticated_select.sql  # 적용됨(2026-06-24 LIVE) — authenticated SELECT 권한 핫픽스
        │   └── 20260624170000_reward_ad_server.sql  # 적용됨(2026-06-25 LIVE) — 리워드 광고 서버
        └── README.md        #   마이그레이션 워크플로우
```

## 프론트 실행

```bash
cd web
npm install
npm run dev          # http://localhost:5173
```

> `web/.env.local` 에 `VITE_SUPABASE_URL` / `VITE_SUPABASE_ANON_KEY` 필요. 자세한 건 `docs/README_supabase.md`.
