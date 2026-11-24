-- 목적: 비로그인 공개용 근무지 상세 RPC(InfoCard 필드만 화이트리스트, contact_name·내부컬럼·리뷰 제외) + 검색 RPC anon 권한
-- 날짜: 2026-07-16 · 담당: 배경록

-- 근무지 정보 화이트리스트 RPC (대표 공고 1개: 활성 우선 → 최신)
drop function if exists get_worksite_public_detail(int);
create or replace function get_worksite_public_detail(p_worksite_id int)
returns table (worksite jsonb, posting jsonb)
language sql security definer set search_path = public as $$
  with rep as (
    select p.*
    from postings p
    where p.worksite_id = p_worksite_id and p.deleted_at is null
    order by p.is_active desc, p.created_at desc
    limit 1
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
    case when rep.id is null then null else
      jsonb_build_object(
        'is_active',               rep.is_active,
        'preferred_track',         rep.preferred_track,
        'min_grade',               rep.min_grade,
        'eligible_degree',         rep.eligible_degree,
        'eligible_status',         rep.eligible_status,
        'recruitment_period_text', rep.recruitment_period_text,
        'recruit_count',           rep.recruit_count,
        'hourly_wage',             rep.hourly_wage,
        'work_period_text',        rep.work_period_text,
        'work_time_text',          rep.work_time_text,
        'job_description',         rep.job_description,
        'preference_notes',        rep.preference_notes,
        'extra_notes',             rep.extra_notes,
        'source_url',              rep.source_url
      )
    end as posting
  from worksites w
  left join rep on true
  where w.id = p_worksite_id and w.deleted_at is null;
$$;

revoke execute on function get_worksite_public_detail(int) from public;
grant  execute on function get_worksite_public_detail(int) to anon, authenticated;

-- 검색 RPC: 이미 화이트리스트(필드 제한). 비로그인 검색 위해 anon 실행 권한만 부여.
grant execute on function search_worksite_cards(text,text,int,int,text[],text[],text[],text[],text[],int[],int[],boolean[]) to anon;

-- 참고: get_worksite_score_cards·get_review_stats 는 이미 anon 허용(20260708 마이그레이션). 변경 없음.
-- 참고: list_worksite_reviews 는 authenticated 전용 유지(리뷰 본문 보호). 변경 없음.
