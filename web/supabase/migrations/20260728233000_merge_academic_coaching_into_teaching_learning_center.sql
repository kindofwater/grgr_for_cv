-- SK미래관 학업코칭 공고의 과거 교수학습개발원/교수학습지원팀을
-- 현재 학부대학 교수학습지원센터로 통합한다.
-- 원격수업 공고는 별도 원격교육센터에 연결되어 있어 이 병합에 포함하지 않는다.

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
    and workplace_name = '교수학습지원센터'
    and deleted_at is null;

  select coalesce(array_agg(id), '{}'::integer[]) into duplicate_ids
  from public.worksites
  where university_id = 1
    and type = 'school'
    and workplace_name in ('교수학습개발원', '교수학습지원팀')
    and deleted_at is null;

  if exists (
    select 1
    from public.postings
    where worksite_id = any(duplicate_ids)
      and deleted_at is null
      and coalesce(raw_text, '') not like '%학업코칭%'
  ) then
    raise exception '학업코칭 외 공고가 포함되어 교수학습 조직을 자동 병합할 수 없음';
  end if;

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
    raise exception '교수학습 학업코칭 근무지 병합 시 중복 리뷰가 발생함';
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
  set workplace_name = '교수학습지원센터',
      normalized_name = '교수학습지원센터',
      address = '미디어관 11층 1101호',
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
    '교수학습개발원·교수학습지원팀',
    '교수학습지원센터',
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
    raise exception '교수학습 학업코칭 근무지 병합 후 참조가 남아 있음';
  end if;

  if (
    select count(*)
    from public.worksites
    where university_id = 1
      and type = 'school'
      and workplace_name in (
        '교수학습개발원',
        '교수학습지원팀',
        '교수학습지원센터'
      )
      and deleted_at is null
  ) <> 1 then
    raise exception '교수학습지원센터 정본 검증 실패';
  end if;
end
$$;

commit;
