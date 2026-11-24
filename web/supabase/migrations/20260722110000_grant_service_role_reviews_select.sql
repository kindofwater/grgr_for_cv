-- 목적: 백필 before/after 검증에서 service_role이 reviews 개수를 읽을 수 있게 SELECT grant
-- 날짜: 2026-07-22 · 담당: 배경록
-- 비고: 읽기전용(SELECT만). 로더/백필은 reviews를 절대 쓰지 않음 — KUPID 백필 전후 리뷰 개수
--       불변 검증 용도. service_role은 RLS 우회하나 테이블 grant가 없어 지금은 reviews를 못 읽음(42501).

begin;
grant select on public.reviews to service_role;
commit;
