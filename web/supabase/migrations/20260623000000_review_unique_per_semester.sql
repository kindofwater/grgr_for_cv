-- 목적: 리뷰 중복 기준을 (user, year, semester)로 — 한 학기당 1리뷰(근무지 불문). 4-col(per-worksite) 되돌림.
-- 날짜: 2026-06-23 · 담당: 배경록
-- 참고: 20260622072050의 4-col unique를 대체. (배경록 결정: 한 학기에 리뷰 1개)

-- reviews의 모든 unique 제약 제거 후 3-col 정본 add (live 이름 무관·멱등)
do $$
declare r record;
begin
  for r in
    select conname from pg_constraint
    where conrelid = 'public.reviews'::regclass and contype = 'u'
  loop
    execute format('alter table public.reviews drop constraint %I', r.conname);
  end loop;
end $$;

alter table public.reviews
  add constraint reviews_user_year_semester_key
  unique (user_id, work_year, work_semester);
-- ⚠ 같은 (user, year, semester) 중복 행이 이미 있으면 이 add가 실패함.
--   전부 더미이므로, 실패 시 마이페이지에서 중복 리뷰를 지우거나 `delete from public.reviews;` 후 재push.
