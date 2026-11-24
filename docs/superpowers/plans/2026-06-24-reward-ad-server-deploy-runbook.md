# ② 리워드 광고 서버 — 배포 런북 (PM 배경록 단독 실행 · 현수 검토)

> 대상 마이그레이션: `web/supabase/migrations/20260624170000_reward_ad_server.sql`
> 선행 ① Auth+RLS 컷오버는 이미 LIVE. 이 작업은 ② 리워드 광고 서버를 prod에 올리는 것.
> 작성 근거: 마이그레이션/클라계약/배포경로 정적 교차검증 + 적대적 리뷰(2026-06-24).
>
> **상태(2026-06-26): 배포 실행 완료.** ad-media 버킷·이미지(재즈프레소)·`db push`(20260624170000)·실제 ads INSERT·`git push`(origin/main = `fae8e0a`) 모두 완료. UI는 `/ad` 페이지 → **교환센터 모달(`components/AdModal`)** 로 리팩터됨(닫기는 X·받기·이미지만, 가게는 새 탭, 미디어 onLoad 후 5초). **남은 것: 현수 사인오프(9단계) + 출시 전 `daily_cap` 1000000→2 복구**(현재 테스트로 무제한 설정해둠).

## 0. 전제 — 검증으로 확인된 사실

- **마이그레이션은 1회 `db push` 기준 건전.** `gen_random_uuid()`는 PG15 core라 ① pgcrypto 드롭과 무관(컷오버가 이미 같은 함수로 uuid화에 성공). `ad_views` ALTER·`watch_ad_reward` drop·RLS 전부 OK.
- **클라↔RPC 계약 정확.** `start_ad_view`는 `media_path`(설계서의 `media_url` 아님)를 반환 → 클라 `adMediaUrl(ad.media_path)`와 일치(이미지 안 깨짐). 인자 `p_token`/`p_ad_id`·리턴 필드·지갑 shape 모두 일치.
- **grant 사고 위험 없음.** `web/src` 전체에서 `ads`/`ad_clicks`/`ad_reward_config`/`ad_views` 직접 `.from()` 쿼리 **0건** → 전부 SECURITY DEFINER RPC 경유. 신규 3테이블에 테이블 grant가 없어도 안전(컷오버 때의 "permission denied" 재발 안 함).
- **클라/DB lockstep.** 로컬 main의 `adQueries.js`는 신규 3 RPC만 호출하고 `watch_ad_reward` 참조 0.
- **배포 현실: 공개 prod 프론트 없음.** CI·호스팅 연동 0건 — 전원 로컬 `npm run dev`(localhost:5173), env는 각자 `web/.env.local`. → "원자적 배포"는 호스팅 전환이 아니라 **디스코드 공지 + 각자 git pull + dev 재시작**으로 처리.

### 사전 보강(이미 마이그레이션에 반영됨 — 추가 SQL 편집 불필요)
검증에서 나온 footgun을 push 전에 SQL에 박아 두었다. 현수 검토 시 아래가 들어있는지 확인:
- **시드 placeholder 제거** — prod `ads`에 `seed-placeholder.jpg`를 넣지 않음(버킷에 없는 파일을 `order by random()`이 뽑아 깨진 이미지 노출하는 사고 차단). 실제 광고는 push 후 4단계에서 직접 INSERT.
- **NO_CONFIG 가드** — `start_ad_view`·`claim_ad_reward` 둘 다 `ad_reward_config`가 비면 예외. (config가 비면 `cap >= NULL`이 false라 캡이 무력화되던 footgun 차단 — "빡빡한 캡" 보장. 특히 실제 적립하는 `claim_ad_reward` 쪽이 핵심.)
- **멱등화** — `create table if not exists`·`add column if not exists`·`create unique index if not exists`·config insert `on conflict (id) do nothing` → 부분 실패 후 재push 안전.

---

## 1단계 — Storage `ad-media` 버킷 생성 (공개 read)

클라(`adQueries.js`)가 `supabase.storage.from('ad-media').getPublicUrl(path)`로 이미지 URL을 만든다. 버킷이 없으면 이미지가 깨진다. **이 단계는 additive라 push 전에 미리 해도 기존 광고가 안 깨진다.**

Supabase 대시보드:
1. 프로젝트 → 왼쪽 **Storage**.
2. **New bucket**.
3. **Name**: `ad-media` (정확히 이 문자열 — 클라 하드코딩과 일치), **Public bucket**: **ON**, 나머지 기본값.
4. **Create bucket**.

---

## 2단계 — 광고 이미지 업로드 (경로 확인)

