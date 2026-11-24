-- Resolve worksite review decisions in one database transaction.
-- The service-role-only RPC locks the queue row, validates the target, learns
-- an alias when requested, and updates the queue without partial writes.

begin;

alter table public.worksite_resolution_queue
  drop constraint if exists worksite_resolution_queue_source_ext_uq;

alter table public.worksite_resolution_queue
  add constraint worksite_resolution_queue_university_source_ext_uq
  unique (university_id, source, external_id);

alter table public.worksite_resolution_queue
  add constraint worksite_resolution_queue_resolution_check
  check (
    (status = 'resolved' and resolved_worksite_id is not null)
    or (status in ('pending', 'skipped') and resolved_worksite_id is null)
  );

create or replace function public.resolve_worksite_review(
  p_queue_id bigint,
  p_action text,
  p_worksite_id integer default null,
  p_new_name varchar default null,
  p_normalized_name varchar default null,
  p_address text default null,
  p_learn_alias boolean default null,
  p_global_alias boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_queue public.worksite_resolution_queue%rowtype;
  v_worksite public.worksites%rowtype;
  v_alias_source varchar(30);
  v_organization_name varchar(200);
  v_should_learn boolean;
begin
  if p_action not in ('existing', 'new', 'skip') then
    raise exception 'unsupported review action: %', p_action
      using errcode = '22023';
  end if;

  select *
    into v_queue
    from public.worksite_resolution_queue
   where id = p_queue_id
   for update;

  if not found then
    raise exception 'queue item not found: %', p_queue_id
      using errcode = 'P0002';
  end if;

  if v_queue.status <> 'pending' then
    raise exception 'queue item % is already %', p_queue_id, v_queue.status
      using errcode = '55000';
  end if;

  if p_action = 'skip' then
    update public.worksite_resolution_queue
       set status = 'skipped',
           resolved_worksite_id = null,
           resolution_method = 'human_skip',
           resolved_at = now(),
           updated_at = now()
     where id = p_queue_id;

    return jsonb_build_object(
      'queue_id', p_queue_id,
      'status', 'skipped',
      'alias_learned', false
    );
  end if;

  v_should_learn := coalesce(
    p_learn_alias,
    v_queue.resolution_reason = 'new_name'
  );

  if p_action = 'existing' then
    if p_worksite_id is null then
      raise exception 'worksite_id is required for existing action'
        using errcode = '22023';
    end if;

    select *
      into v_worksite
      from public.worksites
     where id = p_worksite_id
       and university_id = v_queue.university_id
       and type = 'school'
       and deleted_at is null;

    if not found then
      raise exception 'active school worksite % was not found in university %',
        p_worksite_id, v_queue.university_id
        using errcode = 'P0002';
    end if;
  else
    if nullif(btrim(p_new_name), '') is null
       or nullif(btrim(p_normalized_name), '') is null then
      raise exception 'new_name and normalized_name are required for new action'
        using errcode = '22023';
    end if;

    select *
      into v_worksite
      from public.worksites
     where university_id = v_queue.university_id
       and type = 'school'
       and normalized_name = btrim(p_normalized_name)
       and deleted_at is null
     limit 1;

    if found then
      raise exception
        'active worksite % already uses normalized name "%"; choose existing action',
        v_worksite.id, btrim(p_normalized_name)
        using errcode = '23505';
    end if;

    select w.organization_name
      into v_organization_name
      from public.worksites w
     where w.university_id = v_queue.university_id
       and w.type = 'school'
       and w.deleted_at is null
       and nullif(btrim(w.organization_name), '') is not null
     order by w.id
     limit 1;

    if v_organization_name is null then
      select u.name
        into v_organization_name
        from public.universities u
       where u.id = v_queue.university_id;
    end if;

    insert into public.worksites (
      university_id,
      type,
      location_type,
      organization_name,
      workplace_name,
      normalized_name,
      address
    )
    values (
      v_queue.university_id,
      'school',
      'on_campus',
      v_organization_name,
      btrim(p_new_name),
      btrim(p_normalized_name),
      nullif(btrim(p_address), '')
    )
    returning * into v_worksite;
  end if;

  if v_should_learn then
    v_alias_source := case when p_global_alias then '*' else v_queue.source end;

    insert into public.worksite_aliases (
      university_id,
      source,
      alias_name,
      normalized_alias,
      worksite_id,
      resolution_method,
      updated_at
    )
    values (
      v_queue.university_id,
      v_alias_source,
      v_queue.raw_worksite_name,
      v_queue.normalized_worksite,
      v_worksite.id,
      'human',
      now()
    )
    on conflict (university_id, source, normalized_alias)
    do update set
      alias_name = excluded.alias_name,
      worksite_id = excluded.worksite_id,
      resolution_method = excluded.resolution_method,
      updated_at = now();
  end if;

  update public.worksite_resolution_queue
     set status = 'resolved',
         resolved_worksite_id = v_worksite.id,
         resolution_method = case
           when p_action = 'new' then 'human_new'
           else 'human_existing'
         end,
         resolved_at = now(),
         updated_at = now()
   where id = p_queue_id;

  return jsonb_build_object(
    'queue_id', p_queue_id,
    'status', 'resolved',
    'worksite', jsonb_build_object(
      'id', v_worksite.id,
      'workplace_name', v_worksite.workplace_name,
      'normalized_name', v_worksite.normalized_name,
      'address', v_worksite.address
    ),
    'alias_learned', v_should_learn,
    'alias_scope', case
      when v_should_learn then v_alias_source
      else null
    end
  );
end;
$$;

revoke all on function public.resolve_worksite_review(
  bigint, text, integer, varchar, varchar, text, boolean, boolean
) from public, anon, authenticated;

grant execute on function public.resolve_worksite_review(
  bigint, text, integer, varchar, varchar, text, boolean, boolean
) to service_role;

commit;
