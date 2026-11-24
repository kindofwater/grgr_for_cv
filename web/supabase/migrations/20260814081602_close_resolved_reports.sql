-- 목적: 처리 완료된 신고 3건의 status를 pending → 실제 결말로 닫기
-- 날짜: 2026-08-14 · 담당: 배경록
--
-- 배경: 신고 접수는 report_review RPC로만 들어오고 상태를 바꿀 UI가 없어, 조치는 다 해놓고
--   status는 전부 pending으로 남아 있었다. 결말별로 닫는다(값 정의는 20260814081557 참고).
--
--   id=1 · 리뷰 53 · '기타' · 내용 없음(2026-07-31 opinion 필수화 이전 접수)
--     → **ignored**. 리뷰 53은 지금도 살아 있고(blinded=false·deleted_at=null) 마지막 수정이
--        신고(07-26 12:31)보다 앞선 07-26 09:10 — 접수 후 아무 조치도 이뤄진 적이 없다.
--        사유가 '기타'인데 상세 의견도 없어 판단할 근거 자체가 없었다.
--
--   id=2 · 리뷰 63 · '허위/과장 후기'
--     → **moved**. 공고 데이터로 검증한 결과 허위가 아니라 근무지 오배정이었고,
--        20260810141449가 미디어대학행정팀(6794) → 원격교육센터(6823)로 재배정했다.
--
--   id=3 · 리뷰 119 · '허위/과장 후기' · "제가 여기서 일하는데, 이런 사람 본 적이 없어요"
--     → **blinded**. 근무지 6694에서 실제 근무 중인 PM의 현장 확인으로 허위 확정.
--        20260814071343이 블라인드 + 작성자 포인트 몰수 + 열람권 회수까지 처리했다.
--        (그 push 로그가 동기도 확정했다 — 리뷰 작성 13초 뒤 7일 열람권 활성화.)
--
-- ⚠️ 20260814081557(enum 값 추가)이 **먼저** 적용돼야 한다. 같은 트랜잭션에서 새 enum 값을
--    쓸 수 없어 파일을 나눈 것이므로, 두 파일의 타임스탬프 순서를 뒤집지 말 것.
-- 멱등: 이미 닫힌 행은 `status = 'pending'` 조건에 안 걸려 no-op.
-- reset 안전: 맨바닥 재구축엔 reports 행이 없어 0행 갱신.

begin;

do $$
declare
  v_closed integer;
  v_left   integer;
begin
  update public.reports set status = 'ignored' where id = 1 and status = 'pending';
  update public.reports set status = 'moved'   where id = 2 and status = 'pending';
  update public.reports set status = 'blinded' where id = 3 and status = 'pending';

  select count(*) into v_closed from public.reports where status <> 'pending';
  select count(*) into v_left   from public.reports where status =  'pending';
  raise notice '[신고] 닫힘 %건 / 남은 pending %건', v_closed, v_left;

  if v_left > 0 then
    raise warning '[신고] 아직 pending인 신고가 %건 있습니다 — 이 마이그레이션 작성 이후 새로 접수된 건', v_left;
  end if;
end
$$;

commit;
