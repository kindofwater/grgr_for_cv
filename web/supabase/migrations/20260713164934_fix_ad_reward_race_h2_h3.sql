-- 목적: 보안점검 H2·H3 — claim_ad_reward 이중적립 레이스 + daily_cap 동시성 우회 차단
--       (users 행 잠금으로 사용자별 직렬화 → 락 안에서 cap 재집계, ad_views 행 for update + 조건부 UPDATE,
--        방어선으로 points(ad_view_id) 부분 유니크 인덱스)
-- 날짜: 2026-07-14 · 담당: 현수

-- ── 1. 방어선: 한 시청(ad_view)당 적립 1회 강제 ──
-- 과거 레이스로 이미 중복 적립된 행이 있으면 인덱스 생성이 실패하므로,
-- 뒤에 생긴 중복 행의 링크만 끊는다(포인트 내역·잔액은 건드리지 않음 — 링크 해제일 뿐).
update points p set ad_view_id = null
where p.ad_view_id is not null
  and exists (
    select 1 from points q
    where q.ad_view_id = p.ad_view_id and q.id < p.id
  );

create unique index if not exists points_ad_view_id_key
  on points (ad_view_id) where ad_view_id is not null;

-- ── 2. claim_ad_reward 원자화 (시그니처 동일 → drop 불필요) ──
-- 잠금 순서: users → ad_views (단일 경로라 교착 없음)
create or replace function claim_ad_reward(p_token uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_view ad_views;
  v_min int;
  v_cfg ad_reward_config;
  v_today int;
  v_rows int;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;

  -- H3: 사용자 행 잠금 — 같은 유저의 동시 claim을 직렬화. 뒤따르는 트랜잭션은
  -- 앞선 커밋 이후의 claimed 집계를 보게 되어 cap 검사(count-then-act)가 유효해진다.
  perform 1 from users where id = v_uid for update;

  -- H2: 대상 시청 행도 잠금 — 같은 토큰 동시 호출이 여기서 줄을 선다.
  select * into v_view from ad_views
    where token = p_token and user_id = v_uid and claimed_at is null
    for update;
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

  -- 조건부 UPDATE + row_count 확인: 락을 못 잡는 경로가 생겨도 이중 적립 불가
  update ad_views set claimed_at = now() where id = v_view.id and claimed_at is null;
  get diagnostics v_rows = row_count;
  if v_rows = 0 then raise exception 'INVALID_TOKEN'; end if;

  insert into points (user_id, amount, reason, ad_view_id) values (v_uid, v_cfg.reward_points, 'ad_view', v_view.id);
  update users set point_balance = point_balance + v_cfg.reward_points where id = v_uid;
  return _wallet();
end $$;
