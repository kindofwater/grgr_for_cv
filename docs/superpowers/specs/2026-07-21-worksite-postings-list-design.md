# 근무지 상세 — 공고 목록 노출 (학교근로 다중 공고 혼란 해소, A안)

- 날짜: 2026-07-21
- 담당: 배경록
- 관련: [[2026-07-21-ssc-job-crawler-design]], [[2026-07-17-kupid-portal-crawler-design]], `docs/db-schema.md`
- 상태: 설계 확정(v2) — A안(근무지=부서 유지 + 상세에 공고 목록). B/C 보류.
  Fable 리뷰 3건 반영(최신 RPC 베이스·30개 캡·폴백 왕복 제거).

## 1. 배경 / 문제

**국가근로**는 근무지 하나에 사실상 정기·일관 공고 1개라 문제가 없다. 그러나
**학교근로**(KUPID/SSC)는 한 **게시부서(=근무지)** 가 성격이 다른 여러 일을
공고로 올린다 — 예: `물리학과`가 실험실 조교·행정 조교·도서관을 각각 모집.

현재 근무지 상세는 **대표 공고 1개만** 보여주고(`is_active desc, created_at
desc`로 1개 선택), 나머지 공고는 화면에 없다. 그래서 한 부서가 올린 여러 일이
사용자에게 보이지 않아 **"이 근무지가 무슨 일을 시키는지"가 불투명**하다.

## 2. 결정 — A안 (B/C는 보류)

식별 단위 논의에서 세 갈래가 있었다:

- **A. 근무지=부서 유지 + 상세에 공고 목록** ← **채택**
- **B. 근무지를 '실근무처' 단위로 분리** — 자동 판정 신뢰도 낮음 + MVP에서 리뷰가
  잘게 흩어져 밀도 붕괴 → **보류**(자동 분리 신뢰도 확보 시 재검토).
- **C. 리뷰·공고에 역할 태그(하이브리드)** — 복잡·기존 리뷰 소급 불가 → **보류**
  (부서당 리뷰가 충분히 쌓이면 재검토).

**핵심 근거:** 근로고래의 해자는 리뷰인데 MVP 초기엔 리뷰가 희소하다. 이때
근무지를 쪼개는 B/C는 독이다 — **정밀도보다 밀도**가 사용자에게 유용하다. A는
값싸고(마이그레이션 1개 + 프론트), 공고 본문 노출만으로 혼란을 크게 완화한다.

## 3. 비목표 (이번에 안 하는 것)

- **리뷰 분리·근무지 분리 안 함.** 리뷰는 계속 **근무지(worksite) 단위**로 붙는다.
  → A는 "성격 다른 일 뒤섞임"의 *표현/맥락* 문제를 풀지, *리뷰 혼선*까지 풀지는
  않는다(그건 B/C의 몫, 보류).
- **`postings.title`(공고명) 컬럼 추가 안 함.** 현재 스키마에 공고 제목이 없다.
  깔끔한 공고명 라벨은 **SSC 크롤러 후속**으로 미룬다(크롤러는 이미 '공고명'을
  긁고 있어 나중에 `title` 컬럼 추가로 자연스럽게 개선 가능).
- 데이터 모델 변경 없음. `worksites:postings`는 이미 1:N.

## 4. 데이터 모델 (변경 없음)

- `worksites`(근무지 1) : `postings`(공고 N). 이미 존재.
- `reviews.worksite_id` — 리뷰는 근무지에 붙음. **그대로 둔다.**
- `postings.is_placeholder` — 공고 없는 근무지의 껍데기 표식. 목록에서 제외.

## 5. UI 설계 — 근무지 상세

```
[대표 공고 카드]            ← 현행 InfoCard 그대로 (근무지 공통 태그·신청 버튼 포함)
[이 근무지의 다른 공고 N개]  ← 신규 섹션 (학교근로에서만 채워짐)
  ▸ 직무 요약   [모집중] [모집기간]     ← 접힌 줄
  ▸ 직무 요약   [모집완료] [모집기간]
    └ (펼치면) 직무 내용·근로시간·모집인원·자격·우대조건·기타·신청 버튼
[점수 요약]
[리뷰 목록]                ← 현행 그대로 (근무지 단위, 잠금 정책 동일)
```

**대표 공고**
- 선정 로직 **현행 유지**: `is_active desc, created_at desc`로 첫 번째.
- 렌더 **현행 InfoCard 그대로**. 근무지 공통 태그(`국가근장/학교근장`,
  `교내/교외`)와 주소·신청 버튼은 여기 한 번만.

