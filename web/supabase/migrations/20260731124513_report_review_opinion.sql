-- 목적: reports에 opinion(신고 상세 내용) 컬럼 추가 + report_review RPC에 p_opinion 인자 추가(필수)
-- 날짜: 2026-07-31 · 담당: 배경록
-- (원래 20260731120000_report_opinion.sql — 20260731120000_skip_anonymous_home_hero.sql과 버전 충돌로
--  적용이 막혀 CLI 발급 타임스탬프로 리네임. 수동 작명 금지 교훈 재확인 — supabase README 참조)

alter table reports add column if not exists opinion text;  -- 기존 row는 NULL 유지

-- 시그니처 변경 → 옛 함수 먼저 제거 (CLAUDE.md 규칙: 안 지우면 옛 (int, text) 버전이 남아 RPC가 꼬임)
drop function if exists report_review(int, text);

create or replace function report_review(p_review_id int, p_reason text, p_opinion text)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_reported uuid;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  -- 내용 필수 — 프론트도 막지만 트러스트 바운더리는 서버
  if p_opinion is null or btrim(p_opinion) = '' then raise exception 'OPINION_REQUIRED'; end if;
  if length(p_opinion) > 500 then raise exception 'OPINION_TOO_LONG'; end if;
  select user_id into v_reported from reviews where id = p_review_id;
  insert into reports (reporter_id, reported_user_id, review_id, reason, opinion)
  values (v_uid, v_reported, p_review_id, p_reason, btrim(p_opinion));
end $$;

revoke execute on function report_review(int, text, text) from anon, public;
grant  execute on function report_review(int, text, text) to authenticated;
