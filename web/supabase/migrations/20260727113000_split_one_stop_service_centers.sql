-- 목적: 중앙광장 지하·자연계 ONE-STOP서비스센터 창구를 별도 근무지로 표시한다.
-- 날짜: 2026-07-27 · 담당: 배경록
--
-- 의료공제처럼 계열 표기가 없는 기존 ONE-STOP서비스센터는 그대로 둔다.

insert into public.worksites (
  university_id,
  type,
  location_type,
  organization_name,
  workplace_name,
  region,
  address
)
select
  1,
  'school',
  'on_campus',
  '고려대학교(본교)',
  '중앙광장 지하 ONE-STOP서비스센터',
  null,
  '중앙광장 지하 1층'
where not exists (
  select 1
  from public.worksites
  where university_id = 1
    and type = 'school'
    and workplace_name = '중앙광장 지하 ONE-STOP서비스센터'
    and deleted_at is null
);

insert into public.worksites (
  university_id,
  type,
  location_type,
  organization_name,
  workplace_name,
  region,
  address
)
select
  1,
  'school',
  'on_campus',
  '고려대학교(본교)',
  '자연계 ONE-STOP서비스센터',
  null,
  '하나스퀘어 지하 1층'
where not exists (
  select 1
  from public.worksites
  where university_id = 1
    and type = 'school'
    and workplace_name = '자연계 ONE-STOP서비스센터'
    and deleted_at is null
);

-- KUPID 제목에 자연계 창구가 명시된 과거 공고는 일반 원스탑에서 분리한다.
-- 본문의 인문사회계 표기는 지원 대상이며, 근무지 표기보다 우선하지 않는다.
update public.postings p
set worksite_id = target.id,
    updated_at = now()
from public.worksites current_worksite
join public.worksites target
  on target.university_id = 1
 and target.type = 'school'
 and target.workplace_name = '자연계 ONE-STOP서비스센터'
 and target.deleted_at is null
where p.worksite_id = current_worksite.id
  and current_worksite.university_id = 1
  and current_worksite.type = 'school'
  and current_worksite.workplace_name = 'ONE-STOP서비스센터'
  and current_worksite.deleted_at is null
  and p.source = 'kupid'
  and replace(p.raw_text, ' ', '') like '%ONE-STOP서비스센터(자연계)%'
  and p.deleted_at is null;
