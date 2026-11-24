-- 고려대학교 서울캠퍼스: 2026-07-29 00:00(KST) 이후 지표
--
-- 실행 위치: Supabase Dashboard > SQL Editor
-- 시간 기준: 2026-07-29 00:00:00 한국시간을 포함한다(>=).
-- 캠퍼스 범위: 고려대학교 서울캠퍼스만 집계한다.
--   고려대학교 전체 캠퍼스를 보고 싶으면 각 쿼리의
--   `and univ.campus = '서울'` 조건을 제거한다.
--
-- 집계 정의:
--   회원가입자 = public.users 프로필 생성 완료 사용자
--   열람권 구매자 = points.reason = 'pass_purchase' 기록이 1건 이상인 고유 사용자
--   리뷰 작성자 = 삭제되지 않은 리뷰를 1건 이상 작성한 고유 사용자
--
-- 주의:
--   탈퇴하면 public.users와 points가 삭제되므로, 탈퇴한 사용자의 과거 가입·구매는
--   현재 스키마만으로 복원할 수 없다.
--   열람권 구매자 수는 이후 환불 여부와 무관하게 "구매한 적이 있는 사람"을 센다.


-- 1) 핵심 지표 한 번에 보기
with
params as (
  select timestamptz '2026-07-29 00:00:00+09' as since_at
),
target_users as (
  select
    usr.id,
    usr.nickname,
    usr.created_at
  from public.users as usr
  join public.universities as univ
    on univ.id = usr.university_id
  where univ.name = '고려대학교'
    and univ.campus = '서울'
)
select
  to_char(
    params.since_at at time zone 'Asia/Seoul',
    'YYYY-MM-DD HH24:MI:SS'
  ) as 기준시각_kst,

  (
    select count(*)
    from target_users as usr
    where usr.created_at >= params.since_at
  ) as 회원가입자수,

  (
    select count(distinct point_log.user_id)
    from public.points as point_log
    join target_users as usr
      on usr.id = point_log.user_id
    where point_log.reason = 'pass_purchase'
      and point_log.created_at >= params.since_at
  ) as 열람권_구매자수,

  (
    select count(distinct review.user_id)
    from public.reviews as review
    join target_users as usr
      on usr.id = review.user_id
    where review.created_at >= params.since_at
      and review.deleted_at is null
  ) as 리뷰_작성자수
from params;


-- 2) 열람권 구매자별 구매 횟수 확인
--    한 사람이 여러 번 구매해도 한 행으로 묶인다.
with
params as (
  select timestamptz '2026-07-29 00:00:00+09' as since_at
),
target_users as (
  select
    usr.id,
    usr.nickname
  from public.users as usr
  join public.universities as univ
    on univ.id = usr.university_id
  where univ.name = '고려대학교'
    and univ.campus = '서울'
)
select
  usr.id as 사용자_id,
  usr.nickname as 닉네임,
  count(*) as 구매횟수,
  sum(-point_log.amount) as 구매에_사용한_포인트,
  to_char(
    min(point_log.created_at) at time zone 'Asia/Seoul',
    'YYYY-MM-DD HH24:MI:SS'
  ) as 첫_구매시각_kst,
  to_char(
    max(point_log.created_at) at time zone 'Asia/Seoul',
    'YYYY-MM-DD HH24:MI:SS'
  ) as 최근_구매시각_kst
from public.points as point_log
join target_users as usr
  on usr.id = point_log.user_id
cross join params
where point_log.reason = 'pass_purchase'
  and point_log.created_at >= params.since_at
group by usr.id, usr.nickname
order by max(point_log.created_at) desc;


-- 3) 리뷰 작성자와 작성한 근무지 보기
--    2026-07-29 이후 작성됐고 현재 삭제되지 않은 리뷰만 표시한다.
with
params as (
  select timestamptz '2026-07-29 00:00:00+09' as since_at
),
target_users as (
  select
    usr.id,
    usr.nickname
  from public.users as usr
  join public.universities as univ
    on univ.id = usr.university_id
  where univ.name = '고려대학교'
    and univ.campus = '서울'
)
select
  usr.id as 사용자_id,
  usr.nickname as 닉네임,
  review.id as 리뷰_id,
  review.is_anonymous as 익명리뷰,
  review.is_blinded as 블라인드여부,
  review.work_year as 근무연도,
  review.work_semester as 근무학기,
  worksite.id as 근무지_id,
  worksite.organization_name as 기관명,
  worksite.workplace_name as 근무지명,
  concat_ws(
    ' - ',
    nullif(worksite.organization_name, ''),
    nullif(worksite.workplace_name, '')
  ) as 근무지_표시명,
  to_char(
    review.created_at at time zone 'Asia/Seoul',
    'YYYY-MM-DD HH24:MI:SS'
  ) as 리뷰작성시각_kst
from public.reviews as review
join target_users as usr
  on usr.id = review.user_id
join public.worksites as worksite
  on worksite.id = review.worksite_id
cross join params
where review.created_at >= params.since_at
  and review.deleted_at is null
order by review.created_at desc, review.id desc;
