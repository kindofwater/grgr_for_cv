# ② 리워드 광고 서버 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 로컬 가게 사진광고를 강제 시청(기본 5초)시키고, 1회용 토큰 + 서버 월클럭 + 캡으로 검증해 +5P를 지급하는 자체 리워드 광고 서버를 만든다(콘솔 어뷰징 차단, `watch_ad_reward` 대체).

**Architecture:** `ads`(인벤토리)·`ad_reward_config`(설정)·`ad_clicks`(클릭로그) 테이블 + `ad_views` 확장(토큰·ad_id·claimed_at). `start_ad_view()`가 활성 광고+1회용 토큰을 발급하고 `claim_ad_reward(token)`이 "광고 노출 후 `min_view_seconds` 실제 경과"를 서버에서 재검증해 적립한다. 클라(AdView)는 카운트다운 동안 받기·클릭을 잠그고, 끝나면 해제(강제 시청 UX). 미디어 중립(`media_path`/`media_type`)이라 미래 영상은 렌더만 교체.

**Tech Stack:** Supabase(Postgres + Storage + PostgREST RPC), Supabase CLI 마이그레이션, React + Vite, `@supabase/supabase-js`.

**근거 스펙:** [docs/superpowers/specs/2026-06-24-reward-ad-server-design.md](../specs/2026-06-24-reward-ad-server-design.md).

## Global Constraints
- **⛔ 현수 사인오프 전 `db push` 금지** — 광고 보상·RPC·DB는 현수 영역(spec D7). 배경록 주도 설계·구현 → 사인오프 후 push.
- `watch_ad_reward()` **제거** → 적립은 `start_ad_view`→`claim_ad_reward` 토큰 흐름으로만(콘솔 직접호출 차단).
- **강제 시청:** `min_view_seconds`(기본 5, **데이터** `ads` 컬럼). 그 시간 동안 받기·클릭 잠금, **'그냥 나가기(미지급)'는 자유**. 시간 후 해제. 서버가 월클럭 재검증.
- **캡 = `ad_reward_config`**(싱글톤): `daily_cap=2, reward_points=5, cooldown_minutes=0`. **설정값 — 하드코딩 금지.**
- **미디어 중립:** `ads.media_path` + `media_type text not null default 'photo'`(photo|video). Storage 버킷 **`ad-media`** 공개 read.
- **클릭 추적:** `ad_clicks`(ad_id, user_id, created_at).
- **RLS:** `ads`/`ad_reward_config`/`ad_clicks` RLS on, **클라 정책 없음**(전부 DEFINER RPC 경유). `ad_views`는 컷오버의 `adviews_select_own` 유지.
- **마이그레이션 규칙(CLAUDE.md §3):** 헤더 2줄, `drop function if exists` 먼저. Docker 없음 → 정적 검토(+ 사인오프 후 sandbox/`db push`). 디스코드 사전공유.
- **클라 계약(컷오버 후):** `useAuth()` → `{ user, isLoading, mergeUser, logout }`. 지갑 갱신은 `mergeUser(wallet)`.

---

## File Structure
**신규:** `web/supabase/migrations/<ts>_reward_ad_server.sql` · `web/src/data/adQueries.js`
**수정:** `web/src/pages/AdView.jsx`(재작성) · `web/src/pages/AdView.css`(버튼 상태) · `web/src/data/exchangeQueries.js`(`watchAdReward` 제거)
**수동(대시보드):** Storage 버킷 `ad-media`(공개 read) + 시드 광고
**문서:** `docs/db-schema.md` · `docs/api-spec.md` · `web/src/data/README.md` · `web/src/pages/README.md`

> DB와 클라가 함께 가는 단일 기능. 독립 서브시스템 아님 → 단일 플랜. 실행은 Phase 단위 체크포인트.

---

## Phase 0 — 수동 준비 (대시보드)

### Task 0: Storage 버킷 `ad-media` + 시드 광고 (문서화)
**Files:** Doc: `web/supabase/README.md`(절차 기록)

