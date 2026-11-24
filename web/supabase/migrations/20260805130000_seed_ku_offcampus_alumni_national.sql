-- 목적: 고려대 전용 교외 국가근로 교우회·교우장학회 근무지와 모집 마감 안내 공고를 적재한다.
-- 날짜: 2026-08-05 · 담당: Codex
-- 출처: '24~'26년 연도별 유형별 근로지 현황 — 두 근무지 모두 일반교외, 1·2학기 신청 가능.
-- 현재 모집 기간·인원은 확인되지 않았으므로 모집 마감 안내 공고로만 등록한다.

begin;

create temporary table ku_alumni_national_seed (
  organization_name text not null,
  workplace_name text primary key,
  address text not null,
  normalized_name text not null unique,
  external_id text not null unique
) on commit drop;

insert into ku_alumni_national_seed (
  organization_name, workplace_name, address, normalized_name, external_id
)
values
  (
    '(재)고려대학교 교우장학회',
    '고려대학교 교우장학회',
    '서울 성북구 종암동 29-26번지 고려대학교교우회 503호',
    '고려대학교 교우장학회',
    'ku-manual:alumni-scholarship-foundation'
  ),
  (
    '고려대학교 교우회',
    '고려대학교 교우회',
    '서울 성북구 종암동 13 고려대학교교우회 503호',
    '고려대학교 교우회',
    'ku-manual:alumni-association'
  );

-- 교외지만 고려대 학생에게만 배정되는 근무지이므로 공용 대학(id=0)이 아닌 고려대학교에 귀속한다.
-- 같은 이름의 공용 교외 국가근로 행이 있더라도 별개로 유지한다.
insert into public.worksites (
  university_id, type, location_type, organization_name, workplace_name,
  region, address, normalized_name, national_work_term
)
select
  u.id, 'national', 'off_campus', s.organization_name, s.workplace_name,
  '서울', s.address, s.normalized_name, 'semester'
from ku_alumni_national_seed s
join public.universities u on u.name = '고려대학교'
on conflict (university_id, type, normalized_name)
  where normalized_name is not null and deleted_at is null
do update set
  location_type = excluded.location_type,
  organization_name = excluded.organization_name,
  workplace_name = excluded.workplace_name,
  region = excluded.region,
  address = excluded.address,
  national_work_term = excluded.national_work_term,
  updated_at = now();

do $$
declare
  v_worksite_count integer;
begin
  select count(*) into v_worksite_count
  from ku_alumni_national_seed s
  join public.universities u on u.name = '고려대학교'
  join public.worksites w
    on w.university_id = u.id
   and w.type = 'national'
   and w.location_type = 'off_campus'
   and w.normalized_name = s.normalized_name
   and w.deleted_at is null;

  if v_worksite_count <> 2 then
    raise exception 'Expected 2 resolved KU alumni national worksites, got %', v_worksite_count;
  end if;
end
$$;

-- 실제 모집 공고가 확인되면 이 placeholder 공고만 삭제·교체한다.
insert into public.postings (
  worksite_id, source, external_id, title, job_description, hourly_wage,
  work_duration_type, eligible_degree, eligible_status, recruitment_period_text,
  is_active, is_placeholder, recruit_until, recruit_until_at,
  recruit_until_estimated, manual_override, deadline_basis,
  source_closed_at, source_closed_reason, deleted_at
)
select
  w.id,
  'manual_seed',
  s.external_id,
  '교외 국가근로장학생 모집',
  '고려대학교 학생 전용 교외 국가근로 근무지입니다.',
  12790,
  'long',
  0,
  0,
  '1·2학기 신청 가능 · 현재 모집 마감',
  false,
  true,
  null,
  null,
  false,
  true,
  'human_confirmed',
  current_date,
  'human_confirmed',
  null
from ku_alumni_national_seed s
join public.universities u on u.name = '고려대학교'
join public.worksites w
  on w.university_id = u.id
 and w.type = 'national'
 and w.location_type = 'off_campus'
 and w.normalized_name = s.normalized_name
 and w.deleted_at is null
on conflict (source, external_id)
  where source is not null and external_id is not null
do update set
  worksite_id = excluded.worksite_id,
  title = excluded.title,
  job_description = excluded.job_description,
  hourly_wage = excluded.hourly_wage,
  work_duration_type = excluded.work_duration_type,
  eligible_degree = excluded.eligible_degree,
  eligible_status = excluded.eligible_status,
  recruitment_period_text = excluded.recruitment_period_text,
  is_active = excluded.is_active,
  is_placeholder = excluded.is_placeholder,
  recruit_until = null,
  recruit_until_at = null,
  recruit_until_estimated = false,
  manual_override = true,
  deadline_basis = excluded.deadline_basis,
  source_closed_at = excluded.source_closed_at,
  source_closed_reason = excluded.source_closed_reason,
  deleted_at = null,
  updated_at = now();

do $$
declare
  v_posting_count integer;
begin
  select count(*) into v_posting_count
  from public.postings p
  where p.source = 'manual_seed'
    and p.external_id in (
      'ku-manual:alumni-scholarship-foundation',
      'ku-manual:alumni-association'
    )
    and p.deleted_at is null;

  if v_posting_count <> 2 then
    raise exception 'Expected 2 KU alumni national placeholder postings, got %', v_posting_count;
  end if;
end
$$;

commit;
