-- 목적: 자체 password_hash 인증 → Supabase Auth 클린 컷오버 (UUID 신원·전 테이블 RLS·auth.uid RPC·@korea.ac.kr 가입)
-- 날짜: 2026-06-24 · 담당: 현수(kindofwater)
-- ⚠️ 클린 컷오버: 아래 TRUNCATE로 기존 행 전부 삭제됨. 팀 사인오프 후에만 push.
-- ⚠️ 이 파일은 C2(트리거+RPC)·C3(RLS)에서 이어서 append됨.

-- ── 1. 커스텀 인증 제거 (시그니처 변경/삭제는 DROP 먼저) ──
drop function if exists verify_login(text, text);
drop function if exists register_user(text,text,text,int,text,text,text,int,text,text,int,text);
drop function if exists register_user(text,text,text,int,text,text,text,int,text,text,int);
drop function if exists set_password(text, text);

-- ── 2. 클린 wipe + 신원 UUID화 ──
truncate table reviews, review_helpful, points, ad_views, reports, users restart identity cascade;

-- 6개 FK 제약 먼저 드롭(컬럼 타입 변경 위해)
alter table reviews        drop constraint reviews_user_id_fkey;
alter table review_helpful drop constraint review_helpful_user_id_fkey;
alter table ad_views       drop constraint ad_views_user_id_fkey;
alter table points         drop constraint points_user_id_fkey;
alter table reports        drop constraint reports_reporter_id_fkey;
alter table reports        drop constraint reports_reported_user_id_fkey;

-- users PK int → uuid (빈 테이블)
alter table users drop constraint users_pkey;
alter table users alter column id drop default;
drop sequence if exists users_id_seq;
alter table users alter column id type uuid using gen_random_uuid();
alter table users add primary key (id);
alter table users add constraint users_id_fkey foreign key (id) references auth.users(id) on delete cascade;

-- ── 3. 폐기 컬럼 + FK uuid화 ──
alter table users drop column password_hash;
alter table users drop column email;
drop extension if exists pgcrypto;

alter table reviews        alter column user_id          type uuid using null;
alter table review_helpful drop constraint review_helpful_pkey;
alter table review_helpful alter column user_id          type uuid using null;
alter table ad_views       alter column user_id          type uuid using null;
alter table points         alter column user_id          type uuid using null;
alter table reports        alter column reporter_id       type uuid using null;
alter table reports        alter column reported_user_id  type uuid using null;

alter table reviews        add constraint reviews_user_id_fkey        foreign key (user_id)         references users(id) on delete set null;
alter table review_helpful add constraint review_helpful_user_id_fkey foreign key (user_id)         references users(id) on delete cascade;
alter table review_helpful add primary key (user_id, review_id);
alter table ad_views       add constraint ad_views_user_id_fkey       foreign key (user_id)         references users(id) on delete set null;
alter table points         add constraint points_user_id_fkey         foreign key (user_id)         references users(id) on delete cascade;
alter table reports        add constraint reports_reporter_id_fkey    foreign key (reporter_id)     references users(id) on delete set null;
alter table reports        add constraint reports_reported_user_id_fkey foreign key (reported_user_id) references users(id) on delete set null;

-- reviews 유니크(드리프트 제약명 introspect-drop 후 재생성)
do $$
declare c text;
begin
  for c in select conname from pg_constraint where conrelid='public.reviews'::regclass and contype='u'
  loop execute format('alter table reviews drop constraint %I', c); end loop;
end $$;
alter table reviews add constraint reviews_user_year_semester_key unique (user_id, work_year, work_semester);

-- ── 4. 가입 허용 학교(데이터 주도 확장) ──
alter table universities add column signup_enabled boolean not null default false;
-- lower(trim(...)) 으로 대소문자·공백 드리프트 허용. push 전 live row에 해당 domain이 있는지 확인.
update universities set signup_enabled = true where lower(trim(email_domain)) = 'korea.ac.kr';

-- ── 5. 가입 트리거 (프로필 생성 + @korea.ac.kr 검증) ──
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  m jsonb := new.raw_user_meta_data;
  v_uni_id int := (m->>'university_id')::int;
  v_domain text;
  v_enabled boolean;
  v_college_id int;
  v_department_id int;
