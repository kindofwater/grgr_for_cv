-- 목적: ping() RPC 추가 — 마이그레이션 워크플로우 연습 ('pong' 반환, 무해. 다음 drop으로 제거)
-- 날짜: 2026-06-10 · 담당: 배경록
create or replace function ping()
returns text
language sql
as $$
  select 'pong'::text
$$;

grant execute on function ping() to anon, authenticated;
