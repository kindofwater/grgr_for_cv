# ② 리워드 광고 서버 (로컬 직접 사진광고) — 설계서

- 날짜: 2026-06-24
- 작성: 배경록(PM) · 검토/사인오프: **현수(kindofwater) — 광고 보상·RPC·DB 영역**
- 상태: **제안(Proposal)**. 배경록 주도 설계·구현 → 현수 사인오프 후 `db push`.
- 관계: **①[Supabase Auth+RLS 컷오버](2026-06-24-supabase-auth-rls-cutover-design.md)(LIVE)의 후속.** 신원이 확보돼 `watch_ad_reward` 어뷰징 차단이 가능해짐. 현재 `watch_ad_reward()`는 `auth.uid()`이나 **캡·완료검증·진짜 광고가 없어** 콘솔 무한적립 여지 → 본 스펙이 토큰 흐름으로 교체.
- 6/16 회의 광고 결정 반영(`docs/회의록-2026-06-16.md` §광고 수익화): 사진·로컬·인스타 리다이렉트·5초·Adsterra 미사용·캡(미결)·등록 스캐폴딩=현수. (트랙ⓑ AdSense·영상은 미래.)

---

## 1. 배경 · 목표
①로 "서버가 신뢰하는 신원"이 생겼다. 이제 광고 보상을 **진짜 광고 + 토큰 + 시간 + 캡**으로 검증해 어뷰징을 막는다. 광고는 **자체 직접광고(로컬 가게 사진)** — 5초 보면 +5P, 클릭하면 그 가게 인스타/네이버지도로(선택). 광고주 가치 = 노출 + 인스타 트래픽.

## 2. 범위
**포함:** `ads` 인벤토리 + Supabase Storage(이미지) + 서빙(`start_ad_view`) + 검증·적립(`claim_ad_reward`) + 캡/쿨다운(설정값) + 클릭 로그(`log_ad_click`). 기존 `watch_ad_reward()` **제거**.
**제외(후속):** 트랙ⓑ **AdSense**·**영상** 광고·디스플레이 배너(트랙1)·**풀 관리자 등록 UI**(6/16 현수)·정교한 사기탐지(SSV/ML).

## 3. 확정 결정
| # | 결정 |
|---|---|
| D1 | 소재 = **사진**. 클릭 → 그 가게 인스타/네이버지도 (**선택**, 보상과 무관) |
| D2 | 보상 = **강제 시청**(min_view_seconds 월클럭, 기본5초). 그 시간 동안 '받기'·'가게 보러가기' **잠금**(카운트다운), **'그냥 나가기(미지급)'는 언제든 가능**. 시간 후 받기(+P)·클릭 해제. 클릭은 보상 무관(post-view 보너스 = 광고주 트래픽). → 클릭=스킵 문제 원천 차단 |
| D3 | 검증 = **토큰 + 시간 + 캡** (자체 호스팅판 SSV — "클라 바 호출 안 믿기". 진짜 SSV는 트랙ⓑ) |
| D4 | 캡 = **하루 2회 · 회당 5P · 쿨다운 0**(초기). 단 **설정값**(`ad_reward_config`), 변경=UPDATE |
| D5 | 시청시간 = **`ads.min_view_seconds` 데이터**(기본 5). 나중 15초 = UPDATE 한 줄, 코드 변경 0 |
| D6 | 클릭 추적 = **`ad_clicks` 포함** (광고주에게 보여줄 가치) |
| D7 | 분담 = 배경록 주도 + **현수 사인오프** |
| D8 | 투트랙 중 **이 스펙 = 로컬 트랙ⓐ만** |

> **원칙: 시청시간·캡·보상포인트는 코드에 하드코딩 금지 — 전부 데이터/설정으로.**

## 4. 설계

### A. 데이터 모델
- **`ads` (신규):** `id serial pk, title text, media_path text(Storage 경로), media_type text not null default 'photo'(photo|video — 미래 영상 대비), target_url text(인스타/네이버), min_view_seconds int not null default 5, is_active boolean not null default true, created_at timestamptz default now()`.
- **`ad_reward_config` (신규, 싱글톤):** `id int pk default 1 check(id=1), daily_cap int not null default 2, reward_points int not null default 5, cooldown_minutes int not null default 0, updated_at timestamptz default now()`. 한 행. 캡/보상 변경 = 이 행 UPDATE.
- **`ad_views` (기존 확장):** 현재 `id, user_id(uuid, SET NULL), created_at`. **추가:** `ad_id int references ads(id) on delete set null`, `token uuid not null unique default gen_random_uuid()`, `claimed_at timestamptz`(null=미적립). 의미: `created_at`=광고 노출(시작) 시각, `claimed_at`=보상 지급 시각. (행 1개 = 노출 1건, 적립 여부 포함.)
- **`ad_clicks` (신규):** `id serial pk, ad_id int references ads(id) on delete set null, user_id uuid references users(id) on delete set null, created_at timestamptz default now()`.
- `points.ad_view_id` 링크 유지(적립된 ad_views 행 참조).

**RLS** (① 정책 철학 유지 — 쓰기는 전부 DEFINER RPC):
- `ads`·`ad_reward_config`: RLS on, **클라 SELECT 정책 없음**(서빙은 `start_ad_view` RPC가 DEFINER로 읽어 내려줌). 쓰기 = 관리자/service_role.
- `ad_views`: RLS on, **본인 SELECT**(`adviews_select_own` 이미 존재). 쓰기 = RPC만.
- `ad_clicks`: RLS on, **클라 정책 없음**(쓰기 = `log_ad_click` RPC, 읽기 = 관리자).

