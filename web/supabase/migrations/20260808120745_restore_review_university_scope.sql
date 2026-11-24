-- 목적: write_review_with_points의 대학 스코프 검사(FORBIDDEN_WORKSITE) 복구 — 20260725120000이
--       본문을 재선언하며 조용히 떨어뜨린 것을 되돌린다.
-- 날짜: 2026-08-08 · 담당: 배경록
--
-- 무슨 일이 있었나:
--   20260720060234_review_university_scope가 "내가 볼 수 있는 근무지만 리뷰할 수 있다"는 규칙으로
--   대학 스코프 검사를 넣었다. 그런데 20260725120000_enforce_national_review_semesters가 학기 검증을
--   추가하면서 **그 검사가 없는 본문**으로 create or replace 했고, 이후 20260731105714 →
--   20260808113010이 그 본문을 그대로 이어받아 복사했다. 결과적으로 2026-07-25부터 검사가 없다.
--
-- 무엇이 뚫렸나:
--   write_review_with_points는 security definer라 RLS를 우회한다. 검사가 없으면 로그인한 A대학
--   학생이 supabase.rpc('write_review_with_points', { p_worksite_id: <B대학 근무지> })를 직접 호출해
--   근무한 적 없는 타 대학 근무지에 리뷰를 쓰고 적립까지 받을 수 있다. 프런트를 가려도 RPC 직접
--   호출이면 그만이라 UI 차단으로는 못 막는다. 20260808113010이 적립액을 25/15 → 30/20으로 올려
--   이 구멍의 값어치만 커진 상태다.
--
-- 규칙(20260720060234 원문 그대로): 내 university_id + 공용(0). 검색·홈과 동일한 스코프라
--   읽기/쓰기 권한이 일치한다. 교외 국가근장은 20260720060515가 university_id=0으로 옮겨놨으므로
--   타 대학 학생도 계속 리뷰할 수 있다(공용 분기가 살아 있음).
--
-- 본문은 현행 최신(20260808113010)을 그대로 재현 + 스코프 검사 블록만 복원. 시그니처 불변 →
--   create or replace(DROP 불필요), 기존 grant 유지됨. 프런트는 이미 이 코드를 처리한다
--   (web/src/pages/ReviewForm.jsx의 reviewSaveErrorMessage) — 프런트 변경 불필요.
--
-- update_review_with_points는 손대지 않는다: `id = ? and user_id = auth.uid()`라 남의 리뷰를 못 만지고,
--   검사 공백기(2026-07-25~08-08)에 쓰인 본인 리뷰는 그대로 수정 가능하게 둔다(소급 차단 안 함).
--   ⚠️ 그 기간에 실제로 타 대학 리뷰가 쓰였는지는 이 마이그레이션이 판단·삭제하지 않는다.
--      아래 감사 쿼리로 확인 후 사람이 처리할 것(블라인드·삭제는 운영 판단).
--      **push와 같은 작업 세션에서 돌릴 것** — "나중에"는 안 돌아간다.
--
--   ⚠️ users는 left join이어야 한다: reviews.user_id는 on delete set null이라 탈퇴한 유저의
--      리뷰는 inner join이면 조용히 빠진다(0행 = 깨끗함으로 오독하게 된다).
--      user_uni가 null인 행 = 작성자 탈퇴 → 대학 대조 불가이므로 육안 확인 대상.
--      w.deleted_at도 걸러야 이미 지워진 근무지가 잡히지 않는다.
--
--   select r.id, r.user_id, u.university_id as user_uni, w.university_id as ws_uni,
--          w.organization_name, r.created_at
--     from reviews r
--     join worksites w on w.id = r.worksite_id
--     left join users u on u.id = r.user_id
--    where r.deleted_at is null
--      and w.deleted_at is null
--      and w.university_id <> 0
--      and (u.id is null or w.university_id is distinct from u.university_id)
--    order by r.created_at;

begin;

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
  v_my_uni integer;
  v_ws_uni integer;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;

  -- 대학 스코프 검사 — 검색·홈(search_worksite_cards·get_home_feed)과 같은 규칙.
  -- 학기 검증보다 먼저 한다: 권한이 없으면 대상 근무지의 학기 규칙을 알려줄 이유도 없다.
  select university_id into v_my_uni from public.users where id = v_uid;
  select university_id into v_ws_uni
  from public.worksites
  where id = p_worksite_id and deleted_at is null;

  if v_ws_uni is null then raise exception 'WORKSITE_NOT_FOUND'; end if;
  if v_ws_uni <> 0 and v_ws_uni is distinct from v_my_uni then
    raise exception 'FORBIDDEN_WORKSITE';   -- 프런트가 이 코드로 안내 문구를 띄운다
  end if;

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

commit;
