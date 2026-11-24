-- 목적: 고려대 본교 학부 교내 국가근로 근무지 57개 시드(명부) + placeholder posting — 출시 전 리뷰 선적립
-- 날짜: 2026-07-16 · 담당: 배경록
-- 비고: spec docs/superpowers/specs/2026-07-16-oncampus-national-seed-design.md
--       plan docs/superpowers/plans/2026-07-16-oncampus-national-seed.md
--       ① postings.is_placeholder 컬럼(미래 크롤 교체용 안전표식)
--       ② search_worksite_cards 지역 조건을 location_type 기준으로 수정 — 아래 근거
--       ③ id=6660 region 픽스(②의 부수 영향, 1행)
--       ④ worksites 57행 + placeholder postings 57행 (멱등: where not exists)
--       교외 national 6647개·school 25개·reviews(0건)는 건드리지 않는다. school 25개는 새 KUPID 크롤 시 교체.

-- ── 1. is_placeholder — 미래 교체용 안전표식 ──
-- 지금 쓰는 플래그가 아니다. 공고 시즌에 크롤로 진짜 공고를 넣을 때
--   delete from postings where worksite_id = X and is_placeholder = true;
-- 로 껍데기만 수술 제거하기 위한 것. 그땐 리뷰가 이미 붙어 있어 통짜 wipe가 불가능하고,
-- 플래그가 없으면 "null 패턴"으로 추측해야 해서 위험하다.
-- 리뷰는 worksite_id에 붙으므로 postings만 교체해도 리뷰는 무손상.
alter table postings add column if not exists is_placeholder boolean not null default false;

comment on column postings.is_placeholder is
  '공고 없는 근무지를 노출시키기 위한 껍데기 posting 표식. 실제 공고 크롤 시 이 행만 지우고 교체한다.';

