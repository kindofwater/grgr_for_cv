-- 목적: 주간 크롤 공지(20260804100000)에 자유전공학부 공고 1건을 추가해 '총 3건'으로 정정한다.
--       에브리타임 수기 소스로 들어온 건이라 크롤러 집계에서 빠져 있었다.
-- 날짜: 2026-08-04 · 담당: 배경록
--
-- (원문 영문 주석) The Liberal Studies posting was created this week through the manually
-- curated Everytime source, so include it in the same weekly crawl notice.
--
-- ⚠️ 20260804100000이 먼저 적용돼 있어야 한다 — 그 파일이 만든 제목
--    '근로장학 공고 업데이트 (8월 3일~9일)'를 where로 잡는다.
-- 반영 검증: update 뒤 do 블록이 자유전공학부 문구와 '총 3건'을 모두 확인하고, 없으면 raise로
--    트랜잭션을 되돌린다(조용한 no-op 방지 — 제목이 안 맞으면 0행 update로 지나갔을 것이다).

begin;

update public.notices
set content = E'2026년 8월 3일~9일\n• [시설운영팀 근로장학생 모집]\n• [자유전공학부] 근로장학생 모집\n• [중앙도서관] 제2자료실 근로장학생 모집\n총 3건 업데이트 완료되었습니다.',
    updated_at = now()
where university_id = 1
  and title = '근로장학 공고 업데이트 (8월 3일~9일)';

do $$
begin
  if not exists (
    select 1
    from public.notices
    where university_id = 1
      and title = '근로장학 공고 업데이트 (8월 3일~9일)'
      and content like '%[자유전공학부] 근로장학생 모집%'
      and content like '%총 3건 업데이트 완료되었습니다.%'
  ) then
    raise exception '자유전공학부 주간 공지 반영 검증 실패';
  end if;
end
$$;

commit;
