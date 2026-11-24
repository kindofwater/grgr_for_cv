-- 목적: 평생교육원행정실의 과거 normalized_name을 현재 정규화 규칙과 동기화한다.
-- 날짜: 2026-07-30 · 담당: Codex

do $$
declare
  expected_worksite_id integer := 6845;
begin
  if exists (
    select 1
    from public.worksites
    where id = expected_worksite_id
      and university_id = 1
      and type = 'school'
      and workplace_name = '평생교육원행정실'
      and normalized_name = '평생교육원행정실'
      and deleted_at is null
  ) then
    -- 이미 올바른 상태면 변경하지 않는다.
    return;
  end if;

  update public.worksites
  set normalized_name = '평생교육원행정실',
      updated_at = now()
  where id = expected_worksite_id
    and university_id = 1
    and type = 'school'
    and workplace_name = '평생교육원행정실'
    and normalized_name = '평생교육원행정팀'
    and deleted_at is null;

  if not found then
    raise exception 'Expected active worksite % (평생교육원행정실) with legacy normalized_name was not found', expected_worksite_id;
  end if;
end
$$;
