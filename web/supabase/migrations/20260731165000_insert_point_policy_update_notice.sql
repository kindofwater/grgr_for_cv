-- 목적: 2026-07-31 포인트 적립 및 열람권 가격 정책 변경을 전교 공통 공지로 안내한다.
-- 날짜: 2026-07-31 · 담당: 배경록
-- 본문은 평문이며 Notice.jsx가 white-space: pre-wrap으로 렌더한다.
-- 제목·공통 범위 기준으로 갱신 후 없으면 삽입해 reset·재실행 시 중복을 막는다.

do $do$
declare
  v_title text := '[업데이트] 포인트 및 열람권 정책이 변경됐어요';
  v_content text := $notice$안녕하세요, 근로고래입니다. 🐳

더 많은 근무 경험이 공유될 수 있도록 리뷰 포인트와 열람권 정책을 개편했습니다.

1. 리뷰 작성 포인트가 늘어났어요

닉네임 공개 리뷰는 15P에서 25P로, 익명 리뷰는 5P에서 15P로 상향되었습니다.

정책 변경 전에 리뷰를 작성한 회원에게도 변경된 적립 기준에 맞춰 리뷰별 차액을 자동 지급했습니다.

2. 1시간 열람권이 새로 생겼어요

짧게 리뷰를 확인하고 싶은 분들을 위해 1시간 열람권을 새롭게 추가했습니다.

• 1시간 열람권: 5P

열람권은 교환 후 ‘사용’ 버튼을 누른 시점부터 적용됩니다.

3. 7일·30일 열람권 가격이 인상됐어요

리뷰 작성으로 받을 수 있는 포인트가 늘어남에 따라 기존 열람권의 교환 가격도 함께 조정되었습니다.

• 7일 열람권: 10P → 20P
• 30일 열람권: 25P → 35P

4. 광고 포인트 적립 횟수가 변경됐어요

광고 시청 보상은 기존과 동일하게 회당 5P이며, 하루 적립 가능 횟수는 2회에서 1회로 변경되었습니다.

변경된 정책은 2026년 7월 31일부터 적용됩니다.

앞으로도 근로장학생의 경험이 더 잘 공유될 수 있도록 서비스를 개선하겠습니다.

감사합니다.
근로고래 드림$notice$;
begin
  update public.notices
  set content = v_content,
      is_pinned = false,
      updated_at = now()
  where university_id is null
    and title = v_title;

  if not found then
    insert into public.notices (
      title,
      content,
      is_pinned,
      university_id
    ) values (
      v_title,
      v_content,
      false,
      null
    );
  end if;
end
$do$;
