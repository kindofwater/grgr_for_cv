# 근로고래 DB 스키마

---

## Auth+RLS 컷오버 — **적용됨 (2026-06-24 prod 반영)**

> **컷오버 마이그레이션(`20260624025109_auth_rls_cutover.sql`)은 2026-06-24 prod에 push·적용 완료.**
> 회원가입·로그인·리뷰·포인트·열람권·광고 시청 모두 정상 동작 확인.
>
> **후속 핫픽스 (동일 일자 적용):**
> - `20260624160000_grant_authenticated_select.sql` — `authenticated` 롤에 공개 카탈로그 테이블(`worksites`, `postings`, `notices`, `universities`, `colleges`, `departments`) `SELECT` 권한 부여. 컷오버 전 이 롤은 미사용 상태라 권한이 없었고, 로그인 유저가 "permission denied for table" 에러를 겪었음 → 핫픽스로 해결.
> - `AuthContext.jsx` 클라이언트 픽스 — `onAuthStateChange` 콜백 내부에서 `supabase` 직접 호출(fetchMe)을 하면 GoTrue 내부 lock과 데드락이 발생해 무한 "로딩 중" 상태가 됨 → `setTimeout(0)`으로 다음 틱에 실행하도록 수정.

### 변경 요약

#### 인증 방식
- **제거:** 자체 `password_hash` 컬럼, `pgcrypto` 익스텐션, `verify_login` / `register_user` / `set_password` RPC
- **도입:** Supabase Auth (`auth.users`). 클라이언트는 `supabase.auth.signUp` / `signInWithPassword` 사용. 가입 시 이메일 확인 ON.
- **가입 제한:** `handle_new_user` 트리거가 `universities.email_domain` + 신규 `signup_enabled` 컬럼을 검증 → 현재 `@korea.ac.kr`만 허용.

#### `users` 테이블 변경
| 항목 | 컷오버 전 (폐기) | 컷오버 후 (현재 live) |
|------|----------------------|----------------------|
| `id` 타입 | `SERIAL int` (auto-increment) | `UUID` = `auth.users.id` (1:1, ON DELETE CASCADE) |
| `email` 컬럼 | `VARCHAR(255) UNIQUE NOT NULL` | **삭제** (이메일 정본 = `auth.users.email`) |
| `password_hash` 컬럼 | `VARCHAR(255) NOT NULL` | **삭제** |

#### `universities` 테이블 변경
- `signup_enabled BOOLEAN NOT NULL DEFAULT false` 컬럼 추가. 현재 `korea.ac.kr`만 `true`.

#### FK uuid화 (6개)
컷오버 시 `users.id`가 uuid로 바뀌면서 아래 테이블의 FK도 모두 `uuid`로 변경됨:
`reviews.user_id` / `review_helpful.user_id` / `ad_views.user_id` / `points.user_id` / `reports.reporter_id` / `reports.reported_user_id`

#### RLS (전 12테이블 활성화)
| 테이블 | 정책 |
|--------|------|
| `users` | `authenticated` 본인 행 select/update. 특권 컬럼(`point_balance`, `pass_balances`, `pass_expires_at`, `is_admin`) 직접 수정 차단(컬럼 GRANT 제한) |
| `points` | `authenticated` 본인 행 select |
| `ad_views` | `authenticated` 본인 행 select |
| `review_helpful` | `authenticated` 본인 행 select |
| `reviews` | `authenticated` 본인 행 select (열람은 `list_worksite_reviews` RPC 통해서만) |
| `worksites` / `postings` / `universities` / `colleges` / `departments` | `anon` + `authenticated` 읽기 허용 (공개 카탈로그) |
| `notices` | 공통 공지(`university_id IS NULL`)는 `anon` + `authenticated` 읽기 허용, 학교 공지는 해당 학교의 로그인 사용자만 읽기 허용 |
| `reports` | 클라 정책 없음 (service_role/관리자만) |

#### RPC 변경 요약
**p_user_id 인자 제거 → `auth.uid()` 사용 (10개):**
`_wallet()` / `purchase_pass(p_days int)` / `refund_pass(p_days int)` / `activate_pass(p_days int)` / `change_nickname(p_nickname text)` / `watch_ad_reward()` / `toggle_helpful(p_review_id int)` / `update_profile(p_region, p_admission_year, p_degree_program, p_academic_status, p_grade, p_college_name, p_department_name, p_track)` / `write_review_with_points(...)` / `update_review_with_points(...)` / `delete_review_with_rollback(p_review_id int)`
- 위 모든 RPC: `anon` 실행 권한 회수, `authenticated`만 허용.

**신규 RPC:**
| 함수 | 설명 | 권한 |
|------|------|------|
| `handle_new_user()` | auth.users INSERT 트리거. `raw_user_meta_data`에서 프로필 추출 → `public.users` 행 생성. `signup_enabled` 미충족 시 예외. | 트리거 (직접 호출 불가) |
| `list_worksite_reviews(p_worksite_id int)` | 리뷰 목록 반환. `is_anonymous=true`면 닉네임→`'익명'`, `work_semester→null` 마스킹. `user_id` 미반환. 열람권(`pass_expires_at > now()`) 또는 본인 리뷰만 반환 — 애드센스 재심사용 한시 전면 공개는 2026-11-09 00:00(KST)에 종료(20260927090000 → 연장 20261007102907 → 종료 20261109020715) | `anon`·`authenticated` (anon은 공개 기간 후 0행) |
| `increment_worksite_view(p_worksite_id int)` | 로그인 사용자의 근무지 조회를 KST 일자별 1회 기록하고 누적 조회수 증가 | `authenticated`만 |
| `report_review(p_review_id int, p_reason text, p_opinion text)` | 신고 삽입. `reporter_id = auth.uid()`. `p_opinion` 필수(빈값 `OPINION_REQUIRED`, 500자 초과 `OPINION_TOO_LONG`) | `authenticated`만 |

---

---

## ② 리워드 광고 서버 — **적용됨 (2026-06-25 LIVE, migration 20260624170000)**

> **2026-06-25 prod 적용·동작 확인 완료(LIVE).** db push + `ad-media` 공개 버킷 + 시드(ads 2행) + 클라(`AdModal`)까지 배포됨. 담당: 현수(kindofwater).
> ⚠️ 배포 시 디버깅용으로 `ad_reward_config.daily_cap`을 큰 값으로 둔 이력 있음 — ~~실서비스 전 `update ad_reward_config set daily_cap=2 where id=1;` 확인~~ → **migration `20260717140000`으로 2 확정(§⑨)**.

### 신규 테이블

#### `ads` — 광고 인벤토리
| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | `serial PK` | 광고 고유 ID |
| `title` | `text NOT NULL` | 광고 제목 |
| `media_path` | `text NOT NULL` | 미디어 경로 (Storage 버킷 `ad-media` 기준) |
| `media_type` | `text NOT NULL DEFAULT 'photo'` | `'photo'` 또는 `'video'` |
| `target_url` | `text` | 클릭 시 이동 URL |
| `min_view_seconds` | `int NOT NULL DEFAULT 5` | 최소 시청 시간(초) — 이 이후에만 적립 가능 |
| `is_active` | `boolean NOT NULL DEFAULT true` | 활성 여부 |
| `created_at` | `timestamptz NOT NULL DEFAULT now()` | 등록 일시 |

#### `ad_reward_config` — 보상 설정 (싱글톤, id=1 고정)
| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | `int PK DEFAULT 1 CHECK(id=1)` | 싱글톤 키 |
| `daily_cap` | `int NOT NULL DEFAULT 2` | 일일 최대 적립 횟수 — **현재 운영값 1** (20260731105714, 컬럼 default는 2 유지) |
| `reward_points` | `int NOT NULL DEFAULT 5` | 1회 적립 포인트 |
| `cooldown_minutes` | `int NOT NULL DEFAULT 0` | 시청 간 최소 간격(분). 0이면 제한 없음 |
| `updated_at` | `timestamptz NOT NULL DEFAULT now()` | 설정 수정 일시 |

> 캡·보상·쿨다운은 **데이터로 관리** — 코드 하드코딩 없음.

#### `ad_clicks` — 클릭 로그
| 컬럼 | 타입 | 설명 |
|------|------|------|
| `id` | `serial PK` | 로그 고유 ID |
| `ad_id` | `int REFERENCES ads(id) ON DELETE SET NULL` | 클릭한 광고 |
| `user_id` | `uuid REFERENCES users(id) ON DELETE SET NULL` | 클릭한 유저. 탈퇴 시 NULL |
| `created_at` | `timestamptz NOT NULL DEFAULT now()` | 클릭 일시 |

### `ad_views` 테이블 확장
기존 `ad_views`(컷오버에서 user_id uuid화)에 컬럼 3개 추가:

