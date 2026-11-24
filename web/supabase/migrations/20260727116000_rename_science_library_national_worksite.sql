-- 목적: 국가근로 명부의 과학도서관 학술정보큐레이션팀 이름을 실제 근무지 기준으로 보정한다.
-- 날짜: 2026-07-27 · 담당: 배경록
--
-- 기존 분리 마이그레이션은 school 유형만 대상으로 했으나, 이 행은 national 유형이다.

update public.worksites
set workplace_name = '과학도서관 학술정보큐레이션팀',
    normalized_name = '과학도서관 학술정보큐레이션팀',
    updated_at = now()
where university_id = 1
  and type = 'national'
  and workplace_name = '도서관 학술정보큐레이션팀'
  and address ilike '%과학도서관%'
  and deleted_at is null;
