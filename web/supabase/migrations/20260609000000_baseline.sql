-- ════════════════════════════════════════════════════════════════════
-- 목적: baseline — 현재 live DB(GRGR/main) 스키마를 코드로 옮긴 정본
-- 날짜: 2026-06-09 · 담당: 배경록
-- 출처: docs/db-schema.md(사용자가 live와 일치 검증, 2026-06-09) + DB/ RPC 파일들.
--
-- ⚠️ 적용 방법(Docker 없이):
--   이 파일은 "이미 live에 존재하는 상태"라서 다시 실행하지 않는다.
--   `npx supabase migration repair --status applied 20260609000000` 로
--   "적용됨"만 기록한다. 이후 변경은 새 마이그레이션 + `db push`.
--   (빈 DB/sandbox에 처음부터 재구축할 때만 이 파일이 실제로 실행됨)
--
-- ⚠️ AUTH 미포함 (담당: kindofwater):
--   pgcrypto 확장, verify_login/set_password 함수, users.password_hash REVOKE 는
--   인증 담당이 자기 마이그레이션으로 추가한다. 현재 live에 REVOKE 미적용 = 의도된 개발 중
--   상태이므로 이 baseline도 반영하지 않는다(=현재 live 상태와 일치).
-- ════════════════════════════════════════════════════════════════════

-- ── ENUM 타입 ──────────────────────────────────────────────────────
create type worksite_type_e    as enum ('national', 'school');
create type location_type_e    as enum ('on_campus', 'off_campus');
create type degree_program_e   as enum ('undergrad', 'graduate');
create type academic_status_e  as enum ('enrolled', 'leave', 'completed', 'deferred_graduation');
create type report_status_e    as enum ('pending', 'deleted', 'ignored');
create type duration_type_e    as enum ('short', 'long', 'unknown');

-- ── 테이블 (FK 의존성 순서) ────────────────────────────────────────

-- 학교 (멀티캠퍼스 지원)
create table universities (
  id            serial primary key,
  name          varchar(100) not null,             -- 학교명 (예: 고려대학교)
  campus        varchar(50),                       -- 캠퍼스명 (멀티캠퍼스만, 단일이면 NULL)
  email_domain  varchar(100) not null              -- 회원가입 학교 인증용 도메인 (UNIQUE 아님)
);

-- 단과대학
create table colleges (
  id            serial primary key,
  university_id integer not null references universities(id) on delete restrict,
  name          varchar(100) not null
);

-- 학과
create table departments (
  id            serial primary key,
  college_id    integer not null references colleges(id) on delete restrict,
  name          varchar(100) not null,
  default_track varchar(20) not null               -- 학과 선택 시 자동 세팅되는 계열
);

-- 유저
create table users (
  id              serial primary key,
  university_id   integer not null references universities(id) on delete restrict,
  college_id      integer not null references colleges(id) on delete restrict,
  department_id   integer not null references departments(id) on delete restrict,
  track           varchar(20) not null,             -- 계열 (default_track 자동, 수정 가능)
  email           varchar(255) unique not null,
  password_hash   varchar(255) not null,
  nickname        varchar(50) unique not null,
  admission_year  integer not null,
  degree_program  degree_program_e not null,
  academic_status academic_status_e not null,
  grade           integer check (grade between 1 and 6),
  point_balance   integer default 0 check (point_balance >= 0),
  pass_balances   jsonb default '{}',               -- 미활성 열람권 재고 {"7":2,"30":1}
  pass_expires_at timestamp,                         -- 활성 열람권 만료 시각, 없으면 NULL
  region          varchar(50),
  is_admin        boolean default false,
  created_at      timestamp default now(),
  updated_at      timestamp default now(),
  deleted_at      timestamp                          -- 소프트 삭제 (NULL이면 활성)
);

-- 근장 (근무지 고유 정보)
create table worksites (
  id                serial primary key,
  university_id     integer not null references universities(id) on delete restrict,
  type              worksite_type_e not null,
  location_type     location_type_e not null,
  organization_name varchar(200),
  workplace_name    varchar(200),
  region            varchar(50),
  address           text,
  view_count        integer default 0 check (view_count >= 0),
  created_at        timestamp default now(),
  updated_at        timestamp default now(),
  deleted_at        timestamp
);

-- 모집 공고 (학기/시기마다 달라지는 정보)
create table postings (
  id                      serial primary key,
  worksite_id             integer not null references worksites(id) on delete cascade,
  source_url              text,
  job_category            varchar(100),
  preferred_track         varchar(50),
  preferred_college       varchar(100),
  preferred_dept          varchar(200),
  recruit_count           varchar(20),
  min_grade               integer,
  eligible_degree         smallint default 3,        -- 0=학부만 1=대학원만 2=모두 3=미정
  eligible_status         smallint default 3,        -- 0=재학만 1=휴학만 2=모두 3=미정
  job_description         text,
  preference_notes        text,
  extra_notes             text,
  hourly_wage             integer,
  work_period_text        text,
  work_duration_type      duration_type_e default 'unknown',
  work_time_text          text,
  recruitment_period_text text,
  contact_name            varchar(50),
  contact_phone           varchar(50),
  contact_email           varchar(100),
  raw_text                text,
  is_active               boolean default true,
  created_at              timestamp default now(),
  updated_at              timestamp default now(),
  deleted_at              timestamp
);

