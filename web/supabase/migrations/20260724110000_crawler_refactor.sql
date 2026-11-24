-- 신규 SSC/KUPID 파이프라인의 최소 DB 변경.
-- 별도 source 테이블 없이 대표 공고 한 건만 postings에 보존한다.

begin;

alter table public.postings
  add column if not exists title text;

grant select (source, title)
  on table public.postings to anon, authenticated;

grant select, insert, update
  on table public.notices to service_role;

drop function if exists get_worksite_public_detail(int);

create function get_worksite_public_detail(p_worksite_id int)
returns table (worksite jsonb, postings jsonb)
language sql security definer set search_path = public as $$
  with ps as (
    select p.*
    from postings p
    where p.worksite_id = p_worksite_id and p.deleted_at is null
    order by p.is_active desc, p.created_at desc
    limit 30
  )
  select
    jsonb_build_object(
      'organization_name', w.organization_name,
      'workplace_name',    w.workplace_name,
      'type',              w.type,
      'location_type',     w.location_type,
      'address',           w.address,
      'region',            w.region
    ) as worksite,
    coalesce(
      (select jsonb_agg(
         jsonb_build_object(
           'id',                      ps.id,
           'source',                  ps.source,
           'title',                   ps.title,
           'is_active',               ps.is_active,
           'is_placeholder',          ps.is_placeholder,
           'recruit_until',           ps.recruit_until,
           'recruit_until_estimated', ps.recruit_until_estimated,
           'preferred_track',         ps.preferred_track,
           'min_grade',               ps.min_grade,
           'eligible_degree',         ps.eligible_degree,
           'eligible_status',         ps.eligible_status,
           'recruitment_period_text', ps.recruitment_period_text,
           'recruit_count',           ps.recruit_count,
           'hourly_wage',             ps.hourly_wage,
           'work_period_text',        ps.work_period_text,
           'work_time_text',          ps.work_time_text,
           'job_description',         ps.job_description,
           'preference_notes',        ps.preference_notes,
           'extra_notes',             ps.extra_notes,
           'source_url',              ps.source_url
         )
         order by ps.is_active desc, ps.created_at desc
       ) from ps),
      '[]'::jsonb
    ) as postings
  from worksites w
  where w.id = p_worksite_id and w.deleted_at is null;
$$;

revoke execute on function get_worksite_public_detail(int) from public;
grant execute on function get_worksite_public_detail(int) to anon, authenticated;

commit;
