-- 목적: 중앙도서관 관련 근무지명을 기관·팀 단위로 간결하게 표시한다.
-- 날짜: 2026-07-27 · 담당: 배경록

update public.worksites
set workplace_name = '학술정보개발팀',
    normalized_name = '학술정보개발팀',
    updated_at = now()
where university_id = 1
  and type = 'school'
  and workplace_name = '중앙도서관 학술정보개발팀'
  and deleted_at is null;

update public.worksites
set workplace_name = '중앙도서관',
    normalized_name = '중앙도서관',
    updated_at = now()
where university_id = 1
  and type = 'school'
  and workplace_name = '고려대학교 중앙도서관'
  and deleted_at is null;
