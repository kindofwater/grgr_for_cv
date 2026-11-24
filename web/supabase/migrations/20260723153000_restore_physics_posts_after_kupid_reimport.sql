-- 목적: Sonnet 근무부서 기준 재적재 전 되돌아간 물리학과 공고를 실제 근무지로 복구.
-- 날짜: 2026-07-23 · 담당: 배경록

begin;

update postings p
set worksite_id = physics.id
from worksites physics
where physics.university_id = 1
  and physics.type = 'school'
  and physics.workplace_name = '물리학과'
  and physics.deleted_at is null
  and p.raw_text ilike '%물리학과%';

commit;
