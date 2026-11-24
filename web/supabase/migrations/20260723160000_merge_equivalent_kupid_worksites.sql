-- KUPID 공고에서 상위 조직명·행정실/행정팀 표기만 달랐던 동일 근무지를 통합한다.
-- 기존 공고와 리뷰는 대표 근무지로 옮기고, 원래 근무지는 soft delete한다.
begin;

do $$
declare
  review_conflicts integer;
begin
  with worksite_map(source_id, target_id) as (
    values
      (6756, 6874), (6773, 6880), (6818, 6885), (6899, 6897), (6776, 6896),
      (6801, 6802), (6766, 6767), (6889, 6764), (6894, 6799), (6757, 6758),
      (6777, 6778), (6825, 6826), (6792, 6793), (6795, 6796), (6821, 6822),
      (6830, 6831), (6853, 6854)
  )
  select count(*) into review_conflicts
  from reviews source_review
  join worksite_map map on map.source_id = source_review.worksite_id
  join reviews target_review
    on target_review.worksite_id = map.target_id
   and target_review.user_id is not distinct from source_review.user_id
   and target_review.work_year = source_review.work_year
   and target_review.work_semester = source_review.work_semester;

  if review_conflicts > 0 then
    raise exception 'worksite merge aborted: % duplicate review key(s)', review_conflicts;
  end if;
end $$;

with worksite_map(source_id, target_id) as (
  values
    (6756, 6874), (6773, 6880), (6818, 6885), (6899, 6897), (6776, 6896),
    (6801, 6802), (6766, 6767), (6889, 6764), (6894, 6799), (6757, 6758),
    (6777, 6778), (6825, 6826), (6792, 6793), (6795, 6796), (6821, 6822),
    (6830, 6831), (6853, 6854)
)
update postings posting
set worksite_id = map.target_id,
    updated_at = now()
from worksite_map map
where posting.worksite_id = map.source_id;

with worksite_map(source_id, target_id) as (
  values
    (6756, 6874), (6773, 6880), (6818, 6885), (6899, 6897), (6776, 6896),
    (6801, 6802), (6766, 6767), (6889, 6764), (6894, 6799), (6757, 6758),
    (6777, 6778), (6825, 6826), (6792, 6793), (6795, 6796), (6821, 6822),
    (6830, 6831), (6853, 6854)
)
update reviews review
set worksite_id = map.target_id
from worksite_map map
where review.worksite_id = map.source_id;

with worksite_map(source_id) as (
  values
    (6756), (6773), (6818), (6899), (6776),
    (6801), (6766), (6889), (6894), (6757),
    (6777), (6825), (6792), (6795), (6821), (6830), (6853)
)
update worksites source
set deleted_at = now(),
    updated_at = now()
from worksite_map map
where source.id = map.source_id
  and source.deleted_at is null;

-- 대표 근무지는 기존의 짧은 표기와 같은 normalized_name을 사용한다.
-- 이로써 긴 상위 조직명 표기가 다음 적재에서 새 근무지로 분리되지 않는다.
with normalized_alias(source_id, target_id) as (
  values
    (6756, 6874), (6773, 6880), (6818, 6885), (6899, 6897), (6776, 6896)
)
update worksites target
set normalized_name = source.normalized_name,
    updated_at = now()
from normalized_alias alias
join worksites source on source.id = alias.source_id
where target.id = alias.target_id;

commit;
