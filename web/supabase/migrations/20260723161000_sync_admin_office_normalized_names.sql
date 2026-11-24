-- 행정실/행정팀 정규화 규칙을 적용한 뒤, 짝이 없는 행정실 근무지도
-- 다음 적재에서 같은 이름으로 다시 생성되지 않도록 normalized_name을 동기화한다.
begin;

update worksites
set normalized_name = regexp_replace(normalized_name, '행정실$', '행정팀'),
    updated_at = now()
where type = 'school'
  and deleted_at is null
  and normalized_name like '%행정실';

commit;
