-- 목적: 포인트 정책 개편 — 리뷰 실명 25P·익명 15P(기존 15/5), 열람권 1시간권(5P) 신설·7일 20P(기존 10)·30일 35P(기존 25).
--       광고 시청 5P 유지·일일 캡 2회 → 1회. 공지 가격 표기 동기화.
-- 날짜: 2026-07-31 · 담당: 배경록
-- ⚠️ 배포: 프론트(lib/passes.js·ExchangeCenter·ReviewForm)의 가격 표기와 어긋나므로
--          db push 직후 prod 프론트 배포까지 한 번에 진행할 것(간극 동안 옛 표기로 새 가격이 결제됨).

-- ── 1) 열람권 가격 — 1시간권(5P) 신설 · 7일 20P · 30일 35P ──
-- purchase_pass/refund_pass/activate_pass는 pass_price()를 호출하므로 가격은 이 함수 교체만으로 반영된다.
-- ponytail: p_days=0 을 1시간권 센티널로 사용 — 시그니처·pass_balances 기존 키('7'/'30')·구 프론트와
--           전부 호환(재고 키는 '0'으로 쌓임). 시간 단위 상품이 더 생기면 그때 hours 단위로 리팩터.
create or replace function public.pass_price(p_days int)
returns int
language sql
immutable
as $$
  select case p_days when 0 then 5 when 7 then 20 when 30 then 35 else null end
$$;

-- ── 2) activate_pass — 1시간권(p_days=0)은 1시간, 나머지는 p_days일 연장 ──
-- 시그니처 불변 → drop 불필요. 본문은 최신본(20260624025109) 그대로, 연장 interval 계산만 분기.
create or replace function activate_pass(p_days int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_rows int;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if pass_price(p_days) is null then raise exception 'INVALID_DAYS'; end if;
  update users u
     set pass_balances = jsonb_set(
           coalesce(u.pass_balances, '{}'::jsonb), array[p_days::text],
           to_jsonb(coalesce((u.pass_balances ->> p_days::text)::int, 0) - 1), true),
         pass_expires_at = greatest(now(), coalesce(u.pass_expires_at, now()))
                           + case when p_days = 0 then interval '1 hour'
                                  else (p_days || ' days')::interval end
   where u.id = v_uid and coalesce((u.pass_balances ->> p_days::text)::int, 0) >= 1;
  get diagnostics v_rows = row_count;
  if v_rows = 0 then raise exception 'NO_PASS_STOCK'; end if;
  return _wallet();
end $$;

-- ── 3) 리뷰 적립 — 실명 25P · 익명 15P ──
-- 본문은 최신본(20260725120000) 그대로, 적립 상수만 15/5 → 25/15. 시그니처 불변.
-- delete_review_with_rollback은 실제 적립 합계(sum)를 회수하므로 수정 불필요.
-- ⚠️ update_review_with_points는 편집 시 현행 정책으로 재정산한다 — 개편 전 리뷰(15/5 적립)를
--    한 번이라도 수정하면 차액 +10P가 보전 지급됨(리뷰당 1회 수렴 후 재편집은 delta 0).
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
  v_amount integer := case when coalesce(p_is_anonymous, false) then 15 else 25 end;
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

-- ── 4) 광고 적립 5P 유지 · 일일 캡 2회 → 1회 ──
-- (reward_points는 prod 드리프트 방지용 수렴 — 이미 값이 같으면 no-op)
update ad_reward_config set reward_points = 5, daily_cap = 1, updated_at = now()
where id = 1 and (reward_points is distinct from 5 or daily_cap is distinct from 1);

-- ── 5) 공지 가격·횟수 표기 동기화 (이용 안내 · 리뷰 작성 가이드) ──
update public.notices
set content = replace(content, '실명 15P·익명 5P', '실명 25P·익명 15P')
where content like '%실명 15P·익명 5P%';

update public.notices
set content = replace(content, '광고 시청(1일 2회, 회당 5P)', '광고 시청(1일 1회, 회당 5P)')
where content like '%광고 시청(1일 2회, 회당 5P)%';

update public.notices
set content = replace(content, '열람권(7일 10P·30일 25P)', '열람권(1시간 5P·7일 20P·30일 35P)')
where content like '%열람권(7일 10P·30일 25P)%';

update public.notices
set content = replace(content,
  '닉네임 공개 리뷰는 15P, 익명 리뷰는 5P가 적립됩니다',
  '닉네임 공개 리뷰는 25P, 익명 리뷰는 15P가 적립됩니다')
where content like '%닉네임 공개 리뷰는 15P, 익명 리뷰는 5P가 적립됩니다%';
