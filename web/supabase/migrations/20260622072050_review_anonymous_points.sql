-- 목적: 리뷰 익명 작성/수정 + 차등 포인트(익명 5P/실명 15P, 대칭 레저). 컬럼·4-col unique·RPC 3종 정본 재구축.
-- 날짜: 2026-06-22 · 담당: 배경록
-- 참고: feature/review-form(dodo)의 DB 변경(컬럼·flat15 RPC·4-col unique)을 대체하는 정본.

-- (1) is_anonymous 컬럼 — 데이터 보존(if not exists)
alter table public.reviews
  add column if not exists is_anonymous boolean not null default false;

-- (2) 중복 기준 = (user, worksite, year, semester).
--     live 제약명 불명(드리프트) → 이름 추측 대신 reviews의 모든 unique 제약을 일괄 drop 후 정본 1개 add(이름 무관·멱등).
do $$
declare r record;
begin
  for r in
    select conname from pg_constraint
    where conrelid = 'public.reviews'::regclass and contype = 'u'
  loop
    execute format('alter table public.reviews drop constraint %I', r.conname);
  end loop;
end $$;

alter table public.reviews
  add constraint reviews_user_worksite_year_semester_key
  unique (user_id, worksite_id, work_year, work_semester);

-- (3) write RPC — 차등 포인트(익명 5 / 실명 15). 옛 11-arg + dodo 12-arg(flat15) 모두 drop 후 재생성.
drop function if exists public.write_review_with_points(
  integer, integer, integer, text, numeric, numeric, numeric, numeric, numeric, text, text);
drop function if exists public.write_review_with_points(
  integer, integer, integer, text, numeric, numeric, numeric, numeric, numeric, text, text, boolean);

create or replace function public.write_review_with_points(
  p_user_id integer, p_worksite_id integer, p_work_year integer, p_work_semester text,
  p_work numeric, p_growth numeric, p_vibe numeric, p_flex numeric, p_recommend numeric,
  p_work_content text, p_opinion text, p_is_anonymous boolean default false
) returns integer language plpgsql as $$
declare
  v_review_id integer;
  v_amount integer := case when coalesce(p_is_anonymous, false) then 5 else 15 end;
begin
  insert into public.reviews (
    user_id, worksite_id, work_year, work_semester,
    score_work, score_growth, score_vibe, score_flex, score_recommend,
    work_content, opinion, is_anonymous)
  values (
    p_user_id, p_worksite_id, p_work_year, p_work_semester,
    p_work, p_growth, p_vibe, p_flex, p_recommend,
    p_work_content, p_opinion, coalesce(p_is_anonymous, false))
  returning id into v_review_id;

  insert into public.points (user_id, amount, reason, review_id)
  values (p_user_id, v_amount, 'review_write', v_review_id);

  update public.users set point_balance = point_balance + v_amount where id = p_user_id;
  return v_review_id;
end $$;

-- (4) update RPC — 수정 시 익명 토글. 정규값(5/15)으로 스냅. 포인트 이력 없는 리뷰엔 지급 안 함(게이트).
drop function if exists public.update_review_with_points(
  integer, integer, integer, text, numeric, numeric, numeric, numeric, numeric, text, text, boolean);

create or replace function public.update_review_with_points(
  p_user_id integer, p_review_id integer, p_work_year integer, p_work_semester text,
  p_work numeric, p_growth numeric, p_vibe numeric, p_flex numeric, p_recommend numeric,
  p_work_content text, p_opinion text, p_is_anonymous boolean default false
) returns void language plpgsql as $$
declare
  v_target    integer := case when coalesce(p_is_anonymous, false) then 5 else 15 end;
  v_grant     integer;
  v_has_write boolean;
  v_delta     integer;
  v_balance   integer;
begin
  update public.reviews set
    work_year = p_work_year, work_semester = p_work_semester,
    score_work = p_work, score_growth = p_growth, score_vibe = p_vibe,
    score_flex = p_flex, score_recommend = p_recommend,
    work_content = p_work_content, opinion = p_opinion,
    is_anonymous = coalesce(p_is_anonymous, false), updated_at = now()
  where id = p_review_id and user_id = p_user_id;
  if not found then raise exception 'REVIEW_NOT_FOUND'; end if;

  select coalesce(sum(amount), 0), bool_or(reason = 'review_write')
    into v_grant, v_has_write
  from public.points
  where review_id = p_review_id and reason in ('review_write', 'review_anon_switch');

  -- 포인트 적립 이력(write 행)이 없는 리뷰는 토글로 포인트를 새로 지급하지 않음(공짜 지급 버그 차단).
  if not coalesce(v_has_write, false) then
    return;
  end if;

  v_delta := v_target - v_grant;
  if v_delta <> 0 then
    if v_delta < 0 then
      select point_balance into v_balance from public.users where id = p_user_id;
      if v_balance + v_delta < 0 then raise exception 'INSUFFICIENT_POINTS'; end if;
    end if;
    insert into public.points (user_id, amount, reason, review_id)
    values (p_user_id, v_delta, 'review_anon_switch', p_review_id);
    update public.users set point_balance = point_balance + v_delta where id = p_user_id;
  end if;
end $$;

-- (5) delete RPC — 실제 적립합만큼 회수(하드코딩 15 제거).
create or replace function public.delete_review_with_rollback(p_user_id integer, p_review_id integer)
returns void language plpgsql as $$
declare
  v_grant   integer;
  v_balance integer;
begin
  select coalesce(sum(amount), 0) into v_grant
  from public.points
  where review_id = p_review_id and reason in ('review_write', 'review_anon_switch');

  select point_balance into v_balance from public.users where id = p_user_id;
  if v_balance < v_grant then raise exception 'INSUFFICIENT_POINTS'; end if;

  insert into public.points (user_id, amount, reason, review_id)
  values (p_user_id, -v_grant, 'review_delete', p_review_id);

  delete from public.reviews where id = p_review_id and user_id = p_user_id;
  if not found then raise exception 'REVIEW_NOT_FOUND'; end if;

  update public.users set point_balance = point_balance - v_grant where id = p_user_id;
end $$;
