-- 목적: '[업데이트] 8월 8일' 공지를 전교 공통 1건에서 학교별 2건(고려대·서울대)으로 분리하고,
--       서울대 열람권·적립 조정 내용을 서울대 공지 본문에 합친다. 기존 서울대 전용 공지는 제거.
-- 날짜: 2026-08-09 · 담당: 배경록
--
-- 왜 분리하나: 서울대는 최소 열람권 5분·광고 2P(20260808134041), 고려대는 60분·5P다.
--   한 공지에 담으면 어느 한쪽에 사실이 아닌 안내가 된다. 학교별로 나누면 각 본문이
--   그 학교에서 참인 값만 말한다.
--
-- ⚠️ 트레이드오프: notices RLS는 "university_id is null or university_id = 내 대학"이라
--    university_id를 채우는 순간 **비로그인 방문자에게는 안 보인다**. /notice는 크롤러가 보는
--    거의 유일한 산문이라(20260716130000 애드센스 대응 메모 참고) 공개 텍스트 총량이 줄어든다.
--    되돌리려면 아래 두 공지를 지우고 20260808113010이 만든 공통 공지를 복원하면 된다.
--
-- ⚠️ 서울대 본문의 조정 항목은 '한시적'·'되돌립니다'·사과 표현 없이 사실만 적는다(PM 지시).
--    되돌릴 계획 자체는 university_point_policy 행 삭제로 남아 있고, 그때 공지도 다시 정리한다.

begin;

do $$
declare
  v_ku_id      integer;
  v_snu_id     integer;
  v_common     text;
  v_ku_body    text;
  v_snu_body   text;
begin
  select id into v_ku_id  from public.universities where name = '고려대학교';
  select id into v_snu_id from public.universities where name = '서울대학교';
  if v_ku_id is null or v_snu_id is null then
    raise exception '고려대학교·서울대학교 대학 행을 찾지 못해 공지 분리를 중단합니다';
  end if;

  -- 두 학교 공통 본문(20260808113010이 만든 전교 공통 공지 원문 그대로).
  v_common := $notice$안녕하세요, 근로고래입니다. 🐳

2026년 8월 8일에 반영된 포인트 정책 변경을 안내드립니다.

1. 리뷰 적립 포인트 상향

• 닉네임 공개 리뷰: 25P → 30P
• 익명 리뷰: 15P → 20P

2. 가입 축하금 지급 종료

가입만으로 지급하던 축하 포인트 5P의 지급을 종료했습니다. 이미 지급받으신 포인트는 회수하지 않으며 그대로 사용하실 수 있습니다. 해당 재원은 위의 리뷰 적립 포인트 상향에 사용됩니다.

3. 기존 리뷰 소급 지급

리뷰를 2개 이상 작성해 주신 분들께 포인트를 소급 지급했습니다. 가장 먼저 작성한 리뷰를 제외한 나머지 리뷰마다 5P씩 지급되어, 리뷰 2개는 5P, 3개는 10P가 적립됩니다.

삭제한 리뷰는 작성 개수에 포함되지 않습니다.$notice$;

  v_ku_body := v_common || $notice$

리뷰를 남겨주시는 분들께 더 많은 혜택이 돌아가도록 정책을 조정했습니다. 앞으로도 계속 개선하겠습니다.

감사합니다.
근로고래 드림$notice$;

  -- 서울대 본문 = 공통 + 4항(열람권·적립 조정). 건조하게 사실만.
  v_snu_body := v_common || $notice$

4. 열람권·광고 적립 조정

리뷰 작성 제고를 위해 아래와 같이 조정했습니다.

• 최소 열람권: 1시간 → 5분 (가격은 5P 그대로)
• 광고 시청 적립: 1편당 5P → 2P

7일 열람권(20P)과 30일 열람권(35P)의 기간과 가격은 변동 없습니다.

리뷰를 남겨주시는 분들께 더 많은 혜택이 돌아가도록 정책을 조정했습니다. 앞으로도 계속 개선하겠습니다.

감사합니다.
근로고래 드림$notice$;

  -- ── 고려대 공지 upsert ──
  if exists (select 1 from public.notices
              where university_id = v_ku_id and title = '[업데이트] 8월 8일') then
    update public.notices
       set content = v_ku_body, is_pinned = false, updated_at = now()
     where university_id = v_ku_id and title = '[업데이트] 8월 8일';
  else
    insert into public.notices (title, content, is_pinned, university_id)
    values ('[업데이트] 8월 8일', v_ku_body, false, v_ku_id);
  end if;

  -- ── 서울대 공지 upsert ──
  if exists (select 1 from public.notices
              where university_id = v_snu_id and title = '[업데이트] 8월 8일') then
    update public.notices
       set content = v_snu_body, is_pinned = false, updated_at = now()
     where university_id = v_snu_id and title = '[업데이트] 8월 8일';
  else
    insert into public.notices (title, content, is_pinned, university_id)
    values ('[업데이트] 8월 8일', v_snu_body, false, v_snu_id);
  end if;

  -- ── 전교 공통 원본 제거 ──
  -- 위 두 건이 대체한다. 이 줄이 없으면 서울대 유저에게 공통본과 서울대본이 함께 뜬다.
  delete from public.notices
   where university_id is null and title = '[업데이트] 8월 8일';

  -- ── 구 서울대 전용 공지 제거 ──
  -- 20260808134041이 만든 '[안내] 서울대 열람권·적립 한시 조정'. 내용이 위 4항에 흡수됐다.
  delete from public.notices
   where university_id = v_snu_id and title = '[안내] 서울대 열람권·적립 한시 조정';
end
$$;

commit;
