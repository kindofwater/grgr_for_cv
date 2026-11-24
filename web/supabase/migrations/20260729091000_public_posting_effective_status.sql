-- 공개 상세의 대표 순서와 모집 상태를 공고별 유효 상태로 통일한다.
-- 출처에서 마감을 확인한 공고는 날짜/is_active 값과 무관하게 닫힌다.

begin;

create or replace function public.get_worksite_public_detail(p_worksite_id int)
returns table (worksite jsonb, postings jsonb)
language sql security definer set search_path = public
as $$
  with ps as (
    select ranked.*
    from (
      select p.*,
             case
               when p.source_closed_at is not null then false
               when p.recruit_until is not null
                 then p.recruit_until >= (now() at time zone 'Asia/Seoul')::date
               else coalesce(p.is_active, false)
             end as effective_active
      from public.postings p
      where p.worksite_id = p_worksite_id
        and p.deleted_at is null
    ) ranked
    order by ranked.effective_active desc, ranked.created_at desc
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
           'is_active',               ps.effective_active,
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
           'work_location',           ps.work_location,
           'job_description',         ps.job_description,
           'preference_notes',         ps.preference_notes,
           'extra_notes',             ps.extra_notes,
           'source_url',              ps.source_url
         )
         order by ps.effective_active desc, ps.created_at desc
       ) from ps),
      '[]'::jsonb
    ) as postings
  from public.worksites w
  where w.id = p_worksite_id and w.deleted_at is null;
$$;

revoke execute on function public.get_worksite_public_detail(int) from public;
grant execute on function public.get_worksite_public_detail(int)
  to anon, authenticated;

commit;
