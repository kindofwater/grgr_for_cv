-- 목적: 가입 학교 제한 해제 — 특정 학교(korea.ac.kr)만이 아니라 *.ac.kr 이메일이면 가입 허용.
-- 날짜: 2026-06-27 · 담당: <이름>
-- handle_new_user 트리거에서 학교 signup_enabled·도메인 매칭 검사를 제거하고,
-- 이메일 도메인이 .ac.kr 로 끝나는지만 본다. (단과대/학과 해석은 그대로 — 선택 학교 기준)
-- create or replace 라 기존 grant/trigger 는 보존됨(시그니처 변경 아님).

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  m jsonb := new.raw_user_meta_data;
  v_uni_id int := (m->>'university_id')::int;
  v_college_id int;
  v_department_id int;
begin
  -- 학교 제한 해제: 이메일 도메인이 *.ac.kr 이면 허용 (학교별 signup_enabled/도메인 매칭 검사 제거)
  if lower(split_part(new.email, '@', 2)) not like '%.ac.kr' then
    raise exception 'DOMAIN_NOT_ALLOWED';
  end if;
  if not exists (select 1 from universities where id = v_uni_id) then
    raise exception 'NO_UNIVERSITY';
  end if;

  select id into v_college_id from colleges
    where university_id = v_uni_id and name = (m->>'college_name') limit 1;
  if v_college_id is null then
    select id into v_college_id from colleges where university_id = v_uni_id order by id limit 1;
  end if;
  if v_college_id is null then raise exception 'NO_COLLEGE'; end if;
  select id into v_department_id from departments
    where college_id = v_college_id and name = (m->>'department_name') limit 1;
  if v_department_id is null then
    select id into v_department_id from departments where college_id = v_college_id order by id limit 1;
  end if;
  if v_department_id is null then raise exception 'NO_DEPARTMENT'; end if;

  insert into public.users (id, university_id, college_id, department_id, track,
                            nickname, admission_year, degree_program, academic_status, grade, region)
  values (new.id, v_uni_id, v_college_id, v_department_id, m->>'track',
          m->>'nickname', (m->>'admission_year')::int,
          (m->>'degree_program')::degree_program_e, (m->>'academic_status')::academic_status_e,
          (m->>'grade')::int, m->>'region');
  return new;
exception
  when unique_violation then raise exception 'NICKNAME_TAKEN';
end $$;

revoke execute on function public.handle_new_user() from anon, public;