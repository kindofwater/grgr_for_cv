-- 목적: postings.recruit_count varchar(20) → text (모집인원 원문 자유텍스트, 20자 초과 공고 수용)
-- 날짜: 2026-07-21 · 담당: 배경록
-- 비고: SSC 파서가 "2명 (중국어 상담조교 1명, 영어 상담조교 1명)" 같은 20자 초과 원문을 넣어 22001(value too long).
--       job_description·work_time_text 등 형제 자유텍스트 필드와 동일하게 text로 통일.
--       varchar→text는 바이너리 호환 = 테이블 재작성 없음, 기존 데이터 무손실. additive.

begin;

alter table postings alter column recruit_count type text;

commit;