-- 리뷰 (근무지 단위)
create table reviews (
  id              serial primary key,
  user_id         integer references users(id) on delete set null,   -- 탈퇴 시 NULL(익명)
  worksite_id     integer not null references worksites(id) on delete restrict,
  work_year       integer not null,
  work_semester   varchar(10) not null,
  score_work      numeric(2,1) check (score_work between 0.5 and 5.0),
  score_growth    numeric(2,1) check (score_growth between 0.5 and 5.0),
  score_vibe      numeric(2,1) check (score_vibe between 0.5 and 5.0),
  score_flex      numeric(2,1) check (score_flex between 0.5 and 5.0),
  score_recommend numeric(2,1) check (score_recommend between 0.5 and 5.0),
  work_content    text check (char_length(work_content) between 30 and 1000),
  opinion         text check (char_length(opinion) between 50 and 2000),
  helpful_count   integer default 0,
  created_at      timestamp default now(),
  updated_at      timestamp default now(),
  deleted_at      timestamp,
  unique (user_id, work_year, work_semester)        -- 학기당 1리뷰 (user_id NULL은 복수 허용)
);

-- 도움됐어요 (토글)
create table review_helpful (
  user_id    integer not null references users(id) on delete cascade,
  review_id  integer not null references reviews(id) on delete cascade,
  created_at timestamp default now(),
  primary key (user_id, review_id)
);

-- 광고 시청 (points보다 먼저 — points가 ad_views를 참조)
create table ad_views (
  id         serial primary key,
  user_id    integer references users(id) on delete set null,
  created_at timestamp default now()
);

-- 포인트 내역
create table points (
  id         serial primary key,
  user_id    integer not null references users(id) on delete cascade,
  amount     integer not null,                       -- 양수=획득, 음수=차감
  reason     varchar(50) not null,                   -- review_write/review_delete/ad_view/pass_purchase 등
  review_id  integer references reviews(id) on delete set null,
  ad_view_id integer references ad_views(id) on delete set null,
  created_at timestamp default now()
);

-- 신고
create table reports (
  id               serial primary key,
  reporter_id      integer references users(id) on delete set null,
  reported_user_id integer references users(id) on delete set null,
  review_id        integer references reviews(id) on delete set null,
  reason           varchar(100),
  status           report_status_e default 'pending',
  created_at       timestamp default now()
);

-- 공지사항
create table notices (
  id         serial primary key,
  title      varchar(200) not null,
  content    text,
  is_pinned  boolean default false,
  created_at timestamp default now(),
  updated_at timestamp default now()
);

-- ── RPC: 리뷰 포인트 트랜잭션 (DB/2026-06-02_rpc_review_points.sql) ──

create or replace function write_review_with_points(
  p_user_id int, p_worksite_id int, p_work_year int, p_work_semester text,
  p_work numeric, p_growth numeric, p_vibe numeric, p_flex numeric, p_recommend numeric,
  p_work_content text, p_opinion text
) returns int language plpgsql as $$
declare v_review_id int;
begin
  insert into reviews (user_id, worksite_id, work_year, work_semester,
    score_work, score_growth, score_vibe, score_flex, score_recommend, work_content, opinion)
  values (p_user_id, p_worksite_id, p_work_year, p_work_semester,
    p_work, p_growth, p_vibe, p_flex, p_recommend, p_work_content, p_opinion)
  returning id into v_review_id;

  insert into points (user_id, amount, reason, review_id)
  values (p_user_id, 15, 'review_write', v_review_id);

  update users set point_balance = point_balance + 15 where id = p_user_id;
  return v_review_id;
end $$;

create or replace function delete_review_with_rollback(p_user_id int, p_review_id int)
returns void language plpgsql as $$
declare v_balance int;
begin
  select point_balance into v_balance from users where id = p_user_id;
  if v_balance < 15 then
    raise exception 'INSUFFICIENT_POINTS';
  end if;

  insert into points (user_id, amount, reason, review_id)
  values (p_user_id, -15, 'review_delete', p_review_id);

  delete from reviews where id = p_review_id and user_id = p_user_id;

  if not found then
    raise exception 'REVIEW_NOT_FOUND';
  end if;

  update users set point_balance = point_balance - 15 where id = p_user_id;
end $$;

-- ── RPC: 홈 리뷰 집계 (DB/2026-06-02_rpc_review_stats.sql) ──

create or replace function get_review_stats(worksite_ids int[])
returns table(
  worksite_id   int,
  avg_score     numeric,
  review_count  bigint
)
language sql
security definer
set search_path = public
as $$
  select
    worksite_id,
    round(avg(score_recommend)::numeric, 1) as avg_score,
    count(*)                                as review_count
  from reviews
  where worksite_id = any(worksite_ids)
    and deleted_at is null
  group by worksite_id;
