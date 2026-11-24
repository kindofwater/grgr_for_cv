-- 목적: 허위 리뷰(119) 제재 — 리뷰 블라인드 + 포인트 전액 몰수 + 열람권(활성·재고) 전량 회수
-- 날짜: 2026-08-14 · 담당: 배경록
--
-- 근거: 리뷰 119(근무지 6694 '고려대학교(본교) 학부 - 이과대학행정팀', 2026-1학기, 비익명)는
--   해당 근무지에서 실제 근무 중인 PM이 현장 확인한 결과 그곳에서 근무한 사람이 쓴 글이 아니다.
--   `opinion`도 점(.) 54자로만 채워져 있어 리뷰 최소길이(50자) CHECK를 우회한 형태다.
--   전체 리뷰 79건 중 반복문자만으로 채운 리뷰는 이 1건뿐이다(기계 스캔 확인).
--
-- ⚠️ reason을 'false_review_penalty'로 두는 것이 이 마이그레이션의 핵심이다.
--   update_review_with_points·delete_review_with_rollback은 회수/재정산 시
--     sum(amount) where review_id = ? and reason in ('review_write','review_anon_switch','review_policy_grant')
--   로 "이 리뷰가 받은 적립 합계"를 구한다. 몰수 행을 그 목록 안의 reason으로 넣으면
--   합계가 0이 되어, 작성자가 리뷰를 수정하는 순간 30P가 **다시 지급된다**.
--   목록 밖 reason을 쓰면 합계가 30P로 유지돼 재지급이 발생하지 않는다.
--   → 앞으로 저 목록에 reason을 추가할 때 'false_review_penalty'를 절대 포함시키지 말 것.
--
-- ⚠️ 부수효과(의도된 것): 몰수 후 잔액이 0이므로 작성자가 리뷰 119를 직접 삭제하려 하면
--   delete_review_with_rollback의 `if v_balance < v_grant then raise 'INSUFFICIENT_POINTS'` 에 걸려
--   삭제가 막힌다(증거 보존). 프론트에는 포인트 부족 계열 에러로 보인다.
--
-- 블라인드(§③)는 리뷰를 지우지 않고 목록에 placeholder 슬롯으로 남기며, 서버가 내용·점수·작성자를
--   NULL 마스킹하고 집계 RPC 3종(get_review_stats·get_worksite_score_cards·search_worksite_cards)에서
--   제외한다 → 근무지 6694의 평균·추천율·리뷰수에서 즉시 빠진다.
--
-- 멱등: 같은 (user, review)에 false_review_penalty 행이 이미 있으면 통째로 건너뛴다.
-- reset 안전: 맨바닥 재구축에는 리뷰 119가 없으므로 no-op.
-- 대상이 예상과 다르면(근무지 불일치) 조용히 넘어가지 않고 실패시킨다 — 20260810141449 선례.

begin;

do $$
declare
  v_review_id  constant integer := 119;
  v_worksite   constant integer := 6694;
  v_user       uuid;
  v_ws         integer;
  v_blinded    boolean;
  v_balance    integer;
  v_passes     jsonb;
  v_expires    timestamptz;
begin
  select r.user_id, r.worksite_id, r.is_blinded
    into v_user, v_ws, v_blinded
    from public.reviews r
   where r.id = v_review_id;

  if not found or v_user is null then
    raise notice '리뷰 %가 없거나 작성자가 없어(맨바닥 재구축·탈퇴 등) 건너뜁니다', v_review_id;
    return;
  end if;

  if v_ws <> v_worksite then
    raise exception '리뷰 %의 근무지가 예상(%)과 다릅니다: %', v_review_id, v_worksite, v_ws;
  end if;

  if exists (
    select 1 from public.points
     where user_id = v_user and review_id = v_review_id and reason = 'false_review_penalty'
  ) then
    raise notice '리뷰 % 제재가 이미 적용돼 있어 건너뜁니다', v_review_id;
    return;
  end if;

  select u.point_balance, u.pass_balances, u.pass_expires_at
    into v_balance, v_passes, v_expires
    from public.users u
   where u.id = v_user;

  if not found then
    raise notice '작성자 프로필(%)이 없어 건너뜁니다', v_user;
    return;
  end if;

  raise notice '[제재 전] user=% / is_blinded=% / point_balance=% / pass_balances=% / pass_expires_at=%',
    v_user, v_blinded, v_balance, v_passes, v_expires;

  -- 1) 리뷰 블라인드 — 집계에서 빠지고 목록엔 placeholder만 남는다
  if v_blinded then
    raise notice '[리뷰] 이미 블라인드 상태입니다';
  else
    update public.reviews set is_blinded = true, updated_at = now() where id = v_review_id;
    raise notice '[리뷰] % 블라인드 처리 완료', v_review_id;
  end if;

  -- 2) 포인트 전액 몰수 — 원장에 사유를 남긴다(마이페이지 라벨: '거짓/허위 리뷰 작성')
  if coalesce(v_balance, 0) > 0 then
    insert into public.points (user_id, amount, reason, review_id)
    values (v_user, -v_balance, 'false_review_penalty', v_review_id);

    update public.users set point_balance = 0, updated_at = now() where id = v_user;
    raise notice '[포인트] %P 몰수 완료', v_balance;
  else
    raise notice '[포인트] 잔액이 0이라 몰수할 포인트가 없습니다';
  end if;

  -- 3) 열람권 회수 — 활성(만료시각) + 미활성화 재고 둘 다.
  --    재고를 남기면 작성자가 곧바로 재활성화해 열람권을 다시 쓸 수 있다.
  if v_expires is null then
    raise notice '[열람권] 활성 열람권이 없습니다';
  else
    raise notice '[열람권] 만료시각 % → null 회수', v_expires;
  end if;

  if v_passes is null or v_passes = '{}'::jsonb then
    raise notice '[열람권] 미활성화 재고가 없습니다';
  else
    raise notice '[열람권] 미활성화 재고 % → {} 몰수', v_passes;
  end if;

  update public.users
     set pass_expires_at = null,
         pass_balances   = '{}'::jsonb,
         updated_at      = now()
   where id = v_user;
end
$$;

commit;