- [ ] **Step 1:** Supabase 대시보드 → Storage → **New bucket `ad-media`**, **Public** 체크(공개 read). 정책은 공개 read + 쓰기 service_role 기본.
- [ ] **Step 2:** 시드 광고 이미지 업로드(예: `gimbap.jpg`) + 아래 Task 3 마이그레이션의 시드 INSERT에 그 `media_path`(`gimbap.jpg`)·`target_url`(인스타) 반영.
- [ ] **Step 3:** README에 "ad-media 버킷·공개 read·시드 절차" 한 단락 기록.
- [ ] **Step 4: Commit**
```bash
git add web/supabase/README.md
git commit -m "docs(ad): ad-media Storage 버킷·시드 절차 기록"
```
> ⚠️ 이 단계는 prod 대시보드 작업이라 사인오프 후 실제 클릭. 지금은 절차만 문서화.

---

## Phase 1 — DB 마이그레이션 (단일 파일)

### Task 1: 마이그레이션 스캐폴드 + 테이블 + ad_views 확장 + config 시드
**Files:** Create: `web/supabase/migrations/<ts>_reward_ad_server.sql`

- [ ] **Step 1: 파일 생성**
```bash
cd web && npx supabase migration new reward_ad_server
```
- [ ] **Step 2: 헤더 + 스키마 작성**
```sql
-- 목적: ② 리워드 광고 서버 — ads/ad_reward_config/ad_clicks + ad_views 확장 + 토큰 적립 RPC, watch_ad_reward 대체
-- 날짜: 2026-06-24 · 담당: 현수(kindofwater)

-- ── 1. 광고 인벤토리 ──
create table ads (
  id               serial primary key,
  title            text not null,
  media_path       text not null,                       -- Storage 'ad-media' 내 경로
  media_type       text not null default 'photo' check (media_type in ('photo','video')),
  target_url       text,                                -- 인스타/네이버지도 (선택)
  min_view_seconds int  not null default 5,             -- 강제 시청 시간(데이터)
  is_active        boolean not null default true,
  created_at       timestamptz not null default now()
);

-- ── 2. 보상 설정(싱글톤) ──
create table ad_reward_config (
  id               int primary key default 1 check (id = 1),
  daily_cap        int not null default 2,
  reward_points    int not null default 5,
  cooldown_minutes int not null default 0,
  updated_at       timestamptz not null default now()
);
insert into ad_reward_config (id) values (1);

-- ── 3. 클릭 로그 ──
create table ad_clicks (
  id         serial primary key,
  ad_id      int  references ads(id)   on delete set null,
  user_id    uuid references users(id) on delete set null,
  created_at timestamptz not null default now()
);

-- ── 4. ad_views 확장 (노출 1건 = 행 1개, 적립여부 포함) ──
alter table ad_views add column ad_id      int references ads(id) on delete set null;
alter table ad_views add column token      uuid not null default gen_random_uuid();
alter table ad_views add column claimed_at timestamptz;
create unique index ad_views_token_key on ad_views (token);
update ad_views set claimed_at = created_at where claimed_at is null;  -- 기존(구 watch_ad_reward) 행은 적립됨으로 표기
```
- [ ] **Step 3: 검증(정적, Docker 없음)** — `web/supabase/migrations/20260609000000_baseline.sql`에서 `ad_views`(id,user_id,created_at)·`points`(user_id,amount,reason,ad_view_id)·`users(id uuid)` 컬럼명이 위와 맞는지 대조. (Docker 있으면 `npx supabase db reset`.)
- [ ] **Step 4: Commit**
```bash
git add web/supabase/migrations/*_reward_ad_server.sql
git commit -m "feat(ad): 광고 인벤토리/설정/클릭 테이블 + ad_views 토큰 확장"
```

### Task 2: RLS
**Files:** Modify: 같은 마이그레이션 파일(append)
**Interfaces:** Produces: 신규 3테이블 RLS on(클라 직접 접근 차단; RPC가 DEFINER로 처리).

- [ ] **Step 1: append**
```sql
-- ── 5. RLS (쓰기·읽기 모두 RPC 경유 — 클라 정책 없음) ──
alter table ads              enable row level security;
alter table ad_reward_config enable row level security;
alter table ad_clicks        enable row level security;
-- 정책을 안 만들면 클라(anon/authenticated)는 직접 접근 불가. SECURITY DEFINER RPC(owner=postgres)는 우회.
-- ad_views는 컷오버에서 RLS+adviews_select_own(본인) 이미 적용됨.
```
- [ ] **Step 2: 검증** — 정적: 신규 3테이블에 client 정책 없음(의도) 확인. `ad_views` 정책은 컷오버 것 유지.
- [ ] **Step 3: Commit**
```bash
git commit -am "feat(ad): 광고 테이블 RLS on (접근은 RPC 경유)"
```

