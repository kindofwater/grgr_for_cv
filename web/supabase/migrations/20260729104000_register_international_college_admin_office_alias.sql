-- International College used "administrative office" through 2025 and
-- "administrative team" in its latest 2026 notice. The address, office phone,
-- and duties are unchanged, so retain the latest team name and register the
-- older office label as a confirmed alias.

begin;

do $$
declare
  canonical_id integer;
  verified_posting_count integer;
begin
  select id
    into strict canonical_id
  from public.worksites
  where university_id = 1
    and type = 'school'
    and workplace_name = '국제대학행정팀'
    and deleted_at is null;

  select count(*)
    into verified_posting_count
  from public.postings
  where id in (
    7228, 7273, 7475, 7476, 7499,
    7507, 7508, 7563, 7610, 7652
  )
    and worksite_id = canonical_id
    and deleted_at is null;

  if verified_posting_count <> 10 then
    raise exception
      '국제대학 행정실 별칭 등록 중단: 검증 공고가 %건입니다(기대 10건).',
      verified_posting_count;
  end if;

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
    '국제학부행정실·국제학부행정팀·국제대학 행정실',
    '국제대학행정팀',
    canonical_id,
    'confirmed_rule'
  )
  on conflict (university_id, source, normalized_alias)
  do update
  set alias_name = excluded.alias_name,
      worksite_id = excluded.worksite_id,
      resolution_method = excluded.resolution_method,
      updated_at = now();
end
$$;

commit;
