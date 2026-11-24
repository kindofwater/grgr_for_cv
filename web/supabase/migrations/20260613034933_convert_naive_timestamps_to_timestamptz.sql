-- 목적: public 의 timezone 없는 timestamp 컬럼을 전부 timestamptz 로 전환(저장은 절대시각, 표시는 앱에서 KST).
--       기존 naive 값은 UTC 벽시계로 저장돼 있던 것이 확정됨(서버 now()=UTC) → 'AT TIME ZONE UTC' 로 정확히 절대시각화.
--       프론트는 lib/dates.parseServerDate 가 naive(레거시)·offset(전환후) 양쪽을 모두 UTC로 안전 처리.
-- 날짜: 2026-06-13 · 담당: 배경록
--
-- 비고:
--  - idempotent: data_type 이 'timestamp without time zone' 인 컬럼만 변환 → 재실행/맨바닥 db reset 모두 안전.
--  - activate_pass(교환 도메인): now()::timestamp 캐스트 제거(타입 일관). 시그니처 동일 → create or replace.
--  - verify_login / register_user(auth, 담당: kindofwater) 는 의도적으로 건드리지 않음.
--      RETURNS TABLE 의 pass_expires_at 이 timestamp 라 timestamptz→timestamp 로 캐스트되어 naive(UTC)로 반환되지만,
--      프론트 parseServerDate 가 naive=UTC 로 처리하므로 정상. 추후 두 함수 리턴 타입도 timestamptz 로 맞추는 건 담당자와 조율.

-- [1] public 의 모든 naive timestamp 컬럼 → timestamptz (UTC 해석)
do $$
declare r record;
begin
  for r in
    select table_name, column_name
    from information_schema.columns
    where table_schema = 'public'
      and data_type = 'timestamp without time zone'
    order by table_name, ordinal_position
  loop
    execute format(
      'alter table public.%I alter column %I type timestamptz using %I at time zone ''UTC''',
      r.table_name, r.column_name, r.column_name
    );
    raise notice 'converted %.% -> timestamptz', r.table_name, r.column_name;
  end loop;
end $$;

-- [2] activate_pass: 만료시각 계산을 timestamptz 로 일관되게 (now()::timestamp 캐스트 제거)
--     규칙: 새 만료 = max(now, 현재만료) + days. 시그니처(int,int)→jsonb 동일하므로 grant 유지.
create or replace function activate_pass(p_user_id int, p_days int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_rows int;
begin
  if pass_price(p_days) is null then raise exception 'INVALID_DAYS'; end if;
  update users u
     set pass_balances = jsonb_set(
           coalesce(u.pass_balances, '{}'::jsonb), array[p_days::text],
           to_jsonb(coalesce((u.pass_balances ->> p_days::text)::int, 0) - 1), true),
         pass_expires_at = greatest(now(), coalesce(u.pass_expires_at, now()))
                           + (p_days || ' days')::interval
   where u.id = p_user_id and coalesce((u.pass_balances ->> p_days::text)::int, 0) >= 1;
  get diagnostics v_rows = row_count;
  if v_rows = 0 then raise exception 'NO_PASS_STOCK'; end if;
  return _wallet(p_user_id);
end $$;