### Task 3: RPC 3종 + watch_ad_reward 제거 + grants + 시드 광고
**Files:** Modify: 같은 마이그레이션 파일(append)
**Interfaces:** Produces (클라 계약):
- `start_ad_view()` → `jsonb { ad: { id int, title text, media_path text, media_type text, target_url text, min_view_seconds int }, token uuid }` · 에러 `NOT_AUTHENTICATED`/`CAP_REACHED`/`NO_ADS`
- `claim_ad_reward(p_token uuid)` → `jsonb`(지갑) · 에러 `NOT_AUTHENTICATED`/`INVALID_TOKEN`/`TOO_SOON`/`CAP_REACHED`
- `log_ad_click(p_ad_id int)` → `void`

- [ ] **Step 1: append**
```sql
-- ── 6. 서빙: 활성 광고 + 1회용 토큰 ──
create or replace function start_ad_view()
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_uid uuid := auth.uid();
  v_cfg ad_reward_config;
  v_today int;
  v_last timestamptz;
  v_ad ads;
  v_token uuid;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  select * into v_cfg from ad_reward_config where id = 1;
  select count(*), max(claimed_at) into v_today, v_last
    from ad_views where user_id = v_uid and claimed_at is not null and claimed_at::date = current_date;
  if v_today >= v_cfg.daily_cap then raise exception 'CAP_REACHED'; end if;
  if v_cfg.cooldown_minutes > 0 and v_last is not null
     and now() < v_last + (v_cfg.cooldown_minutes * interval '1 minute') then
    raise exception 'CAP_REACHED';
  end if;
  select * into v_ad from ads where is_active order by random() limit 1;
  if v_ad.id is null then raise exception 'NO_ADS'; end if;
  insert into ad_views (user_id, ad_id) values (v_uid, v_ad.id) returning token into v_token;
  return jsonb_build_object(
    'ad', jsonb_build_object('id', v_ad.id, 'title', v_ad.title, 'media_path', v_ad.media_path,
      'media_type', v_ad.media_type, 'target_url', v_ad.target_url, 'min_view_seconds', v_ad.min_view_seconds),
    'token', v_token);
end $$;

-- ── 7. 적립: 토큰 + 월클럭 시간검증 + 캡 ──
create or replace function claim_ad_reward(p_token uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_view ad_views;
  v_min int;
  v_cfg ad_reward_config;
  v_today int;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  select * into v_view from ad_views where token = p_token and user_id = v_uid and claimed_at is null;
  if v_view.id is null then raise exception 'INVALID_TOKEN'; end if;        -- 잘못/중복 토큰
  select coalesce(min_view_seconds, 5) into v_min from ads where id = v_view.ad_id;
  if now() < v_view.created_at + (coalesce(v_min,5) * interval '1 second') then
    raise exception 'TOO_SOON';                                            -- 5초 전 적립 차단
  end if;
  select * into v_cfg from ad_reward_config where id = 1;
  select count(*) into v_today from ad_views
    where user_id = v_uid and claimed_at is not null and claimed_at::date = current_date;
  if v_today >= v_cfg.daily_cap then raise exception 'CAP_REACHED'; end if;
  update ad_views set claimed_at = now() where id = v_view.id;
  insert into points (user_id, amount, reason, ad_view_id) values (v_uid, v_cfg.reward_points, 'ad_view', v_view.id);
  update users set point_balance = point_balance + v_cfg.reward_points where id = v_uid;
  return _wallet();
end $$;

-- ── 8. 클릭 로그 ──
create or replace function log_ad_click(p_ad_id int)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  insert into ad_clicks (ad_id, user_id) values (p_ad_id, v_uid);
end $$;

-- ── 9. 구 보상 함수 제거 + grants ──
drop function if exists watch_ad_reward();
revoke execute on function start_ad_view()        from anon, public;
revoke execute on function claim_ad_reward(uuid)  from anon, public;
revoke execute on function log_ad_click(int)      from anon, public;
grant  execute on function start_ad_view()        to authenticated;
grant  execute on function claim_ad_reward(uuid)  to authenticated;
grant  execute on function log_ad_click(int)      to authenticated;

-- ── 10. 시드 광고(예시 — Task 0에서 올린 실제 media_path/target_url로 교체) ──
insert into ads (title, media_path, target_url) values
  ('예시 가게', 'seed-placeholder.jpg', 'https://instagram.com/example');
```
- [ ] **Step 2: 검증(정적)** — `_wallet()`·`points` 컬럼 시그니처가 컷오버 마이그레이션과 일치하는지 대조. `start_ad_view`/`claim_ad_reward`/`log_ad_click` 인자·grant 시그니처 일치 확인. `watch_ad_reward()`(무인자, 컷오버 후) 드롭 맞는지.
- [ ] **Step 3: Commit**
```bash
git commit -am "feat(ad): start_ad_view/claim_ad_reward/log_ad_click + watch_ad_reward 제거 + grant + 시드"
```