$$;

grant execute on function get_review_stats(int[]) to anon, authenticated;

-- ── RPC: 도움됐어요 토글 (DB/2026-06-02_rpc_toggle_helpful.sql) ──

create or replace function toggle_helpful(p_user_id int, p_review_id int)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int;
begin
  if exists (
    select 1 from review_helpful
    where user_id = p_user_id and review_id = p_review_id
  ) then
    delete from review_helpful
    where user_id = p_user_id and review_id = p_review_id;

    update reviews
    set helpful_count = greatest(0, helpful_count - 1)
    where id = p_review_id
    returning helpful_count into v_count;
  else
    insert into review_helpful (user_id, review_id)
    values (p_user_id, p_review_id);

    update reviews
    set helpful_count = helpful_count + 1
    where id = p_review_id
    returning helpful_count into v_count;
  end if;

  return v_count;
end $$;

grant execute on function toggle_helpful(int, int) to anon, authenticated;

-- ── RPC: 교환센터 (DB/2026-06-08_exchange.sql) ──

create or replace function pass_price(p_days int)
returns int language sql immutable as $$
  select case p_days when 7 then 10 when 30 then 20 else null end
$$;

create or replace function _wallet(p_user_id int)
returns jsonb language sql security definer set search_path = public as $$
  select jsonb_build_object(
    'point_balance',  u.point_balance,
    'pass_balances',  coalesce(u.pass_balances, '{}'::jsonb),
    'pass_expires_at', u.pass_expires_at
  ) from users u where u.id = p_user_id
$$;

create or replace function purchase_pass(p_user_id int, p_days int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_price int := pass_price(p_days); v_rows int;
begin
  if v_price is null then raise exception 'INVALID_DAYS'; end if;
  update users u
     set point_balance = u.point_balance - v_price,
         pass_balances = jsonb_set(
           coalesce(u.pass_balances, '{}'::jsonb), array[p_days::text],
           to_jsonb(coalesce((u.pass_balances ->> p_days::text)::int, 0) + 1), true)
   where u.id = p_user_id and u.point_balance >= v_price;
  get diagnostics v_rows = row_count;
  if v_rows = 0 then raise exception 'INSUFFICIENT_POINTS'; end if;
  insert into points (user_id, amount, reason) values (p_user_id, -v_price, 'pass_purchase');
  return _wallet(p_user_id);
end $$;

create or replace function refund_pass(p_user_id int, p_days int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_price int := pass_price(p_days); v_rows int;
begin
  if v_price is null then raise exception 'INVALID_DAYS'; end if;
  update users u
     set pass_balances = jsonb_set(
           coalesce(u.pass_balances, '{}'::jsonb), array[p_days::text],
           to_jsonb(coalesce((u.pass_balances ->> p_days::text)::int, 0) - 1), true),
         point_balance = u.point_balance + v_price
   where u.id = p_user_id and coalesce((u.pass_balances ->> p_days::text)::int, 0) >= 1;
  get diagnostics v_rows = row_count;
  if v_rows = 0 then raise exception 'NO_PASS_STOCK'; end if;
  insert into points (user_id, amount, reason) values (p_user_id, v_price, 'pass_refund');
  return _wallet(p_user_id);
end $$;

create or replace function activate_pass(p_user_id int, p_days int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_rows int;
begin
  if pass_price(p_days) is null then raise exception 'INVALID_DAYS'; end if;
  update users u
     set pass_balances = jsonb_set(
           coalesce(u.pass_balances, '{}'::jsonb), array[p_days::text],
           to_jsonb(coalesce((u.pass_balances ->> p_days::text)::int, 0) - 1), true),
         pass_expires_at = greatest(now()::timestamp, coalesce(u.pass_expires_at, now()::timestamp))
                           + (p_days || ' days')::interval
   where u.id = p_user_id and coalesce((u.pass_balances ->> p_days::text)::int, 0) >= 1;
  get diagnostics v_rows = row_count;
  if v_rows = 0 then raise exception 'NO_PASS_STOCK'; end if;
  return _wallet(p_user_id);
end $$;

create or replace function watch_ad_reward(p_user_id int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_ad_id int; v_rows int;
begin
  update users set point_balance = point_balance + 5 where id = p_user_id;
  get diagnostics v_rows = row_count;
  if v_rows = 0 then raise exception 'USER_NOT_FOUND'; end if;
  insert into ad_views (user_id) values (p_user_id) returning id into v_ad_id;
  insert into points (user_id, amount, reason, ad_view_id) values (p_user_id, 5, 'ad_view', v_ad_id);
  return _wallet(p_user_id);
end $$;

grant execute on function pass_price(int)        to anon, authenticated;
grant execute on function _wallet(int)           to anon, authenticated;
grant execute on function purchase_pass(int,int) to anon, authenticated;
grant execute on function refund_pass(int,int)   to anon, authenticated;
grant execute on function activate_pass(int,int) to anon, authenticated;
grant execute on function watch_ad_reward(int)   to anon, authenticated;