-- ── 2. search_worksite_cards — 지역 필터를 location_type 기준으로 ──
-- 기존 조건: (p_regions is null or w.type <> 'national' or w.region = any(p_regions))
-- 20260708110000의 의도는 "교내는 지역 필터 무시"였고(그 헤더 참고), 당시엔 national+on_campus가
-- 0개라 "교내" == "school"이 우연히 참이어서 type으로 판정해도 맞았다.
-- 이 마이그레이션의 시드가 그 전제를 깬다(national이면서 on_campus). region이 NULL인 교내 57개가
-- 지역 필터를 켠 유저에게 통째로 사라지므로, 원래 의도대로 location_type 기준으로 고친다.
-- 교내에 region을 채우는 우회는 쓰지 않는다 — 학교를 추가할 때마다 지역을 채우는 부채가 된다.
--
-- ⚠️ 본문은 현행 최신(20260713172824_search_rpc_limits_and_timeout)을 그대로 재현 +
--    p_regions 한 줄만 변경. 20260708110000에서 복사하면 limit/offset 상한이 롤백된다.
--    시그니처 동일 → create or replace(DROP 불필요), 기존 grant(authenticated·anon) 유지됨.
create or replace function search_worksite_cards(
  p_query  text default null,
  p_sort   text default 'recommend',
  p_limit  int  default 20,
  p_offset int  default 0,
  p_types     text[] default null,
  p_locations text[] default null,
  p_regions   text[] default null,
  p_durations text[] default null,
  p_tracks    text[] default null,
  p_degrees   int[]  default null,
  p_statuses  int[]  default null,
  p_actives   boolean[] default null
)
returns table(
  worksite_id        int,
  organization_name  varchar,
  workplace_name     varchar,
  region             varchar,
  address            text,
  type               worksite_type_e,
  location_type      location_type_e,
  view_count         int,
  is_active          boolean,
  preferred_track    varchar,
  eligible_degree    smallint,
  eligible_status    smallint,
  work_duration_type duration_type_e,
  review_count       bigint,
  avg_recommend      numeric,
  avg_work           numeric,
  avg_growth         numeric,
  avg_vibe           numeric,
  avg_flex           numeric,
  recommend_rate     int,
  total_count        bigint
)
language sql
security definer
as $$
  with rep as (
    select distinct on (p.worksite_id)
      p.worksite_id, p.preferred_track, p.eligible_degree,
      p.eligible_status, p.work_duration_type
    from postings p
    where p.deleted_at is null
    order by p.worksite_id, p.is_active desc, p.created_at desc
  ),
  ws_active as (
    select worksite_id, bool_or(is_active) as is_active
    from postings where deleted_at is null group by worksite_id
  ),
  stats as (
    select worksite_id,
           count(*) as review_count,
           round(avg(score_recommend)::numeric,1) as avg_recommend,
           round(avg(score_work)::numeric,1)      as avg_work,
           round(avg(score_growth)::numeric,1)    as avg_growth,
           round(avg(score_vibe)::numeric,1)      as avg_vibe,
           round(avg(score_flex)::numeric,1)      as avg_flex,
           round(100.0*count(*) filter (where score_recommend>=4.0)/count(*))::int as recommend_rate
    from reviews where deleted_at is null and not is_blinded group by worksite_id
  ),
  joined as (
    select w.id as worksite_id, w.organization_name, w.workplace_name,
           w.region, w.address, w.type, w.location_type, w.view_count,
           coalesce(a.is_active,false) as is_active,
           r.preferred_track, r.eligible_degree, r.eligible_status, r.work_duration_type,
           coalesce(s.review_count,0) as review_count,
           s.avg_recommend, s.avg_work, s.avg_growth, s.avg_vibe, s.avg_flex, s.recommend_rate
    from worksites w
    join rep r           on r.worksite_id = w.id
    left join ws_active a on a.worksite_id = w.id
    left join stats s    on s.worksite_id = w.id
    where w.deleted_at is null
      and ( p_query is null or p_query = '' or
            w.organization_name ilike '%'||p_query||'%' or
            w.workplace_name    ilike '%'||p_query||'%' )
      and (p_actives   is null or coalesce(a.is_active,false) = any(p_actives))
      and (p_types     is null or w.type          = any(p_types::worksite_type_e[]))
      and (p_locations is null or w.location_type = any(p_locations::location_type_e[]))
      and (p_regions   is null or w.location_type = 'on_campus' or w.region = any(p_regions))
      and (p_durations is null or r.work_duration_type = any(p_durations::duration_type_e[]))
      and (p_tracks    is null or r.preferred_track     = any(p_tracks))
      and (p_degrees   is null or r.eligible_degree::int = any(p_degrees))
      and (p_statuses  is null or r.eligible_status::int = any(p_statuses))
  )
  select *, count(*) over() as total_count
  from joined
  order by
    case when p_sort='reviews'   then review_count end desc nulls last,
    case when p_sort='recommend' then avg_recommend end desc nulls last,
    worksite_id
  limit  least(greatest(coalesce(p_limit, 20), 0), 50)
  offset least(greatest(coalesce(p_offset, 0), 0), 10000);
$$;

-- ── 3. id=6660 region 픽스 — 2의 부수 영향 ──
-- 미래성장연구원(school/off_campus/region NULL)은 기존 조건에선 type <> 'national'이라 지역 필터를
-- 우회했지만, 수정 후엔 교외로 분류돼 필터 대상이 되고 region이 없어 지역 필터 시 사라진다.
-- 주소에 "서울 강남구"로 명시돼 있으므로 채운다. 나머지 교외 6647개는 region이 전부 있어 무영향.
-- (school 25개는 새 KUPID 크롤 시 교체되므로 이건 그때까지의 임시 정리.
--  ⚠️ 새 크롤러는 off_campus의 region을 반드시 채울 것 — 비면 지역 필터에서 조용히 사라진다.)
update worksites
   set region = '서울', updated_at = now()
 where type = 'school' and location_type = 'off_campus' and region is null;

