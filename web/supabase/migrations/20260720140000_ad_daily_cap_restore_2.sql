-- 목적: 광고 daily_cap 임시 1000 → 2로 복구 (20260720130000의 짝)
-- 날짜: 2026-07-20 · 담당: 배경록
-- 배경: 리워드 광고 재실행 버그 수동 검증을 위해 캡을 임시로 올렸다(20260720130000).
--   검증이 끝나면 이 파일을 db push해 실서비스 값 2로 되돌린다.
--   두 파일이 짝이라 맨바닥 재구축(db reset) 시에도 최종값은 2로 수렴한다.
update ad_reward_config
   set daily_cap = 2, updated_at = now()
 where id = 1 and daily_cap <> 2;