---

## Phase 2 — 클라이언트

### Task 4: `adQueries.js` (신규)
**Files:** Create: `web/src/data/adQueries.js`
**Interfaces:** Consumes: Task 3 RPC. Produces: `startAdView()`/`claimAdReward(token)`/`logAdClick(adId)`.

- [ ] **Step 1: 작성**
```js
import { supabase } from '../supabase'

// 활성 광고 + 1회용 토큰. 캡 도달 시 'CAP_REACHED', 광고 없으면 'NO_ADS' 에러.
export async function startAdView() {
  const { data, error } = await supabase.rpc('start_ad_view')
  if (error) throw error
  return data // { ad: { id, title, media_path, media_type, target_url, min_view_seconds }, token }
}

// 토큰으로 적립(서버가 min_view_seconds 월클럭 재검증). 'TOO_SOON'/'INVALID_TOKEN'/'CAP_REACHED' 가능.
export async function claimAdReward(token) {
  const { data, error } = await supabase.rpc('claim_ad_reward', { p_token: token })
  if (error) throw error
  return data // 지갑(point_balance, pass_balances, pass_expires_at)
}

// 클릭 로그(fire-and-forget).
export async function logAdClick(adId) {
  const { error } = await supabase.rpc('log_ad_click', { p_ad_id: adId })
  if (error) throw error
}
```
- [ ] **Step 2: 검증** — `cd web && npm run build` 통과(새 파일, additive). 폴더 README에 adQueries 한 줄 추가(data/README.md).
- [ ] **Step 3: Commit**
```bash
git add web/src/data/adQueries.js web/src/data/README.md
git commit -m "feat(ad): adQueries — start_ad_view/claim_ad_reward/log_ad_click 래퍼"
```

### Task 5: `AdView.jsx` 재작성(강제 시청 UX) + `exchangeQueries.watchAdReward` 제거
**Files:** Modify: `web/src/pages/AdView.jsx`(전면 재작성) · `web/src/pages/AdView.css`(버튼 상태) · `web/src/data/exchangeQueries.js`(`watchAdReward` 제거)
**Interfaces:** Consumes: Task 4 adQueries, `useAuth().mergeUser`, Storage 버킷 `ad-media`.

