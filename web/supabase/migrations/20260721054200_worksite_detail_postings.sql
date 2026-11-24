-- 목적: 근무지 상세가 대표 공고 1개(posting) 대신 공고 목록(postings 배열)을 반환 — 학교근로 다중 공고 노출(A안)
-- 날짜: 2026-07-21 · 담당: 배경록

-- 반환 시그니처 변경(posting jsonb → postings jsonb) → DROP 먼저(안 그러면 옛 함수 잔존해 RPC 꼬임)
drop function if exists get_worksite_public_detail(int);

create function get_worksite_public_detail(p_worksite_id int)
returns table (worksite jsonb, postings jsonb)
language sql security definer set search_path = public as $$
  with ps as (
    select p.*
    from postings p
    where p.worksite_id = p_worksite_id and p.deleted_at is null
    order by p.is_active desc, p.created_at desc
    limit 30                                   -- SSC 이력 대비 캡(응답 비대 방지, Fable #2)
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
           'is_active',               ps.is_active,
           'is_placeholder',          ps.is_placeholder,   -- 대표/목록 선별용
           'recruit_until',           ps.recruit_until,     -- 배지 판정(Fable #1)
           'recruit_until_estimated', ps.recruit_until_estimated,   -- 접힌 줄 '마감(추정)' 표기
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
         order by ps.is_active desc, ps.created_at desc     -- 배열 순서 = 활성→최신(대표=첫 원소)
       ) from ps),
      '[]'::jsonb
    ) as postings
  from worksites w
  where w.id = p_worksite_id and w.deleted_at is null;
$$;

-- 개인정보(contact_name 등)는 화이트리스트에서 계속 제외.
revoke execute on function get_worksite_public_detail(int) from public;
grant  execute on function get_worksite_public_detail(int) to anon, authenticated;
