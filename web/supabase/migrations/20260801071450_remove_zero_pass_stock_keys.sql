-- 목적: 열람권 마지막 장 사용 시 pass_balances의 0개 키를 삭제하고 기존 0개 키도 정리한다.
-- 날짜: 2026-08-01 · 담당: Codex
-- 대상은 현재 상품 키 0(1시간)·7·30을 포함한 모든 숫자형 0 이하 재고다.
-- pass_expires_at은 열람 만료 판정과 이력 확인에 쓰므로 만료 후에도 기존처럼 보존한다.

-- 이미 소진됐지만 {"0":0}, {"7":0}, {"30":0}처럼 남은 재고 키를 제거한다.
-- 숫자가 아닌 예외 데이터는 이 마이그레이션에서 임의로 버리지 않고 그대로 보존한다.
update public.users u
set pass_balances = (
  select coalesce(jsonb_object_agg(e.key, e.value), '{}'::jsonb)
  from jsonb_each(coalesce(u.pass_balances, '{}'::jsonb)) e
  where jsonb_typeof(e.value) <> 'number'
     or (e.value::text)::numeric > 0
)
where exists (
  select 1
  from jsonb_each(coalesce(u.pass_balances, '{}'::jsonb)) e
  where jsonb_typeof(e.value) = 'number'
    and (e.value::text)::numeric <= 0
);

-- 마지막 1장을 쓸 때는 값을 0으로 저장하지 않고 해당 상품 키 자체를 삭제한다.
-- 재고가 2장 이상이면 기존처럼 1만 차감한다. 세 상품 모두 같은 경로를 사용한다.
create or replace function public.activate_pass(p_days int)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_rows int;
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  if public.pass_price(p_days) is null then
    raise exception 'INVALID_DAYS';
  end if;

  update public.users u
  set pass_balances = case
        when coalesce((u.pass_balances ->> p_days::text)::int, 0) = 1
          then coalesce(u.pass_balances, '{}'::jsonb) - p_days::text
        else jsonb_set(
          coalesce(u.pass_balances, '{}'::jsonb),
          array[p_days::text],
          to_jsonb(coalesce((u.pass_balances ->> p_days::text)::int, 0) - 1),
          true
        )
      end,
      pass_expires_at = greatest(now(), coalesce(u.pass_expires_at, now()))
        + case
            when p_days = 0 then interval '1 hour'
            else (p_days || ' days')::interval
          end
  where u.id = v_uid
    and coalesce((u.pass_balances ->> p_days::text)::int, 0) >= 1;

  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    raise exception 'NO_PASS_STOCK';
  end if;

  return public._wallet();
end;
$$;

revoke all on function public.activate_pass(int) from public, anon, authenticated;
grant execute on function public.activate_pass(int) to authenticated;
