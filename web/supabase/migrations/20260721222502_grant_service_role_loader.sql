-- 목적: 백엔드 적재 로더(service_role)가 worksites·postings를 읽고 쓸 수 있도록 최소 권한 부여
-- 날짜: 2026-07-21 · 담당: 배경록
-- 비고: Auth+RLS 컷오버 때 기본 grant가 잠겨 service_role이 permission denied(42501).
--       upsert_worksites.py 적재용 — service_role은 RLS 우회 백엔드 역할이라 테이블 권한만 재부여.

grant select, insert, update, delete on public.worksites to service_role;
grant select, insert, update, delete on public.postings  to service_role;
grant usage, select on all sequences in schema public to service_role;
