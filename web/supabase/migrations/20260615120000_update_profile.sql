-- 목적: 프로필 수정 — 거주지역·학적정보(입학연도·학위·학년·학적상태)만 갱신하는 RPC
-- 날짜: 2026-06-15 · 담당: 배경록

-- 시그니처 변경 대비: 같은 이름 기존 함수 제거(없으면 no-op)
drop function if exists update_profile(int, text, int, text, text, int);

-- 프로필 수정 RPC — 프로필 5개 컬럼만 갱신(point_balance·is_admin·password_hash 등은 못 건드림).
-- 서버 인증(JWT) 없는 현 구조라 p_user_id는 클라가 전달 → 컬럼 화이트리스트가 주된 방어.
-- (6/21 anon UPDATE REVOKE 후에도 security definer라 정상 동작)
create or replace function update_profile(
  p_user_id         int,
  p_region          text,
  p_admission_year  int,
  p_degree_program  text,
  p_academic_status text,
  p_grade           int
)
returns table (
  id              int,
  nickname        text,
  email           text,
  region          text,
  admission_year  int,
  degree_program  text,
  academic_status text,
  grade           int,
  track           text,
  point_balance   int,
  pass_expires_at timestamp
)
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  update public.users u
     set region          = p_region,
         admission_year  = p_admission_year,
         degree_program  = p_degree_program::degree_program_e,
         academic_status = p_academic_status::academic_status_e,
         grade           = p_grade,
         updated_at      = now()
   where u.id = p_user_id and u.deleted_at is null;

  return query
    select u.id, u.nickname::text, u.email::text, u.region::text,
           u.admission_year, u.degree_program::text, u.academic_status::text,
           u.grade, u.track::text, u.point_balance, u.pass_expires_at
    from public.users u where u.id = p_user_id;
end $$;

grant execute on function update_profile(int, text, int, text, text, int) to anon, authenticated;
