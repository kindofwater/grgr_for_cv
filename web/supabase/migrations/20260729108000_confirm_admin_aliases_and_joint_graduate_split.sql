-- Confirm three office/team labels as the same workplaces, while restoring
-- the explicitly separate joint graduate-school administrative team posting.

begin;

do $$
declare
  anam_id integer;
  liberal_id integer;
  foreign_id integer;
  political_id integer;
  joint_graduate_id integer;
  posting_count integer;
begin
  select id into strict anam_id
  from public.worksites
  where university_id = 1
    and type = 'school'
    and workplace_name = '안암학사행정팀'
    and deleted_at is null;

  select id into strict liberal_id
  from public.worksites
  where university_id = 1
    and type = 'school'
    and workplace_name = '자유전공학부행정팀'
    and deleted_at is null;

  select id into strict foreign_id
  from public.worksites
  where university_id = 1
    and type = 'school'
    and workplace_name = '외국어센터행정팀'
    and deleted_at is null;

  select id into strict political_id
  from public.worksites
  where university_id = 1
    and type = 'school'
    and workplace_name = '정경대학행정팀'
    and deleted_at is null;

  select id into strict joint_graduate_id
  from public.worksites
  where university_id = 1
    and type = 'school'
    and workplace_name = '정책대학원·융합데이터과학대학원 행정팀'
    and address = 'SK미래관 515호'
    and deleted_at is null;

  select count(*) into posting_count
  from public.postings
  where worksite_id = anam_id
    and deleted_at is null;
  if posting_count <> 6 then
    raise exception '안암학사행정팀 공고 검증 실패: %건(기대 6건)', posting_count;
  end if;

  select count(*) into posting_count
  from public.postings
  where worksite_id = liberal_id
    and deleted_at is null;
  if posting_count <> 3 then
    raise exception '자유전공학부행정팀 공고 검증 실패: %건(기대 3건)', posting_count;
  end if;

  select count(*) into posting_count
  from public.postings
  where worksite_id = foreign_id
    and deleted_at is null;
  if posting_count <> 3 then
    raise exception '외국어센터행정팀 공고 검증 실패: %건(기대 3건)', posting_count;
  end if;

  if not exists (
    select 1
    from public.postings
    where id = 7293
      and source = 'kupid'
      and external_id = 'e21318ff4be033f7'
      and worksite_id = political_id
      and deleted_at is null
  ) then
    raise exception '분리할 정책대학원·융합데이터과학대학원 공고를 찾지 못했습니다';
  end if;

  if exists (
    select 1
    from public.postings
    where worksite_id = joint_graduate_id
      and deleted_at is null
  ) then
    raise exception '분리 대상 근무지에 예상하지 못한 기존 공고가 있습니다';
  end if;

  update public.postings
  set worksite_id = joint_graduate_id,
      updated_at = now()
  where id = 7293
    and source = 'kupid'
    and external_id = 'e21318ff4be033f7'
    and worksite_id = political_id
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
      1,
      '*',
      '안암학사행정실·안암학사 행정실',
      '안암학사행정팀',
      anam_id,
      'confirmed_rule'
    ),
    (
      1,
      '*',
      '자유전공학부행정실·자유전공학부 행정실',
      '자유전공학부행정팀',
      liberal_id,
      'confirmed_rule'
    ),
    (
      1,
      '*',
      '외국어센터행정실·외국어센터 행정실',
      '외국어센터행정팀',
      foreign_id,
      'confirmed_rule'
    )
  on conflict (university_id, source, normalized_alias)
  do update
  set alias_name = excluded.alias_name,
      worksite_id = excluded.worksite_id,
      resolution_method = excluded.resolution_method,
      updated_at = now();

  if (
    select count(*)
    from public.postings
    where worksite_id = joint_graduate_id
      and deleted_at is null
  ) <> 1 then
    raise exception '정책대학원·융합데이터과학대학원 공고 분리 검증 실패';
  end if;

  if exists (
    select 1
    from public.postings
    where id = 7293
      and worksite_id = political_id
      and deleted_at is null
  ) then
    raise exception '정책대학원·융합데이터과학대학원 공고가 정경대학에 남았습니다';
  end if;
end
$$;

commit;