| 추가 컬럼 | 타입 | 설명 |
|-----------|------|------|
| `ad_id` | `int REFERENCES ads(id) ON DELETE SET NULL` | 시청한 광고 |
| `token` | `uuid NOT NULL DEFAULT gen_random_uuid()` | 1회용 적립 토큰 (UNIQUE) |
| `claimed_at` | `timestamptz` | 포인트 적립 시각. NULL이면 미적립 |

### 신규 RPC

모두 `SECURITY DEFINER`, `authenticated`만 실행 가능 (anon 권한 없음).

#### `start_ad_view()` → `jsonb`
광고 1개를 랜덤 선택해 `ad_views` 행을 생성하고 1회용 토큰을 반환.

- 일일 캡 초과 시 `CAP_REACHED` 예외.
- 쿨다운(`cooldown_minutes`) 미경과 시에도 `CAP_REACHED` 예외.
- 활성 광고 없으면 `NO_ADS` 예외.

**반환:**
```json
{
  "ad": { "id", "title", "media_path", "media_type", "target_url", "min_view_seconds" },
  "token": "<uuid>"
}
```

#### `claim_ad_reward(p_token uuid)` → `jsonb`
토큰·시청 시간·일일 캡을 검증한 후 `reward_points`를 지갑에 적립.

| 파라미터 | 타입 |
|----------|------|
| `p_token` | `uuid` |

**에러 코드:**
| 코드 | 의미 |
|------|------|
| `NOT_AUTHENTICATED` | 로그인 안 됨 (`auth.uid()` null) |
| `INVALID_TOKEN` | 토큰 없음·이미 사용됨·다른 유저 토큰 |
| `TOO_SOON` | `min_view_seconds` 미경과 |
| `CAP_REACHED` | 일일 캡 초과 |

**반환:** `_wallet()` 와 동일 shape (`point_balance`, `pass_balances`, `pass_expires_at`, `hour_pass_minutes` — §⑭ 참고)

#### `log_ad_click(p_ad_id int)` → `void`
광고 클릭을 `ad_clicks`에 기록. 실패해도 클라이언트가 무시해도 됨 (fire-and-forget 적합).

| 파라미터 | 타입 |
|----------|------|
| `p_ad_id` | `int` |

### 제거되는 RPC

| 함수 | 대체 |
|------|------|
| `watch_ad_reward()` | `start_ad_view()` + `claim_ad_reward(p_token)` |

### RLS

| 테이블 | 정책 |
|--------|------|
| `ads` | RLS ON. 클라이언트 정책 없음 — 접근은 RPC(`start_ad_view`) 경유 |
| `ad_reward_config` | RLS ON. 클라이언트 정책 없음 — 접근은 RPC 경유 |
| `ad_clicks` | RLS ON. 클라이언트 정책 없음 — 접근은 RPC(`log_ad_click`) 경유 |

### Storage

| 버킷 | 공개 여부 | 용도 |
|------|-----------|------|
| `ad-media` | 공개 read | 광고 이미지·동영상 |

---

## ③ 리뷰 블라인드 — **적용됨 (2026-07-08 LIVE, migration 20260708000000)**

> **2026-07-08 prod 적용(LIVE).** 배경록이 `db push`.

- **`reviews.is_blinded BOOLEAN NOT NULL DEFAULT false`** 컬럼 추가. **관리자 UI 없음** — 팀이 Supabase에서 직접 `true`로 set/해제(`update reviews set is_blinded = true where id = ...`).
- **`list_worksite_reviews`**: 반환에 `is_blinded boolean` 추가. `is_blinded`면 내용·점수·작성자·근로학기를 서버에서 NULL 마스킹(목록엔 "블라인드 처리된 리뷰입니다" placeholder 슬롯으로 남음 — `deleted_at` 삭제와 별개). 반환 시그니처 변경 → `DROP FUNCTION` 먼저.
- **집계 RPC 3개**(`get_review_stats`·`get_worksite_score_cards`·`search_worksite_cards`): `and not is_blinded` 추가로 평균·추천율·리뷰수에서 블라인드 제외.
- 프론트: `ReviewCard`가 `is_blinded`면 placeholder 렌더(마이그레이션 전 undefined면 일반 렌더 — 하위호환), `WorksiteDetail`이 클라 점수요약에서 블라인드 제외.

---

## ④ 교내 국가근로 시드 + 지역 필터 판정 기준 — **db push 대기 (migration 20260716180000)**

- **`postings.is_placeholder BOOLEAN NOT NULL DEFAULT false`** 컬럼 추가. 공고 없는 근무지를 노출시키기 위한 껍데기 posting 표식(상세는 아래 `postings` 스키마 주석).
- **명부 시드 57개**: 고려대 본교 학부 `일반교내` → `type='national'` + `location_type='on_campus'`(**이 조합의 첫 데이터**). 근무지당 placeholder posting 1개(`is_active=false`, 자격은 국가근로 규칙값 `long`/`0`/`0`).
- **`search_worksite_cards` 지역 필터 판정이 `type` → `location_type` 기준으로 바뀜:**

  ```sql
  -- before: and (p_regions is null or w.type <> 'national'          or w.region = any(p_regions))
  -- after:  and (p_regions is null or w.location_type = 'on_campus' or w.region = any(p_regions))
  ```

  `20260708110000`의 의도는 처음부터 **"교내는 지역 필터 무시"** 였다. 당시엔 `national`+`on_campus`가 0개라 "교내" == "school"이 **우연히** 참이어서 `type`으로 판정해도 결과가 같았을 뿐이다. 위 시드가 그 전제를 깬다(national이면서 교내). 시그니처 불변 → `create or replace`.

- **결과 계약:** 교내는 `region`이 NULL이어도 되고(오히려 그게 정상), **교외는 `region`을 반드시 채워야 한다** — 비면 지역 필터에서 조용히 사라진다. 크롤러가 지켜야 할 계약. 이 변경으로 `id=6660`(school/off_campus/region NULL) 1행이 영향받아 `region='서울'`로 정리됨.
- 프론트: `AdvancedSearch.jsx`의 안내 문구도 '지역은 **교외 근무지**에만 적용돼요'로 수정(기존 '국가근장에만'은 부정확해짐).

---

## ⑤ region 정규화 + CHECK 제약 — **적용됨 (2026-07-16 LIVE, migration 20260716190000)**

④의 push 후 회귀 검증 중 발견한 **기존 결함**(④와 무관). 지역별 합계가 교외 총계와 32행 어긋난 게 단서였다.

- **증상:** 교외 national 32행의 `region`이 긴 행정구역명이었다 — `경기도`(15)·`광주광역시`(3)·`서울특별시`(3)·`서울시`(2)·`인천광역시`(2)·`부산광역시`(2)·`충청남도`·`경상북도`·`대구광역시`·`제주특별자치도`·`대전광역시`(각 1). 프론트 지역 필터는 `REGIONS`(짧은 형태 17개)만 보내므로 **이 32행은 지역 필터로 도달 불가능**했다. 검색어·다른 필터로는 나왔으니 "안 보임"이 아니라 **"지역으로는 못 찾음"** — 그래서 몇 달간 안 들켰다.
- **원인:** KOSAF 임포터(`crawling_scripts/import_to_supabase.py`)의 정규화 누락.
- **조치 1 — 백필:** 32행을 짧은 형태로. 매핑은 전부 `address` 앞부분과 대조 확인(불일치 0).
- **조치 2 — `worksites_region_normalized` CHECK:** `region is null or region in (REGIONS 17개)`. NULL 허용은 **교내가 NULL이 정상**이기 때문(④). 이제 임포터가 정규화를 빠뜨리면 **적재가 에러로 터진다** — 조용히 사라지는 것보다 낫다. ⚠️ 순서는 UPDATE → CHECK(제약이 먼저면 기존 32행에 걸려 실패).
- ⚠️ **이중 소스:** CHECK 목록과 `lib/profileOptions.js`의 `REGIONS`가 각각 하드코딩돼 있다. 도 신설 등으로 바뀌면 **양쪽 같이** 고칠 것.
- **검증:** REGIONS 밖 값 0 / NULL 81 = 교내 57 + school 24(전부 교내) / 17개 지역 합계 **6,647 = 교외 총계**(도달 불가 0). 경기 1441→1456 · 서울 988→993 · 광주 439→442 · 제주 89→90.

---

## ⑥ 서울대학교 개설 + 교내 국가근로 24개 시드 — **db push 대기 (migration 20260717000000)**

