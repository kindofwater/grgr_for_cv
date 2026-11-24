-- 목적: 고려대 전용 교우회·교우장학회 국가근로 안내 공고의 직무 내용을 미확인값으로 비운다.
-- 날짜: 2026-08-05 · 담당: Codex

begin;

update public.postings
   set job_description = null,
       updated_at = now()
 where source = 'manual_seed'
   and external_id in (
     'ku-manual:alumni-scholarship-foundation',
     'ku-manual:alumni-association'
   )
   and deleted_at is null
   and job_description is not null;

do $$
declare
  v_blank_count integer;
begin
  select count(*) into v_blank_count
  from public.postings
  where source = 'manual_seed'
    and external_id in (
      'ku-manual:alumni-scholarship-foundation',
      'ku-manual:alumni-association'
    )
    and deleted_at is null
    and job_description is null;

  if v_blank_count <> 2 then
    raise exception 'Expected 2 KU alumni national postings with blank job description, got %', v_blank_count;
  end if;
end
$$;

commit;
