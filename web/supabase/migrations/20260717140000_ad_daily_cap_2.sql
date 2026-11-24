-- 목적: 리워드 광고 일일 적립 캡을 2로 확정 — 배포 때 디버깅용 큰 값으로 둔 이력 정리
-- 날짜: 2026-07-17 · 담당: 배경록
-- 배경: 20260624170000이 default 2로 생성했지만, LIVE 반영 시 디버깅용으로 큰 값을 넣어둔
--       이력이 문서 경고로 남아 있다(docs/db-schema.md §② "실서비스 전 daily_cap=2 확인").
--       수동 SQL 대신 마이그레이션으로 확정한다. 이미 2면 no-op(멱등).
update ad_reward_config
   set daily_cap = 2, updated_at = now()
 where id = 1 and daily_cap <> 2;
