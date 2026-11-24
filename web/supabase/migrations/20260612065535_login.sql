-- ============================================================
-- 로그인/회원가입 (auth) — 이미 SQL 에디터에서 수동 실행된 것을 마이그레이션으로 편입
-- 전부 idempotent (create or replace / if not exists / where password_hash='seed')
-- → 이미 적용된 원격에 db push 해도 안전, 신규 환경(db reset)에서도 정상.
-- 포함: pgcrypto, password_hash 컬럼 보호, verify_login, set_password, 시드 비번 전환, register_user
-- ============================================================

-- [1] pgcrypto — bcrypt 함수(crypt/gen_salt). Supabase 는 extensions 스키마에 설치.
create extension if not exists pgcrypto with schema extensions;

-- [2] anon/authenticated 가 password_hash "컬럼"만 못 읽게 (RLS 없이 컬럼 단위 차단).
revoke select (password_hash) on public.users from anon, authenticated;

-- [3] 로그인 검증 RPC. 서버에서 bcrypt 비교, 성공 시 안전 컬럼만 반환(password_hash 제외).
create or replace function verify_login(p_email text, p_password text)
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
declare v_email text := lower(trim(p_email));
begin
  return query
    select u.id, u.nickname::text, u.email::text,
           u.admission_year, u.degree_program::text, u.academic_status::text,
           u.grade, u.track::text, u.point_balance, u.pass_expires_at
    from public.users u
    where u.email = v_email
      and u.deleted_at is null
      and u.password_hash = crypt(p_password, u.password_hash)
    limit 1;
end $$;
grant execute on function verify_login(text, text) to anon, authenticated;

-- [4] 비밀번호 설정/리셋 도우미 (anon 에 grant 안 함 — 관리용).
create or replace function set_password(p_email text, p_new_password text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_email text := lower(trim(p_email)); v_rows int;
begin
  update public.users
     set password_hash = crypt(p_new_password, gen_salt('bf', 10)),
         updated_at = now()
   where email = v_email and deleted_at is null;
  get diagnostics v_rows = row_count;
  return v_rows > 0;
end $$;

-- [5] 시드 유저 password_hash('seed' 문자열) → 진짜 bcrypt. 이미 전환됐으면 no-op(안전).
update public.users
   set password_hash = extensions.crypt('1q2w3e4r', extensions.gen_salt('bf', 10)),
       updated_at = now()
 where password_hash = 'seed' and deleted_at is null;

-- [6] 회원가입 RPC — 비번 해싱·FK(단과대/학과 이름→id)·중복검사를 전부 서버에서 처리.
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