-- organization_name에 이미 고려대학교가 있으므로 학교근무지 표시명의
-- 중복 학교명 접두어를 제거한다. normalized_name은 이미 접두어가 제거된
-- 상태이므로 변경하지 않는다.

begin;

do $$
declare
  target_count integer;
begin
  select count(*) into target_count
  from public.worksites
  where university_id = 1
    and type = 'school'
    and deleted_at is null
    and (
      workplace_name like '고려대학교%'
      or workplace_name like '고려대%'
    );

  if target_count <> 6 then
    raise exception '학교명 접두어 제거 대상 %건(기대 6건)', target_count;
  end if;
end
$$;

update public.worksites
set workplace_name = case
      when workplace_name like '고려대학교(본교)%'
        then btrim(substr(workplace_name, length('고려대학교(본교)') + 1))
      when workplace_name like '고려대학교%'
        then btrim(substr(workplace_name, length('고려대학교') + 1))
      when workplace_name like '고려대%'
        then btrim(substr(workplace_name, length('고려대') + 1))
      else workplace_name
    end,
    updated_at = now()
where university_id = 1
  and type = 'school'
  and deleted_at is null
  and (
    workplace_name like '고려대학교%'
    or workplace_name like '고려대%'
  );

do $$
begin
  if exists (
    select 1
    from public.worksites
    where university_id = 1
      and type = 'school'
      and deleted_at is null
      and (
        workplace_name = ''
        or workplace_name like '고려대학교%'
        or workplace_name like '고려대%'
      )
  ) then
    raise exception '학교명 접두어 제거 후 표시명 검증 실패';
  end if;
end
$$;

commit;