- [ ] **Step 1: `AdView.jsx` 전면 교체**
```jsx
import { useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../supabase'
import { useAuth } from '../components/AuthContext'
import { startAdView, claimAdReward, logAdClick } from '../data/adQueries'
import './AdView.css'

export default function AdView() {
  const navigate = useNavigate()
  const { user, mergeUser } = useAuth()
  const [status, setStatus] = useState('loading') // loading|ready|capped|noads|error
  const [ad, setAd] = useState(null)
  const [token, setToken] = useState(null)
  const [deadline, setDeadline] = useState(null)
  const [remaining, setRemaining] = useState(0)
  const [claiming, setClaiming] = useState(false)
  const [errMsg, setErrMsg] = useState('')
  const claimed = useRef(false)

  useEffect(() => {
    if (!user) { navigate('/login'); return }
    let active = true
    ;(async () => {
      try {
        const res = await startAdView()
        if (!active) return
        setAd(res.ad); setToken(res.token)
        setRemaining(res.ad.min_view_seconds)
        setDeadline(Date.now() + res.ad.min_view_seconds * 1000)
        setStatus('ready')
      } catch (e) {
        if (!active) return
        const m = e.message || ''
        if (m.includes('CAP_REACHED')) setStatus('capped')
        else if (m.includes('NO_ADS')) setStatus('noads')
        else { setErrMsg(m); setStatus('error') }
      }
    })()
    return () => { active = false }
  }, [user, navigate])

  useEffect(() => {
    if (status !== 'ready' || !deadline) return
    const id = setInterval(() => {
      const left = Math.max(0, Math.ceil((deadline - Date.now()) / 1000))
      setRemaining(left)
      if (left <= 0) clearInterval(id)
    }, 250)
    return () => clearInterval(id)
  }, [status, deadline])

  const unlocked = status === 'ready' && remaining <= 0

  async function grant(viaClick) {
    if (!unlocked || claiming || claimed.current) return
    setClaiming(true)
    try {
      const wallet = await claimAdReward(token)
      claimed.current = true
      mergeUser(wallet)
      if (!viaClick) navigate('/exchange')
    } catch (e) {
      setClaiming(false)
      if ((e.message || '').includes('INVALID_TOKEN')) { claimed.current = true; if (!viaClick) navigate('/exchange') }
      else alert('포인트 적립 중 오류가 발생했어요: ' + e.message)
    }
  }

  function onGoShop() {
    if (!unlocked || !ad?.target_url) return
    window.open(ad.target_url, '_blank', 'noopener')
    logAdClick(ad.id).catch(() => {})
    grant(true) // 클릭도 적립(5초 지났으니 통과). 닫지 않고 머무름.
  }

  if (status === 'loading') return <div className="ad-wrap"><div className="ad-lead">광고 불러오는 중…</div></div>
  if (status === 'capped')  return <div className="ad-wrap"><div className="ad-lead">오늘 광고 보상은 다 받으셨어요.</div><button className="ad-skip" onClick={() => navigate('/exchange')}>돌아가기</button></div>
  if (status === 'noads')   return <div className="ad-wrap"><div className="ad-lead">지금은 볼 수 있는 광고가 없어요.</div><button className="ad-skip" onClick={() => navigate('/exchange')}>돌아가기</button></div>
  if (status === 'error')   return <div className="ad-wrap"><div className="ad-lead">광고를 불러오지 못했어요: {errMsg}</div><button className="ad-skip" onClick={() => navigate('/exchange')}>돌아가기</button></div>

  const mediaUrl = supabase.storage.from('ad-media').getPublicUrl(ad.media_path).data.publicUrl
  return (
    <div className="ad-wrap">
      <div className="ad-lead">광고를 끝까지 보면 포인트가 지급됩니다.</div>
      <div className="ad-box">
        {ad.media_type === 'video'
          ? <video className="ad-media" src={mediaUrl} autoPlay muted playsInline />
          : <img className="ad-media" src={mediaUrl} alt={ad.title} />}
        {!unlocked && <div className="ad-countdown">{remaining}</div>}
      </div>
      <button className="ad-cta" disabled={!unlocked || claiming} onClick={() => grant(false)}>
        {unlocked ? (claiming ? '적립 중…' : '받기') : `${remaining}초 후 받기`}
      </button>
      {ad.target_url &&
        <button className="ad-shop" disabled={!unlocked} onClick={onGoShop}>가게 보러가기</button>}
      <button className="ad-skip" onClick={() => navigate('/exchange')}>그냥 나가기 (포인트 미지급)</button>
    </div>
  )
}
```
- [ ] **Step 2: `AdView.css`에 새 요소 스타일 추가** (기존 `.ad-wrap/.ad-box/.ad-cta/.ad-skip` 재사용, 아래만 추가)
```css
.ad-media { width: 100%; border-radius: 8px; display: block; }
.ad-countdown { position: absolute; top: 10px; right: 14px; background: rgba(0,0,0,.6); color:#fff;
  width: 28px; height: 28px; border-radius: 50%; display:flex; align-items:center; justify-content:center; font-weight:700; }
.ad-box { position: relative; }
.ad-shop { width:100%; margin-top:10px; padding:12px; border-radius:10px; border:1px solid var(--primary);
  background:transparent; color:var(--primary); font-weight:600; cursor:pointer; font-family:inherit; }
.ad-shop:disabled { opacity:.5; cursor:not-allowed; }
```
- [ ] **Step 3: `exchangeQueries.js`에서 `watchAdReward` 제거** — 함수 export 삭제(AdView가 더 이상 import 안 함). `git grep -n "watchAdReward" web/src` → 0 확인.
- [ ] **Step 4: 검증** — `cd web && npm run build` 통과(missing-export 없어야). `git grep -n "watchAdReward" web/src` = 0. 정적: 강제시청 잠금(`disabled={!unlocked}`)·나가기 항상 활성·클릭 후 grant(true) 확인. (런타임은 마이그레이션 적용+시드 후 현수/배경록.)
- [ ] **Step 5: Commit**
```bash
git add web/src/pages/AdView.jsx web/src/pages/AdView.css web/src/data/exchangeQueries.js
git commit -m "feat(ad): AdView 강제시청 UX 재작성(토큰·카운트다운·받기/가게보러가기/나가기) + watchAdReward 제거"
```

