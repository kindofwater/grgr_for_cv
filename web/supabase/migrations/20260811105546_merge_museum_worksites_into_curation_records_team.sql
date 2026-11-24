-- 목적: 고려대학교박물관 중복 근무지(박물관·학예부)를 학예기록팀으로 병합하고 공식 명칭 '박물관 학예기록팀'으로 개명
-- 날짜: 2026-08-11 · 담당: 배경록
--
-- 도슨트 모집 공고가 부서 표기 변천에 따라 세 근무지에 흩어져 있었다:
--   학예부(6852)     ← 도슨트 16기 (2023-2, KUPID)
--   학예기록팀(6851) ← 도슨트 20기 (2025-2, KUPID) + 기록파트 행정보조
--   박물관(6973)     ← 도슨트 22기 (2026-2, 에브리타임 수기) + 리뷰 1건
-- 세 공고 모두 근무지는 고려대학교박물관으로 동일(전시안내·전시실 관리·학예(기록)팀 보조).
-- KOSAF 국가근장 명부의 공식 명칭이 '박물관 학예기록팀(기록파트/학예파트)'이므로
-- 정본을 '박물관 학예기록팀'으로 개명한다 — 검색 RPC가 workplace_name만 매칭하므로
-- '학예기록팀'인 채로 두면 '박물관' 검색에서 사라진다.
--
-- ⚠️ '박물관'(6973)은 크롤·수기 데이터라 맨바닥 db reset에는 없다 — 없으면 건너뛰도록
--    duplicates를 배열로 모은다(20260806100232 선례). 정본(학예기록팀)은
--    20260720015013 시드가 만들므로 reset에서도 존재한다(into strict).
-- 크롤러 짝: crawling_scripts/worksite_norm.py의 _EXPLICIT_ALIASES에
--    박물관/학예부/학예기록팀 → '박물관 학예기록팀' 매핑을 같은 브랜치에서 추가.

begin;

do $$
declare
  canonical_id integer;
  duplicate_ids integer[];
  dup_view_count integer;
begin
  select id into strict canonical_id
  from public.worksites
  where university_id = 1
    and type = 'school'
    and workplace_name = '학예기록팀'
    and deleted_at is null;

  select coalesce(array_agg(id), '{}'::integer[]) into duplicate_ids
  from public.worksites
  where university_id = 1
    and type = 'school'
    and workplace_name in ('박물관', '학예부')
    and deleted_at is null;

  update public.postings
  set worksite_id = canonical_id,
      updated_at = now()
  where worksite_id = any(duplicate_ids);

  -- reviews_user_year_semester_key는 근무지와 무관한 (user, 연도, 학기) 유니크라
  -- 재배정으로 충돌할 수 없다.
  update public.reviews
  set worksite_id = canonical_id,
      updated_at = now()
  where worksite_id = any(duplicate_ids);

  update public.worksite_aliases
  set worksite_id = canonical_id,
      updated_at = now()
  where worksite_id = any(duplicate_ids);

  update public.worksite_resolution_queue
  set resolved_worksite_id = canonical_id,
      updated_at = now()
  where resolved_worksite_id = any(duplicate_ids);

  -- 일일 조회 이벤트는 PK(user, worksite, 날짜)가 겹칠 수 있어 UPSERT 후 원본 삭제.
  insert into public.worksite_view_events (user_id, worksite_id, viewed_on, viewed_at)
  select user_id, canonical_id, viewed_on, viewed_at
  from public.worksite_view_events
  where worksite_id = any(duplicate_ids)
  on conflict (user_id, worksite_id, viewed_on) do nothing;

  delete from public.worksite_view_events
  where worksite_id = any(duplicate_ids);

  -- 인기도 캐시는 매시간 cron이 재계산하므로 중복 행만 지운다.
  delete from public.worksite_popularity_scores
  where worksite_id = any(duplicate_ids);

  -- 누적 고유 일일 조회수 합산(같은 사람이 양쪽을 본 날의 중복은 감수 — 표시용 근사값).
  select coalesce(sum(view_count), 0) into dup_view_count
  from public.worksites
  where id = any(duplicate_ids);

  update public.worksites
  set workplace_name = '박물관 학예기록팀',
      normalized_name = '박물관 학예기록팀',
      view_count = coalesce(view_count, 0) + dup_view_count,
      updated_at = now()
  where id = canonical_id;

  update public.worksites
  set deleted_at = now(),
      updated_at = now()
  where id = any(duplicate_ids)
    and deleted_at is null;

  -- 과거 표기 별칭 등록 — 크롤러가 옛 이름으로 와도 정본에 붙는다.
  -- normalized_alias는 로더가 정규화한 유입명으로 조회하므로 유입명 그대로 둔다.
  insert into public.worksite_aliases (
    university_id, source, alias_name, normalized_alias, worksite_id, resolution_method
  )
  values
    (1, '*', '박물관',     '박물관',     canonical_id, 'historical_name'),
    (1, '*', '학예부',     '학예부',     canonical_id, 'historical_name'),
    (1, '*', '학예기록팀', '학예기록팀', canonical_id, 'historical_name')
  on conflict (university_id, source, normalized_alias)
  do update
  set alias_name = excluded.alias_name,
      worksite_id = excluded.worksite_id,
      resolution_method = excluded.resolution_method,
      updated_at = now();

  if exists (
    select 1 from public.postings where worksite_id = any(duplicate_ids)
  ) or exists (
    select 1 from public.reviews where worksite_id = any(duplicate_ids)
  ) or exists (
    select 1 from public.worksite_aliases where worksite_id = any(duplicate_ids)
  ) or exists (
    select 1 from public.worksite_resolution_queue where resolved_worksite_id = any(duplicate_ids)
  ) or exists (
    select 1 from public.worksite_view_events where worksite_id = any(duplicate_ids)
  ) or exists (
    select 1 from public.worksite_popularity_scores where worksite_id = any(duplicate_ids)
  ) then
    raise exception '박물관 근무지 병합 후 참조가 남아 있음';
  end if;

  if (
    select count(*)
    from public.worksites
    where university_id = 1
      and type = 'school'
      and workplace_name in ('박물관', '학예부', '학예기록팀', '박물관 학예기록팀')
      and deleted_at is null
  ) <> 1 then
    raise exception '박물관 학예기록팀 정본 검증 실패';
  end if;
end
$$;

commit;
