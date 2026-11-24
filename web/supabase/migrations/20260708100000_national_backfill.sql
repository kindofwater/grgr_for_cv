-- 목적: 국가근장(national) 공고를 장기·학부생만·재학생만으로 백필 (KOSAF 임포터가 미정 3/3/unknown으로 넣던 것 → 도메인 규칙값)
-- 날짜: 2026-07-08 · 담당: 배경록
-- 비고: 스키마/RPC 변경이 아닌 데이터 백필. 국가근로장학금은 KOSAF 파일에 학위/학적/기간 컬럼이 없어 임포트 시 전부 미정(eligible_degree=3·eligible_status=3·work_duration_type='unknown')으로 들어갔음. 규칙상 항상 장기·학부생만·재학생만이라 일괄 지정. (크롤러 소스는 추후 재작성 예정이라 미변경 — 재작성 시 이 값으로 넣을 것.)
--       db reset 시엔 postings 데이터가 없어 0행 영향(무해). prod push 시 기존 국가근장 공고에 반영.

update postings p
set work_duration_type = 'long',   -- 장기
    eligible_degree     = 0,       -- 학부생만
    eligible_status     = 0        -- 재학생만
from worksites w
where p.worksite_id = w.id
  and w.type = 'national';
