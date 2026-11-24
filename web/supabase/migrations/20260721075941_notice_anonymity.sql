-- 목적: 공지 1건 추가 — 리뷰 익명성·개인정보 보호 안내(공지 개편 후속, 신뢰 장치 명시)
-- 날짜: 2026-07-21 · 담당: 배경록
-- 멱등: 제목 기준 where not exists(재실행·로컬 reset 안전). 사실관계는 구현과 일치 —
--   기본 닉네임 표시 / is_anonymous면 닉네임·근무학기 서버 마스킹(list_worksite_reviews) /
--   탈퇴 시 reviews.user_id SET NULL(작성자 분리).

insert into notices (title, content, is_pinned)
select
  '[안내] 리뷰 익명성과 개인정보 보호',
  '리뷰는 기본적으로 닉네임으로 표시되며, 작성 시 익명을 선택하면 닉네임과 근무 학기가 모두 숨겨집니다. 어떤 경우에도 이메일 등 계정 정보는 다른 사용자에게 공개되지 않습니다.

회원 탈퇴 시 작성한 리뷰는 작성자 정보와 완전히 분리되어 누가 썼는지 알 수 없게 처리됩니다. 안심하고 솔직한 경험을 남겨 주세요.

개인정보 처리에 대한 자세한 내용은 하단의 개인정보처리방침에서 확인할 수 있습니다.',
  false
where not exists (select 1 from notices where title = '[안내] 리뷰 익명성과 개인정보 보호');
