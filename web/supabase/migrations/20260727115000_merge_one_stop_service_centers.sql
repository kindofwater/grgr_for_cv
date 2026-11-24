-- 목적: ONE-STOP서비스센터의 위치·계열 분리를 취소하고 기존 근무지로 통합한다.
-- 날짜: 2026-07-27 · 담당: 배경록
--
-- 리뷰와 공고를 기존 ONE-STOP서비스센터로 먼저 되돌린 뒤, 분리해 만든 두 근무지를 숨긴다.

begin;

update public.reviews r
set worksite_id = original.id,
    updated_at = now()
from public.worksites split_worksite
join public.worksites original
  on original.university_id = 1
 and original.type = 'school'
 and original.workplace_name = 'ONE-STOP서비스센터'
 and original.deleted_at is null
where r.worksite_id = split_worksite.id
  and split_worksite.university_id = 1
  and split_worksite.type = 'school'
  and split_worksite.workplace_name in (
    '중앙광장 지하 ONE-STOP서비스센터',
    '자연계 ONE-STOP서비스센터'
  )
  and split_worksite.deleted_at is null
  and r.deleted_at is null;

update public.postings p
set worksite_id = original.id,
    updated_at = now()
from public.worksites split_worksite
join public.worksites original
  on original.university_id = 1
 and original.type = 'school'
 and original.workplace_name = 'ONE-STOP서비스센터'
 and original.deleted_at is null
where p.worksite_id = split_worksite.id
  and split_worksite.university_id = 1
  and split_worksite.type = 'school'
  and split_worksite.workplace_name in (
    '중앙광장 지하 ONE-STOP서비스센터',
    '자연계 ONE-STOP서비스센터'
  )
  and split_worksite.deleted_at is null
  and p.deleted_at is null;

update public.worksites
set deleted_at = now(),
    updated_at = now()
where university_id = 1
  and type = 'school'
  and workplace_name in (
    '중앙광장 지하 ONE-STOP서비스센터',
    '자연계 ONE-STOP서비스센터'
  )
  and deleted_at is null;

commit;
