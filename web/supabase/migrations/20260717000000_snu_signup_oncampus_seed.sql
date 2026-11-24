-- 목적: 서울대학교 개설(가입 오픈) + 교내 국가근로 근무지 24개 시드 + placeholder posting
-- 날짜: 2026-07-17 · 담당: 배경록
-- 비고: plan docs/superpowers/plans/2026-07-17-snu-oncampus-seed.md
--       ① universities에 서울대학교(snu.ac.kr, signup_enabled=true) — 고려대 외 첫 학교
--       ② colleges/departments '미분류' 1쌍 — handle_new_user의 NO_COLLEGE/NO_DEPARTMENT 방지
--       ③ worksites 24행(national+on_campus, region NULL) ④ placeholder postings 24행
--       기존 데이터(고려대 근무지·리뷰)는 건드리지 않는다 — 순수 추가.

-- ── 1. 서울대학교 개설 ──
-- 가입 화면 학교 드롭다운은 universities 테이블에서 오므로(fetchUniversities) 프론트 수정 없이 노출된다.
-- 단과대/학과 드롭다운은 profileOptions.js의 고려대 목록 하드코딩이라 서울대생에겐 부정확하지만,
-- handle_new_user가 서울대 소속에서 이름 매칭 실패 → 첫 행 fallback → 아래 '미분류'가 저장된다(가입은 안 깨짐).
-- track은 유저가 고른 계열이 그대로 저장된다(m->>'track'). 실제 서울대 단과대/학과 명부와
-- 프론트 정비는 별도 작업 — 가입 오픈까지 텀이 있어 감수하기로 결정(2026-07-17).
insert into universities (name, campus, email_domain, signup_enabled)
select '서울대학교', null, 'snu.ac.kr', true
 where not exists (select 1 from universities where name = '서울대학교');

-- 재실행 수렴: 행이 이미 있어도 가입 오픈 상태를 보장 (멱등)
update universities set signup_enabled = true
 where name = '서울대학교' and not signup_enabled;

-- ── 2. '미분류' 단과대·학과 1쌍 ──
-- 서울대에 colleges/departments가 0행이면 handle_new_user가 NO_COLLEGE 예외로 가입이 깨진다.
-- default_track은 유저 track에 영향 없음(프론트가 하드코딩 목록에서 자동 세팅) — NOT NULL이라 유효값만 채운다.
insert into colleges (university_id, name)
select u.id, '미분류'
  from universities u
 where not exists (select 1 from colleges c where c.university_id = u.id and c.name = '미분류')
   and u.name = '서울대학교';

insert into departments (college_id, name, default_track)
select c.id, '미분류', '인문사회계열'
  from colleges c
  join universities u on u.id = c.university_id
 where not exists (select 1 from departments d where d.college_id = c.id and d.name = '미분류')
   and u.name = '서울대학교' and c.name = '미분류';

