-- 목적: 포인트 정책 v2 — 가입 축하금 5P 지급 종료, 리뷰 적립 실명 30P·익명 20P(기존 25/15),
--       리뷰 2개 이상 작성자에게 (살아있는 리뷰 수 − 1) × 5P 소급 지급, 공지 문구 동기화.
-- 날짜: 2026-08-08 · 담당: 배경록
-- ⚠️ 배포: 프론트(lib/points·ReviewForm·ExchangeCenter)의 적립가 표기와 한 몸이므로
--          db push 직후 prod 프론트 배포까지 한 번에 진행할 것.
-- ⚠️ 적립가 변경과 소급 지급이 한 트랜잭션이어야 그 사이 들어온 리뷰가 어중간한 금액으로
--    적립되지 않는다 — 파일 전체를 begin/commit으로 감싼다.

begin;

-- ── 1) 가입 축하금 지급 종료 ──
-- 본문은 현행 최신(20260721071224_nickname_policy)을 그대로 재현 + 보너스 2줄만 삭제.
-- 시그니처 불변 → create or replace(DROP 불필요), 기존 grant(authenticated) 유지됨.
-- 이미 지급된 가입 축하금 원장 행·잔액은 건드리지 않는다(회수 없음).
create or replace function create_profile(
  p_nickname        text,
  p_university_id   int,
  p_college_name    text,
  p_department_name text,
  p_track           text,
  p_admission_year  int,
  p_degree_program  text,
  p_academic_status text,
  p_grade           int,
  p_region          text
) returns void
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_college_id int;
  v_department_id int;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  -- 이미 프로필 있으면 재생성하지 않음(더블클릭/재호출 안전). 갱신은 update_profile 담당.
  if exists (select 1 from users u where u.id = v_uid) then
    return;
  end if;

  perform validate_nickname(p_nickname);

  select id into v_college_id from colleges
    where university_id = p_university_id and name = p_college_name limit 1;
  if v_college_id is null then
    select id into v_college_id from colleges where university_id = p_university_id order by id limit 1;
  end if;
  if v_college_id is null then raise exception 'NO_COLLEGE'; end if;
  select id into v_department_id from departments
    where college_id = v_college_id and name = p_department_name limit 1;
  if v_department_id is null then
    select id into v_department_id from departments where college_id = v_college_id order by id limit 1;
  end if;
  if v_department_id is null then raise exception 'NO_DEPARTMENT'; end if;

  insert into users (id, university_id, college_id, department_id, track,
                     nickname, admission_year, degree_program, academic_status, grade, region)
  values (v_uid, p_university_id, v_college_id, v_department_id, p_track,
          trim(p_nickname), p_admission_year,
          p_degree_program::degree_program_e, p_academic_status::academic_status_e,
          p_grade, p_region);
exception
  when unique_violation then raise exception 'NICKNAME_TAKEN';
end $$;

