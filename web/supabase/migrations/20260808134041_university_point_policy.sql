-- 목적: 대학별 포인트 정책 도입 — 서울대 한시 조정(최소 열람권 60분→5분, 광고 적립 5P→2P).
-- 날짜: 2026-08-08 · 담당: 배경록
-- ⚠️ 배포 순서(반대 방향 주의): 20260731105714·20260808113010과 달리 이 마이그레이션은
--          db push가 아니라 프론트(ExchangeCenter.jsx·MyPage.jsx — hour_pass_minutes 배선)를
--          먼저 배포해야 한다. 프론트만 먼저 나가면 서버가 아직 새 키를 안 줘 ?? 60 폴백으로
--          무해하지만, db push가 먼저 나가면 화면엔 "1시간 열람권"이라 찍힌 상품이 실제로는
--          5분만 주는 채로 팔린다 — 위험한 건 이 화면 라벨 자체이지, 이 파일이 함께 올리는
--          공지 때문이 아니다(공지와 동작 변화는 같은 트랜잭션으로 나가 서로 어긋날 수 없다).
--          다만 프론트를 먼저 배포해도 창이 완전히 사라지진 않는다: 지갑은 마운트 시 한
--          번만 불러오므로, db push 시점에 이미 열려 있던 탭은 새로고침 전까지
--          hour_pass_minutes = undefined → 60 폴백을 계속 쓴다(화면엔 옛 라벨이 남는 잔여
--          창). 트래픽이 적은 시간대에 push해 이 창을 줄인다.
--
-- 왜 표인가: 리뷰가 쌓이면 되돌릴 한시 조치다. RPC에 대학 id를 박으면 되돌릴 때 본문을 또
--   replace해야 하는데, 이 저장소는 본문 복사로 로직이 조용히 사라지는 사고를 두 번 겪었다
--   (대학 스코프 검사 유실 → 20260808120745로 복구). 표로 두면 원복이 행 삭제 한 줄이다.
--
-- 되돌리기: delete from public.university_point_policy where university_id = <서울대 id>;
--   헬퍼가 없는 행을 60분·전역 5P로 폴백하므로 RPC는 손댈 필요가 없다. 공지도 함께 정리할 것.

begin;

-- ── 1) 대학별 정책 표 ──
-- ad_reward_points가 null이면 전역 ad_reward_config를 쓴다(전역 기본이 바뀌면 자동 추종).
-- ad_reward_config의 check (id = 1)은 건드리지 않는다 — 전역 기본값 자리로 유지.
create table if not exists public.university_point_policy (
  university_id     int primary key references public.universities(id) on delete cascade,
  hour_pass_minutes int not null default 60 check (hour_pass_minutes between 1 and 1440),
  ad_reward_points  int check (ad_reward_points >= 0),
  note              text,
  updated_at        timestamptz not null default now()
);

-- 클라이언트 직접 접근 차단 — 읽기는 아래 헬퍼(내부 전용)로만.
alter table public.university_point_policy enable row level security;
revoke all on public.university_point_policy from anon, authenticated;

-- ── 2) 공유 헬퍼 — 값 계산을 한 곳으로 모은다 ──
-- ⚠️ security definer 아님. 호출자 4개가 전부 security definer인 것에 의존한다.
--    security invoker 경로에서 부르면 RLS(정책 0건) 때문에 0행을 보고 조용히 기본값으로
--    폴백한다 — 막히는 게 아니라 틀린 값이 나온다. 새 호출부를 만들 때 반드시 확인할 것.
--    두 번째 함정: 테이블 소유자가 RLS를 우회하는 것에도 의존한다. university_point_policy나
--    users 둘 중 하나에라도 나중에 `alter table ... force row level security`를 걸면,
--    에러 없이 서울대 사용자 전원이 조용히 60분·전역 적립액으로 되돌아간다.
create or replace function public.hour_pass_minutes_for(p_uid uuid)
returns int
language sql
stable
set search_path = public
as $$
  select coalesce(
    (select p.hour_pass_minutes
       from public.university_point_policy p
       join public.users u on u.university_id = p.university_id
      where u.id = p_uid),
    60)
$$;

create or replace function public.ad_reward_points_for(p_uid uuid)
returns int
language sql
stable
set search_path = public
as $$
  select coalesce(
    (select p.ad_reward_points
       from public.university_point_policy p
       join public.users u on u.university_id = p.university_id
      where u.id = p_uid),
    (select c.reward_points from public.ad_reward_config c where c.id = 1))