- **`universities`에 서울대학교** (campus NULL, `email_domain='snu.ac.kr'`, `signup_enabled=true`) — 고려대 외 첫 학교. 가입 화면 학교 드롭다운은 DB에서 오므로 서울대가 자동 노출된다. ⚠️ `signup_enabled`는 20260626152144(가입 학교 제한 해제, *.ac.kr 전면 허용)부터 **아무 코드도 읽지 않는 장식 컬럼** — true로 두는 건 기록 목적. 서울대 가입을 실제로 여는 건 universities 행(드롭다운·`university_id`)과 colleges/departments 존재다.
- **'미분류' colleges/departments 1쌍** — `create_profile`(가입 마지막 단계 RPC, 20260626163424)의 `NO_COLLEGE`/`NO_DEPARTMENT` 방지 최소 시드. 이름 미일치 시 fallback(첫 행)이 '미분류'로 착지(`track`은 본인 선택 유지). 실명 시드(§⑦) 이후에도 **안전망으로 유지** — id가 가장 작아 fallback 착지점이 되므로, 미일치가 나도 잘못된 실명 단과대 대신 '미분류'로 떨어진다.
- **worksites 24행** (`type='national'`, `location_type='on_campus'`, `region=NULL`) + **placeholder postings 24행** (`is_active=false`, `long`/`0`/`0`) — 명부 67행(연도 중복) → 근로지명 dedup(최신 연도 우선) 24개. §④ 고려대 시드와 동일 패턴. 간호대학은 연건캠퍼스 주소지만 교내로 분류.

---

## ⑦ 서울대 실명 단과대·학과 시드 + 학교 드롭다운 도메인 고정 — **db push 대기 (migration 20260717110000)**

- **colleges 16·departments 91 시드** — 프론트 `profileOptions.js`의 `colleges[1]`/`departments[1]`(서울대 이중 배열)을 (단과대, 학과, 대표계열) triple로 평탄화. 20260716145738(고려대 시드)과 동일한 do-block·멱등 패턴. `default_track`은 고려대 선례 기준 대표값을 채웠으나 **§⑧에서 컬럼 자체가 제거됨**(개수는 `profileOptions.test.js`가 16/91로 고정).
- **왜**: 실명 행이 없으면 `create_profile` fallback이 전원 '미분류'로 저장하고, `update_profile`(엄격 매칭, fallback 없음)은 `NO_COLLEGE`로 실패 — 서울대 유저가 프로필 수정 불가였다. 고려대 시드와 같은 결함, 같은 처방.
- **프론트(같은 커밋 계열): 학교 드롭다운을 이메일 도메인으로 고정** — `universitiesForEmail()`(lib, 테스트 포함)로 이메일 도메인과 일치하는 학교(캠퍼스)만 드롭다운에 노출 + 첫 행 자동 선택. 이 드롭다운은 학교 "선택"이 아니라 **같은 도메인의 분리 캠퍼스(서울/세종) 선택 용도** — 학교는 이메일이 결정한다. 기존 "기본값 고려대" 방식은 snu 메일 유저가 학교를 안 바꾸면 고려대 소속으로 조용히 저장되는 구멍이 있었다(서버에 도메인↔학교 검사 없음, 20260626152144에서 제거). **미등록 .ac.kr 도메인은 고려대 폴백**(`FALLBACK_EMAIL_DOMAIN`) — `univIndexFromEmail` 기본 0(고려대)과 같은 정책으로, 기존 "기본값 고려대" 동작을 유지하기로 결정(2026-07-17). 단과대/학과 목록(`uniIdx`)도 이메일이 아니라 **선택된 학교의 `email_domain`을 따라가** 저장될 `university_id`와 항상 일치한다.
- `fetchUniversities`가 `email_domain` 컬럼을 추가로 select한다(공개 카탈로그 — anon SELECT 허용이라 무리 없음).
- ⚠️ 배포 순서: **DB push 먼저 → 프론트 나중**. 프론트만 먼저 나가면 서울대 행이 없어 snu 메일 유저의 드롭다운이 비어 가입이 막힌다.

---

## ⑧ departments.default_track 컬럼 제거 — **db push 대기 (migration 20260717120000)**

- **계열(track)의 유일 정본 = `users.track`(프론트 제출값).** `default_track`은 "학과 선택 시 계열 자동 세팅" 구상의 레거시(PM 확인) — 프론트는 자체 드롭다운(`PREFFEREDTRACK`) 제출값을 쓰고 서버(`create_profile`/`update_profile`)는 `p_track`을 저장만 한다. 이 컬럼을 읽는 코드가 어디에도 없어 제거(2026-07-17 결정).
- **서버 후처리 없음이 원칙**: 백엔드는 계열을 배정·보정하지 않는다. 빈 값 방지는 프론트 검증 담당(가입 3단계 trackErr · MyPage 160행 — 둘 다 이미 차단).
- 앞선 시드(20260716145738·§⑥·§⑦)의 insert는 컬럼이 있던 시점 순서로 재생되므로 `db reset` 안전. **이후의 시드/임포터는 departments에 `(college_id, name)`만 넣는다.**

---

## ⑨ 가입 축하 5p + 광고 daily_cap=2 확정 — **db push 대기 (migration 20260717150000·20260717140000)** · ⚠️ 가입 축하 5p는 **⑬에서 폐지됨(2026-08-08)**, daily_cap은 20260731105714에서 1로 변경됨

> 가입 5p는 원래 `20260717130000`이었으나 같은 타임스탬프의 `search_scope_university`(별도 작업)와
> **버전 충돌**(schema_migrations PK)로 push가 실패해 `20260717150000`으로 리네임(2026-07-17).
> 실패분은 트랜잭션 롤백이라 부분 적용 없음.

> **⚠️ 이 5p 지급은 2026-08-08 `20260808113010_point_policy_v2_and_drop_signup_bonus`로
> 폐지됐다.** 아래 서술은 도입 당시(2026-07-17) 기록이며 더 이상 live 동작이 아니다.

- **`create_profile`에 가입 축하 5p 지급 추가** (`20260717150000`, 시그니처 불변 create or replace): users insert 직후 `points` 원장(`reason='signup_bonus'` — 스키마 예약값, 내역 라벨 "가입 축하금") insert + `point_balance` +5. `claim_ad_reward`와 동일한 원장+캐시 패턴. 기존 "프로필 존재 시 조기 return" 가드가 중복 지급 차단. 프론트는 가입 성공 시 토스트("가입 축하 5p를 지급했어요!")만 — 지급은 전적으로 서버.
- **`ad_reward_config.daily_cap = 2` 확정** (`20260717140000`): §②의 "디버깅용 큰 값" 경고를 마이그레이션으로 해소. 이미 2면 no-op.

---

## ⑩ 미인증 가입 5분 자동 정리 — **db push 대기 (migration 20260718121129)**

