-- 목적: 리뷰 작성을 '내 학교 근무지'로 제한 — write_review_with_points에 대학 스코프 검사 추가
-- 날짜: 2026-07-20 · 담당: 배경록

-- 배경(보안): 현행 write_review_with_points는 auth.uid() 존재만 확인하고 근무지가 내 학교인지
--   전혀 검사하지 않았다. 게다가 security definer라 RLS도 우회한다. 그래서 /worksite/:id/review로
--   URL만 바꿔 들어가면 타 대학 근무지에도 리뷰를 쓸 수 있었고, 프런트를 가려도
--   RPC를 직접 호출하면 그만이라 UI 차단으로는 못 막는다. → 서버에서 막는다.
--
-- 규칙: 검색·홈과 동일한 대학 스코프(내 university_id + 공용 0)를 그대로 적용한다.
--   "내가 볼 수 있는 근무지만 리뷰할 수 있다"로 읽기/쓰기 권한을 일치시키는 게 핵심.
--   (별도 규칙을 새로 만들면 목록엔 안 보이는데 쓸 수는 있는 식의 어긋남이 또 생긴다.)
--
-- ⚠️ 현재 데이터 상태 메모(2026-07-20 실측):
--   university_id=0(공용) 근무지가 0건이고, 전국 대상인 교외 국가근장 6,647건이 전부 고려대(1)로
--   태깅돼 있었고, 공용(0) 대학 행 자체가 없어 스코프 SQL의 '공용' 분기가 죽은 코드였다.
--   → 짝이 되는 20260720060515_public_university_offcampus가 공용 행을 만들고 교외를 0으로 옮긴다.
--   ⚠️ 둘은 반드시 같이 적용돼야 한다. 이 검사만 넣고 데이터를 안 고치면
--   타 대학 학생이 전국 공통인 교외 국가근로에 리뷰를 못 쓰게 된다.
--
-- 수정 후 리뷰는 손대지 않는다: update_review_with_points는 `id=? and user_id=auth.uid()`라
--   남의 리뷰는 못 만지고, 이 변경 이전에 쓰인 본인 리뷰는 그대로 수정 가능하게 둔다(소급 차단 안 함).

create or replace function public.write_review_with_points(
  p_worksite_id integer, p_work_year integer, p_work_semester text,
  p_work numeric, p_growth numeric, p_vibe numeric, p_flex numeric, p_recommend numeric,
  p_work_content text, p_opinion text, p_is_anonymous boolean default false
) returns integer language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_review_id integer;
  v_amount integer := case when coalesce(p_is_anonymous, false) then 5 else 15 end;
  v_my_uni integer;
  v_ws_uni integer;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;

  -- 대학 스코프 검사 — 검색·홈(search_worksite_cards·get_home_feed)과 같은 규칙
  select university_id into v_my_uni from public.users where id = v_uid;
  select university_id into v_ws_uni
  from public.worksites
  where id = p_worksite_id and deleted_at is null;

  if v_ws_uni is null then raise exception 'WORKSITE_NOT_FOUND'; end if;
  if v_ws_uni <> 0 and v_ws_uni is distinct from v_my_uni then
    raise exception 'FORBIDDEN_WORKSITE';   -- 프런트가 이 코드로 안내 문구를 띄운다
  end if;

  insert into public.reviews (
    user_id, worksite_id, work_year, work_semester,
    score_work, score_growth, score_vibe, score_flex, score_recommend,
    work_content, opinion, is_anonymous)
  values (
    v_uid, p_worksite_id, p_work_year, p_work_semester,
    p_work, p_growth, p_vibe, p_flex, p_recommend,
    p_work_content, p_opinion, coalesce(p_is_anonymous, false))
  returning id into v_review_id;

  insert into public.points (user_id, amount, reason, review_id)
  values (v_uid, v_amount, 'review_write', v_review_id);

  update public.users set point_balance = point_balance + v_amount where id = v_uid;
  return v_review_id;
end $$;
