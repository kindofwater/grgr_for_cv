-- 목적: 포인트 정책 개편(20260731105714) 소급 보전 — 기존 리뷰를 현행 적립가(실명 25P·익명 15P)로
--       일괄 재정산(리뷰당 전형적으로 +10P, reason='review_policy_grant'). 수정/삭제 RPC의 정산 합계에
--       새 reason을 포함시켜 이중 보전을 차단.
-- 날짜: 2026-07-31 · 담당: 배경록

-- ── 1) 수정/삭제 재정산 합계에 'review_policy_grant' 포함 ──
-- 안 하면: 소급 지급 뒤 리뷰를 수정할 때 합계(구 15)만 보고 또 +10을 지급(이중 보전).
-- 본문은 각 최신본(update: 20260731105714 / delete: 20260624025109) 그대로, reason 목록만 확장. 시그니처 불변.
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
  v_target integer := case when coalesce(p_is_anonymous, false) then 15 else 25 end;
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

create or replace function public.delete_review_with_rollback(p_review_id integer)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_uid     uuid := auth.uid();
  v_grant   integer;
  v_balance integer;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  select coalesce(sum(amount), 0) into v_grant
  from public.points
  where review_id = p_review_id
    and reason in ('review_write', 'review_anon_switch', 'review_policy_grant');

  select point_balance into v_balance from public.users where id = v_uid;
  if v_balance < v_grant then raise exception 'INSUFFICIENT_POINTS'; end if;

  insert into public.points (user_id, amount, reason, review_id)
  values (v_uid, -v_grant, 'review_delete', p_review_id);

  delete from public.reviews where id = p_review_id and user_id = v_uid;
  if not found then raise exception 'REVIEW_NOT_FOUND'; end if;

  update public.users set point_balance = point_balance - v_grant where id = v_uid;
end $$;

-- ── 2) 소급 지급 ──
-- 대상: 삭제 안 된 리뷰 중 review_write 적립 이력이 있고(수정 RPC의 v_has_write 가드와 동일 기준),
--       현행 적립가보다 적게 받은 것. delta = 현행가 − 기존 합계(전형적으로 +10).
-- 멱등: 재실행하면 delta=0이라 0행. 개편 후 이미 수정으로 재정산된 리뷰도 delta=0이라 제외.
-- db reset 재생 시엔 reviews가 비어 있어 no-op(데이터 백필은 prod에서만 의미).
-- 회수(delta<0)는 하지 않는다 — 보전 전용.
with eligible as (
  select r.id as review_id, r.user_id,
         (case when coalesce(r.is_anonymous, false) then 15 else 25 end)
           - sum(p.amount) as delta
  from public.reviews r
  join public.points p
    on p.review_id = r.id
   and p.reason in ('review_write', 'review_anon_switch', 'review_policy_grant')
  where r.user_id is not null
    and r.deleted_at is null
  group by r.id, r.user_id, r.is_anonymous
  having bool_or(p.reason = 'review_write')
     and (case when coalesce(r.is_anonymous, false) then 15 else 25 end) - sum(p.amount) > 0
), granted as (
  insert into public.points (user_id, amount, reason, review_id)
  select user_id, delta, 'review_policy_grant', review_id
  from eligible
  returning user_id, amount
)
update public.users u
set point_balance = u.point_balance + s.total
from (select user_id, sum(amount) as total from granted group by user_id) s
where u.id = s.user_id;
