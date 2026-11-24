-- 목적: 컷오버 후 로그인 사용자(authenticated 역할)의 public 테이블 SELECT 권한 보강 — grant 누락으로 "permission denied for table" 발생(앱이 이전엔 anon만 써서 authenticated 권한이 한 번도 안 깔림). RLS가 행 단위 보호하므로 SELECT grant는 안전.
-- 날짜: 2026-06-24 · 담당: 배경록
grant usage on schema public to anon, authenticated;
grant select on all tables in schema public to anon, authenticated;