$$;

revoke execute on function public.hour_pass_minutes_for(uuid) from public, anon, authenticated;
revoke execute on function public.ad_reward_points_for(uuid)  from public, anon, authenticated;

-- ── 3) 서울대 시드 ──
-- 대학 id를 박지 않고 이름으로 찾는다. 재실행 시 값을 수렴시킨다.
insert into public.university_point_policy (university_id, hour_pass_minutes, ad_reward_points, note)
select u.id, 5, 2, '서울대 리뷰 부족 — 리뷰 선순환을 위한 한시 조정. 되돌릴 때 이 행을 삭제'
from public.universities u
where u.name = '서울대학교'
on conflict (university_id) do update
  set hour_pass_minutes = excluded.hour_pass_minutes,
      ad_reward_points  = excluded.ad_reward_points,
      note              = excluded.note,
      updated_at        = now();

-- ── 4) _wallet — 응답에 hour_pass_minutes 추가 ──
-- 반환이 jsonb라 시그니처는 불변 — 키 추가 자체는 구 프론트가 모르는 키를 무시하므로 안전하다.
-- ⚠️ 그러나 그 값이 반영하는 실제 동작 변화(activate_pass 최소 상품 지속시간)는 배포 순서에
--    안전하지 않다 — 프론트가 먼저 배포돼 있어야 한다. 자세한 이유는 파일 헤더 배포 순서 참고.
create or replace function public._wallet()
returns jsonb
language sql
security definer
set search_path = pg_catalog, pg_temp
as $$
  select jsonb_build_object(
    'point_balance',     u.point_balance,
    'pass_balances',     coalesce(u.pass_balances, '{}'::jsonb),
    'pass_expires_at',   u.pass_expires_at,
    'hour_pass_minutes', public.hour_pass_minutes_for(u.id)
  )
  from public.users u
  where u.id = auth.uid()
$$;

revoke execute on function public._wallet() from public, anon;
grant execute on function public._wallet() to authenticated;

-- ── 5) activate_pass — 최소 상품(p_days=0)의 지속시간을 대학별로 ──
-- 본문은 20260801071450 그대로, interval '1 hour' 자리만 헬퍼로 교체. 시그니처 불변.
create or replace function public.activate_pass(p_days int)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_rows int;
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  if public.pass_price(p_days) is null then
    raise exception 'INVALID_DAYS';
  end if;

  update public.users u
  set pass_balances = case
        when coalesce((u.pass_balances ->> p_days::text)::int, 0) = 1
          then coalesce(u.pass_balances, '{}'::jsonb) - p_days::text
        else jsonb_set(
          coalesce(u.pass_balances, '{}'::jsonb),
          array[p_days::text],
          to_jsonb(coalesce((u.pass_balances ->> p_days::text)::int, 0) - 1),
          true
        )
      end,
      pass_expires_at = greatest(now(), coalesce(u.pass_expires_at, now()))
        + case
            when p_days = 0
              then public.hour_pass_minutes_for(v_uid) * interval '1 minute'
            else (p_days || ' days')::interval
          end
  where u.id = v_uid
    and coalesce((u.pass_balances ->> p_days::text)::int, 0) >= 1;

  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    raise exception 'NO_PASS_STOCK';
  end if;

  return public._wallet();
end;
$$;

