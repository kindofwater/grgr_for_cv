-- 목적: 크롤 공고 알림을 매일 갱신되는 1건에서 **주 단위(월~일) 1건**으로 바꾼다.
--       전환 시점의 고려대 공지를 '근로장학 공고 업데이트 (8월 3일~9일)'로 재작성한다.
-- 날짜: 2026-08-04 · 담당: 배경록
--
-- (원문 영문 주석) Replace the rolling daily crawl notice with one Monday-Sunday notice per week.
-- The two postings below are the verified Korea University source postings
-- created during the current week before weekly aggregation was introduced.
--
-- 본문의 공고 2건은 주간 집계 도입 **전에** 그 주에 생성된 것을 손으로 확인해 넣은 값이다
--   (크롤러가 계산한 게 아니라 이 시점의 스냅샷). 다음 주부터는 크롤러가 채운다.
-- 멱등: 제목 '근로장학 공고 업데이트' 기준 최신 1건을 잡아 없으면 insert · 있으면 update.
--   ⚠️ 뒤이어 20260804101000이 같은 공지에 자유전공학부 1건을 더해 '총 3건'으로 고친다 —
--      이 파일만 보면 '총 2건'이 최종처럼 보이지만 아니다.

begin;

do $$
declare
  notice_id integer;
begin
  select id
    into notice_id
  from public.notices
  where university_id = 1
    and title = '근로장학 공고 업데이트'
  order by id desc
  limit 1;

  if notice_id is null then
    insert into public.notices (title, content, university_id)
    values (
      '근로장학 공고 업데이트 (8월 3일~9일)',
      E'2026년 8월 3일~9일\n• [시설운영팀 근로장학생 모집]\n• [중앙도서관] 제2자료실 근로장학생 모집\n총 2건 업데이트 완료되었습니다.',
      1
    );
  else
    update public.notices
    set title = '근로장학 공고 업데이트 (8월 3일~9일)',
        content = E'2026년 8월 3일~9일\n• [시설운영팀 근로장학생 모집]\n• [중앙도서관] 제2자료실 근로장학생 모집\n총 2건 업데이트 완료되었습니다.',
        updated_at = now()
    where id = notice_id;
  end if;
end
$$;

commit;
