-- 대화로 검토·확정한 상위조직/하위조직 및 파트 표기를 정본 근무지에 연결한다.
-- normalized_alias는 수집 코드가 표기 차이를 정리한 뒤 조회하는 키다.

begin;

-- 현재 활성 행은 normalized_name만 짧고 표시명에는 상위 조직이 남아 있다.
-- 검토에서 확정한 표시 원칙에 맞춰 정본 행 자체도 짧게 만든다.
update public.worksites
set workplace_name = '국제교육팀',
    normalized_name = '국제교육팀',
    updated_at = now()
where university_id = 1
  and type = 'school'
  and workplace_name = '국제처 국제교육팀'
  and normalized_name = '국제교육팀'
  and deleted_at is null;

with confirmed(alias_name, normalized_alias, workplace_name) as (
  values
    (
      '교수학습개발원 원격교육센터·학부대학 원격교육센터',
      '원격교육센터',
      '원격교육센터'
    ),
    ('국제처 국제교류팀', '국제교류팀', '국제교류팀'),
    ('국제처 국제교육팀', '국제교육팀', '국제교육팀'),
    ('국제처 글로벌서비스센터', '글로벌서비스센터', '글로벌서비스센터'),
    ('학생지원팀 장학파트·학생파트', '학생지원팀', '학생지원팀')
)
insert into public.worksite_aliases (
  university_id,
  source,
  alias_name,
  normalized_alias,
  worksite_id,
  resolution_method
)
select
  1,
  '*',
  confirmed.alias_name,
  confirmed.normalized_alias,
  worksite.id,
  'confirmed_rule'
from confirmed
join public.worksites worksite
  on worksite.university_id = 1
 and worksite.type = 'school'
 and worksite.workplace_name = confirmed.workplace_name
 and worksite.deleted_at is null
on conflict (university_id, source, normalized_alias)
do update
set alias_name = excluded.alias_name,
    worksite_id = excluded.worksite_id,
    resolution_method = excluded.resolution_method,
    updated_at = now();

do $$
declare
  missing_count integer;
begin
  select count(*) into missing_count
  from (
    values
      ('원격교육센터'),
      ('국제교류팀'),
      ('국제교육팀'),
      ('글로벌서비스센터'),
      ('학생지원팀')
  ) expected(workplace_name)
  where not exists (
    select 1
    from public.worksites worksite
    where worksite.university_id = 1
      and worksite.type = 'school'
      and worksite.workplace_name = expected.workplace_name
      and worksite.deleted_at is null
  );

  if missing_count <> 0 then
    raise exception '확정 별칭 대상 정본 근무지 %개를 찾지 못함', missing_count;
  end if;
end
$$;

commit;
