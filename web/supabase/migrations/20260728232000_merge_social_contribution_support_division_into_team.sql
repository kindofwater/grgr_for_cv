-- 사회공헌원 중앙광장 B113호의 과거 사회공헌지원부를
-- 최신 공고 명칭인 사회공헌지원팀으로 통합한다.

begin;

do $$
declare
  canonical_id integer;
  duplicate_ids integer[];
begin
  select id into strict canonical_id
  from public.worksites
  where university_id = 1
    and type = 'school'
    and workplace_name = '사회공헌지원팀'
    and deleted_at is null;

  select coalesce(array_agg(id), '{}'::integer[]) into duplicate_ids
  from public.worksites
  where university_id = 1
    and type = 'school'
    and workplace_name = '사회공헌지원부'
    and deleted_at is null;

  if exists (
    select 1
    from public.reviews old_review
    join public.reviews current_review
      on current_review.worksite_id = canonical_id
     and current_review.user_id = old_review.user_id
     and current_review.work_year = old_review.work_year
     and current_review.work_semester = old_review.work_semester
    where old_review.worksite_id = any(duplicate_ids)
  ) then
    raise exception '사회공헌지원부 근무지 병합 시 중복 리뷰가 발생함';
  end if;

  update public.postings
  set worksite_id = canonical_id,
      updated_at = now()
  where worksite_id = any(duplicate_ids);

  update public.reviews
  set worksite_id = canonical_id,
      updated_at = now()
  where worksite_id = any(duplicate_ids);

  update public.worksite_aliases
  set worksite_id = canonical_id,
      updated_at = now()
  where worksite_id = any(duplicate_ids);

  update public.worksite_resolution_queue
  set resolved_worksite_id = canonical_id,
      updated_at = now()
  where resolved_worksite_id = any(duplicate_ids);

  update public.worksites
  set workplace_name = '사회공헌지원팀',
      normalized_name = '사회공헌지원팀',
      address = '사회공헌원 중앙광장 B113호',
      updated_at = now()
  where id = canonical_id;

  update public.worksites
  set deleted_at = now(),
      updated_at = now()
  where id = any(duplicate_ids)
    and deleted_at is null;

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
    '사회공헌지원부',
    '사회공헌지원팀',
    canonical_id,
    'historical_name'
  )
  on conflict (university_id, source, normalized_alias)
  do update
  set alias_name = excluded.alias_name,
      worksite_id = excluded.worksite_id,
      resolution_method = excluded.resolution_method,
      updated_at = now();

  if exists (
    select 1
    from public.postings
    where worksite_id = any(duplicate_ids)
  ) or exists (
    select 1
    from public.reviews
    where worksite_id = any(duplicate_ids)
  ) or exists (
    select 1
    from public.worksite_aliases
    where worksite_id = any(duplicate_ids)
  ) or exists (
    select 1
    from public.worksite_resolution_queue
    where resolved_worksite_id = any(duplicate_ids)
  ) then
    raise exception '사회공헌지원부 근무지 병합 후 참조가 남아 있음';
  end if;

  if (
    select count(*)
    from public.worksites
    where university_id = 1
      and type = 'school'
      and workplace_name in ('사회공헌지원부', '사회공헌지원팀')
      and deleted_at is null
  ) <> 1 then
    raise exception '사회공헌지원팀 정본 검증 실패';
  end if;
end
$$;

commit;
