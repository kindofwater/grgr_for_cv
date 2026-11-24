-- 목적: 닉네임 변경권(20P) 재고·전액 환불·닉네임 변경을 원자적으로 제공한다.
-- 날짜: 2026-08-01 · 담당: Codex
-- 배포 순서: 기존 프론트가 읽는 컬럼/RPC 시그니처는 바꾸지 않는 additive migration이다.
--   _wallet()에는 JSON 키 하나만 추가하므로 DB를 프론트보다 먼저 배포해도 구버전은 이를 무시한다.
-- 정책:
--   · 변경권은 계정당 최대 1장, 미사용권은 구매가(20P) 전액 환불한다.
--   · 닉네임은 기존 validate_nickname() 규칙을 그대로 사용한다.
--   · 성공한 변경에서만 재고를 소모하고 이전/새 닉네임과 변경 시각을 내부 이력으로 남긴다.
--   · 리뷰에는 닉네임 스냅샷을 만들지 않는다. 목록 RPC가 users.nickname을 join하므로 과거 공개 리뷰도
--     변경된 닉네임으로 자연스럽게 표시된다(익명 리뷰의 '익명' 마스킹은 기존 동작 유지).

-- ── 1. 변경권 재고: CHECK + 행 잠금으로 0/1만 허용 ────────────────────────────
alter table public.users
  add column nickname_change_ticket_stock smallint not null default 0
  constraint users_nickname_change_ticket_stock_check
  check (nickname_change_ticket_stock between 0 and 1);

-- 기존 users_update_own RLS가 있어도 이 특권 컬럼은 클라이언트가 직접 갱신할 수 없다.
revoke update (nickname_change_ticket_stock) on public.users from public, anon, authenticated;

-- ── 2. 운영 전용 변경 이력: 클라이언트 정책을 만들지 않아 API에서는 읽을 수 없음 ─────
create table public.nickname_change_history (
  id           bigint generated always as identity primary key,
  user_id      uuid not null references public.users(id) on delete cascade,
  old_nickname varchar(50) not null,
  new_nickname varchar(50) not null,
  changed_at   timestamptz not null default now(),
  constraint nickname_change_history_changed_check check (old_nickname <> new_nickname)
);

create index nickname_change_history_user_changed_idx
  on public.nickname_change_history (user_id, changed_at desc);

alter table public.nickname_change_history enable row level security;
revoke all on table public.nickname_change_history from public, anon, authenticated;
revoke all on sequence public.nickname_change_history_id_seq from public, anon, authenticated;
-- service_role만 운영 조회를 허용한다. 쓰기는 아래 SECURITY DEFINER RPC에서만 수행한다.
grant select on table public.nickname_change_history to service_role;

-- ── 3. 지갑 응답 확장: 기존 세 키는 그대로, 재고 키만 추가 ────────────────────
create or replace function public._wallet()
returns jsonb
language sql
security definer
set search_path = pg_catalog, pg_temp
as $$
  select jsonb_build_object(
    'point_balance',                  u.point_balance,
    'pass_balances',                  coalesce(u.pass_balances, '{}'::jsonb),
    'pass_expires_at',                u.pass_expires_at,
    'nickname_change_ticket_stock',   u.nickname_change_ticket_stock
  )
  from public.users u
  where u.id = auth.uid()
$$;

-- ── 4. 변경권 구매(20P): 사용자 행을 잠가 잔액 차감·재고·원장을 직렬화 ─────────
create or replace function public.purchase_nickname_change_ticket()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_balance integer;
  v_stock smallint;
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select coalesce(u.point_balance, 0), u.nickname_change_ticket_stock
    into v_balance, v_stock
  from public.users u
  where u.id = v_uid
    and u.deleted_at is null
  for update;

  if not found then
    raise exception 'NO_PROFILE';
  end if;
  if v_stock >= 1 then
    raise exception 'NICKNAME_TICKET_ALREADY_OWNED';
  end if;
  if v_balance < 20 then
    raise exception 'INSUFFICIENT_POINTS';
  end if;

  update public.users
  set point_balance = coalesce(point_balance, 0) - 20,
      nickname_change_ticket_stock = 1,
      updated_at = now()
  where id = v_uid;

  insert into public.points (user_id, amount, reason)
  values (v_uid, -20, 'nickname_change_ticket_purchase');

  return public._wallet();
