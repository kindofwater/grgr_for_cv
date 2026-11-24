-- 반자동 크롤러의 공고별 근무장소·마감 근거·출처 마감 상태와
-- 원자적 검토 큐 enqueue를 추가한다. 데이터 백필은 별도 승인 후 수행한다.

begin;

alter table public.postings
  add column if not exists source_department text,
  add column if not exists work_department text,
  add column if not exists work_location text,
  add column if not exists office_phone varchar(30),
  add column if not exists deadline_basis varchar(30),
  add column if not exists source_closed_at date,
  add column if not exists source_closed_reason varchar(50);

alter table public.postings
  drop constraint if exists postings_deadline_basis_check;
alter table public.postings
  add constraint postings_deadline_basis_check check (
    deadline_basis is null or deadline_basis in (
      'explicit', 'posted_window', 'first_seen_window',
      'work_start', 'human_confirmed'
    )
  );

comment on column public.postings.work_location is
  '이 공고에만 해당하는 건물·층·호실. worksites.address 정본을 자동 변경하지 않는다.';
comment on column public.postings.office_phone is
  '근무지 판정 검토용 사무실 유선번호. 공개 컬럼이 아니다.';
comment on column public.postings.source_closed_at is
  '목록 제목의 강한 마감 표지를 처음 확인한 KST 날짜. 자동 재개하지 않는다.';

alter table public.worksite_resolution_queue
  add column if not exists office_phone varchar(30);

-- 공개 상세 RPC를 통해서만 work_location을 전달한다. office_phone과
-- 게시/근무 부서는 기존 postings 컬럼 화이트리스트에 추가하지 않는다.
revoke select (source_department, work_department, office_phone,
               deadline_basis, source_closed_at, source_closed_reason)
  on table public.postings from public, anon, authenticated;

create or replace function public.enqueue_worksite_review(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row public.worksite_resolution_queue%rowtype;
begin
  if nullif(p_payload->>'source', '') is null
     or nullif(p_payload->>'external_id', '') is null
     or nullif(p_payload->>'raw_worksite_name', '') is null
     or nullif(p_payload->>'normalized_worksite', '') is null then
    raise exception 'incomplete worksite review payload'
      using errcode = '22023';
  end if;

  insert into public.worksite_resolution_queue (
    university_id, source, external_id, raw_worksite_name,
    normalized_worksite, title, evidence_text, office_phone,
    resolution_reason, explicit_worksite_names,
    candidate_worksite_ids, candidate_scores, status, updated_at
  )
  values (
    coalesce((p_payload->>'university_id')::integer, 1),
    p_payload->>'source',
    p_payload->>'external_id',
    left(p_payload->>'raw_worksite_name', 200),
    left(p_payload->>'normalized_worksite', 200),
    left(p_payload->>'title', 500),
    left(p_payload->>'evidence_text', 1500),
    left(p_payload->>'office_phone', 30),
    coalesce(nullif(p_payload->>'resolution_reason', ''), 'new_name'),
    coalesce(array(
      select jsonb_array_elements_text(p_payload->'explicit_worksite_names')
    ), '{}'::text[]),
    coalesce(array(
      select value::integer
      from jsonb_array_elements_text(p_payload->'candidate_worksite_ids')
    ), '{}'::integer[]),
    coalesce(p_payload->'candidate_scores', '[]'::jsonb),
    'pending',
    now()
  )
  on conflict (university_id, source, external_id)
  do update set
    raw_worksite_name = excluded.raw_worksite_name,
    normalized_worksite = excluded.normalized_worksite,
    title = excluded.title,
    evidence_text = excluded.evidence_text,
    office_phone = excluded.office_phone,
    resolution_reason = excluded.resolution_reason,
    explicit_worksite_names = excluded.explicit_worksite_names,
    candidate_worksite_ids = excluded.candidate_worksite_ids,
    candidate_scores = excluded.candidate_scores,
    updated_at = now()
  -- 이미 사람이 결정한 행은 늦게 도착한 크롤러가 되돌릴 수 없다.
  where public.worksite_resolution_queue.status = 'pending'
  returning * into v_row;

  if not found then
    select *
      into v_row
      from public.worksite_resolution_queue
     where university_id = coalesce((p_payload->>'university_id')::integer, 1)
       and source = p_payload->>'source'
       and external_id = p_payload->>'external_id';
  end if;

  return to_jsonb(v_row);
end;
$$;

revoke all on function public.enqueue_worksite_review(jsonb)
  from public, anon, authenticated;
grant execute on function public.enqueue_worksite_review(jsonb)
  to service_role;

commit;