-- ── 4. 시드 — worksites 57행 + placeholder postings 57행 ──
-- 소스: 붙임. '24~'26년 연도별 유형별 근로지 현황.xlsx (기관명='고려대학교(본교) 학부' AND 유형='일반교내')
--       160행 → 근로지명 dedup(최신 연도 우선) 57개. 우편번호 접두 [02841] 제거.
-- 2026 목록에 없는 4곳(노동대학원행정팀·정경대학 평화연구소·체육지원팀·학생지원팀(공통))도 포함 —
-- 24/25년 근무자가 리뷰를 쓸 수 있어야 하고, is_active=false("모집완료") 표시와 일관된다.
-- 주소 정리 3건(명부 원본 결함): 스마트보안학부…행정팀은 원본이 깨진 문자를 담고 있어 제거,
-- 오타 '동아시이아'→'동아시아' / '테크노콤플레스'→'테크노콤플렉스'. 근로지명은 원본 그대로.
-- region은 NULL(교내는 지역 필터 대상 아님 — 위 2 참고).
-- 멱등: worksites에 유니크 제약이 없어 on conflict 불가 → where not exists.
with seed(workplace_name, address) as (values
  ('간호대학행정팀', '서울 성북구 안암로 145 고려대학교 간호대학'),
  ('건축팀', '서울 성북구 안암로 145 고려대학교'),
  ('경영대학행정팀', '서울 성북구 안암로 145 고려대학교 경영대학'),
  ('경영지원팀(화정체육관)', '서울 성북구 안암로 145 고려대학교'),
  ('고대신문사', '서울 성북구 안암동5가 65번지 고려대학교MK청산문화관 6층'),
  ('공과대학 건축사회환경공학부', '서울 성북구 안암동5가 1-2번지 고려대학교안암캠퍼스 공과대학 건축사회환경공학과'),
  ('공과대학 건축학과', '서울 성북구 안암로 145 고려대학교 공과대학 건축학과'),
  ('공과대학 기계공학부', '서울 성북구 안암로 145 고려대학교 공과대학 기계공학과'),
  ('공과대학 반도체공학과', '서울 성북구 안암로 145 고려대학교'),
  ('공과대학 신소재공학부', '서울 성북구 안암로 145 고려대학교 공과대학 신소재공학부'),
  ('공과대학 전기전자공학부', '서울 성북구 안암로 145 고려대학교 공과대학 전기전자공학부'),
  ('공과대학 화공생명공학과', '서울 성북구 안암로 145 고려대학교 공과대학 화공생명공학과'),
  ('공학대학원행정팀', '서울 성북구 안암로 145 고려대학교 공학대학원행정실'),
  ('관리팀', '서울 성북구 안암로 145 고려대학교 관리팀(백주년기념관)'),
  ('교육대학원행정팀', '서울 성북구 안암동5가 1-2번지 고려대학교안암캠퍼스'),
  ('국제교육팀', '서울 성북구 안암로 145 국제교육팀 (안암동5가, 고려대학교안암캠퍼스)'),
  ('국제대학원행정팀', '서울 성북구 안암로 145 고려대학교 국제대학원'),
  ('국제대학행정팀', '서울 성북구 안암로 145 국제관 국제학부행정실 (안암동5가, 고려대학교안암캠퍼스)'),
  ('노동대학원행정팀', '서울 성북구 안암로 145 고려대학교 노동대학원'),
  ('도서관 학술정보서비스팀', '서울 성북구 안암로 145 고려대학교 학술정보서비스부'),
  ('도서관 학술정보큐레이션팀', '서울 성북구 안암로 145 고려대학교 과학도서관'),
  ('문과대학행정팀', '서울 성북구 안암로 145 고려대학교 문과대학'),
  ('박물관 학예기록팀(기록파트)', '서울 성북구 안암로 145 고려대학교 박물관 학예기록팀'),
  ('박물관 학예기록팀(학예파트)', '서울 성북구 안암로 145 고려대학교 박물관 학예기록팀'),
  ('법무대학원행정팀', '서울 성북구 안암로 145 고려대학교 법무대학원'),
  ('법학전문대학원행정팀', '서울 성북구 안암동5가 1-2번지 고려대학교안암캠퍼스 법학전문대학원'),
  ('보건과학대학행정팀', '서울 성북구 안암동5가 고려대학교 보건과학대학'),
  ('사범대학 고등교육정책연구소', '서울 성북구 안암로 145 고려대학교 고등교육정책연구소'),
  ('사범대학 교육문제연구소', '서울 성북구 안암로 145 고려대학교 교육문제연구소'),
  ('사범대학 동아시아문화교류연구소', '서울 성북구 안암로 145 고려대학교 동아시아문화교류연구소'),
  ('사범대학 수학교육과 실험실습실', '서울 성북구 안암로 145 고려대학교 사범대학 수학교육과'),
  ('사범대학 지리교육과 실습분석실', '서울 성북구 안암로 145 고려대학교 사범대학 지리교육과'),
  ('사범대학 한국어문교육연구소', '서울 성북구 안암로 145 고려대학교 사범대학 한국어문교육연구소'),
  ('사범대학행정팀(겸:교직팀)', '서울 성북구 안암로 145 고려대학교 사범대학'),
  ('생명과학대학 기기센터', '서울 성북구 안암동5가 고려대학교 생명과학대학'),
  ('생명과학대학 식품과학종합실험실(고대빵)', '서울 성북구 안암로 145 고려대학교 식품사업팀'),
  ('스마트보안학부·정보보호대학원·개인정보보호대학원행정팀', '서울 성북구 안암로 145 ·정보보호대학원·개인정보보호대학원행정팀'),
  ('심리학부행정팀', '서울 성북구 안암로 145 심리학부행정실 (안암동5가, 고려대학교안암캠퍼스)'),
  ('영재교육원', '서울 성북구 안암로 145 고려대학교 영재교육원'),
  ('이과대학행정팀', '서울 성북구 안암로 145 고려대학교 이과대학'),
  ('장애학생지원센터(일반)', '서울 성북구 안암로 145 고려대학교 장애지원센터'),
  ('정경대학 경제연구소', '서울 성북구 안암로 145 고려대학교 경제연구소'),
  ('정경대학 평화연구소', '서울 성북구 안암로 145 고려대학교 평화연구소'),
  ('정경대학행정팀', '서울 성북구 안암로 145 고려대학교 정경대학'),
  ('정보대학행정팀', '서울 성북구 안암로 145 고려대학교 정보대학'),
  ('정책대학원행정팀', '서울 성북구 안암로 145 고려대학교 정책대학원행정팀'),
  ('지속가능경영팀', '서울 성북구 안암로 145 고려대학교 지속가능경영팀'),
  ('체육지원팀', '서울 성북구 안암동5가 1-2번지 고려대학교안암캠퍼스 체육위원회 체육지원팀'),
  ('출판문화원', '서울 성북구 안암로 145 출판문화원 (안암동5가, 고려대학교안암캠퍼스)'),
  ('커뮤니케이션팀(장비대여)', '서울 성북구 안암로 145 미디어관 지하1층 장비대여실'),
  ('테크노콤플렉스기획관리부', '서울 성북구 안암로 145 고려대학교 테크노콤플렉스기획관리부'),
  ('학부대학행정팀', '서울 성북구 안암로 145 고려대학교 학부대학행정팀'),
  ('학사팀', '서울 성북구 안암동5가 고려대학교 학사팀'),
  ('학생상담센터(인문계)', '서울 성북구 안암로 145 고려대학교 학생상담센터'),
  ('학생상담센터(자연계)', '서울 성북구 안암로 145 고려대학교 학생상담센터'),
  ('학생지원팀', '서울 성북구 안암로 145 고려대학교 학생지원팀'),
  ('학생지원팀(공통)', '서울 성북구 안암동5가 1-2번지 고려대학교안암캠퍼스 중앙광장')
)
insert into worksites (university_id, type, location_type, organization_name, workplace_name, region, address)
select 1, 'national', 'on_campus', '고려대학교(본교) 학부', s.workplace_name, null, s.address
  from seed s
 where not exists (
   select 1 from worksites w
    where w.university_id = 1
      and w.type = 'national'
      and w.location_type = 'on_campus'
      and w.workplace_name = s.workplace_name
 );

-- placeholder posting 1개/근무지.
-- 공고 없는 worksite는 앱에 안 뜬다 — 게이트 3중(①검색 RPC의 join rep INNER ②자동완성의 exists postings
-- ③상세의 infoReady = worksite && posting)이 공고 ≥1을 요구한다. 게이트를 푸는 건 검색 본류라
-- blast radius가 커서 껍데기 posting으로 통과시킨다.
-- 자격은 국가근로 규칙값(long/학부만/재학만) — 기본값(3=미정/unknown)으로 두면 유저가 "학부생만"·"장기"
-- 필터를 켜는 순간 57개가 전부 사라진다. 20260708100000_national_backfill의 선례와 같은 값.
insert into postings (worksite_id, is_active, is_placeholder, work_duration_type, eligible_degree, eligible_status)
select w.id, false, true, 'long', 0, 0
  from worksites w
 where w.university_id = 1
   and w.type = 'national'
   and w.location_type = 'on_campus'
   and not exists (
     select 1 from postings p
      where p.worksite_id = w.id and p.is_placeholder = true
   );
