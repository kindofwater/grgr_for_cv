-- 목적: 2026-2학기 고려대 국가근로 희망근로지 107곳(교내 50·교외 57) 공고 적재 + 교내 근무지명을 신청 화면 표기로 정리
-- 날짜: 2026-08-12 · 담당: 배경록
--
-- 출처: 고려대학교 국가장학 희망근로지 신청 화면 (신청기간 2026-08-12 10:00 ~ 2026-08-14 23:59 KST)
-- 화면 컬럼: 순번 | 교내외 구분 | 근로부서 | 모집(명) | 지원(명) | 전화번호 | 수행업무
--   · 전화번호는 개인정보 최소수집 방침(2026-06-19 회의 #15에서 contact_phone 제거)에 따라 적재하지 않는다.
--   · 지원(명)은 실시간으로 변하는 값이라 적재하지 않는다.
--
-- ── 결정 사항 (2026-08-12 PM 확인) ──
-- ① 근무지명은 신청 화면 원문 그대로 쓴다. 기관명 표기가 갈려도 임의 통일하지 않는다
--    (55번 '성북강북교육청(재정지원과)' vs 66번 '성북강북교육지원청(초등교육지원과)' — 원문대로 둘 다 유지).
--    같은 이름이 그대로 반복된 중복 표기만 정리한다:
--      '학생상담센터 _학생상담센터'   → 학생상담센터
--      '학부대학행정팀_학부대학행정팀' → 학부대학행정팀
-- ② 교내 50곳은 전부 기존 행(20260716180000 명부 시드)에 대응한다. 새 교내 근무지는 만들지 않고
--    이름만 신청 화면 표기로 맞춘다 — 리뷰 21건은 worksite_id에 붙어 있어 개명해도 무손상.
--    예외로 도서관 2곳(순번 49·50)은 접두어를 유지한다. '학술정보서비스팀'으로 줄이면
--    '도서관'으로 검색할 때 중앙·과학도서관이 통째로 사라진다(검색 RPC는 이름 ilike 부분일치).
-- ③ 교외 57곳은 고려대 전용(university_id=1)으로 만든다 — 20260805130000 교우회 선례.
--    기존 공용(university_id=0) 전국 명부 6,649행과 완전일치가 8곳뿐이고, 교육지원청은 공용에 대표 1행만
--    있어 과 단위로 나뉜 이번 목록과 입도가 맞지 않는다. 단 교우장학회·교우회 2곳은 이미 고려대(1)에
--    있으므로(20260805130000) 새로 만들지 않고 재사용한다 — normalized_name으로 붙는다.
-- ④ 이번 목록에 없는 기존 교내 6곳(노동대학원행정팀·영재교육원·정경대학 평화연구소·정보대학행정팀·
--    체육지원팀·학생지원팀(공통))과 학생상담센터(자연계)는 남기고 모집완료로 둔다.
--    과거 학기 근무자의 리뷰 작성 경로를 지키기 위함이다(정보대학행정팀에는 이미 리뷰 1건이 있다).
-- ⑤ 시급: 교내 10,320원 / 교외 12,790원 — 20260805100000(서울대 교내)·20260805130000(고려대 교외)과 같은 값.
-- ⑥ 자격은 국가근로 규칙값 long/0(학부만)/0(재학만). 기본값 3(미정)으로 두면 유저가 '학부생만'·'장기'
--    필터를 켜는 순간 이번 107곳이 전부 사라진다 — 20260716180000·20260708100000의 선례와 같은 값.
--
-- 📌 20260810012615(신청 안내 공지)는 recruit_until을 일부러 비워 뒀다 — 그때 교내 57건은 내용 없는
--    placeholder라 "모집중"으로 떠도 눌러볼 게 없었기 때문이다. 이 마이그레이션이 그 전제를 없앤다:
--    placeholder를 모집인원·수행업무가 담긴 실제 공고로 교체하므로 이제 마감일을 넣는 게 맞다.
--    신청은 KUPID 일괄 접수라 근무지별 마감이 따로 있지는 않지만, 107곳의 접수 마감 시각이
--    모두 같으므로 같은 값(8/14 23:59)을 넣으면 화면의 모집중/모집완료가 실제와 일치한다.
--
-- ⚠️ 크롤러 영향 없음: crawling_scripts는 type='school'만 upsert한다(upsert_worksites.py의 eq("type","school")).
--    이 마이그레이션은 type='national'만 건드리므로 KUPID/KOSAF 크롤 매칭과 겹치지 않는다.
--    worksite_norm.py의 별칭 '학예기록팀'→'박물관 학예기록팀'도 school 전용이라 순번 8 개명과 무관하다.
-- ⚠️ 교외 주소: 신청 화면에 주소 컬럼이 없어 address는 NULL로 둔다. region은 '서울'로 채운다
--    (전화번호 국번이 전부 서울권 02/070/1599이고 통학 가능 근무지만 실린 목록).
--    교외에 region이 비면 지역 필터에서 조용히 사라지므로 NULL로 두지 않는다(worksites_region_normalized).
--    상세 페이지에서 주소를 확보하면 별도 마이그레이션으로 보완할 것.

begin;

-- ══════════════════════════════════════════════════════════════════
-- 1. 교내 50곳 — 신청 화면 매핑 (legacy_name = 현재 DB 이름, final_name = 신청 화면 표기)
-- ══════════════════════════════════════════════════════════════════
create temporary table ku_2026_2_oncampus (
  seq             integer primary key,
  legacy_name     text not null unique,
  final_name      text not null unique,
  recruit_count   text not null,
  job_description text not null
) on commit drop;

insert into ku_2026_2_oncampus (seq, legacy_name, final_name, recruit_count, job_description) values
  (1,  '학생지원팀', '학생지원팀', '2',
       '학생지원팀 행정업무 및 전화문의 등 (학생지원, 장학지원)- 테스트'),
  (2,  '경영지원팀(화정체육관)', '경영지원팀', '2',
       '화정체육관 문의 전화 응대 및 사무실 내 업무'),
  (3,  '관리팀', '관리팀', '1',
       '관리팀 업무보조'),
  (4,  '정경대학 경제연구소', '경제연구소', '1',
       '연구소 행정 지원 (사무보조 등)'),
  (5,  '사범대학 교육문제연구소', '교육문제연구소', '1',
       '연구소 업무보조(연구 관련 자료 정리, 문서 작업, 전화 응대 등)'),
  (6,  '고대신문사', '고대신문사', '2',
       '고대신문사 업무 보조'),
  (7,  '생명과학대학 식품과학종합실험실(고대빵)', '식품과학종합실험실', '2',
       E'고대빵 홈페이지관리\n고대빵 행정보조'),
  (8,  '박물관 학예기록팀(기록파트)', '학예기록팀', '3',
       '학예기록팀 기록파트 교사자료 정리 보조 및 목록 작성, 기록물 스캔 및 촬영'),
  (9,  '박물관 학예기록팀(학예파트)', '학예기록팀_박물관', '3',
       '학예업무보조, 박물관홍보(SNS활동), 전시실 운영보조, 박물관 서고 정리 등'),
  (10, '테크노콤플렉스기획관리부', '테크노콤플렉스기획관리팀', '1',
       '사무 업무 보조'),
  (11, '사범대학 동아시아문화교류연구소', '동아시아문화교류연구소', '1',
       '연구소 자료 정리 및 행사 보조'),
  (12, '장애학생지원센터(일반)', '장애학생지원센터', '3',
       E'1. 장애학생지원센터 행정 업무 보조\n2. 장애학생 지원\n3. 교내 편의시설 점검'),
  (13, '사범대학 고등교육정책연구소', '고등교육정책연구소', '1',
       '1. 산단에 서류 제출 및 우편 확인 / 2. 자료 및 문서 정리 / 3. 연구소 비품 관리 및 청소'),
  (14, '사범대학 한국어문교육연구소', '한국어문교육연구소', '1',
       '학술대회 및 학술지 발간 사업 지원, 전화 응대'),
  (15, '생명과학대학 기기센터', '기기센터', '2',
       '기초기기 운영지원, 항온실(저온실, 배양실) 온도 관리, 이외 업무 지원'),
  -- 원문 '학생상담센터 _학생상담센터'의 중복 표기를 정리. 기존 (인문계) 행을 정본으로 쓰고
  -- (자연계) 행은 아래 4절에서 모집완료로 남긴다(둘 다 리뷰 0건).
  (16, '학생상담센터(인문계)', '학생상담센터', '2',
       '학생상담센터 문서수발, 비품 관리 등 센터 운영 보조'),
  (17, '커뮤니케이션팀(장비대여)', '커뮤니케이션팀', '5',
       '실습용 방송 기자재 관리 보조 및 미디어 관리 보조'),
  (18, '출판문화원', '출판문화원', '2',
       '출판문화원 사무 및 편집 업무 보조, 문서 수발 및 서고 정리 보조'),
  (19, '경영대학행정팀', '경영대학행정팀', '4',
       '경영대학 행정팀 업무 지원 (근무시간 평일 9:00-18:00)'),
  (20, '문과대학행정팀', '문과대학행정팀', '2',
       '문과대학행정팀 업무 지원'),
  (21, '정경대학행정팀', '정경대학행정팀', '5',
       '정경대학 행정실 업무 보조(우편함, 학생민원 응대, 문서 관리, 시설 및 비품관리)'),
  (22, '이과대학행정팀', '이과대학행정팀', '3',
       E'1. 이과대학 교내 강의실 기자재 점검 및 교내 각종 업무 서포트\n2. 학과 각종 행정 업무 보조, 홈페이지 및 실험실 관리'),
  (23, '공과대학 기계공학부', '공과대학행정팀_기계공학부', '2',
       '행정실 업무보조 및 실습실 관리'),
  (24, '공과대학 건축학과', '공과대학행정팀_건축학과', '1',
       '건축학과 설계실, 제도실, 세미나실, 실습실 관리 및 학과 행정실 행정 보조'),
  (25, '공과대학 전기전자공학부', '공과대학행정팀_전기전자공학부', '2',
       '전기전자공학부 행정실 업무지원, 실험실습 과목 지원, 실험실관리 보조업무'),
  (26, '공과대학 신소재공학부', '공과대학행정팀_신소재공학부', '2',
       E'신소재공학부 행정실 업무지원\n실험실습 과목 지원, 실험실 관리'),
  (27, '공과대학 건축사회환경공학부', '공과대학행정팀_건축사회환경공학부', '1',
       '건축사회환경공학부 행정 업무 보조'),
  (28, '공과대학 화공생명공학과', '공과대학행정팀_화공생명공학과', '2',
       '화공생명공학과 행정실 행정업무 보조'),
  (29, '공과대학 반도체공학과', '공과대학행정팀_반도체공학과', '1',
       '반도체공학과 사무보조'),
  (30, '사범대학 수학교육과 실험실습실', '사범대학행정팀_수학교육과', '2',
       '실습실 기자재 관리 및 도서 자료 정리'),
  (31, '사범대학행정팀(겸:교직팀)', '사범대학행정팀_교직팀', '2',
       '사범대학행정실 및 교직팀 업무 보조'),
  (32, '사범대학 지리교육과 실습분석실', '사범대학행정팀_지리교육과', '3',
       '실습업무지원(지도, 실습컴퓨터, 실험도구 관리 등)'),
  (33, '간호대학행정팀', '간호대학행정팀', '5',
       '간호대학 실습실 및 인증평가 업무보조'),
  -- 이번 학기에 융합데이터과학대학원이 같은 행정팀 소관으로 붙었다.
  (34, '정책대학원행정팀', '정책대학원·융합데이터과학대학원행정팀', '2',
       '석사과정 업무지원 및 행사준비'),
  (35, '공학대학원행정팀', '공학대학원행정팀', '1',
       '행정팀 업무보조'),
  (36, '교육대학원행정팀', '교육대학원행정팀', '1',
       '교육대학원행정팀 사무보조'),
  (37, '국제대학원행정팀', '국제대학원행정팀', '1',
       '국제대학원 업무 보조, 외국인 학생 응대 등'),
  (38, '스마트보안학부·정보보호대학원·개인정보보호대학원행정팀',
       '스마트보안학부·정보보호대학원·개인정보보호대학원행정팀', '2',
       E'1. 학사행정보조 업무\n2. 컴퓨터실 관리업무\n3. 기자재 대여 및 공간대관 업무 보조\n4. 게시판(키오스크) 관리'),
  (39, '국제교육팀', '국제교육팀', '1',
       '외국인 입시 업무 보조 (외국인 입시 안내 및 서류검토)'),
  (40, '보건과학대학행정팀', '보건과학대학행정팀', '2',
       '보건과학대학 행정팀 업무 보조'),
  (41, '건축팀', '건축팀', '2',
       '문서수발 및 행정 업무 보조'),
  (42, '법학전문대학원행정팀', '법학전문대학원행정팀', '1',
       '법전원 평가 관련데이터 정리, 기초자료 만들기, 전화 및 방문자 응대 등'),
  (43, '법무대학원행정팀', '법무대학원행정팀', '2',
       '야간 수업 진행을 위한 기자재 대여 및 업무보조'),
  (44, '학사팀', '학사팀', '2',
       '교내외 학사업무 지원(문의전화 상담 및 자료 정리)'),
  -- 원문 '학부대학행정팀_학부대학행정팀'의 중복 표기를 정리.
  (45, '학부대학행정팀', '학부대학행정팀', '4',
       E'1. 수업기자재 관리\n2. 문의전화 상담 및 자료정리'),
  (46, '심리학부행정팀', '심리학부행정팀', '1',
       '심리학부행정팀 업무보조(강의실대관, 수업기자재 관리 등)'),
  (47, '지속가능경영팀', '지속가능경영팀', '3',
       '리필로드 및 지속가능뉴스레터 등'),
  (48, '국제대학행정팀', '국제대학행정팀', '3',
       '국제대학 업무 보조 및 외국인 학생 응대'),
  -- 49·50은 '도서관'/'과학도서관' 접두어를 일부러 남긴다(위 결정 ②).
  (49, '도서관 학술정보서비스팀', '도서관 학술정보서비스팀', '32',
       E'1) 자료실 운영 및 서비스 업무 보조\n2) 자료 검색, 도서 탐색 및 배가\n3) 도서 대출/반납 및 도서관 자료 이용 안내\n4) 도서의 오배가/분실/훼손 방지 작업\n5) 도서의 보수(수리) 및 정보화 작업\n6) 자료실/서고 환경 관리 및 이용자 요구 응대\n7) 기타 업무 보조 (출입관리, 자동화장비/집기비품관리, 방역수칙 준수 관련 업무 등)'),
  (50, '과학도서관 학술정보큐레이션팀', '과학도서관 학술정보큐레이션팀', '9',
       '과학도서관 대출/반납 및 서가배열 업무 지원');

-- 매핑이 실제 DB와 어긋나면(앞선 개명 마이그레이션 변경 등) 조용히 일부만 적재되지 않도록 여기서 멈춘다.
do $$
declare
  v_missing text;
  v_matched integer;
begin
  select string_agg(s.legacy_name, ', ' order by s.seq) into v_missing
  from ku_2026_2_oncampus s
  where not exists (
    select 1 from public.worksites w
    where w.university_id = 1 and w.type = 'national' and w.location_type = 'on_campus'
      and w.deleted_at is null and w.workplace_name = s.legacy_name
  );
  if v_missing is not null then
    raise exception '교내 매핑 실패 — DB에 없는 기존 이름: %', v_missing;
  end if;

  select count(*) into v_matched from ku_2026_2_oncampus;
  if v_matched <> 50 then
    raise exception '교내 시드 행 수가 50이 아님: %', v_matched;
  end if;
end
$$;

-- ── 1-1. 개명 (25곳) ──
-- 단일 UPDATE라 스냅샷 기준으로 동작한다. final_name이 다른 행의 legacy_name과 겹치지 않음을 확인했다
-- (예: '학생상담센터'는 legacy '학생상담센터(인문계)/(자연계)'와 다르고, '학예기록팀'인 기존 행은 없다).
update public.worksites w
   set workplace_name = s.final_name,
       updated_at = now()
  from ku_2026_2_oncampus s
 where w.university_id = 1
   and w.type = 'national'
   and w.location_type = 'on_campus'
   and w.deleted_at is null
   and w.workplace_name = s.legacy_name
   and w.workplace_name <> s.final_name;

-- ── 1-2. 교내 50곳의 껍데기 공고 제거 ──
-- 명부 시드가 넣어둔 placeholder(is_active=false)는 실제 공고로 교체한다.
-- 리뷰는 worksite_id에 붙어 있어 공고만 갈아끼워도 무손상(20260716180000 헤더 참고).
delete from public.postings p
 using public.worksites w, ku_2026_2_oncampus s
 where p.worksite_id = w.id
   and p.is_placeholder = true
   and w.university_id = 1
   and w.type = 'national'
   and w.location_type = 'on_campus'
   and w.deleted_at is null
   and w.workplace_name = s.final_name;

-- ── 1-3. 교내 50곳 공고 적재 ──
insert into public.postings (
  worksite_id, source, external_id, title,
  recruit_count, job_description, hourly_wage,
  work_duration_type, eligible_degree, eligible_status,
  recruitment_period_text, is_active, is_placeholder,
  recruit_until, recruit_until_at, recruit_until_estimated,
  manual_override, deadline_basis, source_closed_at, source_closed_reason, deleted_at
)
select
  w.id,
  'ku_portal',
  'ku-2026-2:' || s.seq,
  '2026학년도 2학기 국가근로장학생 희망근로지 신청',
  s.recruit_count,
  s.job_description,
  10320,
  'long',
  0,
  0,
  '2026. 8. 12. 10:00 ~ 2026. 8. 14. 23:59',
  now() < timestamptz '2026-08-14 23:59:00+09',
  false,
  date '2026-08-14',
  timestamptz '2026-08-14 23:59:00+09',
  false,
  true,
  'human_confirmed',
  null,
  null,
  null
from ku_2026_2_oncampus s
join public.worksites w
  on w.university_id = 1
 and w.type = 'national'
 and w.location_type = 'on_campus'
 and w.deleted_at is null
 and w.workplace_name = s.final_name
on conflict (source, external_id)
  where source is not null and external_id is not null
do update set
  worksite_id = excluded.worksite_id,
  title = excluded.title,
  recruit_count = excluded.recruit_count,
  job_description = excluded.job_description,
  hourly_wage = excluded.hourly_wage,
  work_duration_type = excluded.work_duration_type,
  eligible_degree = excluded.eligible_degree,
  eligible_status = excluded.eligible_status,
  recruitment_period_text = excluded.recruitment_period_text,
  is_active = excluded.is_active,
  is_placeholder = false,
  recruit_until = excluded.recruit_until,
  recruit_until_at = excluded.recruit_until_at,
  recruit_until_estimated = false,
  manual_override = true,
  deadline_basis = excluded.deadline_basis,
  source_closed_at = null,
  source_closed_reason = null,
  deleted_at = null,
  updated_at = now();

-- ══════════════════════════════════════════════════════════════════
-- 2. 교외 57곳 — 고려대 전용 근무지 + 공고
-- ══════════════════════════════════════════════════════════════════
-- organization_name / workplace_name 분리 규칙:
--   · 괄호로 부서가 명시된 교육지원청 계열(21곳) → 기관명 / 부서명 ("중부교육지원청 - 초등교육지원과")
--   · 부서 표기가 없는 36곳 → 기관명을 양쪽에 넣는다. 카드가 두 줄(org/place)로 렌더되고
--     기존 교외 명부도 같은 형태를 쓴다(예: id=5216 대원고등학교/대원고등학교, 20260805130000 교우회).
-- normalized_name은 unique(university_id, type, normalized_name) 자연키다.
--   순번 70·77만 기존 고려대 행(20260805130000)의 값을 그대로 써서 새로 만들지 않고 붙는다.
create temporary table ku_2026_2_offcampus (
  seq               integer primary key,
  organization_name text not null,
  workplace_name    text not null,
  normalized_name   text not null unique,
  recruit_count     text not null,
  job_description   text not null,
  work_time_text    text,
  min_grade         integer
) on commit drop;

insert into ku_2026_2_offcampus
  (seq, organization_name, workplace_name, normalized_name, recruit_count, job_description) values
  (51, '(재)서울기독교청년회유지재단', '(재)서울기독교청년회유지재단', '(재)서울기독교청년회유지재단', '2',
       '국제교류 및 개발, 청소년 프로그램 업무 지원, 자료 정리 및 사무작업 등'),
  (52, '중부교육지원청', '초등교육지원과', '중부교육지원청(초등교육지원과)', '2',
       '각종 사무 보조 업무, 행사 준비'),
  (53, 'KBT', 'KBT', 'KBT', '3',
       '영어컨텐츠 연구 및 교재 연구'),
  (54, '이문체육문화센터', '이문체육문화센터', '이문체육문화센터', '2',
       '행정업무보조(행사운영보조, 자료작성 및 조사, 기록물철정리 등)'),
  -- 55·66은 원문이 '교육청'/'교육지원청'으로 갈려 있다. 신청 화면 표기를 그대로 둔다(위 결정 ①).
  (55, '성북강북교육청', '재정지원과', '성북강북교육청(재정지원과)', '1',
       '문서정리, 엑셀 작업 등 행정업무 지원'),
  (56, '용두문화복지센터', '용두문화복지센터', '용두문화복지센터', '2',
       '행정업무 보조(수입금관련, 전화응대, 이용자응대 및 북카페 도서 정리 등)'),
  (57, '중부교육지원청', '재정지원과', '중부교육지원청(재정지원과)', '1',
       E'집계 자료 수합 및 정리 등\n사무 보조 업무'),
  (58, '남부교육지원청', '초등교육지원과', '남부교육지원청(초등교육지원과)', '1',
       E'과 업무 관련 기본 문서 처리,\n회의 및 행사 진행 시 지원 업무'),
  (59, '케이유네트웍스', '케이유네트웍스', '케이유네트웍스', '3',
       '수학 및 영어 문항 검수'),
  (60, '성동광진교육지원청', '학생맞춤협력과', '성동광진교육지원청(학생맞춤협력과)', '2',
       '사무 및 행사 보조 및 전화 민원 응대'),
  (61, '성동광진교육지원청', '행정지원과', '성동광진교육지원청(행정지원과)', '2',
       '행정 업무, 행사 지원 및 민원 응대'),
  (62, '김영삼도서관', '김영삼도서관', '김영삼도서관', '3',
       '도서배가, 서가정리, 도서대출 및 반납 데스크 지원, 이용자 응대, 독서문화프로그램 운영지원, 기타 사서보조'),
  (63, '대원고등학교', '대원고등학교', '대원고등학교', '3',
       '학생 자기 주도 학습(자습) 관리 및 행정 업무'),
  (64, '아차산숲속도서관', '아차산숲속도서관', '아차산숲속도서관', '2',
       E'도서 정리 및 배가, 스티커 작업,\n도서관 프로그램 운영 지원 등'),
  (65, '남부교육지원청', '중등교육지원과', '남부교육지원청(중등교육지원과)', '2',
       '전화응대 및 과 회의 및 행사 진행 시 업무 지원'),
  (66, '성북강북교육지원청', '초등교육지원과', '성북강북교육지원청(초등교육지원과)', '2',
       '간단한 엑셀 작업, 서류 오탈자 검토 및 서류 정리'),
  (67, '중부교육지원청', '행정지원과', '중부교육지원청(행정지원과)', '2',
       '각종 사무 보조 업무, 기록물 스캔 작업, 기록물 보유목록 정리 및 서고 정리 작업 지원 업무'),
  (68, '시립동대문청소년센터', '시립동대문청소년센터', '시립동대문청소년센터', '2',
       '스터디카페 출석 및 뒷정리'),
  (69, '도봉도서관', '도봉도서관', '도봉도서관', '4',
       E'- 자료실 업무지원(종합자료실/어린이실/디지털자료실): 도서/비도서자료 대출·반납, 서가배열, 이용자 응대, 행사운영 보조 등\n- 사무실 업무지원(행정지원과, 정보자료과): 사무업무 보조 및 행사운영 보조 등'),
  -- 70·77은 20260805130000이 만든 고려대 교외 행을 재사용한다(normalized_name이 그 값과 같아야 한다).
  (70, '(재)고려대학교 교우장학회', '고려대학교 교우장학회', '고려대학교 교우장학회', '4',
       E'사무보조 및 전화응대,\n행사 지원 등'),
  (71, '(재)내셔널트러스트 문화유산기금', '(재)내셔널트러스트 문화유산기금', '(재)내셔널트러스트 문화유산기금', '1',
       E'1. 재단 비영리/시민단체 문화유산 지킴이, 사무관리, 소장품 관리 보조\n2. 내셔널트러스트 문화유산기금 프로그램 홍보, 진행 보조\n3. 시민문화유산 일상 관리와 관람객 응대, 도슨트(전시해설)'),
  (72, '동대문청소년독서실', '동대문청소년독서실', '동대문청소년독서실', '2',
       '독서실 접수처 업무'),
  (73, '성북강북교육지원청', '학교통합지원과', '성북강북교육지원청(학교통합지원과)', '3',
       '전화응대, 서류 정리 등 부서 행정업무 보조'),
  (74, '나들목가족도서관', '나들목가족도서관', '나들목가족도서관', '2',
       '서가배열, 대출반납, 어린이 책 읽어주기, 문화프로그램 지원, 추천도서 선정, 물품정리 등 지역사회 어린이를 비롯한 주민에게 책을 포함한 문화 서비스 제공'),
  (75, '(주)인포카', '(주)인포카', '(주)인포카', '5',
       '스마트카 앱(APP)에 관심있는 학생 / 앱 개발기획 및 보조업무'),
  (76, '풀무원다논 주식회사', '풀무원다논 주식회사', '풀무원다논 주식회사', '2',
       E'1. 연구업무보조\n- 샘플 분석\n- 미생물 분석준비\n2. 관능평가보조'),
  (77, '고려대학교 교우회', '고려대학교 교우회', '고려대학교 교우회', '5',
       '각종 사무보조 및 전화응대, 행사지원 등'),
  (78, '남부교육지원청', '학교생활교육과', '남부교육지원청(학교생활교육과)', '1',
       '학교폭력심의, 교권보호 심의 관련 업무 지원 및 과 업무 지원'),
  (79, '광진정보도서관', '광진정보도서관', '광진정보도서관', '2',
       '도서 배가 및 이용자 응대 등 사서 업무 보조'),
  (80, '서울대학교사범대학부설고등학교', '서울대학교사범대학부설고등학교', '서울대학교사범대학부설고등학교', '2',
       '도서대출·반납, 서가정리, 독서프로그램 운영 지원, 장서점검 지원, 폐기도서 정리 등'),
  (81, '이문청소년독서실', '이문청소년독서실', '이문청소년독서실', '2',
       E'서류 업무 및\n독서실 이용자 응대'),
  (82, '중부교육지원청', '학교통합지원과', '중부교육지원청(학교통합지원과)', '2',
       E'문서작성, 행사지원\n전화응대'),
  (83, '답십리2청소년독서실', '답십리2청소년독서실', '답십리2청소년독서실', '2',
       '사무보조, 이용자 응대, 도서 정리 등'),
  (84, '성북구가족센터', '성북구가족센터', '성북구가족센터', '1',
       '센터 전화 문의 및 센터 프로그램 홍보지 제작, 자료 정리'),
  (85, '중부교육지원청', '학생맞춤협력과', '중부교육지원청(학생맞춤협력과)', '1',
       E'문서작성, 행사지원\n전화응대'),
  (86, '동대문책마당도서관', '동대문책마당도서관', '동대문책마당도서관', '3',
       '도서 배가 및 서가 정리, 이용자 안내 등 도서관 업무보조'),
  (87, '성북강북교육지원청', '행정지원과', '성북강북교육지원청(행정지원과)', '1',
       '문서정리 및 자료집계, 전화응대 등 행정업무지원'),
  (88, '남부교육지원청', '학생맞춤협력과', '남부교육지원청(학생맞춤협력과)', '2',
       '과 행정업무 보조 및 전화응대'),
  (89, '배봉산숲속도서관', '배봉산숲속도서관', '배봉산숲속도서관', '2',
       '도서 소독, 배가 및 이용자 응대 등 도서관 제반업무'),
  (90, '성북강북교육지원청', '학생맞춤협력과', '성북강북교육지원청(학생맞춤협력과)', '1',
       '문서정리, 엑셀 작업 등 행정업무 지원'),
  (91, '에듀토셀', '에듀토셀', '에듀토셀', '2',
       '장학생 적성과 은사에 따른 업무 배치 가능/ 웹개발 / 영어컨텐츠 영어교재출판 디자인 업무 지원/ Viral Marketing 및 고객관리업무 지원 / 영어교육컨텐츠 개발 / 영어교육컨텐츠 시장조사 및 영업전략 /영어시험관리감독 지원'),
  (92, '대광중학교', '대광중학교', '대광중학교', '1',
       '사무보조 및 기타 업무'),
  (93, '서울종암초등학교', '서울종암초등학교', '서울종암초등학교', '1',
       '도서관 업무 전반 보조, 수업교구 제작, 독서캠프 등 프로그램 보조진행'),
  (94, '신대방누리도서관', '신대방누리도서관', '신대방누리도서관', '2',
       E'사서 업무 보조(홍보물 제작, 이용자 서비스 등)\n도서 정리 및 배열'),
  (95, '서울대광고등학교', '서울대광고등학교', '서울대광고등학교', '2',
       '교무업무 보조(문서분류 및 정리)'),
  (96, '성북강북교육지원청', '중등교육지원과', '성북강북교육지원청(중등교육지원과)', '2',
       E'각종 행사 지원\n학교 제출 파일 수합\n기타 부서 제반 업무 지원'),
  (97, '중부교육지원청', '중등교육지원과', '중부교육지원청(중등교육지원과)', '3',
       '각종 사무 보조 업무, 전화 응대, 행사 준비 등'),
  (98, '중부교육지원청', '학교생활교육과', '중부교육지원청(학교생활교육과)', '1',
       '각종 사무 보조 업무, 전화 응대, 행사 준비 등'),
  (99, '대방어린이도서관', '대방어린이도서관', '대방어린이도서관', '1',
       '도서 정리 및 배가 / 사서 보조'),
  (100, '전일청소년독서실', '전일청소년독서실', '전일청소년독서실', '2',
       '접수처 업무 보조'),
  (101, '동대문구정보화도서관', '동대문구정보화도서관', '동대문구정보화도서관', '2',
       '도서관 자료실 업무 지원 (도서배가, 오배열 확인, 프로그램 운영 지원, 도서관 홍보 등)'),
  (102, '대원여자고등학교', '대원여자고등학교', '대원여자고등학교', '2',
       '학생 자기주도 학습 관리 및 행정업무'),
  (103, '목동실내빙상장', '목동실내빙상장', '목동실내빙상장', '6',
       E'안내데스크 업무\n(안내, 접수)\n행정보조 업무'),
  (104, '주식회사 쿠노소프트', '주식회사 쿠노소프트', '주식회사 쿠노소프트', '1',
       '보안 관련 서버 및 클라이언트 프로그래밍 웹과 앱 프로그래밍'),
  (105, '남부교육지원청', '학교통합지원과', '남부교육지원청(학교통합지원과)', '1',
       E'- 학교 인력채용 관련 지원업무 (엑셀, pdf 작업, 서류작업,노트북 설치 및 회수 등)\n- 기타 학교통합지원과 업무 보조'),
  (106, '중부교육지원청', '평생교육건강과', '중부교육지원청(평생교육건강과)', '2',
       '민원응대(전화, 대면) 및 기록물이관, 민원서류 분류 및 편철, 행사지원 등 업무'),
  (107, '답십리청소년독서실', '답십리청소년독서실', '답십리청소년독서실', '2',
       '사무보조, 이용자 응대, 도서 정리 등');

-- 광진정보도서관만 수행업무 칸에 근로요일·선호학년이 함께 적혀 있어 해당 컬럼으로 옮긴다.
-- (선호학과는 '상관없음'이라 preferred_* 세 컬럼을 비운다 — KOSAF 파싱 규칙과 동일.)
update ku_2026_2_offcampus
   set work_time_text = '월, 수, 목, 금, 토, 일 (9:00~18:00)',
       min_grade = 2
 where seq = 79;

do $$
declare
  v_count integer;
begin
  select count(*) into v_count from ku_2026_2_offcampus;
  if v_count <> 57 then
    raise exception '교외 시드 행 수가 57이 아님: %', v_count;
  end if;
end
$$;

-- ── 2-1. 교외 근무지 생성 (기존 교우회 2곳은 normalized_name 충돌로 건너뛴다) ──
insert into public.worksites (
  university_id, type, location_type, organization_name, workplace_name,
  region, address, normalized_name, national_work_term
)
select
  1, 'national', 'off_campus', s.organization_name, s.workplace_name,
  '서울', null, s.normalized_name, 'semester'
from ku_2026_2_offcampus s
on conflict (university_id, type, normalized_name)
  where normalized_name is not null and deleted_at is null
do nothing;

do $$
declare
  v_resolved integer;
begin
  select count(*) into v_resolved
  from ku_2026_2_offcampus s
  join public.worksites w
    on w.university_id = 1
   and w.type = 'national'
   and w.location_type = 'off_campus'
   and w.deleted_at is null
   and w.normalized_name = s.normalized_name;

  if v_resolved <> 57 then
    raise exception '교외 근무지 해석 실패 — 57곳 중 %곳만 연결됨', v_resolved;
  end if;
end
$$;

-- ── 2-2. 교외 껍데기 공고 제거 (교우회 2곳의 모집마감 placeholder) ──
delete from public.postings p
 using public.worksites w, ku_2026_2_offcampus s
 where p.worksite_id = w.id
   and p.is_placeholder = true
   and w.university_id = 1
   and w.type = 'national'
   and w.location_type = 'off_campus'
   and w.deleted_at is null
   and w.normalized_name = s.normalized_name;

-- ── 2-3. 교외 57곳 공고 적재 ──
insert into public.postings (
  worksite_id, source, external_id, title,
  recruit_count, job_description, work_time_text, min_grade, hourly_wage,
  work_duration_type, eligible_degree, eligible_status,
  recruitment_period_text, is_active, is_placeholder,
  recruit_until, recruit_until_at, recruit_until_estimated,
  manual_override, deadline_basis, source_closed_at, source_closed_reason, deleted_at
)
select
  w.id,
  'ku_portal',
  'ku-2026-2:' || s.seq,
  '2026학년도 2학기 국가근로장학생 희망근로지 신청',
  s.recruit_count,
  s.job_description,
  s.work_time_text,
  s.min_grade,
  12790,
  'long',
  0,
  0,
  '2026. 8. 12. 10:00 ~ 2026. 8. 14. 23:59',
  now() < timestamptz '2026-08-14 23:59:00+09',
  false,
  date '2026-08-14',
  timestamptz '2026-08-14 23:59:00+09',
  false,
  true,
  'human_confirmed',
  null,
  null,
  null
from ku_2026_2_offcampus s
join public.worksites w
  on w.university_id = 1
 and w.type = 'national'
 and w.location_type = 'off_campus'
 and w.deleted_at is null
 and w.normalized_name = s.normalized_name
on conflict (source, external_id)
  where source is not null and external_id is not null
do update set
  worksite_id = excluded.worksite_id,
  title = excluded.title,
  recruit_count = excluded.recruit_count,
  job_description = excluded.job_description,
  work_time_text = excluded.work_time_text,
  min_grade = excluded.min_grade,
  hourly_wage = excluded.hourly_wage,
  work_duration_type = excluded.work_duration_type,
  eligible_degree = excluded.eligible_degree,
  eligible_status = excluded.eligible_status,
  recruitment_period_text = excluded.recruitment_period_text,
  is_active = excluded.is_active,
  is_placeholder = false,
  recruit_until = excluded.recruit_until,
  recruit_until_at = excluded.recruit_until_at,
  recruit_until_estimated = false,
  manual_override = true,
  deadline_basis = excluded.deadline_basis,
  source_closed_at = null,
  source_closed_reason = null,
  deleted_at = null,
  updated_at = now();

-- ══════════════════════════════════════════════════════════════════
-- 3. 이번 목록에 없는 교내 7행 — 모집완료로 남긴다
-- ══════════════════════════════════════════════════════════════════
-- 노동대학원행정팀 · 영재교육원 · 정경대학 평화연구소 · 정보대학행정팀 · 체육지원팀 ·
-- 학생지원팀(공통) · 학생상담센터(자연계).
-- 소프트 삭제하지 않는다 — 과거 학기 근무자가 리뷰를 쓸 수 있어야 하고,
-- 정보대학행정팀에는 이미 리뷰 1건이 붙어 있다. 껍데기 공고는 그대로 두되 모집완료임을 명시한다.
update public.postings p
   set is_active = false,
       updated_at = now()
  from public.worksites w
 where p.worksite_id = w.id
   and p.deleted_at is null
   and p.is_active
   and w.university_id = 1
   and w.type = 'national'
   and w.location_type = 'on_campus'
   and w.deleted_at is null
   and not exists (
     select 1 from ku_2026_2_oncampus s where s.final_name = w.workplace_name
   );

-- ══════════════════════════════════════════════════════════════════
-- 4. 최종 검증
-- ══════════════════════════════════════════════════════════════════
do $$
declare
  v_postings integer;
  v_oncampus integer;
  v_offcampus integer;
  v_recruit_total integer;
begin
  select count(*) into v_postings
  from public.postings
  where source = 'ku_portal' and external_id like 'ku-2026-2:%' and deleted_at is null;
  if v_postings <> 107 then
    raise exception '2026-2 고려대 공고가 107건이 아님: %', v_postings;
  end if;

  select count(*) into v_oncampus
  from public.postings p
  join public.worksites w on w.id = p.worksite_id
  where p.source = 'ku_portal' and p.external_id like 'ku-2026-2:%'
    and w.location_type = 'on_campus';
  if v_oncampus <> 50 then
    raise exception '교내 공고가 50건이 아님: %', v_oncampus;
  end if;

  select count(*) into v_offcampus
  from public.postings p
  join public.worksites w on w.id = p.worksite_id
  where p.source = 'ku_portal' and p.external_id like 'ku-2026-2:%'
    and w.location_type = 'off_campus';
  if v_offcampus <> 57 then
    raise exception '교외 공고가 57건이 아님: %', v_offcampus;
  end if;

  -- 화면 모집인원 합계와 대조(교내 141 + 교외 120 = 261).
  select sum(recruit_count::integer) into v_recruit_total
  from public.postings
  where source = 'ku_portal' and external_id like 'ku-2026-2:%' and deleted_at is null;
  if v_recruit_total <> 261 then
    raise exception '모집인원 합계가 261이 아님: %', v_recruit_total;
  end if;

  -- 교외는 지역 필터에 걸리려면 region이 반드시 있어야 한다.
  if exists (
    select 1 from public.worksites w
    join public.postings p on p.worksite_id = w.id
    where p.source = 'ku_portal' and p.external_id like 'ku-2026-2:%'
      and w.location_type = 'off_campus' and w.region is null
  ) then
    raise exception '교외 근무지에 region이 비어 있음';
  end if;
end
$$;

commit;
