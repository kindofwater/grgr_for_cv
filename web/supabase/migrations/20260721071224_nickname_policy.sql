-- 목적: 닉네임 서버 검증 도입(허용문자·한글8/영문16 가중길이·예약어) + 직접 UPDATE 경로 차단 — 프론트에만 있던 규칙의 서버 권위 확보
-- 날짜: 2026-07-21 · 담당: 배경록
--
-- 배경: 지금까지 닉네임 제한은 프론트 nicknameError(2~20자)뿐이었다. RPC 직접 호출이면
--   1~50자 아무 문자열이나 통과했고(varchar(50) + unique가 전부), 20260624025109의
--   grant update(... nickname ...)로 로그인 사용자가 API 직접 호출로 무검증 변경도 가능했다.
--   특히 list_worksite_reviews가 익명 리뷰를 문자열 '익명'으로 표시하므로, 닉네임을
--   '익명'으로 지으면 익명 리뷰와 구분이 안 되는 사칭 구멍이 있었다.
--
-- 규칙(프론트 lib/authValidation.js nicknameError와 반드시 동일하게 유지 — 이중 소스):
--   · 허용 문자: 완성형 한글(가-힣)·영문·숫자만 (공백·특수문자·자모·이모지·제로폭 불가)
--   · 길이: 2자 이상 + 가중치(한글 2·영숫자 1) 합 16 이하 → 한글 8자 / 영문 16자 / 혼용 비례
--   · 예약어: 부분 일치(소문자化) 차단 — 운영진·서비스 사칭 및 '익명' 위장 방지.
--     ('admin'이 'badminton'류를 잡는 오탐은 감수 — 한국어 서비스에서 실제 충돌 희박)
--
-- 적용 지점:
--   · create_profile: insert 전 validate_nickname 호출(본문은 20260717150000 그대로 재현 +
--     검증 1줄 + trim 저장. 시그니처 불변 → create or replace, 기존 grant 유지).
--   · update_profile: 닉네임을 안 받으므로 해당 없음.
--   · 직접 UPDATE: 컬럼 grant 회수로 경로 자체를 닫음(변경 UI 없음 — 추후 변경 기능을
--     만들면 validate_nickname을 쓰는 전용 RPC로 열 것).
--
-- ⚠️ CHECK 제약은 의도적으로 안 건다: 기존 행에 이메일 @앞부분 폴백 닉네임(점·하이픈 포함
--   가능)이 있어, NOT VALID로 걸어도 그 행의 무관한 UPDATE(지역 변경 등)까지 터진다.
--   기존 닉네임은 소급하지 않는다(신규·변경만 규제).

-- ── 1. validate_nickname: 규칙 위반 시 예외(NICKNAME_INVALID / NICKNAME_RESERVED) ──
create or replace function public.validate_nickname(p_nickname text)
returns void
language plpgsql
set search_path = public
as $$
declare
  v text := trim(coalesce(p_nickname, ''));
  v_weighted int;
  -- 예약어 목록 — 프론트 authValidation.js RESERVED_NICKNAMES와 동일하게 유지할 것
  v_reserved text[] := array[
    '익명', '운영자', '관리자', '근로고래', '고래지기',
    'admin', 'administrator', 'manager', 'operator', 'staff',
    'system', 'anonymous', 'official', 'grgr', 'geunrogorae'
  ];
  r text;
begin
  if v = '' or v !~ '^[가-힣A-Za-z0-9]+$' then
    raise exception 'NICKNAME_INVALID';
  end if;
  -- 가중 길이 = 전체 글자수 + 한글 글자수 (한글 2·영숫자 1)
  v_weighted := char_length(v) + (char_length(v) - char_length(regexp_replace(v, '[가-힣]', '', 'g')));
  if char_length(v) < 2 or v_weighted > 16 then
    raise exception 'NICKNAME_INVALID';
  end if;
  foreach r in array v_reserved loop
    if position(r in lower(v)) > 0 then
      raise exception 'NICKNAME_RESERVED';
    end if;
  end loop;
end $$;

-- 내부 전용(security definer RPC가 소유자 권한으로 호출) — 클라 직접 호출 불필요.
revoke execute on function public.validate_nickname(text) from public, anon, authenticated;

-- ── 2. create_profile: insert 전 검증 + trim 저장 (본문은 20260717150000 기반) ──
create or replace function create_profile(
  p_nickname        text,
  p_university_id   int,
  p_college_name    text,
  p_department_name text,
  p_track           text,
  p_admission_year  int,
  p_degree_program  text,
  p_academic_status text,
  p_grade           int,
  p_region          text
) returns void
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_college_id int;
  v_department_id int;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  -- 이미 프로필 있으면 재생성하지 않음(더블클릭/재호출 안전). 갱신은 update_profile 담당.
  if exists (select 1 from users u where u.id = v_uid) then
    return;
  end if;

  perform validate_nickname(p_nickname);

  select id into v_college_id from colleges
    where university_id = p_university_id and name = p_college_name limit 1;
  if v_college_id is null then
    select id into v_college_id from colleges where university_id = p_university_id order by id limit 1;
  end if;
  if v_college_id is null then raise exception 'NO_COLLEGE'; end if;
  select id into v_department_id from departments
    where college_id = v_college_id and name = p_department_name limit 1;
  if v_department_id is null then
    select id into v_department_id from departments where college_id = v_college_id order by id limit 1;
  end if;
  if v_department_id is null then raise exception 'NO_DEPARTMENT'; end if;

  insert into users (id, university_id, college_id, department_id, track,
                     nickname, admission_year, degree_program, academic_status, grade, region)
  values (v_uid, p_university_id, v_college_id, v_department_id, p_track,
          trim(p_nickname), p_admission_year,
          p_degree_program::degree_program_e, p_academic_status::academic_status_e,
          p_grade, p_region);

  -- 가입 축하 5p — 원장(내역 표시용) + 지갑 캐시. 위 조기 return 가드 덕에 1회만 지급된다.
  insert into points (user_id, amount, reason) values (v_uid, 5, 'signup_bonus');
  update users set point_balance = point_balance + 5 where id = v_uid;
exception
  when unique_violation then raise exception 'NICKNAME_TAKEN';
end $$;

-- ── 3. 직접 UPDATE 경로 차단: nickname 컬럼 grant 회수 ──
-- 20260624025109가 컬럼 화이트리스트로 grant한 것 중 nickname만 뺀다.
-- (닉네임 변경 UI가 없으므로 정상 경로 영향 0 — 남는 건 우회 호출뿐이었다)
revoke update (nickname) on public.users from authenticated;
