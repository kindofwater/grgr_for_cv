begin;

do $$
declare
  v_worksite_id integer;
  v_posting_count integer;
begin
  select id
    into strict v_worksite_id
    from public.worksites
   where university_id = 1
     and type = 'school'
     and deleted_at is null
     and workplace_name = '사범대학행정팀';

  if exists (
    select 1
      from public.worksites
     where university_id = 1
       and type = 'school'
       and deleted_at is null
       and workplace_name = '사범대학행정실'
  ) then
    raise exception 'active 사범대학행정실 worksite already exists';
  end if;

  select count(*)
    into v_posting_count
    from public.postings
   where deleted_at is null
     and worksite_id = v_worksite_id;

  if v_posting_count <> 5 then
    raise exception
      'expected 5 active teacher-college postings, found %',
      v_posting_count;
  end if;

  update public.worksites
     set workplace_name = '사범대학행정실',
         normalized_name = '사범대학행정실',
         address = '운초우선교육관 401호',
         updated_at = now()
   where id = v_worksite_id;

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
    '사범대학행정팀·사범대학 행정팀·사범대행정팀·사범대행정실·사범대학 행정실',
    '사범대학행정실',
    v_worksite_id,
    'confirmed_rule'
  )
  on conflict (university_id, source, normalized_alias)
  do update
     set alias_name = excluded.alias_name,
         worksite_id = excluded.worksite_id,
         resolution_method = excluded.resolution_method,
         updated_at = now();

  if not exists (
    select 1
      from public.worksites
     where id = v_worksite_id
       and deleted_at is null
       and workplace_name = '사범대학행정실'
       and normalized_name = '사범대학행정실'
       and address = '운초우선교육관 401호'
  ) then
    raise exception 'teacher-college worksite rename verification failed';
  end if;
end
$$;

commit;