1. **Storage** → `ad-media` → **Upload file** 로 실제 광고 이미지 업로드 (예: `seed-ad-1.jpg`).
2. 업로드 파일 클릭 → **파일명(=경로)** 확인. 버킷 루트에 올렸으면 `media_path` 값은 그냥 `seed-ad-1.jpg`. **버킷명 `ad-media`는 경로에 포함하지 않는다**(`getPublicUrl`이 알아서 붙임).
3. 영상 광고면 영상 파일을 올리고 4단계에서 `media_type='video'`로.

---

## 3단계 — db push (PM이 직접)

### 3-1. push 전 디스코드 한 마디 (CLAUDE.md §3 필수)
> "②리워드 광고 db push 들어갑니다. 옛 `/ad` 켜둔 dev 서버 잠깐 내려주시고, 끝나면 `git pull` 후 dev 재시작 부탁."

→ push 순서 꼬임 + 옛 클라가 drop된 `watch_ad_reward`를 부르는 404 창을 0에 가깝게.

### 3-2. 시그니처 변경 drop 확인
마이그레이션에 `drop function if exists watch_ad_reward();` 이미 포함(무인자 = LIVE 시그니처와 정확히 일치). **별도 drop 불필요.** 신규 3 RPC는 신규 생성이라 drop 대상 아님.

### 3-3. push 실행
```bash
cd web && npx supabase db push
```
- 적용 목록에 `20260624170000_reward_ad_server`가 뜨는지 확인 후 진행.
- 단일 트랜잭션이라 중간 실패 시 전체 롤백.
- push가 죽으면 재시도 전에 `npx supabase migration list`로 적용 상태 확인(부분 적용 흔적 점검) → 멱등화돼 있어 재push 안전.

---

## 4단계 — 실제 광고 INSERT (SQL Editor) · placeholder 없음

push로 `ads` 테이블이 생겼다(시드 행 없음 → 지금 광고 모달은 `NO_ADS`). 대시보드 **SQL Editor**에서 실제 광고를 넣는다:

```sql
insert into ads (title, media_path, target_url, media_type) values
  ('실제 가게 이름', 'seed-ad-1.jpg', 'https://instagram.com/실제계정', 'photo');
```
- `media_path` = 2단계에서 확인한 실제 경로.
- ⚠️ **`media_type`은 업로드 파일과 반드시 일치** — 이미지면 `'photo'`, 영상이면 `'video'`. 불일치 시 `<img>`/`<video>` 분기가 어긋나 미디어가 깨진다.
- 광고 여러 개면 행을 더 INSERT. `is_active = true`(기본값)인 행 중 `order by random()`으로 하나 노출.

**검증:** `select id, title, media_path, target_url, media_type, is_active from ads;` — `seed-placeholder.jpg`가 **없어야** 정상(애초에 안 넣음).

---

## 5단계 — 로컬 클라 동기화

```bash
git pull        # 이미 main이면 생략
cd web && npm run dev
```
- 로컬 main의 `adQueries.js`/`components/AdModal.jsx`가 이미 신규 RPC만 호출하므로 git pull 후 재시작이면 끝.
- 팀원에게 "push 완료, `git pull` + dev 재시작" 알림. 실질 광고 깨짐 창 = "db push ~ 각자 재시작" 사이뿐.

---

## 6단계 — 스모크 테스트 (교환센터 광고 모달)

> ⚠️ **당일 구-적립 이력이 없는 클린/신규 계정으로 할 것.** 마이그레이션이 기존 `ad_views`(구 `watch_ad_reward`가 남긴 행)의 `claimed_at`을 backfill하므로, 당일 옛 시스템으로 광고를 본 계정은 캡 카운트가 이미 차 있어 "1회 만에 capped"로 보일 수 있다(버그 아님).

로그인 상태로 **`/exchange`(교환센터) → "광고 시청하기"** 클릭 → 광고 모달:
- [ ] **카운트다운**: 광고가 실제로 뜬 뒤(onLoad)부터 우상단 X 둘레로 5초 링이 차오름. 그 전 "포인트 받기" 버튼 disabled.
- [ ] **이미지 정상**: 광고 이미지가 깨지지 않음(버킷·경로·`media_type` 정합). 영상이면 자동재생(muted). 가장자리에 흰선/검은띠 없음.
- [ ] **받기 +5P**: 5초 후 "포인트 받기 →" → 모달 닫힘 + 사이드바 포인트 +5P 즉시 갱신.
- [ ] **points 행 생성(RLS+DEFINER INSERT 통과 확인)**: `select user_id, amount, reason from points where reason='ad_view' order by id desc limit 3;`
- [ ] **이미지 클릭=가게(새 탭)**: 5초 후 광고 이미지 클릭 → 새 탭으로 `target_url`(`_blank,noopener,noreferrer`) 열림 + 클릭 로그 + 적립 + 모달 닫힘. `select * from ad_clicks order by id desc limit 3;`
- [ ] **캡 2회 후 CAP_REACHED**: 같은 계정으로 적립 2회(=daily_cap) 후 다시 "광고 시청하기" → 모달이 "오늘 광고 보상은 다 받으셨어요."
- [ ] **5초 전 X = 미지급 퇴장**: 카운트 도는 중 X로 닫으면 포인트 변화 없음(claim 안 일어남). **배경 클릭/Esc로는 안 닫힘** — 닫기는 X·받기·이미지 3가지만.
- [ ] **5초 후 X = 받고 나가기**: 카운트 끝난 뒤 X로 닫아도 +5P 적립되고 닫힘.
- [ ] DB 최종: `select user_id, ad_id, claimed_at from ad_views order by created_at desc limit 5;` — 적립 건은 `claimed_at` 채워짐, 미지급은 NULL.

