-- 목적: 국가근로 리뷰의 근무 학기를 모집 시기와 일치시킨다.
-- vacation(C)은 여름·겨울방학만, semester(B)은 1·2학기만 허용한다.

create or replace function public.validate_review_work_semester(
  p_worksite_id integer,
  p_work_semester text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_type worksite_type_e;
  v_term text;
begin
  select type, national_work_term
    into v_type, v_term
  from public.worksites
  where id = p_worksite_id and deleted_at is null;

  if not found then raise exception 'WORKSITE_NOT_FOUND'; end if;
  if v_type <> 'national' then return; end if;

  if v_term = 'vacation' and p_work_semester not in ('여름방학', '겨울방학') then
    raise exception 'INVALID_WORK_SEMESTER';
  end if;
  if v_term = 'semester' and p_work_semester not in ('1학기', '2학기') then
    raise exception 'INVALID_WORK_SEMESTER';
  end if;
end;
$$;

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
  v_amount integer := case when coalesce(p_is_anonymous, false) then 5 else 15 end;
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
  v_target integer := case when coalesce(p_is_anonymous, false) then 5 else 15 end;
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
  where review_id = p_review_id and reason in ('review_write', 'review_anon_switch');

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

revoke execute on function public.validate_review_work_semester(integer, text) from public;
grant execute on function public.validate_review_work_semester(integer, text) to authenticated;
