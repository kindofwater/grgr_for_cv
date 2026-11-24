-- 목적: '공용(전국 공통)' 대학 행(id=0) 신설 + 교외 국가근장 6,647건을 공용으로 이관
-- 날짜: 2026-07-20 · 담당: 배경록

-- 배경: 검색·홈 스코프 SQL(search_worksite_cards·get_home_feed)은 이미
--   `w.university_id = 0 or w.university_id = 내대학` 으로 '공용' 분기를 갖고 있었다.
--   그런데 worksites.university_id는 universities(id) FK인데 **universities에 id=0 행이 없어서**
--   0은 물리적으로 존재할 수 없었다 → 그 공용 분기는 지금까지 한 번도 매치되지 않은 죽은 코드였다.
--   그 결과 전국 대상인 교외 국가근장 6,647건이 전부 고려대(1)로 태깅돼 있고(KOSAF 임포트를
--   고려대만 있던 시절에 돌린 흔적), 서울대 학생은 검색에서 자기 교내 24건 외엔 아무것도 못 봤다.
--
-- 조치: 규약을 새로 만들지 않고 '이미 코드가 기대하던 0번 행'을 실제로 만들어 규약을 살린다.
--   행 단위 제어라 나중에 특정 학교 전용 교외 근무지가 생겨도 그 행만 university_id를 학교로 두면 된다
--   (스코프 SQL에 'off_campus면 무조건 공개' 같은 규칙을 박으면 그런 예외를 표현할 수 없다).
--
-- 영향: 고려대 학생 시야는 불변(공용 6,647 + 고려대 165 = 기존 6,812과 동일).
--   서울대 학생은 24건 → 6,671건으로 늘어난다(원래 보여야 했던 전국 교외 국가근로).
--
-- ⚠️ 가입 드롭다운 오염 방지: Signup은 fetchUniversities() 결과를 universitiesForEmail()로
--   '이메일 도메인 완전일치' 필터링한다. 0번 행의 email_domain을 실제 도메인이 될 수 없는 '-'로 두면
--   어떤 이메일과도 매칭되지 않아 학교 선택지에 뜨지 않는다. (빈 문자열도 안전하지만 '-'가 센티널임이 명확)
-- ⚠️ 앞으로 교외 국가근장을 새로 적재할 때는 university_id를 0으로 넣어야 한다.
--   임포터가 무조건 1을 넣던 것이 이 문제의 원인이었다.

-- 1) 공용 대학 행 — id를 명시 삽입(serial이라 시퀀스는 건드리지 않는다). 이미 있으면 생략(멱등).
insert into universities (id, name, campus, email_domain)
select 0, '공용(전국 공통)', null, '-'
where not exists (select 1 from universities where id = 0);

-- 2) 교외 국가근장 → 공용. 지금 있는 교외는 전부 전국 공통이라는 확인을 받았다(2026-07-20).
update worksites
set university_id = 0, updated_at = now()
where type = 'national'
  and location_type = 'off_campus'
  and university_id <> 0;

-- 3) 자가검증 — 교외에 공용 아닌 행이 남으면 롤백
do $$
declare n int;
begin
  select count(*) into n from worksites
  where type = 'national' and location_type = 'off_campus' and university_id <> 0;
  if n <> 0 then raise exception '교외 국가근장 중 공용 아닌 행 %건 남음', n; end if;

  select count(*) into n from universities where id = 0;
  if n <> 1 then raise exception '공용 대학 행(id=0)이 %건', n; end if;
end $$;