-- ── 6) claim_ad_reward — 적립액을 대학별로 ──
-- 본문은 20260713164934 그대로, 적립액 산출만 헬퍼로 교체(원장·잔액 두 곳 모두).
-- daily_cap·cooldown은 전역 유지 — 이번 조정 대상이 아니다.
create or replace function public.claim_ad_reward(p_token uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_view ad_views;
  v_min int;
  v_cfg ad_reward_config;
  v_today int;
  v_rows int;
  v_amount int;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;

  -- H3: 사용자 행 잠금 — 같은 유저의 동시 claim을 직렬화. 뒤따르는 트랜잭션은
  -- 앞선 커밋 이후의 claimed 집계를 보게 되어 cap 검사(count-then-act)가 유효해진다.
  perform 1 from users where id = v_uid for update;

  -- H2: 대상 시청 행도 잠금 — 같은 토큰 동시 호출이 여기서 줄을 선다.
  select * into v_view from ad_views
    where token = p_token and user_id = v_uid and claimed_at is null
    for update;
  if v_view.id is null then raise exception 'INVALID_TOKEN'; end if;

  select coalesce(min_view_seconds, 5) into v_min from ads where id = v_view.ad_id;
  if now() < v_view.created_at + (coalesce(v_min,5) * interval '1 second') then
    raise exception 'TOO_SOON';
  end if;

  select * into v_cfg from ad_reward_config where id = 1;
  if v_cfg.id is null then raise exception 'NO_CONFIG'; end if;

  select count(*) into v_today from ad_views
    where user_id = v_uid and claimed_at is not null and claimed_at::date = current_date;
  if v_today >= v_cfg.daily_cap then raise exception 'CAP_REACHED'; end if;

  -- 대학별 적립액 — get_ad_reward_status가 화면에 보여주는 값과 같은 헬퍼를 쓴다.
  v_amount := public.ad_reward_points_for(v_uid);

  -- 조건부 UPDATE + row_count 확인: 락을 못 잡는 경로가 생겨도 이중 적립 불가
  update ad_views set claimed_at = now() where id = v_view.id and claimed_at is null;
  get diagnostics v_rows = row_count;
  if v_rows = 0 then raise exception 'INVALID_TOKEN'; end if;

  insert into points (user_id, amount, reason, ad_view_id) values (v_uid, v_amount, 'ad_view', v_view.id);
  update users set point_balance = point_balance + v_amount where id = v_uid;
  return _wallet();
end $$;

-- ── 7) get_ad_reward_status — 화면에 보여줄 적립액도 같은 헬퍼로 ──
-- 본문은 20260802002643 그대로, reward_points 산출만 교체. daily_cap·cooldown은 전역 유지.
create or replace function public.get_ad_reward_status()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_daily_cap integer;
  v_reward_points integer;
  v_cooldown_minutes integer;
  v_claimed_today integer;
  v_last_claimed_at timestamptz;
  v_cooldown_until timestamptz;
  v_available boolean;
  v_reason text;
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select c.daily_cap, c.cooldown_minutes
    into v_daily_cap, v_cooldown_minutes
  from public.ad_reward_config c
  where c.id = 1;

  if not found then
    raise exception 'NO_CONFIG';
  end if;

  v_reward_points := public.ad_reward_points_for(v_uid);

  select count(*)::integer, max(v.claimed_at)
    into v_claimed_today, v_last_claimed_at
  from public.ad_views v
  where v.user_id = v_uid
    and v.claimed_at is not null
    and v.claimed_at::date = current_date;

  v_cooldown_until := case
    when v_cooldown_minutes > 0 and v_last_claimed_at is not null
      then v_last_claimed_at + (v_cooldown_minutes * interval '1 minute')
    else null
  end;

  if v_claimed_today >= v_daily_cap then
    v_available := false;
    v_reason := 'CAP_REACHED';
  elsif v_cooldown_until is not null and now() < v_cooldown_until then
    v_available := false;
    v_reason := 'COOLDOWN';
  else
    v_available := true;
    v_reason := null;
  end if;

  return jsonb_build_object(
    'available', v_available,
    'unavailable_reason', v_reason,
    'daily_cap', v_daily_cap,
    'claimed_today', v_claimed_today,
    'remaining_today', greatest(v_daily_cap - v_claimed_today, 0),
    'reward_points', v_reward_points,
    'cooldown_until', v_cooldown_until
  );
end;
$$;

-- ── 8) 기존 1시간권 재고 방어 환불 ──
-- 2026-08-08 조회 기준 서울대 유저의 미사용 최소상품 재고는 0건이었다. 조회와 적용 사이에
-- 누가 살 수 있으므로, 남아 있으면 산 값(pass_price(0)=5P)만큼 환급하고 키를 제거한다.
-- 예상 결과는 0행이며, 생기면 5P 주고 산 상품이 말없이 1/12로 깎이는 것을 막는다.
-- 0 재고 키를 남기지 않는 규약은 20260801071450과 같다.
with target as (
  select u.id as user_id,
         coalesce((u.pass_balances ->> '0')::int, 0) as stock
  from public.users u
  join public.universities un on un.id = u.university_id
  join public.university_point_policy p on p.university_id = u.university_id
  where un.name = '서울대학교'
    and p.hour_pass_minutes < 60
    and coalesce((u.pass_balances ->> '0')::int, 0) > 0
), refunded as (
  insert into public.points (user_id, amount, reason)
  select t.user_id, t.stock * public.pass_price(0), 'pass_refund'
  from target t
  returning user_id, amount
)
update public.users u
set pass_balances = coalesce(u.pass_balances, '{}'::jsonb) - '0'::text,
    point_balance = u.point_balance + r.amount
