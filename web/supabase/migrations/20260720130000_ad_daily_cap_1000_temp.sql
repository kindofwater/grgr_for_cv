-- 목적: 리워드 광고 캡 재실행 버그 수동 검증용 — daily_cap 2 → 1000 (임시)
-- 날짜: 2026-07-20 · 담당: 배경록
-- ⚠️ 임시 값이다. 검증이 끝나면 바로 뒤 마이그레이션(20260720140000_ad_daily_cap_restore_2)이
--    2로 되돌린다. 이 파일만 단독으로 남기지 말 것 — prod에 디버그 캡을 남긴 전례가 있다
--    (docs/db-schema.md §② 경고, 20260717140000이 그 정리본).
--    맨바닥 재구축(db reset) 시엔 두 파일이 순서대로 적용돼 최종값 2로 수렴한다.
update ad_reward_config
   set daily_cap = 1000, updated_at = now()
 where id = 1;
