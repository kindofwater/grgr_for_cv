-- 목적: 근장상세 담당자 전화번호·이메일 컬럼 제거 (개인정보 최소수집 — 2026-06-16 회의 결정 #15)
-- 날짜: 2026-06-19 · 담당: 배경록

alter table public.postings
  drop column if exists contact_phone,
  drop column if exists contact_email;
