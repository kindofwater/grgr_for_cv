-- 목적: 보관형 닉네임 변경권을 폐지하고 변경 성공 시점에만 20P를 차감하는 즉시 변경 방식으로 전환한다.
-- 날짜: 2026-08-01 · 담당: Codex
-- 전환 전 prod 확인: 보유 재고 0장(보유자 0명). 과거 구매/사용 원장은 감사 이력으로 보존한다.

-- 확인 이후 예기치 않게 재고가 생겼다면 컬럼을 버리지 않고 배포 자체를 중단한다.
do $$
begin
  if exists (
    select 1
    from public.users
    where nickname_change_ticket_stock > 0
  ) then
    raise exception 'NICKNAME_TICKET_STOCK_EXISTS';
  end if;
end
$$;

-- 구 구매·환불 경로를 먼저 닫는다. prod 프론트는 이 RPC들을 아직 사용하지 않아 배포 간극 영향이 없다.
drop function if exists public.purchase_nickname_change_ticket();
drop function if exists public.refund_nickname_change_ticket();

-- 지갑은 원래의 열람권/포인트 shape로 되돌린다. JSON 키 제거는 구 프론트와 호환된다.
create or replace function public._wallet()
returns jsonb
language sql
security definer
set search_path = pg_catalog, pg_temp
as $$
  select jsonb_build_object(
    'point_balance',   u.point_balance,
    'pass_balances',   coalesce(u.pass_balances, '{}'::jsonb),
    'pass_expires_at', u.pass_expires_at
  )
  from public.users u
  where u.id = auth.uid()
$$;

-- 최종 변경 한 번으로 닉네임 검증·20P 차감·닉네임 변경·원장·감사 이력을 모두 처리한다.
-- 어느 단계든 실패하면 전체 트랜잭션이 롤백되므로 포인트만 차감되는 상태는 생기지 않는다.
create or replace function public.change_nickname(p_nickname text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_new_nickname text := trim(coalesce(p_nickname, ''));
  v_old_nickname text;
  v_balance integer;
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  perform public.validate_nickname(v_new_nickname);

  select u.nickname::text, coalesce(u.point_balance, 0)
    into v_old_nickname, v_balance
  from public.users u
  where u.id = v_uid
    and u.deleted_at is null
  for update;

  if not found then
    raise exception 'NO_PROFILE';
  end if;
  if v_old_nickname = v_new_nickname then
    raise exception 'NICKNAME_UNCHANGED';
  end if;
  if v_balance < 20 then
    raise exception 'INSUFFICIENT_POINTS';
  end if;

  begin
    update public.users
    set nickname = v_new_nickname,
        point_balance = point_balance - 20,
        updated_at = now()
    where id = v_uid;
  exception
    when unique_violation then
      raise exception 'NICKNAME_TAKEN';
  end;

  insert into public.points (user_id, amount, reason)
  values (v_uid, -20, 'nickname_change');

  insert into public.nickname_change_history (user_id, old_nickname, new_nickname)
  values (v_uid, v_old_nickname, v_new_nickname);

  return public._wallet() || jsonb_build_object('nickname', v_new_nickname);
end;
$$;

revoke all on function public.change_nickname(text) from public, anon, authenticated;
grant execute on function public.change_nickname(text) to authenticated;

revoke execute on function public._wallet() from public, anon;
grant execute on function public._wallet() to authenticated;

-- 더 이상 읽거나 쓰는 함수가 없으므로 보관형 재고 컬럼과 제약을 함께 제거한다.
alter table public.users
  drop column nickname_change_ticket_stock;
