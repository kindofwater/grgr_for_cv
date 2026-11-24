-- 목적: 프로필 수정에서 단과대/학과/계열 변경 지원 — (1) 고려대(서울) 단과대·학과 시드 동기화(멱등),
--       (2) update_profile 시그니처 확장(+p_college_name/p_department_name/p_track, 엄격 매칭)
--       배경: 실DB colleges/departments가 각 1행뿐이라 create_profile 폴백이 모든 가입자를
--       보건과학대학/바이오시스템의과학부로 저장해왔음(선택값 유실) — 시드를 프론트 목록과 1:1로 채움.
-- 날짜: 2026-07-16 · 담당: (푸시 담당자 기입)

-- ── 1. 단과대/학과 시드 동기화 (프론트 lib/profileOptions colleges/departments와 1:1) ──
-- 이미 있는 이름은 건너뜀(멱등: 기존 보건과학대학·바이오시스템의과학부 행 유지, id 불변).
-- default_track은 "학과 선택 시 자동 세팅용 기본값"이라 대표값으로 채움 — 실제 계열은 사용자가 직접 선택.
do $$
declare
  v_univ int;
  v_college int;
  r record;
begin
  select id into v_univ from universities where name = '고려대학교' and campus = '서울' limit 1;
  if v_univ is null then raise exception 'NO_UNIVERSITY: 고려대학교(서울) 행이 없습니다'; end if;

  for r in
    select * from (values
      ('경영대학', '경영학과', '인문사회계열'),
      ('문과대학', '국어국문학과', '인문사회계열'),
      ('문과대학', '철학과', '인문사회계열'),
      ('문과대학', '한국사학과', '인문사회계열'),
      ('문과대학', '사학과', '인문사회계열'),
      ('문과대학', '사회학과', '인문사회계열'),
      ('문과대학', '한문학과', '인문사회계열'),
      ('문과대학', '영어영문학과', '인문사회계열'),
      ('문과대학', '독어독문학과', '인문사회계열'),
      ('문과대학', '불어불문학과', '인문사회계열'),
      ('문과대학', '중어중문학과', '인문사회계열'),
      ('문과대학', '노어노문학과', '인문사회계열'),
      ('문과대학', '일어일문학과', '인문사회계열'),
      ('문과대학', '서어서문학과', '인문사회계열'),
      ('문과대학', '언어학과', '인문사회계열'),
      ('생명과학대학', '생명과학부', '자연계열'),
      ('생명과학대학', '생명공학부', '자연계열'),
      ('생명과학대학', '식품공학과', '자연계열'),
      ('생명과학대학', '환경생태공학부', '자연계열'),
      ('생명과학대학', '식품자원경제학과', '자연계열'),
      ('정경대학', '정치외교학과', '인문사회계열'),
      ('정경대학', '경제학과', '인문사회계열'),
      ('정경대학', '통계학과', '인문사회계열'),
      ('정경대학', '행정학과', '인문사회계열'),
      ('이과대학', '수학과', '자연계열'),
      ('이과대학', '물리학과', '자연계열'),
      ('이과대학', '화학과', '자연계열'),
      ('이과대학', '지구환경과학과', '자연계열'),
      ('공과대학', '화공생명공학과', '자연계열'),
      ('공과대학', '건축사회환경공학부', '자연계열'),
      ('공과대학', '건축학과', '자연계열'),
      ('공과대학', '기계공학부', '자연계열'),
      ('공과대학', '전기전자공학부', '자연계열'),
      ('공과대학', '신소재공학부', '자연계열'),
      ('공과대학', '산업경영공학부', '자연계열'),
      ('공과대학', '반도체공학과', '자연계열'),
      ('공과대학', '융합에너지공학과', '자연계열'),
      ('공과대학', '차세대통신학과', '자연계열'),
      ('의과대학', '의(예)학과', '자연계열'),
      ('사범대학', '교육학과', '인문사회계열'),
      ('사범대학', '체육교육과', '예체능계열'),
      ('사범대학', '가정교육과', '자연계열'),
      ('사범대학', '수학교육과', '자연계열'),
      ('사범대학', '국어교육과', '인문사회계열'),
      ('사범대학', '영어교육과', '인문사회계열'),
      ('사범대학', '지리교육과', '인문사회계열'),
      ('사범대학', '역사교육과', '인문사회계열'),
      ('간호대학', '간호학과', '자연계열'),
      ('정보대학', '컴퓨터학과', '자연계열'),
      ('정보대학', '데이터과학과', '자연계열'),
      ('정보대학', '인공지능학과', '자연계열'),
      ('디자인조형학부', '디자인조형학부', '예체능계열'),
      ('국제대학', '국제학부', '인문사회계열'),
      ('국제대학', '글로벌한국융합학부', '인문사회계열'),
      ('국제대학', '글로벌자율학부', '인문사회계열'),
      ('미디어대학', '미디어학부', '인문사회계열'),
      ('미디어대학', '글로벌엔터테인먼트학부', '인문사회계열'),
      ('보건과학대학', '바이오의공학부', '자연계열'),
      ('보건과학대학', '바이오시스템의과학부', '자연계열'),
      ('보건과학대학', '보건환경융합과학부', '자연계열'),
      ('보건과학대학', '보건정책관리학부', '인문사회계열'),
      ('자유전공학부', '자유전공학부', '인문사회계열'),
      ('스마트보안학부', '사이버국방학과', '자연계열'),
      ('스마트보안학부', '스마트보안학부', '자연계열'),
      ('심리학부', '심리학부', '인문사회계열'),
      ('스마트모빌리티학부', '스마트모빌리티학부', '자연계열'),
      ('학부대학', '학부대학', '인문사회계열')
    ) as t(college_name, dept_name, dept_track)
  loop
    select id into v_college from colleges
      where university_id = v_univ and name = r.college_name limit 1;
    if v_college is null then
      insert into colleges (university_id, name) values (v_univ, r.college_name)
        returning id into v_college;
    end if;
    if not exists (
      select 1 from departments d where d.college_id = v_college and d.name = r.dept_name
    ) then
      insert into departments (college_id, name, default_track)
        values (v_college, r.dept_name, r.dept_track);
    end if;
  end loop;
