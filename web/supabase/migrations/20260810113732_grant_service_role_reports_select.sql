-- 목적: 신고(reports) 운영 조회를 위해 service_role에 읽기 전용 SELECT 권한 부여 — 20260722110000(reviews SELECT) 선례와 동일 패턴
-- 날짜: 2026-08-10 · 담당: 배경록
--
-- 왜: 신고 처리(블라인드 여부 판단)는 운영 작업인데 reports는 어떤 백엔드 경로로도 읽을 수 없어
--     매번 Studio를 열어야 했다. service_role은 클라이언트에 노출되지 않는 백엔드 키이고,
--     쓰기 권한은 주지 않는다 — 신고 접수는 지금처럼 report_review RPC만 거친다.
-- 멱등: GRANT는 반복 실행해도 안전하다.

grant select on public.reports to service_role;
