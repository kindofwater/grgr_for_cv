-- 목적: 이메일 가입 여부 사전검사 RPC. 로그인 화면 이메일 단계에서 "있으면 로그인 / 없으면 가입" 분기용.
-- 날짜: 2026-06-27 · 담당: <이름>
-- ⚠️ enumeration 트레이드오프: 이 RPC는 "이 이메일이 가입돼 있나"를 anon 에 노출한다(의도된 결정).
--    boolean 만 반환하며 이메일·신원·확인여부는 노출하지 않는다.
--    완화책(rate limit / 캡차)은 후속 작업으로 남김.
-- security definer 라 auth.users 를 읽는다(함수 소유자=postgres 가 auth.users SELECT 권한 보유).
-- search_path='' + 완전수식(auth.users) 으로 search_path 하이재킹 방지.

create or replace function public.email_registered(p_email text)
returns boolean
language sql
security definer
set search_path = ''
as $$
  select exists (
    select 1 from auth.users
    where lower(email) = lower(trim(p_email))
  );
$$;

-- 기본 PUBLIC grant 회수 후 anon/authenticated 에만 부여 (anon 이 로그인 전 호출)
revoke execute on function public.email_registered(text) from public;
grant execute on function public.email_registered(text) to anon, authenticated;