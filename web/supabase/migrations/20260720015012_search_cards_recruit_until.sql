-- 목적: 검색·공개상세 RPC가 recruit_until을 반환 — 카드/상세의 "모집중"을 날짜 기반(effectiveActive)으로 판정 가능하게
-- 날짜: 2026-07-20 · 담당: 배경록
-- 비고: 리턴 타입 변경이므로 DROP 먼저 + grant(authenticated·anon) 재부여.
--       (재발급) 원래 20260717095637이었으나 서울대 시드 등(20260717000000~20260718121129)이 먼저
--       적용되며 순서가 꼬여 20260720015012로 리네임 — 20260717150000의 리네임 선례와 동일 처방.
--       본문은 최신본 20260717130000(대학 스코프)에서 복사 — 옛 판(20260716180000 이전)에서 뜨면
--       대학 스코프·limit/offset 상한·지역 조건이 롤백된다.
--       변경 3곳: ①returns table에 recruit_until ②ws_active CTE에 max(recruit_until) ③joined select.
--       active 롤업 필터(p_actives)·정렬은 여전히 is_active — recruit_until 기반 전환은 스코프 밖(spec).
--       search_worksite_suggestions는 건드리지 않는다(20260717130000판 유지).

drop function if exists search_worksite_cards(text,text,int,int,text[],text[],text[],text[],text[],int[],int[],boolean[]);

create function search_worksite_cards(
  p_query  text default null,
  p_sort   text default 'recommend',
  p_limit  int  default 20,
  p_offset int  default 0,
  p_types     text[] default null,
  p_locations text[] default null,
  p_regions   text[] default null,
  p_durations text[] default null,
  p_tracks    text[] default null,
  p_degrees   int[]  default null,
  p_statuses  int[]  default null,
  p_actives   boolean[] default null
)
returns table(
  worksite_id        int,
  organization_name  varchar,
  workplace_name     varchar,
  region             varchar,
  address            text,
  type               worksite_type_e,
  location_type      location_type_e,
  view_count         int,
  is_active          boolean,
  recruit_until      date,
  preferred_track    varchar,
  eligible_degree    smallint,
  eligible_status    smallint,
  work_duration_type duration_type_e,
  review_count       bigint,
  avg_recommend      numeric,
  avg_work           numeric,
  avg_growth         numeric,
  avg_vibe           numeric,
  avg_flex           numeric,
  recommend_rate     int,
  total_count        bigint
)
language sql
security definer
as $$
  with rep as (
    select distinct on (p.worksite_id)
      p.worksite_id, p.preferred_track, p.eligible_degree,
      p.eligible_status, p.work_duration_type
    from postings p
    where p.deleted_at is null
    order by p.worksite_id, p.is_active desc, p.created_at desc
  ),
  ws_active as (
    select worksite_id, bool_or(is_active) as is_active, max(recruit_until) as recruit_until
    from postings where deleted_at is null group by worksite_id
  ),
  stats as (
    select worksite_id,
           count(*) as review_count,
           round(avg(score_recommend)::numeric,1) as avg_recommend,
           round(avg(score_work)::numeric,1)      as avg_work,
           round(avg(score_growth)::numeric,1)    as avg_growth,
           round(avg(score_vibe)::numeric,1)      as avg_vibe,
           round(avg(score_flex)::numeric,1)      as avg_flex,
           round(100.0*count(*) filter (where score_recommend>=4.0)/count(*))::int as recommend_rate
    from reviews where deleted_at is null and not is_blinded group by worksite_id
  ),
  joined as (
    select w.id as worksite_id, w.organization_name, w.workplace_name,
           w.region, w.address, w.type, w.location_type, w.view_count,
           coalesce(a.is_active,false) as is_active,
           a.recruit_until,
           r.preferred_track, r.eligible_degree, r.eligible_status, r.work_duration_type,
           coalesce(s.review_count,0) as review_count,
           s.avg_recommend, s.avg_work, s.avg_growth, s.avg_vibe, s.avg_flex, s.recommend_rate
    from worksites w
    join rep r           on r.worksite_id = w.id
    left join ws_active a on a.worksite_id = w.id
    left join stats s    on s.worksite_id = w.id
    where w.deleted_at is null
      -- 대학 스코프: 비로그인은 전체, 로그인은 자기 대학 + 공용(university_id=0)
      and ( auth.uid() is null
            or w.university_id = 0
            or w.university_id = (select u.university_id from public.users u where u.id = auth.uid()) )
      and ( p_query is null or p_query = '' or
            w.organization_name ilike '%'||p_query||'%' or
            w.workplace_name    ilike '%'||p_query||'%' )
      and (p_actives   is null or coalesce(a.is_active,false) = any(p_actives))
      and (p_types     is null or w.type          = any(p_types::worksite_type_e[]))
      and (p_locations is null or w.location_type = any(p_locations::location_type_e[]))
      and (p_regions   is null or w.location_type = 'on_campus' or w.region = any(p_regions))
      and (p_durations is null or r.work_duration_type = any(p_durations::duration_type_e[]))
      and (p_tracks    is null or r.preferred_track     = any(p_tracks))
      and (p_degrees   is null or r.eligible_degree::int = any(p_degrees))
      and (p_statuses  is null or r.eligible_status::int = any(p_statuses))
  )
  select *, count(*) over() as total_count
  from joined
  order by
    case when p_sort='reviews'   then review_count end desc nulls last,
    case when p_sort='recommend' then avg_recommend end desc nulls last,
    worksite_id
  limit  least(greatest(coalesce(p_limit, 20), 0), 50)
  offset least(greatest(coalesce(p_offset, 0), 0), 10000);
$$;

-- DROP으로 grant가 소멸 — 재부여 (authenticated=로그인 검색, anon=비로그인 공개 검색: 20260716120000)
grant execute on function search_worksite_cards(text,text,int,int,text[],text[],text[],text[],text[],int[],int[],boolean[]) to authenticated, anon;

-- 공개 상세: posting jsonb에 recruit_until 추가 (jsonb 반환이라 시그니처 불변 → create or replace)
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
        'recruit_until',           rep.recruit_until,
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
