-- 목적: 중앙도서관·과학도서관은 소속 팀을 붙여 별도 근무지로 표시한다.
-- 날짜: 2026-07-27 · 담당: 배경록
--
-- 재구축 DB의 기존 시드도 크롤러 예외 규칙과 같은 이름을 쓰도록 맞춘다.
-- 운영 DB에 대상 행이 없으면 아무 변경도 하지 않는다.

update public.worksites
set workplace_name = '중앙도서관 학술정보개발팀',
    normalized_name = '중앙도서관 학술정보개발팀',
    updated_at = now()
where university_id = 1
  and type = 'school'
  and deleted_at is null
  and workplace_name = '학술정보개발팀'
  and address ilike '%중앙도서관%';

update public.worksites
set workplace_name = '과학도서관 학술정보큐레이션팀',
    normalized_name = '과학도서관 학술정보큐레이션팀',
    updated_at = now()
where university_id = 1
  and type = 'school'
  and deleted_at is null
  and workplace_name = '도서관 학술정보큐레이션팀'
  and address ilike '%과학도서관%';
