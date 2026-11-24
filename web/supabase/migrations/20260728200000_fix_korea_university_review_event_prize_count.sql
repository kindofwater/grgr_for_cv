-- 목적: 고려대학교 서울캠퍼스 리뷰 이벤트 공지의 아메리카노 경품 인원을 10명으로 정정한다.
-- 날짜: 2026-07-28 · 담당: 배경록
-- 고려대 리뷰 이벤트 공지의 아메리카노 경품 수를 10명으로 바로잡는다.
-- 서울대 공지는 5명이므로 고려대학교 공지에만 적용한다.

update public.notices as n
set content = replace(
  n.content,
  '메가커피 아메리카노 교환권 5명',
  '메가커피 아메리카노 교환권 10명'
)
from public.universities as u
where n.university_id = u.id
  and u.name = '고려대학교'
  and u.campus = '서울'
  and n.title = '[이벤트] 근무지 리뷰 작성 이벤트'
  and n.content like '%메가커피 아메리카노 교환권 5명%';
