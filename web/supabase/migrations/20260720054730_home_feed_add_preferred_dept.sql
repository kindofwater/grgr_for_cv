-- 목적: get_home_feed 카드에 preferred_dept·preferred_college 추가 — 히어로 '추천 이유' 배지용
-- 날짜: 2026-07-20 · 담당: 배경록
-- 비고: 직전 20260720054341에서 누락. 홈의 recReasons()가 preferred_dept로 "🎓 내 학과 맞춤"을
--   판단하는데 카드에 없어 배지가 영영 안 뜬다. 시그니처·리턴타입(jsonb) 불변이라
--   create or replace로 충분(DROP 불필요, grant도 유지된다).
--   ⚠️ 본문은 20260720054341 전체 복사 + carded의 jsonb_build_object에 2줄 추가가 전부다.
--   (rep CTE는 이미 두 컬럼을 뽑고 있었고 joined에서만 안 실어보내고 있었음)

create or replace function get_home_feed(
  p_types   text[]    default null,   -- ['national'] | ['school'] | null=전체
  p_actives boolean[] default null    -- [true]=모집중만 | [false]=완료만 | null=전체
)
returns jsonb
language sql
security definer
set search_path = public
as $$
with
me as (
  select u.university_id, u.degree_program::text as degree, u.academic_status::text as status,
         u.grade, u.track, c.name as college, d.name as department, u.region
  from users u
  left join colleges    c on c.id = u.college_id
  left join departments d on d.id = u.department_id
  where u.id = auth.uid()
),
rep as (
  select distinct on (p.worksite_id)
    p.worksite_id, p.preferred_track, p.preferred_college, p.preferred_dept,
    p.min_grade, p.eligible_degree, p.eligible_status, p.work_duration_type
  from postings p
  where p.deleted_at is null
  order by p.worksite_id, p.is_active desc, p.created_at desc
),
ws_active as (
  select p.worksite_id,
         bool_or(
           case when p.recruit_until is not null
                then p.recruit_until >= (now() at time zone 'Asia/Seoul')::date
                else coalesce(p.is_active, false)
           end
         ) as is_active
  from postings p
  where p.deleted_at is null
  group by p.worksite_id
),
stats as (
  select worksite_id,
         count(*) as review_count,
         round(avg(score_recommend)::numeric, 1) as avg_score
  from reviews
  where deleted_at is null and not is_blinded
  group by worksite_id
),
joined as (
  select
    w.id as worksite_id, w.organization_name, w.workplace_name, w.region,
    w.type, w.location_type, w.view_count,
    coalesce(a.is_active, false) as is_active,
    r.preferred_track, r.preferred_college, r.preferred_dept,
    r.work_duration_type, r.eligible_degree, r.eligible_status,
    coalesce(s.review_count, 0) as review_count,
    s.avg_score,
    (
      m.university_id is null
      or (
            not (m.degree = 'undergrad' and r.eligible_degree = 1)
        and not (m.degree = 'graduate'  and r.eligible_degree = 0)
        and not (m.status = 'enrolled'  and r.eligible_status = 1)
        and not (m.status = 'leave'     and r.eligible_status = 0)
        and not (r.min_grade is not null and m.grade < r.min_grade)
        and not (r.preferred_track   is not null and r.preferred_track   <> '' and r.preferred_track   is distinct from m.track)
        and not (r.preferred_college is not null and r.preferred_college <> '' and r.preferred_college is distinct from m.college)
        and not (r.preferred_dept    is not null and r.preferred_dept    <> '' and r.preferred_dept    is distinct from m.department)
        and not (w.region            is not null and w.region            <> '' and w.region            is distinct from m.region)
      )
    ) as eligible,
    (
        case when r.preferred_dept    is not null and r.preferred_dept    = m.department then 3 else 0 end
      + case when r.preferred_college is not null and r.preferred_college = m.college    then 2 else 0 end
      + case when r.preferred_track   is not null and r.preferred_track   = m.track      then 2 else 0 end
      + case when w.region            is not null and w.region            = m.region     then 1 else 0 end
    ) as match_score
  from worksites w
  join rep r            on r.worksite_id = w.id
  left join ws_active a on a.worksite_id = w.id
  left join stats s     on s.worksite_id = w.id
  left join me m        on true
  where w.deleted_at is null
    and ( auth.uid() is null
          or w.university_id = 0
          or w.university_id = (select university_id from me) )
),
carded as (
  select j.*, jsonb_build_object(
    'worksite_id',        j.worksite_id,
    'organization_name',  j.organization_name,
    'workplace_name',     j.workplace_name,
    'region',             j.region,
    'type',               j.type,
    'location_type',      j.location_type,
    'view_count',         j.view_count,
    'is_active',          j.is_active,
    'preferred_track',    j.preferred_track,
    'preferred_college',  j.preferred_college,   -- 추가
    'preferred_dept',     j.preferred_dept,      -- 추가: recReasons "내 학과 맞춤" 배지
    'work_duration_type', j.work_duration_type,
    'eligible_degree',    j.eligible_degree,
    'eligible_status',    j.eligible_status,
    'review_count',       j.review_count,
    'avg_score',          j.avg_score
  ) as card
  from joined j
),
filtered as (
  select * from carded
  where (p_types   is null or type      = any(p_types::worksite_type_e[]))
    and (p_actives is null or is_active = any(p_actives))
)
select jsonb_build_object(
  'hero', (
    select card from carded
    order by is_active desc, eligible desc, match_score desc, avg_score desc nulls last, worksite_id
    limit 1
  ),
  'top_score', coalesce((
    select jsonb_agg(t.card order by t.avg_score desc nulls last, t.review_count desc, t.worksite_id)
    from (select * from filtered order by avg_score desc nulls last, review_count desc, worksite_id limit 10) t
  ), '[]'::jsonb),
  'popular', coalesce((
    select jsonb_agg(t.card order by t.view_count desc nulls last, t.worksite_id)
    from (select * from filtered order by view_count desc nulls last, worksite_id limit 10) t
  ), '[]'::jsonb),
  'most_reviewed', coalesce((
    select jsonb_agg(t.card order by t.review_count desc, t.avg_score desc nulls last, t.worksite_id)
    from (select * from filtered order by review_count desc, avg_score desc nulls last, worksite_id limit 10) t
  ), '[]'::jsonb)
);
$$;
