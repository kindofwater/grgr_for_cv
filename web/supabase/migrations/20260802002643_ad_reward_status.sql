-- 목적: 교환센터가 광고 모달을 열기 전에 오늘의 보상 가능 여부를 조회할 수 있게 한다.
-- 날짜: 2026-08-02 · 담당: Codex

create or replace function public.get_ad_reward_status()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_daily_cap integer;
  v_reward_points integer;
  v_cooldown_minutes integer;
  v_claimed_today integer;
  v_last_claimed_at timestamptz;
  v_cooldown_until timestamptz;
  v_available boolean;
  v_reason text;
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select c.daily_cap, c.reward_points, c.cooldown_minutes
    into v_daily_cap, v_reward_points, v_cooldown_minutes
  from public.ad_reward_config c
  where c.id = 1;

  if not found then
    raise exception 'NO_CONFIG';
  end if;

  select count(*)::integer, max(v.claimed_at)
    into v_claimed_today, v_last_claimed_at
  from public.ad_views v
  where v.user_id = v_uid
    and v.claimed_at is not null
    and v.claimed_at::date = current_date;

  v_cooldown_until := case
    when v_cooldown_minutes > 0 and v_last_claimed_at is not null
      then v_last_claimed_at + (v_cooldown_minutes * interval '1 minute')
    else null
  end;

  if v_claimed_today >= v_daily_cap then
    v_available := false;
    v_reason := 'CAP_REACHED';
  elsif v_cooldown_until is not null and now() < v_cooldown_until then
    v_available := false;
    v_reason := 'COOLDOWN';
  else
    v_available := true;
    v_reason := null;
  end if;

  return jsonb_build_object(
    'available', v_available,
    'unavailable_reason', v_reason,
    'daily_cap', v_daily_cap,
    'claimed_today', v_claimed_today,
    'remaining_today', greatest(v_daily_cap - v_claimed_today, 0),
    'reward_points', v_reward_points,
    'cooldown_until', v_cooldown_until
  );
end;
$$;

revoke all on function public.get_ad_reward_status() from public, anon, authenticated;
grant execute on function public.get_ad_reward_status() to authenticated;