-- ── 2) 리뷰 적립 — 실명 30P · 익명 20P ──
-- 본문은 각 최신본(write: 20260731105714 / update: 20260731120439) 그대로, 적립 상수만 25/15 → 30/20.
-- 시그니처 불변. delete_review_with_rollback은 실제 적립 합계(sum)를 회수하므로 수정 불필요.
create or replace function public.write_review_with_points(
  p_worksite_id integer, p_work_year integer, p_work_semester text,
  p_work numeric, p_growth numeric, p_vibe numeric, p_flex numeric, p_recommend numeric,
  p_work_content text, p_opinion text, p_is_anonymous boolean default false
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_review_id integer;
  v_amount integer := case when coalesce(p_is_anonymous, false) then 20 else 30 end;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  perform public.validate_review_work_semester(p_worksite_id, p_work_semester);

  insert into public.reviews (
    user_id, worksite_id, work_year, work_semester,
    score_work, score_growth, score_vibe, score_flex, score_recommend,
    work_content, opinion, is_anonymous
  ) values (
    v_uid, p_worksite_id, p_work_year, p_work_semester,
    p_work, p_growth, p_vibe, p_flex, p_recommend,
    p_work_content, p_opinion, coalesce(p_is_anonymous, false)
  ) returning id into v_review_id;

  insert into public.points (user_id, amount, reason, review_id)
  values (v_uid, v_amount, 'review_write', v_review_id);

  update public.users set point_balance = point_balance + v_amount where id = v_uid;
  return v_review_id;
end;
$$;

-- ⚠️ 정산 합계의 reason 목록에 'review_policy_grant'가 반드시 포함돼야 한다
--    (20260731120439에서 추가된 것 — 빼면 소급 지급분을 못 보고 차액을 또 지급한다).
create or replace function public.update_review_with_points(
  p_review_id integer, p_work_year integer, p_work_semester text,
  p_work numeric, p_growth numeric, p_vibe numeric, p_flex numeric, p_recommend numeric,
  p_work_content text, p_opinion text, p_is_anonymous boolean default false
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_worksite_id integer;
  v_target integer := case when coalesce(p_is_anonymous, false) then 20 else 30 end;
  v_grant integer;
  v_has_write boolean;
  v_delta integer;
  v_balance integer;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;

  select worksite_id into v_worksite_id
  from public.reviews
  where id = p_review_id and user_id = v_uid;
  if not found then raise exception 'REVIEW_NOT_FOUND'; end if;

  perform public.validate_review_work_semester(v_worksite_id, p_work_semester);

  update public.reviews set
    work_year = p_work_year, work_semester = p_work_semester,
    score_work = p_work, score_growth = p_growth, score_vibe = p_vibe,
    score_flex = p_flex, score_recommend = p_recommend,
    work_content = p_work_content, opinion = p_opinion,
    is_anonymous = coalesce(p_is_anonymous, false), updated_at = now()
  where id = p_review_id and user_id = v_uid;

  select coalesce(sum(amount), 0), bool_or(reason = 'review_write')
    into v_grant, v_has_write
  from public.points
  where review_id = p_review_id
    and reason in ('review_write', 'review_anon_switch', 'review_policy_grant');

  if not coalesce(v_has_write, false) then return; end if;

  v_delta := v_target - v_grant;
  if v_delta <> 0 then
    if v_delta < 0 then
      select point_balance into v_balance from public.users where id = v_uid;
      if v_balance + v_delta < 0 then raise exception 'INSUFFICIENT_POINTS'; end if;
    end if;
    insert into public.points (user_id, amount, reason, review_id)
    values (v_uid, v_delta, 'review_anon_switch', p_review_id);
    update public.users set point_balance = point_balance + v_delta where id = v_uid;
  end if;
end;
$$;

-- ── 3) 소급 지급 — (살아있는 리뷰 수 − 1) × 5P ──
-- 리뷰를 여러 개 쓴 기여자에게만 보상한다. 1개=0P, 2개=5P, 3개=10P.
-- 대상: user_id 있음 · 삭제 안 됨 · review_write 적립 이력 있음(수정 RPC의 v_has_write 가드와 동일 기준).
--       삭제된 리뷰는 이미 적립분을 회수당했으므로 카운트에서 제외.
-- 지급 방식: 유저 단위 뭉텅이가 아니라 리뷰별 원장 행으로 붙인다 — update/delete RPC가
--       review_id별 적립 합계로 재정산하기 때문. review_id가 null인 행은 그 합계에 안 잡혀
--       옛 리뷰를 수정할 때마다 차액이 또 나가는 이중 보전이 된다.
-- 제외 규칙: 유저별 최소 id 리뷰 1건(rn=1)은 제외 → 그 리뷰만 합계가 구 정책가로 남는다.
--       그 리뷰를 수정하면 update RPC가 차액 +5P를 보전한다(유저당 최대 1회·5P). 정책상 감수.
-- 멱등: 재실행하면 합계가 이미 현행가라 delta<=0 → 0행. db reset 재생 시엔 reviews가 비어 no-op.
-- 회수 안 함: delta<=0 인 리뷰는 대상에서 제외(보전 전용).
with eligible as (
  select r.id as review_id,
         r.user_id,
         coalesce(r.is_anonymous, false) as is_anonymous,
         sum(p.amount) as granted
  from public.reviews r
  join public.points p
    on p.review_id = r.id
   and p.reason in ('review_write', 'review_anon_switch', 'review_policy_grant')
  where r.user_id is not null
    and r.deleted_at is null
  group by r.id, r.user_id, r.is_anonymous
  having bool_or(p.reason = 'review_write')
), ranked as (
  select e.review_id,
         e.user_id,
         row_number() over (partition by e.user_id order by e.review_id) as rn,
         (case when e.is_anonymous then 20 else 30 end) - e.granted as delta
  from eligible e
), targeted as (
  select review_id, user_id, delta
  from ranked
  where rn > 1
    and delta > 0
), granted_rows as (
  insert into public.points (user_id, amount, reason, review_id)
  select user_id, delta, 'review_policy_grant', review_id
  from targeted
  returning user_id, amount
)
update public.users u
set point_balance = u.point_balance + s.total
from (select user_id, sum(amount) as total from granted_rows group by user_id) s
where u.id = s.user_id;

-- ── 4) 현행 정책 서술 공지의 숫자 동기화 ──
-- 대상은 '[필독] 근로고래 이용 안내'(20260801050000에서 3건을 통합한 것).
-- ⚠️ 과거 날짜 업데이트 공지('[업데이트] 8월 1일'의 "15P → 25P" 이력)는 건드리지 않는다 —
--    그 시점의 사실 기록이다.
update public.notices
set content = replace(content,
  '닉네임 공개 리뷰 작성 25P, 익명 리뷰 작성 15P',
  '닉네임 공개 리뷰 작성 30P, 익명 리뷰 작성 20P')
