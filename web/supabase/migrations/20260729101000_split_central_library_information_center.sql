-- Split the Central Library Information Center from the broader Central
-- Library worksite. These seven SSC notices consistently name the information
-- center in both the title and body.

begin;

insert into worksites (
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
  '중앙도서관 인포메이션센터',
  '중앙도서관 인포메이션센터',
  null,
  '중앙도서관(신관) 인포메이션센터'
where not exists (
  select 1
  from worksites
  where university_id = 1
    and type = 'school'
    and workplace_name = '중앙도서관 인포메이션센터'
    and deleted_at is null
);

do $$
declare
  central_library_id integer;
  information_center_id integer;
  candidate_count integer;
begin
  select id
    into strict central_library_id
  from worksites
  where university_id = 1
    and type = 'school'
    and workplace_name = '중앙도서관'
    and deleted_at is null;

  select id
    into strict information_center_id
  from worksites
  where university_id = 1
    and type = 'school'
    and workplace_name = '중앙도서관 인포메이션센터'
    and deleted_at is null;

  select count(*)
    into candidate_count
  from postings
  where id in (7194, 7196, 7204, 7206, 7210, 7223, 7246)
    and source = 'ssc'
    and deleted_at is null
    and worksite_id in (central_library_id, information_center_id)
    and (
      raw_text like '%인포메이션센터%'
      or raw_text like '%인포메이션 센터%'
    );

  if candidate_count <> 7 then
    raise exception
      '중앙도서관 인포메이션센터 분리 중단: 검증된 후보가 %건입니다(기대 7건).',
      candidate_count;
  end if;

  update postings
  set worksite_id = information_center_id,
      updated_at = now()
  where id in (7194, 7196, 7204, 7206, 7210, 7223, 7246)
    and source = 'ssc'
    and deleted_at is null
    and worksite_id = central_library_id;

  select count(*)
    into candidate_count
  from postings
  where id in (7194, 7196, 7204, 7206, 7210, 7223, 7246)
    and deleted_at is null
    and worksite_id = information_center_id;

  if candidate_count <> 7 then
    raise exception
      '중앙도서관 인포메이션센터 분리 후 검증 실패: 대상 공고가 %건입니다(기대 7건).',
      candidate_count;
  end if;
end $$;

commit;
