-- 21일 마감 정책 백필은 이 마이그레이션만으로 실행되지 않는다.
-- 서비스 역할이 미리보기의 대상 건수를 확인한 뒤 RPC를 명시 호출해야 한다.

begin;

create or replace function public.apply_school_deadline_backfill(
  p_expected_count integer
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_count integer;
  v_updated integer;
begin
  select count(*)
    into v_count
    from public.postings p
    join public.worksites w on w.id = p.worksite_id
   where w.university_id = 1
     and w.type = 'school'
     and w.deleted_at is null
     and p.deleted_at is null
     and not p.is_placeholder
     and p.source in ('ssc', 'kupid', 'everytime_manual')
     and not p.manual_override
     and (p.recruit_until_estimated or p.recruit_until is null)
     and p.id <> 7257;

  if v_count <> p_expected_count then
    raise exception 'deadline backfill target changed: expected %, actual %',
      p_expected_count, v_count
      using errcode = '40001';
  end if;

  -- 실제 마감을 사람이 확인한 산학협력단 연구지원팀 공고는 재개 금지.
  update public.postings
     set is_active = false,
         deadline_basis = 'human_confirmed',
         source_closed_at = coalesce(
           source_closed_at,
           (now() at time zone 'Asia/Seoul')::date
         ),
         source_closed_reason = coalesce(
           source_closed_reason, 'human_confirmed'
         )
   where id = 7257
     and deleted_at is null;

  update public.postings p
     set recruit_until =
           ((p.created_at at time zone 'Asia/Seoul')::date + 20),
         recruit_until_estimated = true,
         deadline_basis = case
           when p.source = 'everytime_manual' then 'first_seen_window'
           else 'posted_window'
         end,
         is_active = (
           ((p.created_at at time zone 'Asia/Seoul')::date + 20)
           >= (now() at time zone 'Asia/Seoul')::date
         )
    from public.worksites w
   where w.id = p.worksite_id
     and w.university_id = 1
     and w.type = 'school'
     and w.deleted_at is null
     and p.deleted_at is null
     and not p.is_placeholder
     and p.source in ('ssc', 'kupid', 'everytime_manual')
     and not p.manual_override
     and (p.recruit_until_estimated or p.recruit_until is null)
     and p.id <> 7257;

  get diagnostics v_updated = row_count;
  return jsonb_build_object(
    'updated', v_updated,
    'protected_human_confirmed_id', 7257
  );
end;
$$;

revoke all on function public.apply_school_deadline_backfill(integer)
  from public, anon, authenticated;
grant execute on function public.apply_school_deadline_backfill(integer)
  to service_role;

commit;