---

## Phase 3 — 문서 · 반영(게이트)

### Task 6: 문서 갱신
**Files:** Modify: `docs/db-schema.md` · `docs/api-spec.md` · `web/src/pages/README.md`

- [ ] **Step 1:** db-schema에 `ads`·`ad_reward_config`·`ad_clicks`·`ad_views` 확장 + 3 RPC + RLS 반영. api-spec에 `start_ad_view`/`claim_ad_reward`/`log_ad_click` 추가·`watch_ad_reward` 제거 표기. pages/README의 AdView 행을 "강제 시청 리워드 광고"로 갱신.
- [ ] **Step 2: Commit**
```bash
git commit -am "docs(ad): 리워드 광고 서버 스키마/RPC/RLS 문서 반영"
```

### Task 7: 반영 (⛔ 현수 사인오프 게이트)
- [ ] **Step 1:** 디스코드 사전공유. **현수와 `watch_ad_reward` 드롭·새 RPC push 타이밍 합의.**
- [ ] **Step 2:** 대시보드에서 **`ad-media` 버킷 생성 + 시드 광고 이미지 업로드**, 시드 INSERT의 `media_path`/`target_url`을 실제값으로 교체.
- [ ] **Step 3:** `cd web && npx supabase db push`(작성자) → PostgREST 스키마 reload → 클라 배포.
- [ ] **Step 4: 스모크** — 로그인 → `/ad`: 카운트다운 동안 받기/가게보러가기 잠김·나가기 됨 → 5초 후 받기(+5P)·클릭 동작 → 하루 2회 후 `CAP_REACHED` → 콘솔 `supabase.rpc('claim_ad_reward',{p_token:'00000000-0000-0000-0000-000000000000'})` → `INVALID_TOKEN`. (= spec 검증.)

---

## Self-Review (작성자 점검)
- **스펙 커버리지:** 데이터모델(Task1)·RLS(Task2)·3 RPC+watch_ad_reward 제거(Task3)·adQueries(Task4)·AdView 강제시청 UX+watchAdReward 제거(Task5)·Storage/시드(Task0,7)·캡 설정값(Task1 config)·미디어중립(Task1 media_type)·클릭추적(Task1 ad_clicks/Task3 log_ad_click)·문서(Task6)·게이트(Task7). 스펙 §4 A~G 전부 대응.
- **타입 일관성:** RPC 반환 shape(`start_ad_view`의 ad 필드·`token`) ↔ adQueries ↔ AdView 일치. `claim_ad_reward(p_token uuid)` ↔ grant 시그니처 ↔ adQueries 인자 일치. `mergeUser(wallet)`(컷오버 계약) 사용.
- **범위 밖:** AdSense 트랙ⓑ·영상 렌더 구현·풀 관리자 등록 UI·쿨다운(설정 0)·정교 사기탐지 — 본 플랜 제외.
- **리스크:** Storage public URL은 클라가 `getPublicUrl`로 생성(SQL에 프로젝트 URL 하드코딩 회피). 강제시청은 클라 잠금 + 서버 월클럭 이중이나 "실제 눈" 보장은 못함(캡이 backstop) — 스펙대로.