- **`purge_unverified_signups()` RPC 신설 + pg_cron 매분 실행(`purge-unverified-signups`).** 가입 인증 메일(OTP)에 5분간 무응답인 미인증 계정을 `auth.users`에서 삭제한다. 조건(전부 만족): `email_confirmed_at is null` · 마지막 인증 메일 발송 후 5분 경과(resend 시 창 리셋) · recovery 메일도 발송 후 5분 경과(#35 "미인증자 recovery 구제" 경로 보호) · `last_sign_in_at is null`(로그인 이력 있는 행 보호 — 현 플로우에선 항상 참, 미래 방어).
- **효과:** 이탈한 이메일이 5~6분 안에 풀려 재가입 가능(`email_registered()` false 복귀). `withdrawn_emails` 해시는 저장 안 함 — 가입 미완 이탈은 30일 쿨다운 대상이 아님. 첫 실행 때 기존 미인증 잔재도 일괄 삭제. `public.users`는 FK cascade지만 미인증자는 프로필이 없어 실제로는 auth 행만 지워진다.
- **주의:** 정책상 5분이 사실상 코드 유효시간이 된다(Auth OTP 만료 설정 3600초보다 짧음 — 5분 넘겨 입력하면 계정 없음 계열 에러 → 재가입으로 해소). 클라 실행 권한 없음(service_role·cron만). 부수 잡 `purge-cron-history`(매일 04:30 UTC)가 7일 지난 `cron.job_run_details`를 정리해 매분 잡의 이력 비대를 막는다.

---

## ⑪ 검색·공개상세 RPC가 `recruit_until` 반환 — **db push 대기 (migration 20260720015012)**

> 원래 `20260717095637`이었으나 이미 적용된 ⑥~⑩보다 타임스탬프가 앞서 순서가 꼬여
> `20260720015012`로 재발급(2026-07-20, ⑨의 리네임 선례와 동일 처방). 본문도 대학 스코프
> (`20260717130000_search_scope_university`) **적용 이후 최신본 기반으로 재작성** — 옛 본문(20260716180000 기반)을
> 그대로 올리면 대학 스코프가 롤백되기 때문.

- **`search_worksite_cards`**: 반환에 `recruit_until date` 추가. `20260805090000`부터 서버가 `recruit_until_at`(정확한 시각) → `recruit_until`(KST 날짜) → `is_active` 순으로 판정하며, 검색 카드는 서버의 최종 `is_active`를 그대로 사용한다.
- **`get_worksite_public_detail`**: posting jsonb에 `recruit_until`·`recruit_until_at` 키 추가 — 상세의 `effectiveActive`도 같은 우선순위를 사용한다. jsonb 반환이라 시그니처 불변 → `create or replace`.

### 공고 목록 반환 (`20260721054200_worksite_detail_postings`) — 학교근로 다중 공고 노출(A안)

- **`get_worksite_public_detail`**: 반환이 `posting jsonb`(대표 1개) → **`postings jsonb`(공고 배열, 활성→최신, 최근 30개 캡)**. 각 원소에 `is_placeholder`·`recruit_until` 포함. **대표/목록 선별은 서버가 아니라 클라**(`web/src/lib/postings.js` `selectPostings` — 비-placeholder 첫째=대표, 나머지=목록, 전부 placeholder면 폴백). ⚠️ 리턴 시그니처 변경이라 `DROP FUNCTION` 먼저 + `anon`·`authenticated` grant 재부여. 개인정보(`contact_name` 등)는 화이트리스트에서 계속 제외.
- **배포 순서 무관:** 프론트(`fetchWorksitePublicDetail`)가 `postings`(신)·`posting`(구)를 모두 수용 → db push와 프론트 배포 순서에 관계없이 안 깨진다. db push 전엔 대표만, 후엔 목록까지 노출.

---

## ⑫ 닉네임 서버 검증 + 직접 변경 경로 차단 — **적용됨 (2026-07-21 push, migration 20260721071224)**

배경: 닉네임 제한이 프론트 검증(2~20자)뿐이라 RPC 직접 호출로 1~50자 아무 문자열이 들어갔고,
`grant update(... nickname ...)`(컷오버 20260624025109)로 로그인 사용자가 API 직접 호출로 무검증 변경도 가능했다.
특히 `list_worksite_reviews`가 익명 리뷰를 문자열 `'익명'`으로 표시하므로 닉네임 "익명" = 익명 리뷰 사칭 구멍.

- **`validate_nickname(p_nickname text) returns void` 신설** — 위반 시 예외. 클라 grant 없음(내부 전용).
  - 허용 문자: 완성형 한글(가-힣)·영문·숫자만 → `NICKNAME_INVALID`
  - 길이: 2자 이상 + **가중 길이(한글 2·영숫자 1) 16 이하** = 한글 8자/영문 16자/혼용 비례 → `NICKNAME_INVALID`
  - 예약어 부분 일치(소문자화): 익명·운영자·관리자·근로고래·고래지기·admin·administrator·manager·operator·staff·system·anonymous·official·grgr·geunrogorae → `NICKNAME_RESERVED`
- **`create_profile`**: insert 전 `validate_nickname` 호출 + `trim(p_nickname)` 저장 (본문 20260717150000 재현, 시그니처 불변 replace).
- **`revoke update (nickname) on users from authenticated`** — 직접 UPDATE 경로 차단. 변경 UI가 없어 정상 경로 영향 0. 추후 닉네임 변경 기능은 `validate_nickname`을 쓰는 전용 RPC로 열 것.
- ⚠️ **프론트 `web/src/lib/authValidation.js`(`nicknameError`·`RESERVED_NICKNAMES`·`nicknameFromEmail`)와 이중 소스** — 규칙·예약어를 바꾸면 양쪽 함께. 닉네임 미입력 시 이메일 @앞부분 폴백도 프론트에서 같은 규칙으로 정제(`nicknameFromEmail`, 통과 불가 이메일은 직접 입력 요구).
- ⚠️ **CHECK 제약은 의도적 미적용** — 기존 행에 정제 전 폴백 닉네임(점·하이픈 포함 가능)이 있어, NOT VALID로 걸어도 그 행의 무관한 UPDATE(지역 변경 등)까지 실패한다. 기존 닉네임은 소급하지 않음(신규·변경만 규제).

---

## ⑬ 포인트 정책 v2 — 가입 축하금 폐지 + 리뷰 적립 30P/20P (migration `20260808113010_point_policy_v2_and_drop_signup_bonus`)

스키마 변경 **없음** — RPC 본문과 데이터만 바뀐다.

- **가입 축하금 폐지**: `create_profile`에서 `signup_bonus` 원장 insert + `point_balance` +5 두 줄 제거(⑨에서 도입한 것). 시그니처 불변 replace. **이미 지급된 원장 행·잔액은 회수하지 않는다** — 잔액이 부족한 유저에게서 차감하려면 음수 방지 로직이 필요하고 민원 소지가 크다. 따라서 `points.reason` 의 `signup_bonus` 값과 `MyPage.jsx` 의 '가입 축하금' 라벨은 **계속 살아 있어야 한다**(지우면 기존 유저 내역에 원문 reason이 노출된다).
- **리뷰 적립 상향**: 실명 25P → **30P**, 익명 15P → **20P**. `write_review_with_points`·`update_review_with_points` 의 상수만 변경(시그니처 불변). `delete_review_with_rollback` 은 실제 적립 합계를 회수하므로 무수정.
- **소급 지급 `(살아있는 리뷰 수 − 1) × 5P`**: 1개=0P, 2개=5P, 3개=10P. 대상은 `user_id is not null` + `deleted_at is null` + `review_write` 원장이 있는 리뷰. 유저별 최소 `id` 1건을 제외한 각 리뷰에 `reason='review_policy_grant'` +5P 행을 붙인다. **뭉텅이 지급이 아니라 리뷰별로 붙이는 이유** — `update_review_with_points`·`delete_review_with_rollback` 이 `review_id` 별 적립 합계로 재정산하므로, `review_id` 가 null이면 옛 리뷰를 수정할 때마다 차액이 또 나간다.
  - ⚠️ **알려진 틈**: 제외된 "첫 리뷰"는 합계가 구 정책가로 남아, 그 리뷰를 수정하면 차액 +5P가 보전된다(유저당 최대 1회·5P). `(n−1)×5` 규칙을 유지하는 대가로 감수한 것(PM 승인).
- **트랜잭션**: 파일 전체가 `begin`/`commit`. 적립가 변경과 소급 지급 사이에 리뷰가 들어오면 어중간한 금액으로 적립되기 때문.
- **공지**: 현행 정책 서술 공지(`[필독] 근로고래 이용 안내`)의 숫자 갱신 + `[업데이트] 8월 8일` 신설. 과거 날짜 업데이트 공지의 "15P → 25P" 이력은 사실 기록이라 유지.
- **프론트 짝**: `web/src/lib/points.js` 에 `PUBLIC_REVIEW_POINTS`/`ANONYMOUS_REVIEW_POINTS`/`reviewPoints()` 신설(기존엔 `ReviewForm.jsx` 지역 상수 + `ExchangeCenter.jsx` 문자열 리터럴로 이중 소스), `Signup.jsx` 가입 축하 토스트 제거. **db push 직후 prod 프론트 배포까지 한 묶음.**

spec `docs/superpowers/specs/2026-08-08-point-policy-v2-design.md` · plan `docs/superpowers/plans/2026-08-08-point-policy-v2.md`

---

## ⑭ 대학별 포인트 정책 도입 + 서울대 한시 조정 — **db push 대기 (migration `20260808134041_university_point_policy`)**

리뷰가 쌓이면 되돌릴 한시 조치라, RPC 본문에 대학 id를 박는 대신 대학별 오버라이드 표를 새로 둔다. 이 저장소는 본문 복사 과정에서 로직이 조용히 사라지는 사고를 두 번 겪었다(대학 스코프 검사 유실 → `20260808120745`로 복구) — 표로 두면 원복이 행 삭제 한 줄이다.

- **신규 표 `university_point_policy`**: `university_id int PRIMARY KEY REFERENCES universities(id) ON DELETE CASCADE` · `hour_pass_minutes int NOT NULL DEFAULT 60 CHECK (hour_pass_minutes BETWEEN 1 AND 1440)` · `ad_reward_points int CHECK (ad_reward_points >= 0)`(nullable — **NULL이면 전역 `ad_reward_config.reward_points`를 그대로 따른다**) · `note text` · `updated_at timestamptz NOT NULL DEFAULT now()`. RLS ON, 정책 0건 + `anon`·`authenticated` 모두 `REVOKE ALL` — 클라이언트는 이 표에 직접 접근할 수 없고, 읽기는 아래 헬퍼로만 이뤄진다.
- **공유 헬퍼 2개** `hour_pass_minutes_for(uuid)`·`ad_reward_points_for(uuid)`(둘 다 `language sql stable`) — 값 계산을 한 곳으로 모아 RPC 간 드리프트를 구조적으로 막는다(각자 계산하면 화면엔 5P, 지급은 2P로 갈릴 수 있다). 정책 행이 없는 대학은 각각 60분·전역 `ad_reward_config` 값으로 폴백한다.
  - ⚠️ **security definer가 아니다** — 아래 RPC 4개가 전부 definer인 것에 기대는 구조다. security invoker 경로에서 이 헬퍼를 부르면 RLS(정책 0건)에 막혀 **에러 없이 0행을 보고 조용히 기본값으로 폴백한다** — 즉 틀린 값이 나오는데 실패하지는 않는다. 새 호출부를 추가할 때 반드시 확인할 것.
- **읽는 RPC 4개**(전부 `security definer`, 시그니처 전부 불변 replace): `activate_pass`(`p_days=0` 최소상품의 실제 지속시간) · `claim_ad_reward`(적립액 — `points` 원장 insert와 `users.point_balance` 갱신 두 곳 모두 같은 헬퍼값을 쓴다) · `get_ad_reward_status`(화면에 보여줄 적립액) · `_wallet`(반환 jsonb에 `hour_pass_minutes` 키 추가 → `claim_ad_reward`도 결국 `_wallet()`을 반환하므로 §②의 반환 shape에도 이 키가 늘었다). ⚠️ `activate_pass`·`get_ad_reward_status`·`_wallet`은 `search_path = pg_catalog, pg_temp`라 헬퍼를 `public.`으로 완전 수식해서 호출한다(`claim_ad_reward`는 `search_path = public`이라 무관).
- **서울대 시드**: `hour_pass_minutes = 5`, `ad_reward_points = 2`(전역 5P 대신) — 리뷰가 부족해 선순환이 필요하다는 한시 조정.
- **되돌리기**: `delete from university_point_policy where university_id = <서울대 id>;` 한 줄 — 헬퍼가 없는 행을 60분·전역값으로 폴백하므로 RPC는 무수정, 프론트도 자동 복귀한다(공지는 별도 정리 필요).
- ⚠️ **배포 순서가 §⑬(포인트 정책 v2)과 반대 — 프론트 먼저, DB 나중.** 프론트(`ExchangeCenter.jsx`·`MyPage.jsx`)가 먼저 나가면 서버가 아직 `hour_pass_minutes`를 안 줘 `?? 60` 폴백으로 무해하지만, DB push가 먼저 나가면 화면엔 "1시간 열람권"이라 찍힌 상품이 실제로는 5분만 주는 채로 팔린다 — 이 마이그레이션이 함께 넣는 서울대 전용 공지가 이미 "5분으로 바뀌었다"고 안내하고 있어 더 위험하다.

spec `docs/superpowers/specs/2026-08-08-university-point-policy-design.md` · plan `docs/superpowers/plans/2026-08-08-university-point-policy.md`

---

## ⑮ 허위 리뷰 제재 — 포인트 몰수 원장 reason 신설 — **적용됨 (2026-08-14 push, migration `20260814071343_penalize_false_review_119`)**

스키마 변경 **없음** — `points.reason`에 값 하나(`false_review_penalty`)가 늘고, 특정 유저의 데이터만 바뀐다.

> **push 로그가 동기를 확정했다.** 리뷰 작성 `06:53:35` → **13초 뒤** `pass_expires_at = 2026-08-21 06:53:48`(정확히 7일권).
> 즉 30P를 받자마자 20P로 7일 열람권을 사서 활성화했고 잔액 10P가 남아 있었다 — **리뷰를 열람권 결제 수단으로 쓴 것**이라
> 허위 판단과 정황이 일치한다. 실제 몰수 10P + 7일 열람권 회수, `pass_balances`는 `{}`라 재고 몰수는 no-op.
> live 검증: `reviews.id=119 → is_blinded=true`, 근무지 6694 집계 대상 6→5건(추천점수 평균 5.00 유지 — 나머지 5건이 전부 5.0).

- **대상**: 리뷰 119(근무지 6694 '고려대학교(본교) 학부 - 이과대학행정팀', 2026-1학기, 비익명, 2026-08-14 15:53 KST 작성). 해당 근무지에서 **실제 근무 중인 PM이 현장 확인**한 결과 그곳에서 근무한 사람이 쓴 글이 아니다. 부수 정황으로 `opinion`이 점(`.`) 54자뿐이라 리뷰 최소길이(50자) CHECK를 우회했다 — 전체 리뷰 79건을 기계 스캔했을 때 반복문자만으로 채운 리뷰는 이 1건뿐이다.
- **조치 3가지**: ①**리뷰 블라인드**(`reviews.is_blinded = true`) ②보유 포인트 **전액 몰수**(`points`에 음수 원장 + `users.point_balance = 0`) ③**열람권 전량 회수**(`users.pass_expires_at = null` + `pass_balances = '{}'::jsonb`).
- **블라인드를 고른 이유**(삭제 아님): §③대로 목록엔 placeholder 슬롯이 남고 서버가 내용·점수·작성자를 마스킹하며 집계 RPC 3종(`get_review_stats`·`get_worksite_score_cards`·`search_worksite_cards`)에서 제외된다 → 근무지 6694의 평균·추천율·리뷰수에서 즉시 빠지면서 조치 흔적은 남는다.
- **재고까지 회수하는 이유**: `pass_expires_at`만 null로 두면 `pass_balances`에 남은 미활성화 열람권을 곧바로 재활성화해 다시 쓸 수 있다.
- ⚠️ **`reason = 'false_review_penalty'`가 이 조치의 핵심이다.** `update_review_with_points`·`delete_review_with_rollback`은 "이 리뷰가 받은 적립 합계"를

  ```sql
  sum(amount) where review_id = ? and reason in ('review_write','review_anon_switch','review_policy_grant')
  ```

  로 구한다. 몰수 행을 **이 목록 안의 reason으로 넣으면 합계가 0이 되어, 작성자가 리뷰를 수정하는 순간 30P가 다시 지급된다.** 목록 밖 reason이라야 합계가 30P로 유지돼 재지급이 없다. 앞으로 이 목록에 reason을 추가할 때 `false_review_penalty`를 절대 포함시키지 말 것.
- ⚠️ **의도된 부수효과**: 잔액이 0이므로 작성자가 리뷰 119를 직접 삭제하려 하면 `delete_review_with_rollback`의 `if v_balance < v_grant then raise 'INSUFFICIENT_POINTS'`에 걸려 **삭제가 막힌다**(증거 보존). 프론트에는 포인트 부족 계열 에러로 보인다.
- **push 로그**: 제재 전 상태(`is_blinded`·`point_balance`·`pass_balances`·`pass_expires_at`)와 각 단계 결과를 `raise notice`로 출력한다 — service_role은 `users`를 읽을 수 없어(`reports`·`reviews` SELECT만 grant됨) push 시점 로그가 유일한 감사 기록이다.
- **프론트 짝**: `MyPage.jsx`의 `REASON_LABELS`에 `false_review_penalty: '거짓/허위 리뷰 작성'` 추가. 없으면 유저 포인트 내역에 원문 reason이 그대로 노출된다(§⑬의 `signup_bonus` 라벨 유지 이유와 같은 구조).
- **멱등·reset 안전**: 같은 (user, review)에 제재 행이 있으면 skip, 맨바닥 재구축엔 리뷰가 없어 no-op, 근무지가 예상과 다르면 `raise`로 실패(20260810141449 선례).

---

## ⑯ 신고 상태 정리 — `report_status_e` 확장 + 밀린 신고 3건 종결 — **적용됨 (2026-08-14 push, migration `20260814081557` + `20260814081602`)**

> live 검증: pending 3→0건, id=1 `ignored` · id=2 `moved` · id=3 `blinded` 확인.

신고 접수는 `report_review` RPC로만 들어오고 **상태를 바꿀 UI가 없어**, 조치는 다 해놓고 `status`는 전부 `pending`으로 남아 있었다.

- **enum 2종 추가** (`20260814081557`): `blinded`(타당해서 블라인드 — 삭제 아님) · `moved`(허위가 아니라 근무지 오배정이라 재배정). 기존 3종으로는 지금까지의 결말을 표현할 수 없었다 — `ignored`로 닫으면 "무시함"이 되어 사실과 정반대고, `deleted`는 삭제한 적이 없으니 거짓이다. 뭉뚱그린 `resolved` 대신 결말을 그대로 남긴 건, 상태값의 용도가 **운영자가 큐를 훑을 때 "이건 어떻게 끝났나"를 즉시 읽는 것**이기 때문이다. 둘 다 재발하는 조치다(블라인드는 §③의 표준 수단, 재배정은 근무지 오선택이 원인일 때).
- **신고 3건 종결** (`20260814081602`): id=1(리뷰 53) → `ignored` · id=2(리뷰 63) → `moved` · id=3(리뷰 119) → `blinded`.
- ⚠️ **파일을 둘로 나눈 이유**: `ALTER TYPE ... ADD VALUE`로 추가한 값은 **같은 트랜잭션에서 사용할 수 없다**(Postgres 제약). 한 파일에 합치면 UPDATE가 `unsafe use of new value of enum type`으로 실패한다. 그래서 값 추가 파일엔 `begin/commit`을 넣지 않았고, 두 파일의 타임스탬프 순서를 뒤집으면 안 된다.
- ⚠️ **Postgres는 enum 값을 제거할 수 없다** — 되돌리려면 타입을 다시 만들어야 한다.
- 프론트 영향 없음 — `reports`는 클라 정책 0건(service_role 전용)이라 `status`를 읽는 화면이 없다.

## 기존 스키마 (현재 live 상태)

```sql
-- ──────────────────────────────────────────────────────────────
-- ENUM 타입 정의 (PostgreSQL CREATE TYPE)
-- ──────────────────────────────────────────────────────────────
CREATE TYPE worksite_type_e    AS ENUM ('national', 'school');
  -- national: 국가근로  /  school: 학교근로

CREATE TYPE location_type_e    AS ENUM ('on_campus', 'off_campus');
  -- on_campus: 교내  /  off_campus: 교외

CREATE TYPE degree_program_e   AS ENUM ('undergrad', 'graduate');

CREATE TYPE academic_status_e  AS ENUM ('enrolled', 'leave', 'completed', 'deferred_graduation');
  -- enrolled: 재학  /  leave: 휴학  /  completed: 수료  /  deferred_graduation: 졸업유예

CREATE TYPE report_status_e    AS ENUM ('pending', 'deleted', 'ignored', 'blinded', 'moved');
  -- pending: 미처리 / deleted: 타당해서 리뷰 삭제 / ignored: 부당하거나 조치할 내용 없음
  -- blinded: 타당해서 리뷰 블라인드(삭제 아님 — 목록에 placeholder 남음) / moved: 허위가 아니라
  --          근무지 오배정이라 올바른 근무지로 재배정  ← 뒤 2개는 20260814081557에서 추가(§⑯)
  -- ⚠️ Postgres는 enum 값을 제거할 수 없다. ADD VALUE로 넣은 값은 같은 트랜잭션에서 못 쓴다.

CREATE TYPE duration_type_e    AS ENUM ('short', 'long', 'unknown');
  -- 학교근장: short=6주(42일) 미만 / long=6주 이상 / unknown=기간·명시 표현 불명확
  -- 여러 기간 선택지는 가장 긴 기간 기준. 국가근장은 학기 단위로 간주해 long.

-- ──────────────────────────────────────────────────────────────
-- 삭제 정책 요약 (ON DELETE)
-- ──────────────────────────────────────────────────────────────
-- ※ 기본 경로는 소프트 삭제: 탈퇴·삭제는 row를 지우지 않고 deleted_at에 시각만 기록한다
--   (users·worksites·postings·reviews). 이 경우 row가 남으므로 ID·이메일 등도 보존됨.
--   아래 ON DELETE 규칙은 관리자 영구 삭제(하드 삭제) 시에만 발동하는 fallback이다.
-- users 삭제        → reviews.user_id          SET NULL  (익명 유지)
--                  → review_helpful.user_id    CASCADE   (helpful_count는 건드리지 않음)
--                  → points.user_id            CASCADE   (포인트 소멸)
--                  → ad_views.user_id          SET NULL  (광고 기록 보존)
--                  → reports.reporter_id       SET NULL  (신고 기록 보존)
--                  → reports.reported_user_id  SET NULL  (신고 기록 보존)
-- worksites 삭제   → postings.worksite_id      CASCADE
--                  → reviews.worksite_id       RESTRICT  (리뷰 있으면 삭제 불가)
-- reviews 삭제     → review_helpful.review_id  CASCADE
--                  → reports.review_id         SET NULL  (신고 기록 보존)
--                  → points.review_id          SET NULL  (포인트 기록 보존)
-- universities 삭제 → colleges, worksites      RESTRICT
-- colleges 삭제    → departments               RESTRICT

-- ──────────────────────────────────────────────────────────────

-- 학교 (멀티캠퍼스 지원)
universities
  id            SERIAL PRIMARY KEY                -- 학교 고유 ID
  name          VARCHAR(100) NOT NULL             -- 학교명 (예: 고려대학교)
  campus        VARCHAR(50)                       -- 캠퍼스명. 멀티캠퍼스일 때만 사용 (예: 서울, 세종), 단일캠퍼스면 NULL
  email_domain  VARCHAR(100) NOT NULL             -- 회원가입 학교 인증용 이메일 도메인 (예: korea.ac.kr)
  -- ※ email_domain 에 UNIQUE 걸지 않음
  --   같은 도메인을 쓰는 캠퍼스(서울·세종 등)가 복수 row로 존재 가능
  --   회원가입 시 도메인으로 조회 → 복수 결과면 캠퍼스 선택 UI 제공

-- 단과대학
colleges
  id              SERIAL PRIMARY KEY                -- 단과대학 고유 ID
  university_id   INTEGER NOT NULL REFERENCES universities(id) ON DELETE RESTRICT  -- 소속 학교
  name            VARCHAR(100) NOT NULL             -- 단과대학명 (예: 정보대학, 공과대학)

-- 학과
departments
  id              SERIAL PRIMARY KEY                -- 학과 고유 ID
  college_id      INTEGER NOT NULL REFERENCES colleges(id) ON DELETE RESTRICT      -- 소속 단과대학
  name            VARCHAR(100) NOT NULL             -- 학과명 (예: 컴퓨터학과)
  -- ※ default_track 컬럼은 20260717120000에서 제거됨(§⑧) — 계열은 users.track(프론트 제출값)이 유일 정본

-- 유저
users
  id              UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE  -- 유저 고유 ID (= auth.users.id)
  university_id   INTEGER NOT NULL REFERENCES universities(id) ON DELETE RESTRICT   -- 소속 학교
  college_id      INTEGER NOT NULL REFERENCES colleges(id) ON DELETE RESTRICT       -- 소속 단과대학
  department_id   INTEGER NOT NULL REFERENCES departments(id) ON DELETE RESTRICT    -- 소속 학과
  -- ※ university_id · college_id · department_id 세 컬럼 모두 저장 (역정규화)
  --   UI 팝업("변경하시겠습니까?")으로 입력 검사 → 앱 레이어에서 일관성 보장
  track           VARCHAR(20) NOT NULL      -- 계열 (인문사회계열/자연계열/예체능계열). 프론트 계열 드롭다운(PREFFEREDTRACK) 제출값을
                                            -- 그대로 저장 — 서버 자동 세팅·후처리 없음(§⑧). 빈 값 방지는 프론트 검증 담당
  -- ※ 이메일 정본 = auth.users.email (public.users.email/password_hash 컬럼은 컷오버에서 삭제됨)
  nickname        VARCHAR(50) UNIQUE NOT NULL       -- 서비스 내 표시 이름
  admission_year  INTEGER NOT NULL                  -- 입학년도 (예: 2021)
  degree_program  degree_program_e NOT NULL         -- 학위 과정 (학부/대학원)
  academic_status academic_status_e NOT NULL        -- 재학 상태 (재학/휴학/수료/졸업유예)
  grade           INTEGER CHECK (grade BETWEEN 1 AND 6)  -- 학년 (1~6)
  point_balance   INTEGER DEFAULT 0 CHECK (point_balance >= 0)  -- 현재 보유 포인트
  pass_balances   JSONB DEFAULT '{}'          -- 미활성화(재고) 열람권 개수 {"0": 1, "7": 2, "30": 1} (키: 유효기간(일) · "0"=1시간권 센티널). 마지막 장 사용 시 0을 남기지 않고 키 삭제
  pass_expires_at TIMESTAMPTZ                   -- 현재 활성화된 열람권 만료 시각. 없으면 NULL
  -- ※ 활성화 로직: pass_balances[type] -= 1
  --               expires_at = GREATEST(expires_at, NOW()) + interval  ← 연장 방식 (B안)
  --   현재 열람권이 남아있어도 새 열람권 활성화 시 잔여 기간 + 추가 기간으로 연장됨
  region          VARCHAR(50)                       -- 거주 지역 (예: 서울, 충남). 자세한 정책은 추후 결정
  is_admin        BOOLEAN DEFAULT FALSE             -- 관리자 여부
  created_at      TIMESTAMPTZ DEFAULT NOW()           -- 가입 일시
  updated_at      TIMESTAMPTZ DEFAULT NOW()           -- 정보 수정 일시
  deleted_at      TIMESTAMPTZ                         -- 탈퇴 일시. NULL이면 활성 계정 (소프트 삭제)

-- 닉네임 변경 이력 (운영 감사 전용, 클라이언트 직접 접근 불가)
nickname_change_history
  id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY
  user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE
  old_nickname VARCHAR(50) NOT NULL
  new_nickname VARCHAR(50) NOT NULL
  changed_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
  -- RLS ON + anon/authenticated 권한 없음. change_nickname RPC가 성공 트랜잭션 안에서만 기록.
  -- 공개 리뷰는 닉네임 스냅샷 대신 users.nickname을 JOIN하므로 과거 비익명 리뷰도 새 닉네임으로 표시.

-- 근장 (근무지 자체 — 변하지 않는 고유 정보)
-- 같은 부서/기관이 매 학기 모집해도 row는 1개, 공고는 postings에 쌓임
worksites
  id                SERIAL PRIMARY KEY                -- 근무지 고유 ID
  university_id     INTEGER NOT NULL REFERENCES universities(id) ON DELETE RESTRICT  -- 이 근무지를 등록한 학교
  type              worksite_type_e NOT NULL           -- 근무지 유형 (국가근로/학교근로)
  location_type     location_type_e NOT NULL           -- 근무 위치 유형 (교내/교외)
  organization_name VARCHAR(200)                       -- 기관명. 국가근로: 근로장학기관 / 학교근로: 대학교명(+캠퍼스)
  workplace_name    VARCHAR(200)                       -- 근무지명. 국가근로: 근로지 / 학교근로: 부서명
  -- ※ 표시용: "{organization_name} - {workplace_name}"
  normalized_name   VARCHAR(200)  -- 소스 간 매칭용 정규화 이름키(SSC/KUPID 크롤러 매칭, 20260721150404).
                                  --   unique(university_id, type, normalized_name) where not null and deleted_at is null
                                  --   백필은 로더(Python 정규화)가 정본 — 이 마이그레이션은 컬럼·인덱스만 추가
  region            VARCHAR(50)                        -- 근무 지역 (예: 서울, 충남, 제주)
  -- CHECK worksites_region_normalized: region IS NULL OR region IN (REGIONS 17개)  ← 20260716190000
  -- ※ 교내(location_type='on_campus')는 NULL이 정상 — 지역 필터가 교내를 건너뛴다(아래 search_worksite_cards 참고).
  --   교외(off_campus)는 **REGIONS의 짧은 형태로 정규화**해 반드시 채울 것('경기도'❌ → '경기'⭕).
  --   비거나 긴 행정구역명이면 지역 필터로 도달 불가능해진다 — CHECK가 이제 그런 적재를 거부한다.
  --   ⚠️ 목록은 web/src/lib/profileOptions.js의 REGIONS와 이중 소스다. 바뀌면 양쪽 같이 고칠 것.
  address           TEXT                               -- 상세 주소. 국가근로만 사용, 학교근로는 NULL일 수도 있음
  view_count        INTEGER DEFAULT 0 CHECK (view_count >= 0)  -- 로그인 사용자 기준 KST 일일 고유 조회 누적값
  created_at        TIMESTAMPTZ DEFAULT NOW()            -- 등록 일시
  updated_at        TIMESTAMPTZ DEFAULT NOW()            -- 수정 일시
  deleted_at        TIMESTAMPTZ                          -- 삭제 일시. NULL이면 활성 (소프트 삭제, 관리자만)

-- 근무지 일일 고유 조회 이벤트 (20260731162000)
worksite_view_events
  user_id           UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE
  worksite_id       INTEGER NOT NULL REFERENCES worksites(id) ON DELETE CASCADE
  viewed_on         DATE NOT NULL                       -- KST 기준 조회일
  viewed_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()  -- 실제 조회 시각
  PRIMARY KEY (user_id, worksite_id, viewed_on)         -- 새로고침·같은 날 재방문 중복 방지
  -- RLS 활성화. anon/authenticated의 직접 접근은 차단하고 increment_worksite_view RPC로만 기록한다.
  -- 90일이 지난 이벤트는 pg_cron으로 매일 삭제한다. 누적 worksites.view_count는 유지한다.

-- 홈 최근 인기도 캐시 (20260731163000, safeupdate 보정 20260731164000)
worksite_popularity_scores
  worksite_id       INTEGER PRIMARY KEY REFERENCES worksites(id) ON DELETE CASCADE
  recent_view_score DOUBLE PRECISION NOT NULL DEFAULT 0 CHECK (recent_view_score >= 0)
  calculated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
  -- 최근 30일 이벤트를 sum(0.5 ^ (조회 후 경과 초 / 604800))로 계산한다(반감기 7일).
  -- pg_cron이 매시간 5분에 갱신하며 get_home_feed는 원본 이벤트 대신 이 캐시를 읽는다.
  -- service_role만 직접 읽을 수 있고 홈 RPC는 security definer로 접근한다.

-- 모집 공고 (학기/시기마다 달라지는 정보)
-- 같은 worksite라도 모집 기간·인원·조건이 다를 수 있으므로 별도 테이블
postings
  id                SERIAL PRIMARY KEY                -- 공고 고유 ID
  worksite_id       INTEGER NOT NULL REFERENCES worksites(id) ON DELETE CASCADE  -- 연결된 근무지
  source_url        TEXT                              -- 원본 공고 URL

  -- 모집 조건
  job_category      VARCHAR(100)              -- 직무 카테고리 (예: 경영·회계·사무)
  preferred_track   VARCHAR(50)               -- 선호 계열. 국가근로만 사용, 학교근로는 NULL일 수도 있음
  preferred_college VARCHAR(100)              -- 선호 단과대. 교내 국가근로만 사용, 학교근로는 NULL일 수도 있음
  preferred_dept    VARCHAR(200)              -- 선호 학과/학부. 교내 국가근로만 사용, 학교근로는 NULL일 수도 있음
  -- ※ KOSAF 선호학과 원문 파싱 규칙:
  --   '상관없음' → 세 컬럼 모두 NULL
  --   공백/쉼표로 분리 후 suffix로 분류: 계열→preferred_track, 대학→preferred_college, 학과·학부→preferred_dept
  recruit_count     TEXT                      -- 모집인원 원문 (예: 2, O명, 00명, "2명 (중국어 상담조교 1명, 영어 상담조교 1명)"). 20260721230000에서 varchar(20)→text (SSC 원문 20자 초과 수용)
  min_grade         INTEGER                   -- 지원 가능 최소 학년
  eligible_degree   SMALLINT DEFAULT 3        -- 학위 과정 지원 자격 (0=학부생만, 1=대학원생만, 2=모두, 3=미정)
  eligible_status   SMALLINT DEFAULT 3        -- 재학 상태 지원 자격 (0=재학생만, 1=휴학생만, 2=모두, 3=미정)
  job_description   TEXT                      -- 업무 내용
  preference_notes  TEXT                      -- 우대조건 원문
  extra_notes       TEXT                      -- AI가 감지한 중요 특이사항

  -- 급여
  hourly_wage       INTEGER                   -- 시급 (원). 정액 지급이면 NULL

  -- 근무 기간
  work_period_text  TEXT                      -- 근무기간 원문 (예: 학기 단위 (연장 가능))
  work_duration_type duration_type_e DEFAULT 'unknown'
                                              -- 단기/장기/미분류 (크롤링 파싱 결과)

  -- 근무 시간
  work_time_text    TEXT                      -- 근무시간 원문 (학기중/방학중 구분 포함)

  -- 모집 기간
  recruitment_period_text TEXT                -- 모집기간 원문

  -- 담당자 정보
  contact_name      VARCHAR(50)               -- 담당자 이름
  -- contact_phone·contact_email: 개인정보 최소수집 위해 제거 (2026-06-19, 회의 결정 #15)

  -- 원본
  raw_text          TEXT                      -- 크롤링 원문 전체
  is_active         BOOLEAN DEFAULT TRUE      -- 현재 노출 여부 (비활성화 시 FALSE)
  is_placeholder    BOOLEAN NOT NULL DEFAULT FALSE  -- 공고 없는 근무지를 노출시키기 위한 껍데기 posting 표식
  -- ※ 앱은 공고 ≥1을 요구한다(검색 RPC의 INNER join·자동완성의 exists·상세의 infoReady) → 명부 시드처럼
  --   공고가 없는 근무지는 껍데기 posting 1개(is_active=false)로 게이트를 통과시킨다.
  --   실제 공고를 크롤로 넣을 때 `delete from postings where worksite_id=X and is_placeholder=true` 후 insert.
  --   그땐 리뷰가 이미 붙어 있어 통짜 wipe 불가 — 플래그 없이 "null 패턴"으로 추측하면 위험하다.
  --   리뷰는 worksite_id에 붙으므로 postings만 교체해도 무손상. (20260716180000)

  -- 외부 소스 연동 (SSC/KUPID 크롤러 멱등 UPSERT용, 20260721150404)
  source            VARCHAR(20)   -- 공고 출처 ('ssc' | 'kupid'). NULL=레거시/수동 행
  external_id       VARCHAR(100)  -- 소스별 공고 자연키(SSC=board_no, KUPID=stable_key 해시). unique(source, external_id) where 둘 다 not null
  manual_override   BOOLEAN NOT NULL DEFAULT FALSE  -- true면 크롤러가 content 컬럼(시급·직무 등)을 덮어쓰지 않음(사람 수정 보호)
  -- ※ 백필(normalized_name·기존 행의 source/external_id)은 로더(Python)가 정본 — 이 마이그레이션은 컬럼·인덱스만 추가

  -- 모집 마감 판정 (동적 is_active의 대체)
  recruit_until     DATE                      -- 이 날짜까지 접수 가능(추정 포함). NULL=판정 불가(레거시) → 프론트 is_active 폴백
  recruit_until_at  TIMESTAMPTZ               -- 정확한 마감 순간. 있으면 recruit_until보다 우선하며 해당 순간부터 모집완료
  recruit_until_estimated BOOLEAN NOT NULL DEFAULT FALSE  -- true면 추정값(명시 마감일 없음)
  -- 학교근장: SSC는 구조화 모집기간, KUPID는 명시 마감일 또는 추정(등록일+21일과 근무시작일 전날 중 더 빠른 쪽)으로 채움
  -- 국가근장: 추측 금지 — 학기·방학 모집기간 확정 시 일괄 UPDATE (web/supabase/README.md 뼈대 참고)

  created_at        TIMESTAMPTZ DEFAULT NOW()   -- 공고 등록 일시
  updated_at        TIMESTAMPTZ DEFAULT NOW()   -- 수정 일시
  deleted_at        TIMESTAMPTZ                 -- 삭제 일시. NULL이면 활성 (소프트 삭제, 관리자만)

-- 리뷰 (특정 공고가 아닌 근무지 단위로 달림)
reviews
  id              SERIAL PRIMARY KEY                -- 리뷰 고유 ID
  user_id         UUID REFERENCES users(id) ON DELETE SET NULL  -- 작성자. 탈퇴 시 NULL (익명 유지)
  -- ※ NULL 허용: 탈퇴 후 익명 유지 정책에 따라 user_id → NULL 처리
  worksite_id     INTEGER NOT NULL REFERENCES worksites(id) ON DELETE RESTRICT  -- 리뷰 대상 근무지
  work_year       INTEGER NOT NULL                  -- 근무 연도 (예: 2024)
  work_semester   VARCHAR(10) NOT NULL              -- 근무 학기 (1학기/여름방학/2학기/겨울방학)
  score_work      NUMERIC(2,1) CHECK (score_work BETWEEN 0.5 AND 5.0)      -- 업무량 점수 (0.5~5.0)
  score_growth    NUMERIC(2,1) CHECK (score_growth BETWEEN 0.5 AND 5.0)    -- 자기계발 점수 (0.5~5.0)
  score_vibe      NUMERIC(2,1) CHECK (score_vibe BETWEEN 0.5 AND 5.0)      -- 분위기 점수 (0.5~5.0)
  score_flex      NUMERIC(2,1) CHECK (score_flex BETWEEN 0.5 AND 5.0)      -- 시간유연성 점수 (0.5~5.0)
  score_recommend NUMERIC(2,1) CHECK (score_recommend BETWEEN 0.5 AND 5.0) -- 추천 점수 (0.5~5.0)
  work_content    TEXT CHECK (char_length(work_content) BETWEEN 30 AND 1000)   -- 업무 내용 서술 (30~1000자)
  opinion         TEXT CHECK (char_length(opinion) BETWEEN 50 AND 2000)        -- 종합 의견 (50~2000자)
  is_anonymous    BOOLEAN NOT NULL DEFAULT false     -- 익명 작성 여부(true면 작성자 닉네임·근로학기 숨김)
  is_blinded      BOOLEAN NOT NULL DEFAULT false     -- 블라인드 처리 여부(true면 목록에 placeholder·내용/점수/작성자 서버 마스킹·집계 제외, §③). 관리자 UI 없이 Supabase에서 직접 set
  helpful_count   INTEGER DEFAULT 0                 -- 도움됐어요 수 캐시. 유저 탈퇴 후에도 유지
  created_at      TIMESTAMPTZ DEFAULT NOW()           -- 작성 일시
  updated_at      TIMESTAMPTZ DEFAULT NOW()           -- 수정 일시
  deleted_at      TIMESTAMPTZ                         -- 삭제 일시. NULL이면 활성 (소프트 삭제, 관리자만)
  UNIQUE (user_id, work_year, work_semester)   -- 한 학기당 1리뷰(근무지 불문, user_id NULL은 복수 허용) (제약명: reviews_user_year_semester_key)
  -- ※ 학기당 1리뷰 제약 — DB 레벨에서 race condition 방지
  --   user_id=NULL인 row(탈퇴 후 익명)는 PostgreSQL이 NULL≠NULL로 처리하므로 여러 개 허용됨 (정상)

-- 도움됐어요 (토글 방식 — INSERT=좋아요, DELETE=취소)
-- 카운트 숫자만 유지되면 충분 → 유저 탈퇴 시 row는 CASCADE 삭제, helpful_count는 보존
review_helpful
  user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE     -- 누른 유저
  review_id  INTEGER NOT NULL REFERENCES reviews(id) ON DELETE CASCADE   -- 대상 리뷰
  created_at TIMESTAMPTZ DEFAULT NOW()                                     -- 누른 일시
  PRIMARY KEY (user_id, review_id)           -- 동일 유저 중복 클릭 방지

-- 포인트 내역
points
  id              SERIAL PRIMARY KEY                -- 내역 고유 ID
  user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE   -- 대상 유저
  amount          INTEGER NOT NULL                  -- 변동 포인트 (양수=획득, 음수=차감)
  reason          VARCHAR(50) NOT NULL              -- 사유 (review_write/review_delete/review_anon_switch/review_policy_grant/false_review_penalty/ad_view/signup_bonus/pass_purchase/pass_refund/nickname_change)
  -- ※ false_review_penalty(허위 리뷰 제재 몰수)는 재정산 reason 목록
  --   ('review_write','review_anon_switch','review_policy_grant')에 **절대 넣지 말 것** — §⑮ 참고
  review_id       INTEGER REFERENCES reviews(id) ON DELETE SET NULL         -- 리뷰 관련 사유일 때만 사용, 나머지는 NULL
  ad_view_id      INTEGER REFERENCES ad_views(id) ON DELETE SET NULL        -- 광고 시청 사유일 때만 사용, 나머지는 NULL
  -- ※ signup_bonus, pass_purchase, nickname_change는 참조 row 없음 → 두 컬럼 모두 NULL
  -- ※ nickname_change_ticket_purchase/refund는 보관형 변경권 폐지 전의 과거 원장 reason으로만 남을 수 있음
  -- ※ 리뷰 삭제 시 반드시 트랜잭션으로 처리:
  --   1. points INSERT (reason='review_delete', amount=-25(실명 예시 — 실제론 그 리뷰의 적립합), review_id=<id>)
  --   2. reviews DELETE → ON DELETE SET NULL 발동 → 두 points row의 review_id가 NULL로
  created_at      TIMESTAMPTZ DEFAULT NOW()           -- 발생 일시

-- 신고
reports
  id                SERIAL PRIMARY KEY              -- 신고 고유 ID
  reporter_id       UUID REFERENCES users(id) ON DELETE SET NULL      -- 신고한 유저. 탈퇴 시 NULL
  reported_user_id  UUID REFERENCES users(id) ON DELETE SET NULL      -- 신고당한 유저. 탈퇴 시 NULL
  review_id         INTEGER REFERENCES reviews(id) ON DELETE SET NULL    -- 신고 대상 리뷰. 리뷰 삭제 시 NULL
  reason            VARCHAR(100)                    -- 신고 사유
  opinion           TEXT                            -- 신고 상세 내용(2026-07-31~ 필수, 이전 row는 NULL)
  status            report_status_e DEFAULT 'pending'  -- 처리 상태 (대기/삭제/무시)
  created_at        TIMESTAMPTZ DEFAULT NOW()         -- 신고 일시

-- 광고 시청
ad_views
  id              SERIAL PRIMARY KEY                -- 시청 기록 고유 ID
  user_id         UUID REFERENCES users(id) ON DELETE SET NULL  -- 시청한 유저. 탈퇴 시 NULL (기록 보존)
  created_at      TIMESTAMPTZ DEFAULT NOW()           -- 시청 일시
  -- ② 확장(ad_id/token/claimed_at)은 push 대기 — 아래 §리워드 광고 서버 참조
  -- ※ 일정 시간 내 n회 이하 제한 → 앱 레이어에서 COUNT 쿼리로 검증
  --   구체적 제한 횟수는 policy.md 참고

-- 공지사항
notices
  id          SERIAL PRIMARY KEY                    -- 공지 고유 ID
  title       VARCHAR(200) NOT NULL                 -- 공지 제목
  content     TEXT                                  -- 공지 내용
  university_id INTEGER REFERENCES universities(id) ON DELETE RESTRICT  -- NULL: 공통 공지, 값 있음: 해당 학교/캠퍼스 공지
  is_pinned   BOOLEAN DEFAULT FALSE                 -- 상단 고정 여부
  created_at  TIMESTAMPTZ DEFAULT NOW()               -- 작성 일시
  updated_at  TIMESTAMPTZ DEFAULT NOW()               -- 수정 일시
```
