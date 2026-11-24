-- 목적: PostgREST safeupdate 환경에서도 인기도 캐시 갱신이 동작하도록 전체 DELETE를 제거한다.
-- 날짜: 2026-07-31 · 담당: 배경록
-- PostgREST 세션의 safeupdate 설정에서도 인기도 캐시를 갱신할 수 있도록
-- 조건 없는 전체 DELETE를 UPSERT + 만료 행 조건부 DELETE로 교체한다.

create or replace function public.refresh_worksite_popularity_scores()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_refreshed integer;
begin
  insert into public.worksite_popularity_scores (
    worksite_id,
    recent_view_score,
    calculated_at
  )
  select
    v.worksite_id,
    sum(power(
      0.5::double precision,
      extract(epoch from (now() - v.viewed_at)) / 604800.0
    )),
    now()
  from public.worksite_view_events v
  join public.worksites w on w.id = v.worksite_id
  where v.viewed_at >= now() - interval '30 days'
    and w.deleted_at is null
  group by v.worksite_id
  on conflict (worksite_id) do update
  set recent_view_score = excluded.recent_view_score,
      calculated_at = excluded.calculated_at;

  get diagnostics v_refreshed = row_count;

  delete from public.worksite_popularity_scores s
  where not exists (
    select 1
    from public.worksite_view_events v
    join public.worksites w on w.id = v.worksite_id
    where v.worksite_id = s.worksite_id
      and v.viewed_at >= now() - interval '30 days'
      and w.deleted_at is null
  );

  return v_refreshed;
end
$$;

revoke execute on function public.refresh_worksite_popularity_scores()
  from public, anon, authenticated;
grant execute on function public.refresh_worksite_popularity_scores()
  to service_role;