begin
  select email_domain, signup_enabled into v_domain, v_enabled
    from universities where id = v_uni_id;
  if v_domain is null then raise exception 'NO_UNIVERSITY'; end if;
  if not coalesce(v_enabled, false) then raise exception 'SCHOOL_NOT_ENABLED'; end if;
  if lower(split_part(new.email, '@', 2)) <> lower(v_domain) then
    raise exception 'DOMAIN_NOT_ALLOWED';
  end if;

  select id into v_college_id from colleges
    where university_id = v_uni_id and name = (m->>'college_name') limit 1;
  if v_college_id is null then
    select id into v_college_id from colleges where university_id = v_uni_id order by id limit 1;
  end if;
  if v_college_id is null then raise exception 'NO_COLLEGE'; end if;
  select id into v_department_id from departments
    where college_id = v_college_id and name = (m->>'department_name') limit 1;
  if v_department_id is null then
    select id into v_department_id from departments where college_id = v_college_id order by id limit 1;
  end if;
  if v_department_id is null then raise exception 'NO_DEPARTMENT'; end if;

  insert into public.users (id, university_id, college_id, department_id, track,
                            nickname, admission_year, degree_program, academic_status, grade, region)
  values (new.id, v_uni_id, v_college_id, v_department_id, m->>'track',
          m->>'nickname', (m->>'admission_year')::int,
          (m->>'degree_program')::degree_program_e, (m->>'academic_status')::academic_status_e,
          (m->>'grade')::int, m->>'region');
  return new;
exception
  when unique_violation then raise exception 'NICKNAME_TAKEN';
end $$;
revoke execute on function public.handle_new_user() from anon, public;

create trigger on_auth_user_created
  after insert on auth.users for each row execute function public.handle_new_user();

-- ── 6. p_user_id RPC 10개 → auth.uid() 전환 (신원만 교체, 점수/포인트 로직 보존) ──
-- 6-1. _wallet: (int)→() · 무인자, id = auth.uid()
drop function if exists _wallet(int);
create or replace function _wallet()
returns jsonb language sql security definer set search_path = public as $$
  select jsonb_build_object(
    'point_balance',  u.point_balance,
    'pass_balances',  coalesce(u.pass_balances, '{}'::jsonb),
    'pass_expires_at', u.pass_expires_at
  ) from users u where u.id = auth.uid()
$$;