end $$;

-- ── 2. update_profile 확장: 단과대/학과/계열 갱신 (시그니처 변경 → DROP 먼저) ──
-- create_profile과 달리 이름 미일치 폴백 없음(엄격) — 조용히 다른 단과대로 저장되는 사고 방지.
-- 반환에 college_name/department_name 추가: 프론트가 컨텍스트 user(college/department {name})를 갱신할 수 있게.
-- ⚠️ 새 인자 3개는 default null: DB를 먼저 push해도 구버전 프론트(5인자 호출, prod grgr.kr)가
--    계속 동작해야 함(배포 모델: 스키마 먼저 → 프론트 나중). null이면 해당 값 유지.
drop function if exists update_profile(text, int, text, text, int);
create function update_profile(
  p_region          text,
  p_admission_year  int,
  p_degree_program  text,
  p_academic_status text,
  p_grade           int,
  p_college_name    text default null,
  p_department_name text default null,
  p_track           text default null
)
returns table (
  id              uuid,
  nickname        text,
  region          text,
  admission_year  int,
  degree_program  text,
  academic_status text,
  grade           int,
  track           text,
  point_balance   int,
  pass_expires_at timestamptz,
  college_name    text,
  department_name text
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_univ int;
  v_college_id int;
  v_department_id int;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;

  select u.university_id into v_univ
    from public.users u where u.id = v_uid and u.deleted_at is null;
  if v_univ is null then raise exception 'NO_PROFILE'; end if;

  -- 단과대/학과는 쌍으로만 갱신(둘 다 null이면 기존 유지 — 구버전 프론트 호환 경로)
  if p_college_name is not null or p_department_name is not null then
    if p_college_name is null or p_department_name is null then
      raise exception 'COLLEGE_DEPT_PAIR_REQUIRED';
    end if;
    select c.id into v_college_id from colleges c
      where c.university_id = v_univ and c.name = p_college_name limit 1;
    if v_college_id is null then raise exception 'NO_COLLEGE'; end if;
    select d.id into v_department_id from departments d
      where d.college_id = v_college_id and d.name = p_department_name limit 1;
    if v_department_id is null then raise exception 'NO_DEPARTMENT'; end if;
  end if;

  update public.users u
     set region          = p_region,
         admission_year  = p_admission_year,
         degree_program  = p_degree_program::degree_program_e,
         academic_status = p_academic_status::academic_status_e,
         grade           = p_grade,
         college_id      = coalesce(v_college_id, u.college_id),
         department_id   = coalesce(v_department_id, u.department_id),
         track           = coalesce(p_track, u.track),
         updated_at      = now()
   where u.id = v_uid and u.deleted_at is null;

  return query
    select u.id, u.nickname::text, u.region::text,
           u.admission_year, u.degree_program::text, u.academic_status::text,
           u.grade, u.track::text, u.point_balance, u.pass_expires_at,
           c.name::text, d.name::text
    from public.users u
    join colleges c    on c.id = u.college_id
    join departments d on d.id = u.department_id
    where u.id = v_uid;
end $$;

revoke execute on function update_profile(text, int, text, text, int, text, text, text) from anon, public;
grant  execute on function update_profile(text, int, text, text, int, text, text, text) to authenticated;
