-- 목적: 공지 1건 추가 — 아직 등록되지 않은 근로장학 정보(SSC 전용 공고·KUPID 조교) 안내
-- 날짜: 2026-07-20 · 담당: 배경록

-- 스키마 변경 없음(notices 데이터 insert만). 제목 기준 멱등 — db reset·재push 시 중복 방지.
-- 본문은 평문(notices.content) — Notice.jsx가 pre-wrap 텍스트로 렌더(HTML 파싱 안 함).
-- is_pinned=false: 데이터를 채우면 내릴 임시 안내라 상단 고정하지 않는다(PM 결정).
--   나중에 두 출처를 적재하면 이 공지를 삭제할 것 — 삭제는 20260720041021 방식(제목 기준 delete) 참고.

insert into notices (title, content, is_pinned)
select
  '[안내] 아직 등록되지 않은 근로장학 정보가 있어요',
  $notice$현재 근로고래에 아직 들어오지 않은 근로장학 정보가 있습니다.
준비되는 대로 채워 넣겠습니다.


■ 아직 등록되지 않은 정보

· SSC(Student Success Center)에만 올라오는 학교근로장학
· KUPID의 조교 학교근로장학


■ 언제 들어오나요

근시일 내에 순차적으로 추가할 예정입니다.
그때까지는 해당 근로장학을 찾으신다면 KUPID와 SSC 공지를 함께 확인해 주세요.


찾으시는 근무지가 보이지 않는다면 문의사항으로 알려주세요.
어떤 정보부터 채울지 정하는 데 큰 도움이 됩니다.$notice$,
  false
where not exists (
  select 1 from notices
  where title = '[안내] 아직 등록되지 않은 근로장학 정보가 있어요'
);