end;
$$;

-- ── 5. 미사용권 전액 환불: 재고 1장을 20P로 되돌리고 원장 기록 ────────────────
create or replace function public.refund_nickname_change_ticket()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_stock smallint;
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select u.nickname_change_ticket_stock
    into v_stock
  from public.users u
  where u.id = v_uid
    and u.deleted_at is null
  for update;

  if not found then
    raise exception 'NO_PROFILE';
  end if;
  if v_stock < 1 then
    raise exception 'NO_NICKNAME_TICKET';
  end if;

  update public.users
  set point_balance = coalesce(point_balance, 0) + 20,
      nickname_change_ticket_stock = 0,
      updated_at = now()
  where id = v_uid;

  insert into public.points (user_id, amount, reason)
  values (v_uid, 20, 'nickname_change_ticket_refund');

  return public._wallet();
end;
$$;

-- ── 6. 변경권 사용: 검증·변경·재고 소모·이력 기록을 한 트랜잭션으로 수행 ────────
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
  v_stock smallint;
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  -- 기존 가입 정책과 같은 서버 권위 검증. 실패 시 아직 어떤 행도 변경하지 않는다.
  perform public.validate_nickname(v_new_nickname);

  -- 구매/환불/다른 변경 요청과 같은 사용자 행에서 직렬화한다.
  select u.nickname::text, u.nickname_change_ticket_stock
    into v_old_nickname, v_stock
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
  if v_stock < 1 then
    raise exception 'NO_NICKNAME_TICKET';
  end if;

  -- users.nickname UNIQUE가 동시 변경까지 최종 판정한다. 위반 시 이 함수 호출 전체가
  -- 롤백되므로 변경권은 소모되지 않고 이력도 남지 않는다.
  begin
    update public.users
    set nickname = v_new_nickname,
        nickname_change_ticket_stock = 0,
        updated_at = now()
    where id = v_uid;
  exception
    when unique_violation then
      raise exception 'NICKNAME_TAKEN';
  end;

  insert into public.nickname_change_history (user_id, old_nickname, new_nickname)
  values (v_uid, v_old_nickname, v_new_nickname);

  return public._wallet() || jsonb_build_object('nickname', v_new_nickname);
end;
$$;

-- ── 7. RPC 권한: 생성 시 PUBLIC 기본 실행권을 회수하고 authenticated만 허용 ─────
revoke all on function public.purchase_nickname_change_ticket() from public, anon, authenticated;
revoke all on function public.refund_nickname_change_ticket() from public, anon, authenticated;
revoke all on function public.change_nickname(text) from public, anon, authenticated;

grant execute on function public.purchase_nickname_change_ticket() to authenticated;
grant execute on function public.refund_nickname_change_ticket() to authenticated;
grant execute on function public.change_nickname(text) to authenticated;

-- _wallet()은 기존부터 authenticated 전용이다. 교체 후 권한을 명시적으로 다시 수렴한다.
revoke execute on function public._wallet() from public, anon;
grant execute on function public._wallet() to authenticated;

-- 수동 검증 예시(트랜잭션/테스트 계정에서만 실행):
--   select public._wallet();
--   select public.purchase_nickname_change_ticket(); -- -20P, stock=1
--   select public.refund_nickname_change_ticket();   -- +20P, stock=0
--   select public.purchase_nickname_change_ticket();
--   select public.change_nickname('새닉네임');        -- stock=0, nickname 포함
--   select user_id, old_nickname, new_nickname, changed_at
--     from public.nickname_change_history order by id desc limit 1; -- service_role/SQL editor only
