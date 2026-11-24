-- 목적: 로그인/회원가입 RPC가 region(거주지역) + 소속학교(id·이름·캠퍼스)도 반환 → 컨텍스트에 실림.
--       추가로 회원가입 때 누락되던 region 저장 보완(register_user에 p_region 추가·insert).
-- 날짜: 2026-06-15 · 담당: 배경록 (verify_login/register_user는 현수 auth — 리뷰 후 push)

-- ── verify_login: region + 소속학교(universities 조인) 컬럼 추가 ──
drop function if exists verify_login(text, text);
create or replace function verify_login(p_email text, p_password text)
returns table (
  id                int,
  nickname          text,
  email             text,
  region            text,
  university_id     int,
  university_name   text,
  university_campus text,
  admission_year    int,
  degree_program    text,
  academic_status   text,
  grade             int,
  track             text,
  point_balance     int,
  pass_expires_at   timestamp
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_email text := lower(trim(p_email));
begin
  return query
    select u.id, u.nickname::text, u.email::text,
           u.region::text, u.university_id, uni.name::text, uni.campus::text,
           u.admission_year, u.degree_program::text, u.academic_status::text,
           u.grade, u.track::text, u.point_balance, u.pass_expires_at
    from public.users u
    join public.universities uni on uni.id = u.university_id
    where u.email = v_email
      and u.deleted_at is null
      and u.password_hash = crypt(p_password, u.password_hash)
    limit 1;
end $$;
grant execute on function verify_login(text, text) to anon, authenticated;

-- ── register_user: p_region 추가(저장) + verify_login과 동일한 반환(소속학교 포함) ──
drop function if exists register_user(text, text, text, int, text, text, text, int, text, text, int);
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
  p_grade           int,
  p_region          text default null
)
returns table (
  id                int,
  nickname          text,
  email             text,
  region            text,
  university_id     int,
  university_name   text,
  university_campus text,
  admission_year    int,
  degree_program    text,
  academic_status   text,
  grade             int,
  track             text,
  point_balance     int,
  pass_expires_at   timestamp
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

  -- 학과 id: 학교 내 이름으로, 없으면 위 단과대학의 첫 학과
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
    nickname, admission_year, degree_program, academic_status, grade, region
  ) values (
    p_university_id, v_college_id, v_department_id, p_track, v_email,
    crypt(p_password, gen_salt('bf', 10)),
    p_nickname, p_admission_year,
    p_degree_program::degree_program_e,
    p_academic_status::academic_status_e,
    p_grade, p_region
  )
  returning users.id into v_new_id;

  return query
    select u.id, u.nickname::text, u.email::text,
           u.region::text, u.university_id, uni.name::text, uni.campus::text,
           u.admission_year, u.degree_program::text, u.academic_status::text,
           u.grade, u.track::text, u.point_balance, u.pass_expires_at
    from users u
    join universities uni on uni.id = u.university_id
    where u.id = v_new_id;
end $$;

grant execute on function register_user(text, text, text, int, text, text, text, int, text, text, int, text)
  to anon, authenticated;
