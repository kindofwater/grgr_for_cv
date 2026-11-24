-- Use the current public-facing institute name for the single social
-- contribution worksite at Central Plaza B113. Historical support
-- division/team labels and KUSSO/KUSR/KUIS acronym variants remain aliases.

begin;

do $$
declare
  canonical_id integer;
  posting_count integer;
  conflicting_alias_count integer;
begin
  select id
    into strict canonical_id
  from public.worksites
  where university_id = 1
    and type = 'school'
    and workplace_name = '사회공헌지원팀'
    and deleted_at is null;

  if exists (
    select 1
    from public.worksites
    where university_id = 1
      and type = 'school'
      and workplace_name = '사회공헌원'
      and deleted_at is null
  ) then
    raise exception '사회공헌원 대표명 변경 중단: 별도 활성 근무지가 이미 존재함';
  end if;

  select count(*)
    into posting_count
  from public.postings
  where worksite_id = canonical_id
    and deleted_at is null;

  if posting_count <> 5 then
    raise exception
      '사회공헌원 대표명 변경 중단: 연결 공고가 %건입니다(기대 5건).',
      posting_count;
  end if;

  select count(*)
    into conflicting_alias_count
  from public.worksite_aliases
  where university_id = 1
    and source = '*'
    and normalized_alias = '사회공헌원'
    and worksite_id <> canonical_id;

  if conflicting_alias_count <> 0 then
    raise exception
      '사회공헌원 대표명 변경 중단: 다른 근무지를 가리키는 별칭이 %건 있음',
      conflicting_alias_count;
  end if;

  update public.worksites
  set workplace_name = '사회공헌원',
      normalized_name = '사회공헌원',
      address = '중앙광장 B113호',
      updated_at = now()
  where id = canonical_id;

  update public.worksite_aliases
  set alias_name = '사회공헌지원부·사회공헌지원팀·사회공헌원(KUSSO/KUSR/KUIS)',
      normalized_alias = '사회공헌원',
      worksite_id = canonical_id,
      resolution_method = 'confirmed_rule',
      updated_at = now()
  where university_id = 1
    and source = '*'
    and normalized_alias = '사회공헌지원팀';

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
    '사회공헌지원부·사회공헌지원팀·사회공헌원(KUSSO/KUSR/KUIS)',
    '사회공헌원',
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
    where university_id = 1
      and type = 'school'
      and workplace_name = '사회공헌원'
      and normalized_name = '사회공헌원'
      and deleted_at is null
  ) <> 1 then
    raise exception '사회공헌원 대표 근무지 검증 실패';
  end if;
end
$$;

commit;
