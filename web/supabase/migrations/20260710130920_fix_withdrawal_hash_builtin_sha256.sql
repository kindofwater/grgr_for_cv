-- 목적: 회원탈퇴 해시 버그픽스 — extensions.digest(존재X, pgcrypto 스키마 불일치) → Postgres 내장 sha256() 사용
-- 날짜: 2026-07-10 · 담당: 배경록
-- 배경: 20260710121300_account_withdrawal.sql이 encode(extensions.digest(...,'sha256'),'hex')를 썼는데
--       이 인스턴스엔 extensions.digest가 없어(42883) delete_account·handle_new_user 둘 다 런타임 에러.
--       특히 handle_new_user는 가입 트리거라 "전 가입 실패" 유발 → 긴급. 확장 의존 없는 내장 sha256로 교체.
--       encode(sha256(convert_to(text,'UTF8')),'hex') = 전부 pg_catalog 내장, search_path='' 에서도 동작.

-- ── delete_account: 해시 계산만 교체(나머지 동일) ──
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

  delete from public.withdrawn_emails where withdrawn_at <= now() - interval '30 days';

  insert into public.withdrawn_emails (email_hash, withdrawn_at)
  values (encode(sha256(convert_to(lower(trim(v_email)), 'UTF8')), 'hex'), now())
  on conflict (email_hash) do update set withdrawn_at = excluded.withdrawn_at;

  delete from auth.users where id = v_uid;
end $$;

revoke execute on function public.delete_account() from anon, public;
grant execute on function public.delete_account() to authenticated;

-- ── handle_new_user: 쿨다운 검사 해시만 교체(도메인 검사 동일) ──
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if lower(split_part(new.email, '@', 2)) not like '%.ac.kr' then
    raise exception 'DOMAIN_NOT_ALLOWED';
  end if;
  if exists (
    select 1 from public.withdrawn_emails w
    where w.email_hash = encode(sha256(convert_to(lower(trim(new.email)), 'UTF8')), 'hex')
      and w.withdrawn_at > now() - interval '30 days'
  ) then
    raise exception 'WITHDRAWN_COOLDOWN';
  end if;
  return new;
end $$;
revoke execute on function public.handle_new_user() from anon, public;