---

## 7단계 — git push (PM이 직접)

```bash
git status            # 보강한 .sql·문서가 커밋됐는지 확인
git push origin main
```
- 에이전트는 push 안 함(CLAUDE.md) — **push는 PM이 직접.** 자동배포 트리거 없음(CI 없음). 목적은 팀원이 `git pull`로 lockstep 클라를 받게 하는 것.
- prod에 적용된 SQL과 리포가 일치해야 드리프트가 안 생긴다(보강분 커밋 필수).

---

## 8단계 — 롤백 / 킬스위치

`db push`는 단일 트랜잭션 → **push 중 에러면 자동 전체 롤백**(부분 적용 없음). 에러 메시지 보고 재push(멱등화돼 안전).

**push 성공 후 문제 발견 시:**
- 즉시 광고 끄기(코드 변경 없이): `update ads set is_active = false;` → `start_ad_view`가 `NO_ADS` → 광고 모달이 "광고 없어요"로 안전 정지. **가장 빠른 킬스위치.**
- 보상 0으로: `update ad_reward_config set reward_points = 0 where id = 1;`
- 구조 되돌리기(테이블/RPC 제거)는 **새 reverting 마이그레이션**으로만(`migration new` → drop). **SQL 에디터 수동 DROP 금지**(CLAUDE.md §3 드리프트). `ad_views` 추가 컬럼/인덱스 되돌림은 데이터 손실 위험 → 함부로 drop 말고 킬스위치로 버티며 원인 수정 후 새 마이그레이션.

---

## 9단계 — 현수(kindofwater) 검토 체크리스트

- [ ] **사전 보강 반영**: 시드 INSERT가 prod에 placeholder를 안 넣음(주석 처리), `start_ad_view`·`claim_ad_reward` 둘 다 `if v_cfg.id is null then raise exception 'NO_CONFIG'`, config insert `on conflict (id) do nothing`, create/alter/index에 `if not exists`.
- [ ] **클라 직접 쿼리 0건**: `web/src`에서 `ads`/`ad_clicks`/`ad_reward_config`/`ad_views` 직접 `.from()` 없음 → 신규 3테이블 grant 부재 무해 동의.
- [ ] **watch_ad_reward 잔존 참조 0건**: 클라 어디에도 호출 없음 → drop 후 404 위험 없음.
- [ ] **RPC 시그니처 정합**: `start_ad_view()`/`claim_ad_reward(p_token uuid)`/`log_ad_click(p_ad_id int)` ↔ `adQueries.js`.
- [ ] **media_path vs media_url**: `start_ad_view`가 `media_path` 반환, 클라 `adMediaUrl(ad.media_path)` 사용 — 일치.
- [ ] **지갑 shape**: `claim_ad_reward` → `_wallet()`(point_balance/pass_balances/pass_expires_at), `mergeUser` 스프레드 머지 수용.
- [ ] **DEFINER·grant**: 세 RPC `security definer`+`set search_path`, anon/public revoke + authenticated grant.
- [ ] **운영 선행**: `ad-media`(Public) 버킷 생성, 이미지 업로드, `ads` 행이 실제값(`seed-placeholder.jpg` 잔존 0).
- [ ] **스모크 통과**(6단계, 클린 계정): 캡 2회 후 CAP_REACHED, 5초 전 X로 닫기 미지급, points 행 생성.
- [ ] **킬스위치 인지**: `update ads set is_active = false;`로 즉시 정지 가능.

---

## 관련 파일
- 마이그레이션: `web/supabase/migrations/20260624170000_reward_ad_server.sql`
- 클라 RPC 래퍼: `web/src/data/adQueries.js` · 광고 모달: `web/src/components/AdModal.jsx`
- 스키마/계약 문서: `docs/db-schema.md §② 리워드 광고 서버` · `docs/api-spec.md §4`
- 설계·계획: `docs/superpowers/specs/2026-06-24-reward-ad-server-design.md` · `docs/superpowers/plans/2026-06-24-reward-ad-server.md`