where content like '%닉네임 공개 리뷰 작성 25P, 익명 리뷰 작성 15P%';

-- 구 '[필독] 리뷰 작성 방법 안내'는 20260801050000에서 통합·삭제됐으므로 prod에선 0행이지만,
-- db reset 재생 순서(생성 → 갱신 → 삭제)와 무관하게 안전하도록 방어적으로 둔다.
update public.notices
set content = replace(content,
  '닉네임 공개 리뷰는 25P, 익명 리뷰는 15P가 적립됩니다',
  '닉네임 공개 리뷰는 30P, 익명 리뷰는 20P가 적립됩니다')
where content like '%닉네임 공개 리뷰는 25P, 익명 리뷰는 15P가 적립됩니다%';

-- ── 5) 변경 안내 공지 ──
-- 제목 기준 upsert라 재실행·db reset에 안전하다. is_pinned=false(고정은 필독 공지만),
-- university_id=null(전교 공통·비로그인 공개).
do $$
declare
  v_notice_id integer;
begin
  select id into v_notice_id
  from public.notices
  where university_id is null
    and title = '[업데이트] 8월 8일'
  order by id
  limit 1;

  if v_notice_id is null then
    insert into public.notices (title, content, is_pinned, university_id)
    values (
      '[업데이트] 8월 8일',
      $notice$안녕하세요, 근로고래입니다. 🐳

2026년 8월 8일에 반영된 포인트 정책 변경을 안내드립니다.

1. 리뷰 적립 포인트 상향

• 닉네임 공개 리뷰: 25P → 30P
• 익명 리뷰: 15P → 20P

2. 가입 축하금 지급 종료

가입만으로 지급하던 축하 포인트 5P의 지급을 종료했습니다. 이미 지급받으신 포인트는 회수하지 않으며 그대로 사용하실 수 있습니다. 해당 재원은 위의 리뷰 적립 포인트 상향에 사용됩니다.

3. 기존 리뷰 소급 지급

리뷰를 2개 이상 작성해 주신 분들께 포인트를 소급 지급했습니다. 가장 먼저 작성한 리뷰를 제외한 나머지 리뷰마다 5P씩 지급되어, 리뷰 2개는 5P, 3개는 10P가 적립됩니다.

삭제한 리뷰는 작성 개수에 포함되지 않습니다.

리뷰를 남겨주시는 분들께 더 많은 혜택이 돌아가도록 정책을 조정했습니다. 앞으로도 계속 개선하겠습니다.

감사합니다.
근로고래 드림$notice$,
      false,
      null
    );
  else
    update public.notices
    set content = $notice$안녕하세요, 근로고래입니다. 🐳

2026년 8월 8일에 반영된 포인트 정책 변경을 안내드립니다.

1. 리뷰 적립 포인트 상향

• 닉네임 공개 리뷰: 25P → 30P
• 익명 리뷰: 15P → 20P

2. 가입 축하금 지급 종료

가입만으로 지급하던 축하 포인트 5P의 지급을 종료했습니다. 이미 지급받으신 포인트는 회수하지 않으며 그대로 사용하실 수 있습니다. 해당 재원은 위의 리뷰 적립 포인트 상향에 사용됩니다.

3. 기존 리뷰 소급 지급

리뷰를 2개 이상 작성해 주신 분들께 포인트를 소급 지급했습니다. 가장 먼저 작성한 리뷰를 제외한 나머지 리뷰마다 5P씩 지급되어, 리뷰 2개는 5P, 3개는 10P가 적립됩니다.

삭제한 리뷰는 작성 개수에 포함되지 않습니다.

리뷰를 남겨주시는 분들께 더 많은 혜택이 돌아가도록 정책을 조정했습니다. 앞으로도 계속 개선하겠습니다.

감사합니다.
근로고래 드림$notice$,
        updated_at = now()
    where id = v_notice_id;
  end if;
end
$$;

commit;
