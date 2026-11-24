-- 목적: 가입 트리거(handle_new_user)에 '+' 태그 주소 차단 추가 — 같은 메일함으로 별칭 무한 생성(가입/포인트 어뷰징) 서버 권위 차단.
-- 날짜: 2026-07-13 · 담당: <이름>
-- 프론트(emailError)도 '+'를 막지만 그건 UI 검사일 뿐 — API 직접 호출 우회를 여기서 끊는다.
-- ⚠️ 본문은 20260710130920(도메인 검사 + 재가입 쿨다운·내장 sha256) 기반 + '+' 검사만 추가.
--    이전 버전(otp_signup) 기반으로 replace 하면 쿨다운 검사가 지워지므로 주의.
-- 시그니처 변경 없음(returns trigger 동일) → create or replace 로 안전. 기존 계정(INSERT 전) 영향 없음.

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if lower(split_part(new.email, '@', 2)) not like '%.ac.kr' then
    raise exception 'DOMAIN_NOT_ALLOWED';
  end if;
  -- '+' 별칭(user+tag@...) 차단
  if position('+' in new.email) > 0 then
    raise exception 'EMAIL_ALIAS_NOT_ALLOWED';
  end if;
  -- 재가입 쿨다운: 30일 내 탈퇴 이메일이면 가입 차단 (20260710121300 도입 · 130920에서 내장 sha256로 교체)
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
