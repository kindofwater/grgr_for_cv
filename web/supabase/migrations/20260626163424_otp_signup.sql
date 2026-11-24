-- 목적: 회원가입 OTP 재설계 — 트리거는 도메인 검사만, 프로필 저장은 create_profile RPC(맨 마지막)로.
-- 날짜: 2026-06-27 · 담당: <이름>

-- [1] 트리거 슬림화: 프로필 insert·단과/학과 해석·닉네임 검사 제거, *.ac.kr 검사만 유지.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if lower(split_part(new.email, '@', 2)) not like '%.ac.kr' then
    raise exception 'DOMAIN_NOT_ALLOWED';
  end if;
  return new;
end $$;
revoke execute on function public.handle_new_user() from anon, public;

-- [2] create_profile: 프로필 입력 완료 후 호출. 본인(auth.uid()) 행 생성.
drop function if exists create_profile(text,int,text,text,text,int,text,text,int,text);
create function create_profile(
  p_nickname        text,
  p_university_id   int,
  p_college_name    text,
  p_department_name text,
  p_track           text,
  p_admission_year  int,
  p_degree_program  text,
  p_academic_status text,
  p_grade           int,
  p_region          text
) returns void
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_college_id int;
  v_department_id int;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  -- 이미 프로필 있으면 재생성하지 않음(더블클릭/재호출 안전). 갱신은 update_profile 담당.
  if exists (select 1 from users u where u.id = v_uid) then
    return;
  end if;

  select id into v_college_id from colleges
    where university_id = p_university_id and name = p_college_name limit 1;
  if v_college_id is null then
    select id into v_college_id from colleges where university_id = p_university_id order by id limit 1;
  end if;
  if v_college_id is null then raise exception 'NO_COLLEGE'; end if;
  select id into v_department_id from departments
    where college_id = v_college_id and name = p_department_name limit 1;
  if v_department_id is null then
    select id into v_department_id from departments where college_id = v_college_id order by id limit 1;
  end if;
  if v_department_id is null then raise exception 'NO_DEPARTMENT'; end if;

  insert into users (id, university_id, college_id, department_id, track,
                     nickname, admission_year, degree_program, academic_status, grade, region)
  values (v_uid, p_university_id, v_college_id, v_department_id, p_track,
          p_nickname, p_admission_year,
          p_degree_program::degree_program_e, p_academic_status::academic_status_e,
          p_grade, p_region);
exception
  when unique_violation then raise exception 'NICKNAME_TAKEN';
end $$;
revoke execute on function create_profile(text,int,text,text,text,int,text,text,int,text) from anon, public;
grant execute on function create_profile(text,int,text,text,text,int,text,text,int,text) to authenticated;