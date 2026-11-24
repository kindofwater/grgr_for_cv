-- 목적: 모집 상태를 날짜로 판정하기 위한 postings.recruit_until / recruit_until_estimated 추가 (정적 is_active의 낡음 해소)
-- 날짜: 2026-07-17 · 담당: 배경록
-- 비고: spec docs/superpowers/specs/2026-07-17-kupid-school-postings-design.md §2
--       학교근장=파이프라인 캐스케이드 추정 / 국가근장=학기·방학 기간 확정 시 일괄 UPDATE(추측 금지).
--       NULL=판정 불가(레거시 포함) → 프론트 effectiveActive가 is_active로 폴백한다.

alter table postings add column if not exists recruit_until date;
alter table postings add column if not exists recruit_until_estimated boolean not null default false;

comment on column postings.recruit_until is
  '이 날짜까지 접수 가능(추정 포함). NULL=판정 불가(레거시) — 프론트는 is_active 폴백.';
comment on column postings.recruit_until_estimated is
  'true면 recruit_until이 추정값(명시 마감일 없음 — 근무시작 전날 또는 등록일+30일).';

-- ⚠️ postings는 컬럼 화이트리스트 GRANT(20260713144538, H1) — 새 컬럼은 grant에 넣어야
--    프론트 직접 조회(HOME_POSTING_COLS·fetchRepresentativePosting)가 select할 수 있다.
grant select (recruit_until, recruit_until_estimated)
  on table public.postings to anon, authenticated;
