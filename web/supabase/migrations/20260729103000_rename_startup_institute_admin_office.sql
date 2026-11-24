-- The latest SSC notice names the actual workplace as the Startup Institute
-- administrative office. Preserve that explicit suffix instead of applying a
-- blanket administrative-office-to-team rewrite.

begin;

do $$
declare
  canonical_id integer;
  posting_count integer;
begin
  select id
    into strict canonical_id
  from public.worksites
  where university_id = 1
    and type = 'school'
    and workplace_name = '경영대학 스타트업연구원'
    and deleted_at is null;

  if exists (
    select 1
    from public.worksites
    where university_id = 1
      and type = 'school'
      and workplace_name = '스타트업연구원 행정실'
      and deleted_at is null
  ) then
    raise exception
      '스타트업연구원 행정실 대표명 변경 중단: 별도 활성 근무지가 이미 존재함';
  end if;

  select count(*)
    into posting_count
  from public.postings
  where worksite_id = canonical_id
    and deleted_at is null;

  if posting_count <> 3 then
    raise exception
      '스타트업연구원 행정실 대표명 변경 중단: 연결 공고가 %건입니다(기대 3건).',
      posting_count;
  end if;

  update public.worksites
  set workplace_name = '스타트업연구원 행정실',
      normalized_name = '스타트업연구원 행정실',
      address = '경영본관 2층 202호',
      updated_at = now()
  where id = canonical_id;

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
    '경영대학 스타트업연구원·스타트업 연구원 행정실',
    '스타트업연구원 행정실',
    canonical_id,
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
    from public.worksites
    where id = canonical_id
      and workplace_name = '스타트업연구원 행정실'
      and normalized_name = '스타트업연구원 행정실'
      and address = '경영본관 2층 202호'
      and deleted_at is null
  ) <> 1 then
    raise exception '스타트업연구원 행정실 대표 근무지 검증 실패';
  end if;
end
$$;

commit;
