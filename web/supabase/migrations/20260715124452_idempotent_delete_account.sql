-- 목적: delete_account 멱등화 — 이미 삭제된 계정 재호출 시 USER_NOT_FOUND 대신 조용히 성공(void)
-- 날짜: 2026-07-15 · 담당: 배경록
--
-- 왜: 클라 타임아웃(WithdrawModal, 15초) 후 서버에서 삭제가 늦게 성공하면, JWT는 아직 유효해
--     auth.uid()는 UUID를 돌려주지만 auth.users 행은 이미 없다. 이때 사용자가 '다시 시도'하면
--     기존 함수는 USER_NOT_FOUND로 터져 "탈퇴했는데 또 에러"가 됐다. 이미 원하는 종료 상태(삭제됨)에
--     도달했으므로 재호출은 조용히 성공(no-op)해야 한다. 시그니처 불변 → create or replace만(DROP 불필요).
--
-- ⚠️ 해시는 내장 sha256 사용(20260710130920 픽스와 동일) — extensions.digest는 이 인스턴스에 없음(42883).
--    이 파일은 그 픽스보다 나중 타임스탬프라 delete_account의 최종 정의가 된다. (handle_new_user는 안 건드림 →
--    그 픽스도 함께 push되어야 함: db push는 미적용 마이그레이션을 모두 순서대로 적용한다.)

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
  -- 이미 삭제된 계정(유효 JWT + 없는 user 행): 재시도로 보고 멱등하게 성공 처리.
  -- 해시는 최초 삭제 때 이미 저장됐으므로 여기서 재저장 불필요.
  if v_email is null then return; end if;

  -- 30일 지난 해시 파기(기회적 청소)
  delete from public.withdrawn_emails where withdrawn_at <= now() - interval '30 days';

  -- 재가입 차단용 해시 저장(평문 아님, 내장 sha256)
  insert into public.withdrawn_emails (email_hash, withdrawn_at)
  values (encode(sha256(convert_to(lower(trim(v_email)), 'UTF8')), 'hex'), now())
  on conflict (email_hash) do update set withdrawn_at = excluded.withdrawn_at;

  -- 계정 삭제 → FK cascade 로 나머지 정리
  delete from auth.users where id = v_uid;
end $$;

revoke execute on function public.delete_account() from anon, public;
grant execute on function public.delete_account() to authenticated;
