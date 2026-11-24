-- 목적: 교외 근무지 32행의 region 정규화 + CHECK 제약으로 재발 방지 — 지역 필터로 도달 불가능하던 것 해소
-- 날짜: 2026-07-16 · 담당: 배경록
-- 비고: 20260716180000 push 후 검증 중 발견한 별건(그 마이그레이션과 무관한 기존 결함).
--
-- 무엇이 문제였나:
--   KOSAF 임포터가 region을 정규화하지 않아 일부 행이 긴 행정구역명으로 들어갔다
--   ('경기도'·'서울특별시'·'서울시'·'광주광역시' 등 11종 32행, 전부 national/off_campus).
--   프론트 지역 필터는 lib/profileOptions.js의 REGIONS(짧은 형태 '서울'·'경기' … 17개)만
--   보내므로, 이 32행은 **지역 필터로 영원히 도달 불가**였다(교외 6,647 중 0.5%).
--   검색어·다른 필터로는 나왔으므로 "안 보임"이 아니라 "지역으로는 못 찾음" — 그래서 안 들켰다.
--
-- 매핑 근거: 32행 전부 address 앞부분과 대조해 확인(불일치 0). 추측 없음.
-- 멱등: 짧은 형태로 바뀌면 where 절에 다시 걸리지 않는다(재실행 = 0행 갱신).
--
-- ⚠️ 순서 주의: UPDATE(1) → CHECK(2). 제약을 먼저 걸면 기존 32행 때문에 실패한다.

-- ── 1. 32행 백필 ──
update worksites w
   set region = m.short_name,
       updated_at = now()
  from (values
    ('서울특별시',     '서울'),
    ('서울시',         '서울'),
    ('경기도',         '경기'),
    ('인천광역시',     '인천'),
    ('부산광역시',     '부산'),
    ('대구광역시',     '대구'),
    ('대전광역시',     '대전'),
    ('광주광역시',     '광주'),
    ('충청남도',       '충남'),
    ('경상북도',       '경북'),
    ('제주특별자치도', '제주')
  ) as m(long_name, short_name)
 where w.region = m.long_name;

-- ── 2. 재발 방지 — region은 REGIONS 17개 또는 NULL만 ──
-- 목록은 web/src/lib/profileOptions.js의 REGIONS와 일치해야 한다(지역 필터가 보내는 값의 전체 집합).
-- 한국 시·도는 닫힌 집합이라 하드코딩이 적절하다. 바뀌면(예: 도 신설) 양쪽을 같이 고칠 것.
--
-- NULL 허용 이유: **교내(on_campus)는 region이 NULL이 정상**이다(20260716180000 참고 —
-- 지역 필터가 교내를 건너뛴다). 현재 NULL 81행 = 교내 국가근로 57 + school 24, 전부 교내.
--
-- 이 제약의 값어치: 임포터가 정규화를 빠뜨리면 **적재가 에러로 터진다.**
-- 지금까지는 조용히 들어가서 "지역 필터에서만 안 보이는" 상태로 몇 달을 갔다 — 그게 이 버그다.
-- 시끄러운 실패가 조용한 데이터 유실보다 낫다.
--
-- ⚠️ 새 KOSAF/KUPID 크롤러는 이 계약을 지켜야 한다: 교외는 짧은 형태로 정규화, 교내는 NULL.
--    (근본 원인은 여전히 임포터다. crawling_scripts/import_to_supabase.py는 재작성 예정.)
alter table worksites drop constraint if exists worksites_region_normalized;

alter table worksites
  add constraint worksites_region_normalized
  check (region is null or region in (
    '서울', '경기', '부산', '경남', '인천', '경북', '대구', '충남', '전남',
    '전북', '충북', '강원', '대전', '광주', '울산', '제주', '세종'
  ));

comment on constraint worksites_region_normalized on worksites is
  'region은 REGIONS(lib/profileOptions.js) 짧은 형태 17개 또는 NULL(교내)만. 정규화 누락이 조용히 들어와 지역 필터에서 사라지는 것을 막는다.';
