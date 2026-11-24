-- 목적: 신고로 확인된 리뷰 63을 미디어대학행정팀(6794) → 원격교육센터(6823)로 재배정 — 근무지 오배정 정정
-- 날짜: 2026-08-10 · 담당: 배경록
--
-- 근거(신고 id=2 '허위/과장 후기' 검증, 2026-08-10):
--   리뷰 63(2024-1학기·익명)은 '블랙보드 어흥톡 응대'·'공강시간만 이용해 근무' 후기인데,
--   미디어대학행정팀 공고는 2023~2025 전부 휴학(예정)생만·월~금 9~16시 고정 풀타임이라
--   공강 근무가 구조적으로 불가능하다(신고 취지와 일치). 반면 원격교육센터의 2024-1학기
--   공고(posting 7518)는 업무가 정확히 '유선 전화 및 챗봇(어흥톡) 응대'이고 학부 재학생
--   대상·평일 오전/오후 시간 선택(공강 활용형)이다. 두 근무지 모두 미디어관 소재라 리뷰
--   작성 시 '미디어' 검색으로 잘못 선택한 것으로 판단 — 허위가 아니라 오배정이므로
--   블라인드 대신 재배정한다(PM 결정).
--
-- reports.status(id=2)는 pending으로 둔다 — report_status_e('pending'/'deleted'/'ignored')에
--   '이동 조치'에 맞는 값이 없다. 필요하면 별도 마이그레이션에서 enum 확장.
-- 평점은 라이브 집계(get_review_stats 등)라 이동만으로 양쪽 근무지에 즉시 반영된다.
-- 멱등·reset 안전: 이미 6823이면 no-op, 리뷰가 없으면(맨바닥 재구축) 건너뛴다.
--   근무지가 6794도 6823도 아니면 예기치 못한 상태이므로 실패시킨다.

begin;

do $$
declare
  v_worksite integer;
begin
  select worksite_id into v_worksite
    from public.reviews
   where id = 63 and deleted_at is null;

  if v_worksite is null then
    raise notice '리뷰 63이 없어(맨바닥 재구축 등) 건너뜁니다';
    return;
  end if;

  if v_worksite = 6823 then
    return; -- 이미 이동됨
  end if;

  if v_worksite <> 6794 then
    raise exception '리뷰 63의 근무지가 예상(6794)과 다릅니다: %', v_worksite;
  end if;

  perform 1
     from public.worksites
    where id = 6823 and workplace_name = '원격교육센터' and deleted_at is null;
  if not found then
    raise exception '원격교육센터(6823) 근무지를 찾지 못했습니다';
  end if;

  update public.reviews
     set worksite_id = 6823,
         updated_at  = now()
   where id = 63;
end
$$;

commit;