-- 6-2. purchase_pass: (int,int)→(int)
drop function if exists purchase_pass(int, int);
create or replace function purchase_pass(p_days int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_price int := pass_price(p_days); v_rows int;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if v_price is null then raise exception 'INVALID_DAYS'; end if;
  update users u
     set point_balance = u.point_balance - v_price,
         pass_balances = jsonb_set(
           coalesce(u.pass_balances, '{}'::jsonb), array[p_days::text],
           to_jsonb(coalesce((u.pass_balances ->> p_days::text)::int, 0) + 1), true)
   where u.id = v_uid and u.point_balance >= v_price;
  get diagnostics v_rows = row_count;
  if v_rows = 0 then raise exception 'INSUFFICIENT_POINTS'; end if;
  insert into points (user_id, amount, reason) values (v_uid, -v_price, 'pass_purchase');
  return _wallet();
end $$;

-- 6-3. refund_pass: (int,int)→(int)
drop function if exists refund_pass(int, int);
create or replace function refund_pass(p_days int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_price int := pass_price(p_days); v_rows int;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if v_price is null then raise exception 'INVALID_DAYS'; end if;
  update users u
     set pass_balances = jsonb_set(
           coalesce(u.pass_balances, '{}'::jsonb), array[p_days::text],
           to_jsonb(coalesce((u.pass_balances ->> p_days::text)::int, 0) - 1), true),
         point_balance = u.point_balance + v_price
   where u.id = v_uid and coalesce((u.pass_balances ->> p_days::text)::int, 0) >= 1;
  get diagnostics v_rows = row_count;
  if v_rows = 0 then raise exception 'NO_PASS_STOCK'; end if;
  insert into points (user_id, amount, reason) values (v_uid, v_price, 'pass_refund');
  return _wallet();
end $$;

-- 6-4. activate_pass: (int,int)→(int) (최신본: 20260613034933, now() timestamptz)
drop function if exists activate_pass(int, int);
create or replace function activate_pass(p_days int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_rows int;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if pass_price(p_days) is null then raise exception 'INVALID_DAYS'; end if;
  update users u
     set pass_balances = jsonb_set(
           coalesce(u.pass_balances, '{}'::jsonb), array[p_days::text],
           to_jsonb(coalesce((u.pass_balances ->> p_days::text)::int, 0) - 1), true),
         pass_expires_at = greatest(now(), coalesce(u.pass_expires_at, now()))
                           + (p_days || ' days')::interval
   where u.id = v_uid and coalesce((u.pass_balances ->> p_days::text)::int, 0) >= 1;
  get diagnostics v_rows = row_count;
  if v_rows = 0 then raise exception 'NO_PASS_STOCK'; end if;
  return _wallet();
end $$;

-- 6-5. watch_ad_reward: (int)→()
drop function if exists watch_ad_reward(int);
create or replace function watch_ad_reward()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_ad_id int; v_rows int;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  update users set point_balance = point_balance + 5 where id = v_uid;
  get diagnostics v_rows = row_count;
  if v_rows = 0 then raise exception 'USER_NOT_FOUND'; end if;
  insert into ad_views (user_id) values (v_uid) returning id into v_ad_id;
  insert into points (user_id, amount, reason, ad_view_id) values (v_uid, 5, 'ad_view', v_ad_id);
  return _wallet();
end $$;

-- 6-6. toggle_helpful: (int,int)→(int)
drop function if exists toggle_helpful(int, int);
create or replace function toggle_helpful(p_review_id int)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_count int;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if exists (
    select 1 from review_helpful
    where user_id = v_uid and review_id = p_review_id
  ) then
    delete from review_helpful
    where user_id = v_uid and review_id = p_review_id;

    update reviews
    set helpful_count = greatest(0, helpful_count - 1)
    where id = p_review_id
    returning helpful_count into v_count;
  else
    insert into review_helpful (user_id, review_id)
    values (v_uid, p_review_id);

    update reviews
    set helpful_count = helpful_count + 1
    where id = p_review_id
    returning helpful_count into v_count;
  end if;

  return v_count;
end $$;

-- 6-7. update_profile: (int,text,int,text,text,int)→(text,int,text,text,int) (최신본: 20260615140000)
drop function if exists update_profile(int, text, int, text, text, int);
create or replace function update_profile(
  p_region          text,
  p_admission_year  int,
  p_degree_program  text,
  p_academic_status text,
  p_grade           int
)
returns table (
  id              uuid,
  nickname        text,
  region          text,
  admission_year  int,
  degree_program  text,
  academic_status text,
  grade           int,
  track           text,
  point_balance   int,
  pass_expires_at timestamptz
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  update public.users u
     set region          = p_region,
         admission_year  = p_admission_year,
         degree_program  = p_degree_program::degree_program_e,
         academic_status = p_academic_status::academic_status_e,
         grade           = p_grade,
         updated_at      = now()
   where u.id = v_uid and u.deleted_at is null;

  return query
    select u.id, u.nickname::text, u.region::text,
           u.admission_year, u.degree_program::text, u.academic_status::text,
           u.grade, u.track::text, u.point_balance, u.pass_expires_at
    from public.users u where u.id = v_uid;
end $$;

-- 6-8. write_review_with_points: 첫 인자 제거 + DEFINER 승격 (최신본: 20260622072050)
drop function if exists public.write_review_with_points(
  integer, integer, integer, text, numeric, numeric, numeric, numeric, numeric, text, text, boolean);
create or replace function public.write_review_with_points(
  p_worksite_id integer, p_work_year integer, p_work_semester text,
  p_work numeric, p_growth numeric, p_vibe numeric, p_flex numeric, p_recommend numeric,
  p_work_content text, p_opinion text, p_is_anonymous boolean default false
) returns integer language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_review_id integer;
  v_amount integer := case when coalesce(p_is_anonymous, false) then 5 else 15 end;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  insert into public.reviews (
    user_id, worksite_id, work_year, work_semester,
    score_work, score_growth, score_vibe, score_flex, score_recommend,
    work_content, opinion, is_anonymous)
  values (
    v_uid, p_worksite_id, p_work_year, p_work_semester,
    p_work, p_growth, p_vibe, p_flex, p_recommend,
    p_work_content, p_opinion, coalesce(p_is_anonymous, false))
  returning id into v_review_id;

  insert into public.points (user_id, amount, reason, review_id)
  values (v_uid, v_amount, 'review_write', v_review_id);

  update public.users set point_balance = point_balance + v_amount where id = v_uid;
  return v_review_id;
end $$;

-- 6-9. update_review_with_points: 첫 인자 제거 + DEFINER 승격 (최신본: 20260622072050)
drop function if exists public.update_review_with_points(
  integer, integer, integer, text, numeric, numeric, numeric, numeric, numeric, text, text, boolean);
create or replace function public.update_review_with_points(
  p_review_id integer, p_work_year integer, p_work_semester text,
  p_work numeric, p_growth numeric, p_vibe numeric, p_flex numeric, p_recommend numeric,
  p_work_content text, p_opinion text, p_is_anonymous boolean default false
) returns void language plpgsql security definer set search_path = public as $$
declare
  v_uid       uuid    := auth.uid();
  v_target    integer := case when coalesce(p_is_anonymous, false) then 5 else 15 end;
  v_grant     integer;
  v_has_write boolean;
  v_delta     integer;
  v_balance   integer;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  update public.reviews set
    work_year = p_work_year, work_semester = p_work_semester,
    score_work = p_work, score_growth = p_growth, score_vibe = p_vibe,
    score_flex = p_flex, score_recommend = p_recommend,
    work_content = p_work_content, opinion = p_opinion,
    is_anonymous = coalesce(p_is_anonymous, false), updated_at = now()
  where id = p_review_id and user_id = v_uid;
  if not found then raise exception 'REVIEW_NOT_FOUND'; end if;

  select coalesce(sum(amount), 0), bool_or(reason = 'review_write')
    into v_grant, v_has_write
  from public.points
  where review_id = p_review_id and reason in ('review_write', 'review_anon_switch');

  -- 포인트 적립 이력(write 행)이 없는 리뷰는 토글로 포인트를 새로 지급하지 않음(공짜 지급 버그 차단).
  if not coalesce(v_has_write, false) then
    return;
  end if;

  v_delta := v_target - v_grant;
  if v_delta <> 0 then
    if v_delta < 0 then
      select point_balance into v_balance from public.users where id = v_uid;
      if v_balance + v_delta < 0 then raise exception 'INSUFFICIENT_POINTS'; end if;
    end if;
    insert into public.points (user_id, amount, reason, review_id)
    values (v_uid, v_delta, 'review_anon_switch', p_review_id);
    update public.users set point_balance = point_balance + v_delta where id = v_uid;
  end if;
end $$;

-- 6-10. delete_review_with_rollback: 첫 인자 제거 + DEFINER 승격 (최신본: 20260622072050)
drop function if exists public.delete_review_with_rollback(integer, integer);
create or replace function public.delete_review_with_rollback(p_review_id integer)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_uid     uuid := auth.uid();
  v_grant   integer;
  v_balance integer;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  select coalesce(sum(amount), 0) into v_grant
  from public.points
  where review_id = p_review_id and reason in ('review_write', 'review_anon_switch');

  select point_balance into v_balance from public.users where id = v_uid;
  if v_balance < v_grant then raise exception 'INSUFFICIENT_POINTS'; end if;

  insert into public.points (user_id, amount, reason, review_id)
  values (v_uid, -v_grant, 'review_delete', p_review_id);

  delete from public.reviews where id = p_review_id and user_id = v_uid;
  if not found then raise exception 'REVIEW_NOT_FOUND'; end if;

  update public.users set point_balance = point_balance - v_grant where id = v_uid;
end $$;

-- ── 7. 실행 권한: 신원 필요한 RPC는 anon 회수 ──
do $$
declare f text;
begin
  foreach f in array array[
    'update_profile(text,int,text,text,int)','_wallet()','purchase_pass(int)','refund_pass(int)',
    'activate_pass(int)','watch_ad_reward()','toggle_helpful(int)',
    'write_review_with_points(int,int,text,numeric,numeric,numeric,numeric,numeric,text,text,boolean)',
    'update_review_with_points(int,int,text,numeric,numeric,numeric,numeric,numeric,text,text,boolean)',
    'delete_review_with_rollback(int)'
  ]
  loop
    execute format('revoke execute on function %s from anon, public', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

-- ── 8. RLS ──
alter table users          enable row level security;
alter table reviews        enable row level security;
alter table points         enable row level security;
alter table ad_views       enable row level security;
alter table reports        enable row level security;
alter table review_helpful enable row level security;
alter table worksites      enable row level security;
alter table postings       enable row level security;
alter table notices        enable row level security;
alter table universities   enable row level security;
alter table colleges       enable row level security;
alter table departments    enable row level security;

-- 본인 범위
create policy users_select_own   on users          for select to authenticated using (id = auth.uid());
create policy users_update_own   on users          for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
create policy points_select_own  on points         for select to authenticated using (user_id = auth.uid());
create policy adviews_select_own on ad_views       for select to authenticated using (user_id = auth.uid());
create policy helpful_select_own on review_helpful for select to authenticated using (user_id = auth.uid());
create policy reviews_select_own on reviews        for select to authenticated using (user_id = auth.uid());

-- 공개 카탈로그(읽기 전용)
create policy worksites_read   on worksites    for select to anon, authenticated using (true);
create policy postings_read    on postings     for select to anon, authenticated using (true);
create policy notices_read     on notices      for select to anon, authenticated using (true);
create policy uni_read         on universities for select to anon, authenticated using (true);
create policy colleges_read    on colleges     for select to anon, authenticated using (true);
create policy departments_read on departments  for select to anon, authenticated using (true);
-- reports: 클라 정책 없음(service_role/관리자만). 쓰기는 섹션 9 report_review.

-- 특권 컬럼 2중 방어: 컬럼 GRANT(RLS는 행 단위라 컬럼은 못 막음)
revoke update on public.users from authenticated;
grant update (region, admission_year, degree_program, academic_status, grade, track, nickname, updated_at)
  on public.users to authenticated;

-- ── 9. 공개 리뷰목록(익명 마스킹) + view/report ──
create or replace function list_worksite_reviews(p_worksite_id int)
returns table (id int, work_year int, work_semester text, score_recommend numeric,
               score_work numeric, score_growth numeric, score_vibe numeric, score_flex numeric,
               work_content text, opinion text, is_anonymous boolean, helpful_count int,
               author_nickname text, created_at timestamptz)
language sql security definer set search_path = public as $$
  select r.id, r.work_year,
         case when r.is_anonymous then null else r.work_semester end,
         r.score_recommend, r.score_work, r.score_growth, r.score_vibe, r.score_flex,
         r.work_content, r.opinion, r.is_anonymous, r.helpful_count,
         case when r.is_anonymous then '익명' else u.nickname end,
         r.created_at
  from reviews r left join users u on u.id = r.user_id
  where r.worksite_id = p_worksite_id and r.deleted_at is null
  order by r.created_at desc;
$$;  -- user_id를 반환하지 않음 → 익명 신원 노출 차단

create or replace function increment_worksite_view(p_worksite_id int)
returns void language plpgsql security definer set search_path = public as $$
begin update worksites set view_count = view_count + 1 where id = p_worksite_id; end $$;

create or replace function report_review(p_review_id int, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_reported uuid;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  select user_id into v_reported from reviews where id = p_review_id;
  insert into reports (reporter_id, reported_user_id, review_id, reason)
  values (v_uid, v_reported, p_review_id, p_reason);
end $$;

-- D6: 리뷰 열람/조회수/신고는 authenticated만 (anon 제외)
revoke execute on function list_worksite_reviews(int)   from anon, public;
grant  execute on function list_worksite_reviews(int)   to authenticated;
revoke execute on function increment_worksite_view(int) from anon, public;
grant  execute on function increment_worksite_view(int) to authenticated;
revoke execute on function report_review(int, text)     from anon, public;
grant  execute on function report_review(int, text)     to authenticated;
