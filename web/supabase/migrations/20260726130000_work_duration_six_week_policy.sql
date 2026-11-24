-- 목적: 학교근장 장기/단기를 6주(42일) 기준으로 보정
-- 정책: 42일 미만=short, 42일 이상=long. 여러 기간 선택지는 가장 긴 기간 기준.
-- 국가근장은 기존 정책대로 전부 long을 유지한다.

-- 기간을 'N주'로 명시한 공고는 가장 큰 N을 기준으로 일괄 보정한다.
with week_durations as (
  select p.id, max((m.value)[1]::int) as max_weeks
  from postings p
  cross join lateral regexp_matches(
    coalesce(p.work_period_text, ''),
    '([0-9]+)[[:space:]]*주',
    'g'
  ) as m(value)
  join worksites w on w.id = p.worksite_id
  where p.deleted_at is null
    and w.deleted_at is null
    and w.type = 'school'
  group by p.id
)
update postings p
set work_duration_type = case
  when d.max_weeks >= 6 then 'long'::duration_type_e
  else 'short'::duration_type_e
end
from week_durations d
where p.id = d.id
  and p.work_duration_type is distinct from case
    when d.max_weeks >= 6 then 'long'::duration_type_e
    else 'short'::duration_type_e
  end;

-- 현재 대표공고 감사에서 확인된 날짜 범위형 6주 미만 공고 2건.
update postings p
set work_duration_type = 'short'
from worksites w
where w.id = p.worksite_id
  and w.type = 'school'
  and p.deleted_at is null
  and w.deleted_at is null
  and p.work_duration_type <> 'short'
  and (
    p.work_period_text = '7/29~8/14 (연수 기간 외 준비 및 정리로 전/후 3일 간 출근 가능)'
    or p.work_period_text = '2026년 7월 5일 ~ 8월 1일'
  );

-- 방어: 국가근장은 이 정책 변경과 관계없이 학기 단위 장기로 유지한다.
update postings p
set work_duration_type = 'long'
from worksites w
where w.id = p.worksite_id
  and w.type = 'national'
  and p.deleted_at is null
  and w.deleted_at is null
  and p.work_duration_type <> 'long';
