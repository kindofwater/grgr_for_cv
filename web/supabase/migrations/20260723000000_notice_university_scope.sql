-- School-scoped notices.
-- university_id NULL means a common notice that guests and all signed-in users can read.
-- A non-NULL university_id targets exactly that university/campus row.

alter table public.notices
  add column if not exists university_id integer
  references public.universities(id) on delete restrict;

create index if not exists notices_university_id_idx
  on public.notices (university_id);

-- Replace the formerly public-read policy.  This is deliberately enforced in
-- RLS rather than only in the client, so a direct REST request cannot read a
-- notice targeted at another university.
drop policy if exists notices_read on public.notices;

create policy notices_read on public.notices
  for select to anon, authenticated
  using (
    university_id is null
    or university_id = (
      select u.university_id
      from public.users u
      where u.id = auth.uid()
    )
  );