**대표/목록 선별 규칙(클라 단일 정본 — Fable #3)**
- 서버(RPC·쿼리)는 폴백 분기 없이 공고 배열(캡 30, 활성→최신 순, `is_placeholder`
  포함)만 내려준다. 선별은 `WorksiteDetail`에서 한 번:
  `nonPh = 비-placeholder 필터` → **대표 = `nonPh[0] ?? postings[0]`** →
  **목록 = `nonPh.slice(1)`**.
- 국가근로(placeholder 1개)는 자연히 대표만 뜨고 목록이 빈다 — 별도 분기 불요.

**다른 공고 목록 (신규 `PostingList`)**
- 대상 = 위 선별 규칙의 `nonPh.slice(1)`, 대표와 같은 순서(활성→최신).
- 각 공고 = **펼침 가능한 미니 카드**:
  - **접힌 줄:** `직무 요약` + 태그 클러스터 **`[모집중/모집완료]` `[모집기간]`**.
    - 직무 요약 = `job_description` 앞부분 truncate(약 40자). 없으면 `(직무 미상)`.
    - ⚠️ **시급 태그는 넣지 않는다** — 학교근로 시급은 대부분 최저임금에 수렴해
      변별력이 없다(배경록 결정 2026-07-21).
  - **펼치면:** 그 공고의 상세 필드 — 직무 내용·근로시간·모집인원·학위/학적
    자격·우대조건·기타 + 신청 버튼(`source_url`). InfoCard 본문 로직 재사용.
- **근무지 공통 태그는 각 줄에 반복하지 않는다**(도배 노이즈 방지). 공고 줄엔
  공고별로 실제 다른 것만.

**국가근로/미크롤 근무지 = 자동으로 현행 유지**
- 이런 근무지는 placeholder 공고 1개뿐 → 비-placeholder 목록이 비어
  **"다른 공고" 섹션이 아예 안 뜬다.** "국가근로는 문제 없다"는 요구와 일치.
- 대표 공고가 placeholder여도(국가근로 시드) 대표 카드는 현행처럼 표시.

**공개/잠금 (현행 정책 유지)**
- 공고 정보는 **공개 카탈로그** → 비로그인·무열람권도 공고 목록을 본다.
- **리뷰만 잠긴다**(티저/잠금 경로 현행 그대로). A는 리뷰 게이팅을 건드리지 않음.

## 6. 파일 변경

| 대상 | 변경 |
|------|------|
| `web/supabase/migrations/<ts>_worksite_detail_postings.sql` (신규) | `get_worksite_public_detail` 반환을 `posting jsonb`(1개) → **`postings jsonb`(배열)** 로. `deleted_at is null` 공고를 활성/최신 순 `jsonb_agg`, **최근 30개 캡**(Fable #2 — SSC 이력 유입 시 응답 비대 방지, get_home_feed 220KB 교훈). placeholder 포함해 내려보내고 대표/목록 선별은 클라 규칙(§5)이 함(Fable #3 — 폴백 왕복·이중 규칙 제거). 각 공고 jsonb에 `is_placeholder` 포함. **⚠️ 베이스는 최신 정의( `20260720015012` — `recruit_until` 키 추가본)** — 옛 20260716 버전을 베이스로 쓰면 `recruit_until`이 증발해 배지 오판(Fable #1). **⚠️ 리턴 시그니처 변경 → `DROP FUNCTION IF EXISTS` 먼저 + `anon,authenticated` grant 재부여** (CLAUDE.md §3). 공고당 화이트리스트 필드는 현행과 동일(개인정보 `contact_name` 등 제외 유지) + `recruit_until`·`is_placeholder`. |
| `web/src/data/worksiteQueries.js` | `fetchRepresentativePosting`(limit 1) → **`fetchPostings(worksiteId)`**(배열: `deleted_at` 필터는 RLS/쿼리, 활성/최신 순, **limit 30** — RPC와 동일 규칙·동일 캡). 폴백 분기 없음 — 선별은 §5 클라 규칙 한 곳. `fetchWorksitePublicDetail`는 `{worksite, postings}` 반환. |
| `web/src/pages/WorksiteDetail.jsx` | `state.posting` → `state.postings`(배열). **선별 규칙(단일 정본):** `nonPh = postings.filter(p => !p.is_placeholder)` → 대표 = `nonPh[0] ?? postings[0]`(국가근로 placeholder 폴백) → 목록 = `nonPh.slice(1)`. `infoReady` 판정은 `worksite && postings` 기준. `InfoCard(대표)` + `PostingList(목록, worksite)`. 3개 fetch 경로(비로그인 RPC / 무열람권 / 열람권) 모두 배열로 통일. |
| `web/src/components/PostingList.jsx` (신규) + CSS | 접힘/펼침 미니 카드 목록. 섹션 제목 "이 근무지의 다른 공고 N개". 목록이 비면 렌더 안 함. |
| `web/src/components/InfoCard.jsx` | 공고 상세 필드 렌더(직무·시간·자격·우대·신청 버튼 등)를 **`PostingFields` 서브컴포넌트로 추출**해 InfoCard 본문과 PostingList 펼침이 공유(중복 제거). InfoCard의 겉모습·대표 카드 동작은 불변. |
| `docs/db-schema.md` | `get_worksite_public_detail` 시그니처 변경 반영(스키마 변경 동반 갱신). |
| `web/supabase/README.md` / 관련 README | RPC 변경 한 줄. |

DB는 **마이그레이션 1개(RPC 리턴 타입 변경)** 뿐. 나머지는 프론트.

## 7. 엣지 케이스

- **공고 1개뿐(대표만):** 다른 공고 목록 비어 섹션 미표시.
- **대표가 placeholder(국가근로):** 비-placeholder 없음 → 섹션 미표시. 현행 동일.
- **`job_description` 없음:** 접힌 줄 라벨 `(직무 미상)`으로.
- **정렬 일관성:** 로그인 경로(테이블 쿼리)와 비로그인 경로(RPC)의 정렬을
  **동일 규칙**(`is_active desc, created_at desc`)으로 맞춘다. 대표=배열 첫 원소.
- **모집 상태 배지:** 공고별 `effectiveActive`(recruit_until 기반, 현행 로직)로
  각 줄 독립 판정.
- **SSC 이력 대량 유입:** 서버가 **최근 30개로 캡**(Fable #2) — 응답 비대·페이지
  폭증 방지. 30개 초과 부서가 실제로 생기면 "지난 공고 더보기"(페이지네이션)는
  후속 — 이번 범위 밖.

## 8. 구현 순서

1. **마이그레이션** — `get_worksite_public_detail` 배열 반환. 로컬 검증(같은
   근무지 상세가 배열로 오는지, 국가근로 폴백) 후 수동 `db push`.
2. **`InfoCard` 리팩터** — `PostingFields` 추출(겉모습 회귀 없는지 확인).
3. **`worksiteQueries.js`** — `fetchPostings` + `fetchWorksitePublicDetail` 배열화.
4. **`PostingList` 신규** + CSS.
5. **`WorksiteDetail.jsx` 배선** — 3개 경로 배열 통일, 대표+목록 렌더.
6. **검증** — 학교근로(다중 공고)·국가근로(단일 placeholder)·비로그인·무열람권·
   열람권 5경우 육안 확인.

## 8.5. 구현 중 변경 (2026-07-21 확정)

로컬 5173 검증에서 배경록 결정으로 스펙과 달라진 것:

- **`is_placeholder`는 클라 테이블 쿼리에서 셀렉트하지 않음** — `postings`는 컬럼
  화이트리스트 grant(`20260713144538`)라 grant 밖 컬럼 셀렉트 = 전체 `permission
  denied`. `selectPostings`는 필드 부재를 非-placeholder로 취급해 동작 동일.
  placeholder 필터는 security definer RPC(비로그인 경로)만 수행 — grant 추가 불필요.
- **접힌 줄 단순화**: 태그 클러스터(모집중/완료·모집기간) 제거 → **직무 요약 +
  `마감 YYYY-MM-DD`**(추정값이면 `마감(추정)`, `recruit_until_estimated`). 상태는
  줄 좌측 테두리 색(`status-open` 파랑/`closed` 회색)이 담당. `created_at`은 크롤
  적재일이라 '올라온 날짜'로 쓰지 않음.
- **직무 없는 공고는 목록에서 제외**(`hasJobDescription`) — "(직무 미상)" 줄 방지.
  옛 KUPID 파싱 실패분 포함, DB엔 유지(SSC 재크롤이 채우면 자연 복귀).
- **최근 3개년 필터**(`filterRecentPostings`) — 기준은 `recruit_until` 우선,
  없으면 `created_at` 폴백, 둘 다 없으면 유지. 섹션 제목 "이 근무지의 최근 3개년
  공고 N개". 대표는 필터 밖.
- **목록 위치** — InfoCard 바로 아래가 아니라 **점수 요약 아래**(넓은·좁은 공통).

## 9. 미해결 / 후속

- **공고명(`title`) 컬럼** — SSC 크롤러 후속에서 추가하면 접힌 줄 라벨이
  `job_description` truncate → 실제 공고명으로 개선. 이번 범위 밖.
- **B/C(리뷰 분리·역할 태그)** — 부서당 리뷰가 충분히 쌓이고 자동 분리 신뢰도가
  확보되면 재검토.
- **"지난 공고 접기/더보기"** — 이력이 실제로 길어지면 도입. 지금은 전량 노출.
