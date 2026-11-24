## Supabase 연결 설정

### 1. 코드 받기

```bash
git clone https://github.com/brightdear/honeyjang.git
cd honeyjang
```

이미 클론 받았다면 최신 상태로 업데이트:
```bash
git pull
```

`web/` 폴더는 git에 포함되어 있어서 자동으로 받아져요.
다만 아래 두 가지는 `.gitignore`에 포함되어 있어서 **각자 따로 만들어야 합니다**:
- `web/.env.local` — API 키 (보안상 git에 안 올림)
- `web/node_modules/` — npm 패키지 (용량 큼)

---

### 2. `.env.local` 파일 만들기

`web/.env.local` 파일을 새로 만들고 아래 내용을 붙여넣으세요.
키 값은 PM한테 따로 받으세요.

```
VITE_SUPABASE_URL=https://hawsypzrpacelmxdbwih.supabase.co
VITE_SUPABASE_ANON_KEY=여기에_PM한테_받은_키_입력
```

> ⚠️ 이 파일은 절대 GitHub에 올리지 마세요.
---

### 3. 패키지 설치

```bash
cd web
npm install
```

`node_modules`도 gitignore라 첫 설치 한 번만 해주면 됩니다.
새 패키지 추가될 때는 다시 `npm install` 실행.

---

### 4. 개발 서버 실행

```bash
npm run dev
```

브라우저에서 `http://localhost:5173` 열기.

---

### 5. Supabase 클라이언트 사용법

`web/src/supabase.js`에 클라이언트가 이미 설정되어 있어요.
본인 컴포넌트에서 import해서 쓰면 됩니다.

```js
import { supabase } from './supabase'
```

#### 데이터 조회 예시

```js
const { data, error } = await supabase
  .from('worksites')
  .select('*')

if (error) console.error(error)
else console.log(data)
```

#### 데이터 삽입 예시

```js
const { error } = await supabase
  .from('reviews')
  .insert({ worksite_id: 1, work_year: 2024, work_semester: '1학기', ... })
```

#### Join 쿼리 예시

```js
const { data } = await supabase
  .from('postings')
  .select(`
    id, hourly_wage,
    worksite:worksites (organization_name, workplace_name)
  `)
  .limit(10)
```

---

### 6. 주의사항

- **`service_role` 키는 절대 코드에 넣지 마세요.** PM만 보관합니다.
- 테이블 구조는 `docs/db-schema.md`를 참고하세요.
- 공유 파일(`App.jsx`, `index.css`, `package.json`)을 수정할 때는 팀에 먼저 알려주세요.

---

## 7. DB를 다루는 방법 — RPC & 마이그레이션 (꼭 읽기)

DB 얘기는 두 층으로 나뉩니다: **(A) 앱이 DB랑 대화하는 법**, **(B) DB를 바꾸는 법.**

### (A) 앱 ↔ DB 대화: 일반 쿼리 vs RPC

앱(`web/src/data/`)이 DB를 다루는 방법은 두 가지예요.

**① 일반 쿼리 `.from()`** — 🍳 냉장고에서 재료 직접 꺼내기. 단순 조회/저장.
```js
const { data } = await supabase.from('worksites').select('*')
```

**② RPC `.rpc()`** — 🍲 "비빔밥 하나요!" 주문하기. DB 안에 미리 만든 **함수**를 이름만 불러 실행. 주방(DB)이 여러 작업을 한 번에 처리하고 결과만 줌.
```js
const { data } = await supabase.rpc('write_review_with_points', { /* 인자 */ })
```

**언제 RPC?** 여러 작업이 **전부 되거나 전부 안 되어야** 할 때(원자성), 또는 민감 데이터를 숨기고 결과만 줄 때.
예) 리뷰 작성 = 리뷰 INSERT + 포인트 +15 + 잔액 갱신 **3개를 한 묶음**으로 → 중간에 끊겨도 반쪽 사고 방지.
👉 그래서 리뷰처럼 **부수효과(포인트 등) 있는 쓰기는 직접 `.insert()` 말고 RPC로.**

**우리 RPC:** (auth) **Supabase Auth로 대체 — `verify_login`·`register_user`·`set_password` 제거** / (프로필·지갑) `update_profile`·`_wallet`·`change_nickname` / (리뷰) `write_review_with_points`·`update_review_with_points`·`delete_review_with_rollback`·`toggle_helpful`·`report_review`·`list_worksite_reviews`·`increment_worksite_view`·`get_review_stats`·`get_worksite_score_cards` / (교환) `purchase_pass`·`refund_pass`·`activate_pass` / (광고) `watch_ad_reward`는 ②(push 대기)로 제거 예정 → `start_ad_view`·`claim_ad_reward`·`log_ad_click`(push 대기).
신원 인자(`p_user_id`)는 전부 `auth.uid()`로 대체.
→ 정확한 목록은 [docs/api-spec.md §4](./api-spec.md). 함수 본체 SQL은 `web/supabase/migrations/`, 앱 호출은 `web/src/data/`.

> 📌 리워드 광고(push 대기): Storage 버킷 `ad-media`(공개 read) 생성이 선행조건 — 담당 현수. (상세는 [docs/db-schema.md §② 리워드 광고 서버 → Storage](./db-schema.md))

### (B) DB를 바꾸는 법: 마이그레이션 ← **새 방식, 모두 이거 따르기**

- **옛날(레거시) ❌:** SQL을 SQL 에디터에 복붙 → Run → 디스코드에 손으로 기록. **이제 안 함.**
- **현재 ✅:** Supabase CLI 마이그레이션. 모든 변경이 **파일(git)로 자동 기록**.

```bash
cd web
npx supabase migration new 주제      # SQL 파일 1개 생성
#   → 파일 맨 위 헤더 2줄 필수:
#        -- 목적: <무엇을 왜 바꾸는지>
#        -- 날짜: YYYY-MM-DD · 담당: <이름>
#   → 그 아래 SQL 작성 (테이블 변경이든 RPC든)
npx supabase db push                 # live DB에 반영 (변경한 사람이 직접)
git add . && git commit              # 기록
```

- **RPC 추가/수정도 똑같이** 이 방식으로 (`create or replace function ...`). 함수 **시그니처 바꿀 땐 `drop function if exists ...` 먼저** (안 그러면 옛 함수가 남아 꼬임).
- ❌ **SQL 에디터 수동 편집 금지** (옛/새 섞이면 드리프트 → 사고).
- 자세한 규칙·워크플로우: [web/supabase/README.md](../web/supabase/README.md), [CLAUDE.md §3](../CLAUDE.md)

### 처음 합류했다면 (온보딩)
```bash
git pull
cd web && npm install
npx supabase login          # 브라우저 로그인
npx supabase link           # 목록에서 GRGR 선택
```
→ 끝. baseline은 이미 live에 적용돼 있어서 따로 할 것 없어요. 이제 위 **(B) 방식**으로 DB 바꾸면 됩니다.

> 레거시 기록: 예전 수동 복붙 SQL은 `DB/` 폴더에 참고용으로 남아 있어요(새 변경은 거기 추가 ❌).
