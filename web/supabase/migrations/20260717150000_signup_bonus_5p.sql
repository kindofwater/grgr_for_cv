-- 목적: 가입 축하 5p 지급 — create_profile이 프로필 생성과 원자적으로 포인트 원장+지갑 적립
-- 날짜: 2026-07-17 · 담당: 배경록
-- 방식: points 원장(reason='signup_bonus' — 스키마가 처음부터 예약한 값) insert + point_balance 캐시
--       증가. claim_ad_reward(20260624170000)와 동일한 원장+캐시 패턴.
--       users.point_balance default를 5로 바꾸는 방식은 원장 행이 안 남아 내역 표시가 불가라 탈락.
-- 중복 지급 안전: create_profile의 기존 "프로필 존재 시 조기 return" 가드가 재호출을 걸러낸다.
-- ⚠️ 본문은 현행 최신(20260626163424_otp_signup)을 그대로 재현 + 보너스 2줄만 추가.
--    시그니처 불변 → create or replace(DROP 불필요), 기존 grant(authenticated) 유지됨.
create or replace function create_profile(
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

  -- 가입 축하 5p — 원장(내역 표시용) + 지갑 캐시. 위 조기 return 가드 덕에 1회만 지급된다.
  insert into points (user_id, amount, reason) values (v_uid, 5, 'signup_bonus');
  update users set point_balance = point_balance + 5 where id = v_uid;
exception
  when unique_violation then raise exception 'NICKNAME_TAKEN';
end $$;