### B. Storage (이미지)
- 버킷 **`ad-media`**(사진·영상 공용) — **공개 read**(광고 소재는 공개), 쓰기 = 관리자/service_role. `start_ad_view`가 `media_path` → public URL을 반환.

### C. 서빙 — `start_ad_view()` RPC (DEFINER, authenticated)
1. `v_uid := auth.uid()`; null이면 `NOT_AUTHENTICATED`.
2. `ad_reward_config` 읽기. **캡/쿨다운 검사**: 오늘(`created_at::date = current_date`) 본인 `claimed_at not null` 수 ≥ `daily_cap` → `CAP_REACHED`. (cooldown>0이면 마지막 claim + cooldown > now도 차단.)
3. 활성 광고 랜덤 1개(`is_active`); 없으면 `NO_ADS`.
4. `ad_views` insert(`user_id=v_uid, ad_id, token=gen_random_uuid()`).
5. return `jsonb { ad: { id, title, media_url(public URL), media_type, target_url, min_view_seconds }, token }`.

### D. 검증·적립 — `claim_ad_reward(p_token uuid)` RPC (DEFINER, authenticated) — 핵심
1. `v_uid := auth.uid()`; null이면 `NOT_AUTHENTICATED`.
2. 토큰으로 본인 미적립 ad_view 찾기(`token=p_token and user_id=v_uid and claimed_at is null`); 없으면 `INVALID_TOKEN`.
3. **시간검증:** `now() ≥ created_at + (해당 ad의 min_view_seconds * interval '1 second')` 아니면 `TOO_SOON`.
4. **캡/쿨다운 재검사**(시작~적립 사이 초과 방지) → `CAP_REACHED`.
5. `update ad_views set claimed_at=now() where id=...`; `insert points(v_uid, reward_points, 'ad_view', ad_view_id)`; `update users.point_balance += reward_points`; `return _wallet()`.
- ⚠️ **`watch_ad_reward()`는 `drop function if exists` + revoke** — 적립 경로를 토큰 흐름으로만 한정(콘솔 직접호출 차단 = ②의 핵심 성과).

### E. 클릭 — `log_ad_click(p_ad_id int)` RPC (DEFINER, authenticated)
- `v_uid := auth.uid()`; `insert ad_clicks(p_ad_id, v_uid)`. fire-and-forget(실패해도 UX 안 막음).

### F. 클라이언트 (강제 시청 UX)
- **`web/src/data/adQueries.js`(신규):** `startAdView()`, `claimAdReward(token)`, `logAdClick(adId)`. (기존 `watchAdReward` 제거.)
- **`web/src/pages/AdView.jsx` 재작성:** mount 시 `startAdView()` → 광고 소재(`media_type`=photo→`<img>`, 미래 video→`<video>`) + **`min_view_seconds` 카운트다운**(서버값, 하드코딩 X).
  - **카운트다운 중:** "받기"·"가게 보러가기" **잠금**(비활성, 남은 초 표시). **"그냥 나가기(포인트 미지급)"는 항상 활성**(교환센터로 복귀).
  - **카운트다운 후 해제:**
    - "받기"(+P) → `claimAdReward(token)` → `mergeUser(wallet)` → 교환센터.
    - "가게 보러가기" → `target_url` **새 탭** + `logAdClick(adId)` + `claimAdReward(token)`(미적립이면 적립 — 5초 지났으니 통과).
  - 둘 중 무엇이든 적립은 **1회**(`claimed_at`). `CAP_REACHED`("오늘 광고 보상은 다 받으셨어요")·`NO_ADS`("지금은 광고가 없어요") 처리.
- 서버(`claim_ad_reward`)가 5초 월클럭을 **별도 검증** → 클라 잠금 + 서버 = **이중 방어**.

### G. 광고 등록 (admin)
- **v1:** 광고가 몇 곳뿐 → **Supabase 대시보드/시드 SQL로 `ads` insert + 이미지 Storage 수동 업로드.** 풀 관리자 UI는 후속(현수).

## 5. 마이그레이션 · 롤아웃 (CLAUDE.md §3)
- 마이그레이션 1파일: `ads`·`ad_reward_config`·`ad_clicks` 생성, `ad_views` 컬럼 추가, RLS+정책, `start_ad_view`/`claim_ad_reward`/`log_ad_click` 생성, **`watch_ad_reward` drop+revoke**, `ad_reward_config` 기본행 insert. 헤더 2줄, `drop function if exists` 먼저.
- **Storage 버킷 `ad-media`** 생성(대시보드 수동 1회) + 공개 read 정책.
- **시드 광고**(배경록 수주분) 등록.
- Docker 없음 → 정적 검토 + 사인오프 후 `db push`(현수 조율). 클라 AdView 교체.
- `docs/db-schema.md`·`api-spec.md`·관련 README 갱신.

## 6. 미결 / 협의
- 현수 사인오프(광고 보상·DB push 순서).
- Storage 버킷 생성(대시보드 1회).
- 쿨다운 도입 여부(현재 0 — 하루 2회를 연속 가능; 필요시 cooldown_minutes만 올리면 됨).

## 7. 범위 밖 / 후속
- 트랙ⓑ **AdSense**(디스플레이, 보상 불가 — 정책), **영상** 광고(트랙ⓑ에서 min_view 15초+토큰 재활용 가능), 디스플레이 배너(트랙1), 풀 관리자 등록 UI, 사기탐지.
- **회원탈퇴 시 탈퇴→재가입 어뷰징**이 본 캡을 우회할 수 있음([[project-withdrawal-deferred]]) — 회원탈퇴 스펙과 **재가입 쿨다운**을 같이 볼 것.
