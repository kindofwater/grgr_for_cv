-- Split the repeated interlibrary-loan assignment from the broad Central
-- Library worksite. "Interlibrary loan room" and "Interlibrary Loan Center
-- inside Reading Room 2" identify the same workplace.

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
  '중앙도서관 상호대차센터',
  '중앙도서관 상호대차센터',
  null,
  '중앙도서관 3층 제2자료실 내 상호대차센터'
where not exists (
  select 1
  from public.worksites
  where university_id = 1
    and type = 'school'
    and workplace_name = '중앙도서관 상호대차센터'
    and deleted_at is null
);

do $$
declare
  central_library_id integer;
  interlibrary_loan_id integer;
  candidate_count integer;
begin
  select id
    into strict central_library_id
  from public.worksites
  where university_id = 1
    and type = 'school'
    and workplace_name = '중앙도서관'
    and deleted_at is null;

  select id
    into strict interlibrary_loan_id
  from public.worksites
  where university_id = 1
    and type = 'school'
    and workplace_name = '중앙도서관 상호대차센터'
    and deleted_at is null;

  select count(*)
    into candidate_count
  from public.postings
  where id in (7200, 7234)
    and source = 'ssc'
    and deleted_at is null
    and worksite_id in (central_library_id, interlibrary_loan_id)
    and raw_text like '%상호대차%'
    and raw_text like '%제2자료실%';

  if candidate_count <> 2 then
    raise exception
      '중앙도서관 상호대차센터 분리 중단: 검증된 후보가 %건입니다(기대 2건).',
      candidate_count;
  end if;

  update public.postings
  set worksite_id = interlibrary_loan_id,
      updated_at = now()
  where id in (7200, 7234)
    and source = 'ssc'
    and deleted_at is null
    and worksite_id = central_library_id;

  insert into public.worksite_aliases (
    university_id,
    source,
    alias_name,
    normalized_alias,
    worksite_id,
    resolution_method
  )
  values (
    1,
    '*',
    '중앙도서관 상호대차실·제2자료실 내 상호대차센터',
    '중앙도서관 상호대차센터',
    interlibrary_loan_id,
    'confirmed_rule'
  )
  on conflict (university_id, source, normalized_alias)
  do update
  set alias_name = excluded.alias_name,
      worksite_id = excluded.worksite_id,
      resolution_method = excluded.resolution_method,
      updated_at = now();

  select count(*)
    into candidate_count
  from public.postings
  where id in (7200, 7234)
    and deleted_at is null
    and worksite_id = interlibrary_loan_id;

  if candidate_count <> 2 then
    raise exception
      '중앙도서관 상호대차센터 분리 후 검증 실패: 대상 공고가 %건입니다(기대 2건).',
      candidate_count;
  end if;
end
$$;

commit;