from refunded r
where u.id = r.user_id;

-- ── 9) 서울대 전용 공지 ──
-- university_id를 서울대로 한정해 다른 학교엔 안 보인다. is_pinned=false(고정은 필독 공지만).
-- 제목 기준 upsert라 재실행·db reset에 안전하다.
do $$
declare
  v_uni_id integer;
  v_notice_id integer;
  v_content text := $notice$안녕하세요, 근로고래입니다. 🐳

서울대학교 이용자분들께 열람권과 포인트 적립 관련 한시 조정을 안내드립니다.

1. 무엇이 바뀌나요

• 최소 열람권: 1시간 → 5분 (가격은 5P 그대로입니다)
• 광고 시청 적립: 1편당 5P → 2P

7일 열람권(20P)과 30일 열람권(35P)의 기간과 가격은 그대로입니다.

2. 왜 조정하나요

서울대학교는 아직 서비스 초기 단계입니다. 리뷰가 충분히 모여야 열람권의 가치도 살아나기 때문에, 리뷰가 쌓이는 선순환이 자리잡을 때까지 한시적으로 조정했습니다.

3. 언제 되돌리나요

리뷰가 충분히 모이면 다른 학교와 동일한 기준으로 되돌립니다. 되돌릴 때 공지로 다시 안내드리겠습니다.

이용에 불편을 드려 죄송합니다. 더 나은 정보를 더 빨리 드릴 수 있도록 하겠습니다.

감사합니다.
근로고래 드림$notice$;
begin
  select id into v_uni_id from public.universities where name = '서울대학교';
  if v_uni_id is null then
    raise exception '서울대학교 대학 행을 찾지 못해 공지 등록을 중단합니다';
  end if;

  select id into v_notice_id
  from public.notices
  where university_id = v_uni_id
    and title = '[안내] 서울대 열람권·적립 한시 조정'
  order by id
  limit 1;

  if v_notice_id is null then
    insert into public.notices (title, content, is_pinned, university_id)
    values ('[안내] 서울대 열람권·적립 한시 조정', v_content, false, v_uni_id);
  else
    update public.notices
    set content = v_content, updated_at = now()
    where id = v_notice_id;
  end if;
end
$$;

-- ── 10) 전역 필독 공지 문구 동기화 — 학교 불변 값으로 오해될 문구 정정 ──
-- 대상은 '[필독] 근로고래 이용 안내'(university_id null · is_pinned true, 20260801050000에서
-- 통합, 20260808113010에서 적립가 30P/20P로 갱신). notices RLS는
-- "university_id is null or university_id = 내 대학"의 합집합이고 목록은 고정 공지를
-- 먼저 보여주므로, 서울대 사용자 화면에서는 이 전역 공지가 9)의 서울대 전용 공지보다
-- 항상 위에 뜬다. 이 공지가 "1시간 열람권 5P"·"광고 시청 1회 5P"를 학교 무관 현재값처럼
-- 단정한 채로 두면, 바로 아래 뜨는 서울대 정정 공지를 화면에서 도로 덮어써 보인다.
-- 7일권 20P·30일권 35P는 여전히 학교 무관 전역값이라 그대로 둔다.
-- 재실행 시 두 replace 모두 대상 문구가 이미 사라져 0행 매치 — 멱등.
update public.notices
set content = replace(content,
  '광고 시청 1회 5P로 모을 수 있습니다',
  '광고 시청으로 모을 수 있습니다. 광고 적립액은 학교마다 다를 수 있으며, 정확한 금액은 교환센터 화면에서 확인할 수 있습니다')
where content like '%광고 시청 1회 5P로 모을 수 있습니다%';

update public.notices
set content = replace(content,
  '교환센터에서 1시간 열람권 5P, 7일 열람권 20P, 30일 열람권 35P로 교환할 수 있습니다',
  '교환센터에서 최소 열람권 5P, 7일 열람권 20P, 30일 열람권 35P로 교환할 수 있습니다. 최소 열람권의 열람 가능 시간은 학교마다 다를 수 있으며, 정확한 시간은 교환센터 화면에 표시됩니다')
where content like '%교환센터에서 1시간 열람권 5P, 7일 열람권 20P, 30일 열람권 35P로 교환할 수 있습니다%';

commit;
