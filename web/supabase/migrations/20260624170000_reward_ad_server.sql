-- 목적: ② 리워드 광고 서버 — ads/ad_reward_config/ad_clicks + ad_views 확장 + 토큰 적립 RPC, watch_ad_reward 대체
-- 날짜: 2026-06-24 · 담당: 현수(kindofwater)

-- ── 1. 광고 인벤토리 ──
create table if not exists ads (
  id               serial primary key,
  title            text not null,
  media_path       text not null,
  media_type       text not null default 'photo' check (media_type in ('photo','video')),
  target_url       text,
  min_view_seconds int  not null default 5,
  is_active        boolean not null default true,
  created_at       timestamptz not null default now()
);

-- ── 2. 보상 설정(싱글톤) ──
create table if not exists ad_reward_config (
  id               int primary key default 1 check (id = 1),
  daily_cap        int not null default 2,
  reward_points    int not null default 5,
  cooldown_minutes int not null default 0,
  updated_at       timestamptz not null default now()
);
insert into ad_reward_config (id) values (1) on conflict (id) do nothing;

-- ── 3. 클릭 로그 ──
create table if not exists ad_clicks (
  id         serial primary key,
  ad_id      int  references ads(id)   on delete set null,
  user_id    uuid references users(id) on delete set null,
  created_at timestamptz not null default now()
);

-- ── 4. ad_views 확장 ──
alter table ad_views add column if not exists ad_id      int references ads(id) on delete set null;
alter table ad_views add column if not exists token      uuid not null default gen_random_uuid();
alter table ad_views add column if not exists claimed_at timestamptz;
create unique index if not exists ad_views_token_key on ad_views (token);
update ad_views set claimed_at = created_at where claimed_at is null;

-- ── 5. RLS (접근은 RPC 경유 — 클라 정책 없음) ──
alter table ads              enable row level security;
alter table ad_reward_config enable row level security;
alter table ad_clicks        enable row level security;

-- ── 6. 서빙 ──
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
  if v_cfg.id is null then raise exception 'NO_CONFIG'; end if;
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

-- ── 7. 적립 ──
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
  if v_view.id is null then raise exception 'INVALID_TOKEN'; end if;
  select coalesce(min_view_seconds, 5) into v_min from ads where id = v_view.ad_id;
  if now() < v_view.created_at + (coalesce(v_min,5) * interval '1 second') then
    raise exception 'TOO_SOON';
  end if;
  select * into v_cfg from ad_reward_config where id = 1;
  if v_cfg.id is null then raise exception 'NO_CONFIG'; end if;
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
revoke execute on function start_ad_view()       from anon, public;
revoke execute on function claim_ad_reward(uuid) from anon, public;
revoke execute on function log_ad_click(int)     from anon, public;
grant  execute on function start_ad_view()       to authenticated;
grant  execute on function claim_ad_reward(uuid) to authenticated;
grant  execute on function log_ad_click(int)     to authenticated;

-- ── 10. 시드 광고 ──
-- ⚠️ placeholder를 prod ads에 넣지 않는다: 버킷에 없는 파일을 start_ad_view의 order by random()이
--    뽑으면 깨진 이미지가 노출된다. 실제 광고는 db push 후 ad-media 버킷에 이미지 업로드 →
--    SQL Editor에서 직접 INSERT한다(배포 런북 4단계 참조). media_type은 업로드 파일과 일치(photo|video).
-- 예) insert into ads (title, media_path, target_url, media_type)
--     values ('실제 가게', 'seed-ad-1.jpg', 'https://instagram.com/실제계정', 'photo');
