-- 목적: withdrawn_emails 만료 해시 자동 파기 — pg_cron 일일 청소로 "탈퇴 후 30일 보관·파기" 방침 준수
-- 날짜: 2026-07-16 · 담당: 배경록
--
-- 왜: 기존 청소는 delete_account() 안의 기회적(opportunistic) 삭제뿐이라, 탈퇴가 뜸하면 만료 해시가
--     30일을 넘겨 남는다. 개인정보처리방침 제4조는 재가입 제한 목적 보유기간을 "회원 탈퇴 후 30일",
--     "이메일 해시값만 30일간 보관"으로 명시하므로, 실제 파기를 스케줄로 보장한다.
--
-- ⚠️ handle_new_user()의 재가입 검사 필터(`withdrawn_at > now() - interval '30 days'`)는 그대로 둔다.
--    역할이 다르다: 필터 = 정책 집행(정확성) / cron = 보유기간 파기(컴플라이언스).
--    - cron이 실패·지연·미적용돼도 가입 판정은 정확해야 한다(필터 없으면 조용히 부당 차단).
--    - cron은 하루 1회라 필터를 빼면 실질 쿨다운이 "30일 + 최대 24시간"이 되어 방침과 어긋난다.
--    delete_account() 안의 기회적 삭제도 그대로 둔다(이중 안전망, 해가 없음).

-- pg_cron: Supabase 지원 스케줄러. cron 스키마를 만든다(이 프로젝트 첫 사용).
create extension if not exists pg_cron;

-- 매일 04:00 UTC(=13:00 KST) 30일 지난 해시 파기.
-- cron.schedule은 같은 job 이름이면 갱신(upsert) → 재실행·맨바닥 재구축에 안전(멱등).
select cron.schedule(
  'purge-withdrawn-emails',
  '0 4 * * *',
  $$delete from public.withdrawn_emails where withdrawn_at <= now() - interval '30 days'$$
);

-- 확인용(선택):
--   select jobid, jobname, schedule, command, active from cron.job;
--   select jobid, status, start_time, end_time, return_message
--     from cron.job_run_details order by start_time desc limit 5;
-- 해제하려면: select cron.unschedule('purge-withdrawn-emails');
