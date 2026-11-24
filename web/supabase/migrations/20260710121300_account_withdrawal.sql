-- 목적: 회원탈퇴 — 재가입 쿨다운(30일) 테이블 + delete_account RPC(방식 B: auth.users 직접 삭제) + handle_new_user 쿨다운 검사
-- 날짜: 2026-07-10 · 담당: 배경록

-- ── 1. 탈퇴 이메일 해시 테이블 (재가입 쿨다운 판정 전용 · 개인정보 최소화: 평문 대신 sha256) ──
create table if not exists public.withdrawn_emails (
  email_hash   text primary key,
  withdrawn_at timestamptz not null default now()
);
-- 직접 접근 차단: RLS on + 정책 0개 → authenticated/anon 은 못 읽/씀.
-- security definer 함수(소유자 postgres)는 RLS 우회하므로 정상 동작.
alter table public.withdrawn_emails enable row level security;

-- ── 2. delete_account: 본인(auth.uid()) 계정 삭제 ──
-- 순서: 만료해시 청소 → 이메일 해시 저장 → auth.users 삭제(cascade: public.users → points CASCADE 소멸·열람권 컬럼 소멸·reviews SET NULL 익명)
create or replace function public.delete_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := auth.uid();
  v_email text;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;

  select email into v_email from auth.users where id = v_uid;
  if v_email is null then raise exception 'USER_NOT_FOUND'; end if;

  -- 30일 지난 해시 파기(기회적 청소)
  delete from public.withdrawn_emails where withdrawn_at <= now() - interval '30 days';

  -- 재가입 차단용 해시 저장(평문 아님)
  insert into public.withdrawn_emails (email_hash, withdrawn_at)
  values (encode(extensions.digest(lower(trim(v_email)), 'sha256'), 'hex'), now())
  on conflict (email_hash) do update set withdrawn_at = excluded.withdrawn_at;

  -- 계정 삭제 → FK cascade 로 나머지 정리
  delete from auth.users where id = v_uid;
end $$;

revoke execute on function public.delete_account() from anon, public;
grant execute on function public.delete_account() to authenticated;

-- ── 3. handle_new_user: 기존 도메인 검사 + 재가입 쿨다운(30일) 차단 추가 ──
-- (auth.users after-insert 트리거는 이미 존재 — create or replace 로 함수 본문만 교체, 트리거는 그대로 유지)
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if lower(split_part(new.email, '@', 2)) not like '%.ac.kr' then
    raise exception 'DOMAIN_NOT_ALLOWED';
  end if;
  -- 재가입 쿨다운: 30일 내 탈퇴 이메일이면 raise → auth.users insert 롤백(가입 차단)
  if exists (
    select 1 from public.withdrawn_emails w
    where w.email_hash = encode(extensions.digest(lower(trim(new.email)), 'sha256'), 'hex')
      and w.withdrawn_at > now() - interval '30 days'
  ) then
    raise exception 'WITHDRAWN_COOLDOWN';
  end if;
  return new;
end $$;
revoke execute on function public.handle_new_user() from anon, public;
