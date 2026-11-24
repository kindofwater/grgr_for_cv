-- 목적: 이과대학행정팀이 대신 게시한 물리학과 공고를 실제 근무지로 복구.
--       이후 KUPID 적재도 제목 기준으로 물리학과에 연결하도록 보정했다.
-- 날짜: 2026-07-23 · 담당: 배경록

begin;

insert into worksites (
  university_id, type, location_type, organization_name, workplace_name,
  region, address, normalized_name
)
select
  1, 'school', 'on_campus', '고려대학교(본교)', '물리학과',
  null, '아산이학관 436B호', '물리학과'
where not exists (
  select 1
  from worksites
  where university_id = 1
    and type = 'school'
    and workplace_name = '물리학과'
    and deleted_at is null
);

update postings p
set worksite_id = physics.id
from worksites posting_dept
join worksites physics
 on physics.university_id = 1
 and physics.type = 'school'
 and physics.workplace_name = '물리학과'
 and physics.deleted_at is null
where p.worksite_id = posting_dept.id
  and posting_dept.university_id = 1
  and posting_dept.type = 'school'
  and posting_dept.workplace_name in ('이과대학행정팀', '이과대학행정실')
  and p.raw_text ilike '%물리학과%';

commit;
