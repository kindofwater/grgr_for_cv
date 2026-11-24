-- 목적: 보안점검(2026-07-10) H1 — postings 컬럼 화이트리스트. raw_text(크롤 원문, 연락처 포함 가능) 등 비공개 컬럼의 anon 전량 노출 차단.
-- 날짜: 2026-07-13 · 담당: <이름>
-- 배경: RLS 정책(postings_read, using(true))은 행 수준만 제어 — 컬럼 제한은 GRANT로(users 화이트리스트 패턴 동일).
--   contact_phone/email 은 20260619 에 이미 컬럼 drop → 남은 위험은 raw_text. updated_at/deleted_at 도 내부용이라 제외.
--   프론트 직접 조회(fetchRepresentativePosting cols · HOME_POSTING_COLS)가 쓰는 컬럼 전수 포함 확인(2026-07-13).
--   검색/추천 RPC 는 security definer(소유자 postgres)라 이 GRANT 와 무관하게 계속 동작.

revoke select on table public.postings from public, anon, authenticated;
grant select (id, worksite_id, source_url, job_category, preferred_track,
  preferred_college, preferred_dept, recruit_count, min_grade, eligible_degree,
  eligible_status, job_description, preference_notes, extra_notes, hourly_wage,
  work_period_text, work_duration_type, work_time_text, recruitment_period_text,
  contact_name, is_active, created_at)
  on table public.postings to anon, authenticated;
