-- Resolve the final reviewed candidates:
--   * merge Sustainability Management Team into the Sustainability Institute;
--   * split the College of Liberal Arts equipment room;
--   * merge Talent Discovery / Admissions Management into Admissions;
--   * rename Startup Support Team to the Crimson Startup Support Group.

begin;

insert into public.worksites (
  university_id,
  type,
  location_type,
  organization_name,
  workplace_name,
  normalized_name,
  region,
  address
)
select
  1,
  'school',
  'on_campus',
  '고려대학교(본교)',
  '문과대학 서관 기자재실',
  '문과대학 서관 기자재실',
  null,
  '문과대학 서관 기자재실'
where not exists (
  select 1
  from public.worksites
  where university_id = 1
    and type = 'school'
    and workplace_name = '문과대학 서관 기자재실'
    and deleted_at is null
);

do $$
declare
  sustainability_id integer;
  sustainability_team_id integer;
  literature_admin_id integer;
  literature_equipment_id integer;
  admissions_id integer;
  admissions_management_id integer;
  startup_id integer;
  candidate_count integer;
begin
  select id into strict sustainability_id
  from public.worksites
  where university_id = 1 and type = 'school'
    and workplace_name = '지속가능원' and deleted_at is null;

  select id into strict sustainability_team_id
  from public.worksites
  where university_id = 1 and type = 'school'
    and workplace_name = '지속가능경영팀' and deleted_at is null;

  select id into strict literature_admin_id
  from public.worksites
  where university_id = 1 and type = 'school'
    and workplace_name = '문과대학행정팀' and deleted_at is null;

  select id into strict literature_equipment_id
  from public.worksites
  where university_id = 1 and type = 'school'
    and workplace_name = '문과대학 서관 기자재실' and deleted_at is null;

  select id into strict admissions_id
  from public.worksites
  where university_id = 1 and type = 'school'
    and workplace_name = '입학처' and deleted_at is null;

  select id into strict admissions_management_id
  from public.worksites
  where university_id = 1 and type = 'school'
    and workplace_name = '입학전형관리팀' and deleted_at is null;

  select id into strict startup_id
  from public.worksites
  where university_id = 1 and type = 'school'
    and workplace_name = '창업지원팀' and deleted_at is null;

  if exists (
    select 1 from public.worksites
    where university_id = 1 and type = 'school'
      and workplace_name = '크림슨창업지원단'
      and deleted_at is null
  ) then
    raise exception '크림슨창업지원단 대표명이 이미 별도 근무지로 존재합니다';
  end if;

  if exists (
    select 1
    from public.reviews old_review
    join public.reviews current_review
      on current_review.worksite_id = sustainability_id
     and current_review.user_id = old_review.user_id
     and current_review.work_year = old_review.work_year
     and current_review.work_semester = old_review.work_semester
    where old_review.worksite_id = sustainability_team_id
  ) then
    raise exception '지속가능원 병합 시 중복 리뷰가 발생합니다';
  end if;

  if exists (
    select 1
    from public.reviews old_review
    join public.reviews current_review
      on current_review.worksite_id = admissions_id
     and current_review.user_id = old_review.user_id
     and current_review.work_year = old_review.work_year
     and current_review.work_semester = old_review.work_semester
    where old_review.worksite_id = admissions_management_id
  ) then
    raise exception '입학처 병합 시 중복 리뷰가 발생합니다';
  end if;

  select count(*) into candidate_count
  from public.postings
  where id in (7416, 7463)
    and worksite_id = sustainability_team_id
    and raw_text like '%지속가능원%'
    and deleted_at is null;
  if candidate_count <> 2 then
    raise exception '지속가능원 병합 공고 검증 실패: %건(기대 2건)', candidate_count;
  end if;

  select count(*) into candidate_count
  from public.postings
  where id in (7570, 7641)
    and worksite_id = literature_admin_id
    and raw_text like '%문과대학 서관 기자재실%'
    and deleted_at is null;
  if candidate_count <> 2 then
    raise exception '문과대학 기자재실 분리 공고 검증 실패: %건(기대 2건)', candidate_count;
  end if;

  if not exists (
    select 1 from public.postings
    where id = 7548
      and worksite_id = admissions_management_id
      and raw_text like '%인재발굴처%'
      and deleted_at is null
  ) then
    raise exception '입학처 병합 공고 검증 실패';
  end if;

  select count(*) into candidate_count
  from public.postings
  where worksite_id = startup_id
    and deleted_at is null;
  if candidate_count <> 4 then
    raise exception '크림슨창업지원단 대표명 변경 공고 검증 실패: %건(기대 4건)', candidate_count;
  end if;

  update public.postings
  set worksite_id = sustainability_id,
      updated_at = now()
  where worksite_id = sustainability_team_id;

  update public.reviews
  set worksite_id = sustainability_id,
      updated_at = now()
  where worksite_id = sustainability_team_id;

  update public.worksite_aliases
  set worksite_id = sustainability_id,
      updated_at = now()
  where worksite_id = sustainability_team_id;

  update public.worksite_resolution_queue
  set resolved_worksite_id = sustainability_id,
      updated_at = now()
  where resolved_worksite_id = sustainability_team_id;

  update public.postings
  set worksite_id = literature_equipment_id,
      updated_at = now()
  where id in (7570, 7641)
    and worksite_id = literature_admin_id
    and deleted_at is null;

  update public.worksites
  set address = null,
      updated_at = now()
  where id = literature_admin_id;

  update public.postings
  set worksite_id = admissions_id,
      updated_at = now()
  where worksite_id = admissions_management_id;

  update public.reviews
  set worksite_id = admissions_id,
      updated_at = now()
  where worksite_id = admissions_management_id;

  update public.worksite_aliases
  set worksite_id = admissions_id,
      updated_at = now()
  where worksite_id = admissions_management_id;

  update public.worksite_resolution_queue
  set resolved_worksite_id = admissions_id,
      updated_at = now()
  where resolved_worksite_id = admissions_management_id;

  update public.worksites
  set workplace_name = '지속가능원',
      normalized_name = '지속가능원',
      address = '중앙광장 B113호',
      updated_at = now()
  where id = sustainability_id;

  update public.worksites
  set workplace_name = '입학처',
      normalized_name = '입학처',
      address = '라이시움 1·2층',
      updated_at = now()
  where id = admissions_id;

  update public.worksites
  set workplace_name = '크림슨창업지원단',
      normalized_name = '크림슨창업지원단',
      address = '파이빌99 A401호',
      updated_at = now()
  where id = startup_id;

  update public.worksites
  set deleted_at = now(),
      updated_at = now()
  where id in (sustainability_team_id, admissions_management_id)
    and deleted_at is null;

  insert into public.worksite_aliases (
    university_id,
    source,
    alias_name,
    normalized_alias,
    worksite_id,
    resolution_method
  )
  values
    (
      1, '*',
      '지속가능경영팀',
      '지속가능원',
      sustainability_id,
      'confirmed_rule'
    ),
    (
      1, '*',
      '인재발굴처·입학전형관리팀',
      '입학처',
      admissions_id,
      'confirmed_rule'
    ),
    (
      1, '*',
      '창업지원팀·크림슨창업지원단 행정실',
      '크림슨창업지원단',
      startup_id,
      'confirmed_rule'
    )
  on conflict (university_id, source, normalized_alias)
  do update
  set alias_name = excluded.alias_name,
      worksite_id = excluded.worksite_id,
      resolution_method = excluded.resolution_method,
      updated_at = now();

  if (
    select count(*) from public.postings
    where worksite_id = sustainability_id and deleted_at is null
  ) <> 3 then
    raise exception '지속가능원 최종 공고 수 검증 실패';
  end if;

  if (
    select count(*) from public.postings
    where worksite_id = literature_equipment_id and deleted_at is null
  ) <> 2 then
    raise exception '문과대학 서관 기자재실 최종 공고 수 검증 실패';
  end if;

  if (
    select count(*) from public.postings
    where worksite_id = admissions_id and deleted_at is null
  ) <> 3 then
    raise exception '입학처 최종 공고 수 검증 실패';
  end if;

  if (
    select count(*) from public.postings
    where worksite_id = startup_id and deleted_at is null
  ) <> 4 then
    raise exception '크림슨창업지원단 최종 공고 수 검증 실패';
  end if;

  if exists (
    select 1 from public.postings
    where worksite_id in (sustainability_team_id, admissions_management_id)
  ) or exists (
    select 1 from public.reviews
    where worksite_id in (sustainability_team_id, admissions_management_id)
  ) or exists (
    select 1 from public.worksite_aliases
    where worksite_id in (sustainability_team_id, admissions_management_id)
  ) or exists (
    select 1 from public.worksite_resolution_queue
    where resolved_worksite_id in (sustainability_team_id, admissions_management_id)
  ) then
    raise exception '병합 후 비활성 근무지에 참조가 남았습니다';
  end if;
end
$$;

commit;