-- ── 3. 시드 — worksites 24행 ──
-- 소스: 붙임. '24~'26년 연도별 유형별 근로지 현황.xlsx (기관명='서울대학교(본교) 학부' AND 유형='일반교내')
--       67행(24/25/26 연도별 중복 포함) → 근로지명 dedup(최신 연도 우선) 24개. 우편번호 접두 [0xxxx] 제거.
-- 2026 목록에 없는 2곳(약학대학=2025·자유전공학부=2024)도 포함 — 과거 근무자 리뷰 선적립 목적(고려대 선례와 동일).
-- 간호대학은 연건캠퍼스(종로구 대학로) 주소지만 서울대 교내이므로 on_campus.
-- region은 NULL(교내는 지역 필터 대상 아님 — 20260716180000의 location_type 판정 참고).
-- 멱등: worksites에 유니크 제약이 없어 on conflict 불가 → where not exists.
with uni as (
  select id from universities where name = '서울대학교'
),
seed(workplace_name, address) as (values
  ('간호대학', '서울 종로구 대학로 103 간호대학 (연건동, 서울대학교)'),
  ('경영대학', '서울 관악구 관악로 1, 서울대학교 경영대학'),
  ('공과대학', '서울 관악구 관악로 1, 서울대학교 공과대학'),
  ('규장각한국학연구원', '서울 관악구 관악로 1, 서울대학교 규장각한국학연구원'),
  ('글로벌사회공헌단', '서울 관악구 관악로 1, 서울대학교 글로벌사회공헌단'),
  ('농업생명과학대학', '서울 관악구 관악로 1, 서울대학교 농업생명과학대학'),
  ('미술대학', '서울 관악구 관악로 1, 서울대학교 미술대학'),
  ('사범대학', '서울 관악구 관악로 1, 서울대학교 사범대학'),
  ('사회과학대학', '서울 관악구 관악로 1, 서울대학교 사회과학대학'),
  ('생활과학대학', '서울 관악구 관악로 1, 서울대학교 생활과학대학'),
  ('시설기획과', '서울 관악구 관악로 1, 서울대학교 행정관 시설기획과'),
  ('약학대학', '서울 관악구 관악로 1, 서울대학교 약학대학'),
  ('언어교육원', '서울 관악구 관악로 1, 서울대학교 137-1동 202호'),
  ('음악대학', '서울 관악구 관악로 1, 서울대학교 종합교육연구동 220동 411호 음악대학 교학행정실'),
  ('인문대학', '서울 관악구 관악로 1, 서울대학교 인문대학'),
  ('자연과학대학', '서울 관악구 관악로 1, 서울대학교 자연과학대학'),
  ('자유전공학부', '서울 관악구 관악로 1, 서울대학교 자유전공학부'),
  ('장학복지과', '서울 관악구 관악로 1, 서울대학교 행정관 장학복지과'),
  ('정보화본부', '서울 관악구 관악로 1, 서울대학교 정보화본부'),
  ('중앙도서관', '서울 관악구 관악로 1, 서울대학교 중앙도서관'),
  ('첨단융합학부', '서울 관악구 관악로 1 첨단융합학부'),
  ('평생교육원', '서울 관악구 관악로 1, 54동 107호 서울대학교 (신림동)'),
  ('학부대학', '서울 관악구 관악로 1 학부대학 (신림동, 서울대학교)'),
  ('홍보팀', '서울 관악구 관악로 1 60동 행정관 (신림동, 서울대학교)')
)
insert into worksites (university_id, type, location_type, organization_name, workplace_name, region, address)
select uni.id, 'national', 'on_campus', '서울대학교(본교) 학부', s.workplace_name, null, s.address
  from seed s, uni
 where not exists (
   select 1 from worksites w
    where w.university_id = uni.id
      and w.type = 'national'
      and w.location_type = 'on_campus'
      and w.workplace_name = s.workplace_name
 );

-- ── 4. placeholder postings 24행 (근무지당 1개) ──
-- 공고 없는 worksite는 앱에 안 뜬다 — 게이트 3중(①검색 RPC의 join rep INNER ②자동완성의 exists postings
-- ③상세의 infoReady = worksite && posting)이 공고 ≥1을 요구한다. 껍데기 posting으로 통과시킨다.
-- 자격은 국가근로 규칙값(long/학부만/재학만) — 기본값(3=미정/unknown)으로 두면 유저가 "학부생만"·"장기"
-- 필터를 켜는 순간 24개가 전부 사라진다. 20260716180000 선례와 같은 값.
-- 실제 공고를 넣을 땐 `delete from postings where worksite_id=X and is_placeholder=true` 후 insert.
insert into postings (worksite_id, is_active, is_placeholder, work_duration_type, eligible_degree, eligible_status)
select w.id, false, true, 'long', 0, 0
  from worksites w
  join universities u on u.id = w.university_id
 where u.name = '서울대학교'
   and w.type = 'national'
   and w.location_type = 'on_campus'
   and not exists (
     select 1 from postings p
      where p.worksite_id = w.id and p.is_placeholder = true
   );
