-- Purpose: Require home hero recommendations to have avg recommendation score >= 4.0.
-- Date: 2026-07-21 · Owner: Codex
-- Note: Bottom shelves keep their existing rankings. This only gates the personalized hero card.

create or replace function get_home_feed(
  p_types   text[]    default null,
  p_actives boolean[] default null
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
    'preferred_college',  j.preferred_college,
    'preferred_dept',     j.preferred_dept,
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
),
hero_candidates as (
  select * from carded
  where avg_score >= 4.0
)
select jsonb_build_object(
  'hero', (
    select card from hero_candidates
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

grant execute on function get_home_feed(text[], boolean[]) to authenticated, anon;
