-- 목적: 홈 화면 조립을 서버로 — get_home_feed RPC 신설(히어로 추천 + 선반 3종을 한 번에)
-- 날짜: 2026-07-20 · 담당: 배경록

-- 배경: 홈은 후보 공고를 브라우저로 전부 받아 프런트에서 dedup·정렬했다. 국가근장이 6,700여 곳이라
--   전량 조회가 불가능해 쿼리별 상한(학교 300·국가 30)을 뒀는데, 실제 모수가 그보다 커서
--   학교근장 408중 108건·국가근장 교내 81중 51건이 후보에서 잘렸다(법학전문대학원행정팀 등).
--   더 큰 문제는 정확성이다: "추천 점수 높은 근장 10곳"이 실제로는 '우연히 받아온 것 중 top 10'이라,
--   잘려나간 쪽에 1등이 있으면 영원히 노출되지 않는다. 상한을 올려도 모수가 늘면 재발한다.
-- 방식: 후보 선정·정렬·상위 N개 추출을 서버가 수행하고 카드에 필요한 필드만 내려준다.
--   페이로드 220KB+ → 수십 KB, 선반은 전수 기준의 진짜 상위 10개가 된다.
--   필터(유형·모집상태)는 인자로 받아 왕복 1회로 끝낸다(선반 3종을 한 RPC가 함께 반환).
--
-- 설계 메모
--  · 카드 모양은 search_worksite_cards와 같은 계열(flat) — data 계층이 프런트 모양으로 변환한다.
--  · 히어로는 필터와 무관하게 전체에서 고른다(상단 고정 추천이라 기존 프런트 동작과 동일).
--  · 개인화(자격·매칭)는 프로필을 클라가 넘기지 않고 auth.uid()로 서버가 직접 읽는다.
--  · ⚠️ effectiveActive는 '공고별 판정 후 OR'이다. max(recruit_until) 롤업으로 바꾸면
--    "만료된 공고 + recruit_until이 NULL인 레거시 활성 공고"가 섞일 때 프런트(lib/recruit.js)와
--    판정이 갈린다. 레거시 교외 6,647건이 recruit_until NULL이라 실제로 발생하는 조합이다.
--  · 리뷰 집계는 not is_blinded까지 제외한다(get_review_stats는 안 걸러 홈이 더 관대했다).

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
-- 로그인 유저 프로필(비로그인이면 0행 → 아래 left join으로 전부 NULL)
me as (
  select u.university_id, u.degree_program::text as degree, u.academic_status::text as status,
         u.grade, u.track, c.name as college, d.name as department, u.region
  from users u
  left join colleges    c on c.id = u.college_id
  left join departments d on d.id = u.department_id
  where u.id = auth.uid()
),
-- 근무지당 대표 공고 1건(활성 우선, 최신순) — 카드 태그·자격 판정의 근거
rep as (
  select distinct on (p.worksite_id)
    p.worksite_id, p.preferred_track, p.preferred_college, p.preferred_dept,
    p.min_grade, p.eligible_degree, p.eligible_status, p.work_duration_type
  from postings p
  where p.deleted_at is null
  order by p.worksite_id, p.is_active desc, p.created_at desc
),
-- 근무지 모집상태 = 공고 하나라도 모집중이면 모집중(공고별 effectiveActive 후 OR)
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
    r.preferred_track, r.work_duration_type, r.eligible_degree, r.eligible_status,
    coalesce(s.review_count, 0) as review_count,
    s.avg_score,
    -- 자격 부합: 프로필이 없으면(비로그인) 전부 통과. JS isEligible과 1:1.
    --   is distinct from을 쓰는 이유 = 내 값이 NULL일 때도 '불일치'로 봐야 JS와 같다
    --   (JS: 'x' !== undefined → true → 탈락).
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
    -- 개인화 매칭 점수 — 구체적일수록 높게(학과3·단대2·계열2·지역1). JS matchScore와 동일.
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
    -- 대학 스코프: 비로그인은 전체, 로그인은 자기 대학 + 공용(0) — search_worksite_cards와 동일 정책
    and ( auth.uid() is null
          or w.university_id = 0
          or w.university_id = (select university_id from me) )
),
-- 카드 1건 jsonb(프런트 PlaceCard가 쓰는 필드만)
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
    'work_duration_type', j.work_duration_type,
    'eligible_degree',    j.eligible_degree,
    'eligible_status',    j.eligible_status,
    'review_count',       j.review_count,
    'avg_score',          j.avg_score
  ) as card
  from joined j
),
-- 선반용: 필터 적용본
filtered as (
  select * from carded
  where (p_types   is null or type      = any(p_types::worksite_type_e[]))
    and (p_actives is null or is_active = any(p_actives))
)
select jsonb_build_object(
  -- 히어로: 필터 무관 전체에서 ①모집중 ②자격부합 ③개인화매칭 ④추천점수
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

-- 홈은 비로그인도 보는 화면(PUBLIC_BROWSE) — anon에도 실행 권한을 준다.
--   RPC가 카드 필드만 화이트리스트로 반환하므로 테이블 grant는 필요 없다.
grant execute on function get_home_feed(text[], boolean[]) to authenticated, anon;
