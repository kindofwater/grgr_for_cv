-- 목적: 가입 인증 메일(OTP)에 5분간 무응답인 미인증 계정 자동 삭제 — purge_unverified_signups() RPC + pg_cron 매분 실행
-- 날짜: 2026-07-18 · 담당: 배경록
--
-- 왜: signUp 직후 이탈한 유저는 미인증 auth.users 행으로 남는다. 이 행 때문에 email_registered()가
--     true를 돌려줘 로그인 화면이 "가입된 이메일"로 분기하고(#17이 OTP 재개로 완화), 완주 의사가
--     없던 이메일이 계속 점유된다. 인증 창을 "메일 발송 후 5분"으로 정의하고, 지나면 행을 지워
--     처음부터 다시 가입할 수 있는 깨끗한 상태로 되돌린다. 첫 실행 때 기존 미인증 잔재도 일괄 삭제된다.
--
-- 무엇을 지우나 (아래 전부 만족하는 auth.users 행):
--   · email_confirmed_at is null — OTP 미검증(가입 미완). 인증만 하고 프로필을 안 만든 유저는
--     confirmed라 대상 아님(needsProfile 라우팅이 이어서 처리).
--   · 마지막 인증 메일 발송(confirmation_sent_at) 후 5분 경과 — resend 시 GoTrue가 이 값을 갱신하므로
--     "재전송" 클릭이 창을 자동 리셋한다. null이면 created_at 폴백(발송 실패 행이 불멸하지 않게).
--   · recovery 메일 발송 후에도 5분 경과 — #35 결정("비번까지 잊은 미인증자는 recovery가 인증 겸 구제")
--     경로 보호: recovery 검증도 email_confirmed_at을 세팅하므로, 그 메일 직후의 행을 지우면 구제가
--     막힌다. 메일 rate limit(시간당 2통)이라 이 조건으로 가비지 행을 무한 연명시킬 수는 없다.
--   · last_sign_in_at is null — 로그인 이력 있는 행은 절대 안 지움. 현 플로우에선 미인증=미로그인이라
--     항상 참(no-op)이지만, 미래에 이메일 미검증 상태로 세션이 생기는 경로(예: OAuth)가 들어와도
--     실계정을 쓸어내지 않게 하는 방어선.
--
-- 지운 뒤: public.users는 FK cascade(미인증자는 세션이 없어 create_profile 불가 → 애초에 행 없음),
--   identities·one_time_tokens 등 auth 부속 테이블도 GoTrue FK cascade — delete_account()와 같은 경로.
--   withdrawn_emails 해시는 저장하지 않는다(의도) — 가입을 완료한 적 없는 이탈은 30일 쿨다운 대상이
--   아니고, 행이 사라져야 email_registered()가 false로 돌아와 재가입이 열린다.
--
-- ⚠️ 5분이 사실상의 인증 코드 유효시간이 된다. Auth의 OTP 만료 설정(로컬 config 3600초)보다 짧으므로,
--    5분 넘겨 코드를 입력한 유저는 "만료" 대신 계정 없음 계열 에러를 받는다(재가입으로 해소).
--    인증 경계의 동시성은 안전: verify가 먼저 커밋되면 confirmed가 되어 삭제 조건에서 빠지고,
--    삭제가 먼저면 verify가 에러로 떨어질 뿐 어긋난 상태가 남지 않는다.

create or replace function public.purge_unverified_signups()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deleted integer;
begin
  delete from auth.users u
  where u.email_confirmed_at is null
    and u.last_sign_in_at is null
    and coalesce(u.confirmation_sent_at, u.created_at) <= now() - interval '5 minutes'
    and coalesce(u.recovery_sent_at, timestamptz '-infinity') <= now() - interval '5 minutes';
  get diagnostics v_deleted = row_count;
  return v_deleted;
end $$;

-- 클라이언트 호출 없음 — cron(postgres)·운영 수동 실행(service_role)만.
revoke execute on function public.purge_unverified_signups() from public, anon, authenticated;
grant execute on function public.purge_unverified_signups() to service_role;

-- 매분 실행 — "5분 무응답" 정책의 집행 지연을 최대 1분으로 묶는다.
-- pg_cron 확장·cron 스키마는 20260716170000(purge-withdrawn-emails)이 이미 활성화함.
-- cron.schedule은 job 이름 기준 upsert라 멱등(재push·reset 안전). 해제: select cron.unschedule('purge-unverified-signups');
select cron.schedule(
  'purge-unverified-signups',
  '* * * * *',
  $$select public.purge_unverified_signups()$$
);

-- 매분 잡은 실행 이력(cron.job_run_details)을 하루 1,440행씩 쌓는다 — 7일 지난 이력을 매일 정리.
-- (pg_cron 권장 하우스키핑. 기존 일일 잡 이력에도 적용되지만 디버깅엔 7일이면 충분.)
select cron.schedule(
  'purge-cron-history',
  '30 4 * * *',
  $$delete from cron.job_run_details where end_time < now() - interval '7 days'$$
);
