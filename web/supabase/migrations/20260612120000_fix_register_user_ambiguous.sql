-- 목적: register_user 의 column reference ambiguous(42702) 수정 — RETURNS TABLE OUT 컬럼명(id/email/nickname)과 테이블 컬럼이 충돌하던 것을 전부 별칭으로 qualify
-- 날짜: 2026-06-12 · 담당: 배경록
-- 비고: 시그니처(인자·리턴) 동일 → create or replace 로 덮어씀(DROP 불필요). 직전 20260612065535_login.sql 가 이미 applied 로 기록돼 push 가 스킵하므로 새 파일로 재적용.

create or replace function register_user(
  p_email           text,
  p_password        text,
  p_nickname        text,
  p_university_id   int,
  p_college_name    text,
  p_department_name text,
  p_track           text,
  p_admission_year  int,
  p_degree_program  text,
  p_academic_status text,
  p_grade           int
)
returns table (
  id              int,
  nickname        text,
  email           text,
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
declare
  v_email         text := lower(trim(p_email));
  v_college_id    int;
  v_department_id int;
  v_new_id        int;
begin
  if exists (select 1 from users u where u.email = v_email and u.deleted_at is null) then
    raise exception 'EMAIL_TAKEN';
  end if;
  if exists (select 1 from users u where u.nickname = p_nickname) then
    raise exception 'NICKNAME_TAKEN';
  end if;

  -- 단과대학 id: 이름으로 찾고 없으면 해당 학교의 첫 단과대학 (FK 보장)
  select c.id into v_college_id from colleges c
    where c.university_id = p_university_id and c.name = p_college_name limit 1;
  if v_college_id is null then
    select c.id into v_college_id from colleges c
      where c.university_id = p_university_id order by c.id limit 1;
  end if;
  if v_college_id is null then
    raise exception 'NO_COLLEGE';
  end if;

  -- 학과 id: 학교 내(어느 단과대든) 이름으로, 없으면 위 단과대학의 첫 학과
  select d.id into v_department_id
    from departments d join colleges c on c.id = d.college_id
    where c.university_id = p_university_id and d.name = p_department_name limit 1;
  if v_department_id is null then
    select d.id into v_department_id from departments d
      where d.college_id = v_college_id order by d.id limit 1;
  end if;
  if v_department_id is null then
    raise exception 'NO_DEPARTMENT';
  end if;

  insert into users (
    university_id, college_id, department_id, track, email, password_hash,
    nickname, admission_year, degree_program, academic_status, grade
  ) values (
    p_university_id, v_college_id, v_department_id, p_track, v_email,
    crypt(p_password, gen_salt('bf', 10)),
    p_nickname, p_admission_year,
    p_degree_program::degree_program_e,
    p_academic_status::academic_status_e,
    p_grade
  )
  returning users.id into v_new_id;

  return query
    select u.id, u.nickname::text, u.email::text,
           u.admission_year, u.degree_program::text, u.academic_status::text,
           u.grade, u.track::text, u.point_balance, u.pass_expires_at
    from users u where u.id = v_new_id;
end $$;

grant execute on function register_user(text, text, text, int, text, text, text, int, text, text, int)
  to anon, authenticated;
