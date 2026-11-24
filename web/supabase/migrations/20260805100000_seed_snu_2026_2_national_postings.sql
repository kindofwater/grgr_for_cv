-- 서울대학교 포털의 2026학년도 2학기 국가근로 모집 현황을 근로지별 공고 1건으로 적재한다.
-- 원본 열 중 모집인원만 유형별로 보존하며 신청인원·전화번호·선택 버튼은 저장하지 않는다.
-- 기존 근로지/리뷰/주소는 재사용하고, 신규 근로지만 서울대 공식 기관 주소로 추가한다.

begin;

create temporary table snu_2026_2_national_seed (
  workplace_name text primary key,
  type1_count integer,
  type2_count integer,
  type3_count integer,
  address text not null,
  constraint snu_2026_2_positive_counts check (
    coalesce(type1_count, 1) > 0
    and coalesce(type2_count, 1) > 0
    and coalesce(type3_count, 1) > 0
  )
) on commit drop;

insert into snu_2026_2_national_seed
  (workplace_name, type1_count, type2_count, type3_count, address)
values
  ('학부대학', 11, 12, 10, '서울 관악구 관악로 1 학부대학 (신림동, 서울대학교)'),
  ('인문대학', 39, 16, 6, '서울 관악구 관악로 1, 서울대학교 인문대학'),
  ('사회과학대학', 55, 15, 3, '서울 관악구 관악로 1, 서울대학교 사회과학대학'),
  ('자연과학대학', 42, 7, 6, '서울 관악구 관악로 1, 서울대학교 자연과학대학'),
  ('간호대학', 7, 3, 1, '서울 종로구 대학로 103 간호대학 (연건동, 서울대학교)'),
  ('경영대학', 13, 18, 2, '서울 관악구 관악로 1, 서울대학교 경영대학'),
  ('공과대학', 88, 49, 7, '서울 관악구 관악로 1, 서울대학교 공과대학'),
  ('농업생명과학대학', 36, 18, 2, '서울 관악구 관악로 1, 서울대학교 농업생명과학대학'),
  ('미술대학', 15, 5, 1, '서울 관악구 관악로 1, 서울대학교 미술대학'),
  ('사범대학', 48, 8, 1, '서울 관악구 관악로 1, 서울대학교 사범대학'),
  ('생활과학대학', 20, null, 1, '서울 관악구 관악로 1, 서울대학교 생활과학대학'),
  ('수의과대학', 11, 1, 1, '서울 관악구 관악로 1, 서울대학교 85동 수의과대학'),
  ('약학대학', 12, 2, 2, '서울 관악구 관악로 1, 서울대학교 약학대학'),
  ('음악대학', 25, null, 1, '서울 관악구 관악로 1, 서울대학교 종합교육연구동 220동 411호 음악대학 교학행정실'),
  ('의과대학', 12, 12, 4, '서울 종로구 대학로 103, 서울대학교 의과대학'),
  ('첨단융합학부', 16, 6, null, '서울 관악구 관악로 1 첨단융합학부'),
  ('보건대학원', 3, 3, 1, '서울 관악구 관악로 1, 서울대학교 221동 보건대학원'),
  ('행정대학원', 6, 3, 2, '서울 관악구 관악로 1, 서울대학교 57-1동 행정대학원'),
  ('환경대학원', 9, 2, 1, '서울 관악구 관악로 1, 서울대학교 82동 환경대학원'),
  ('국제대학원', 6, null, 3, '서울 관악구 관악로 1, 서울대학교 140-1동 국제대학원'),
  ('치의학대학원', 5, null, null, '서울 종로구 대학로 101, 서울대학교 치의학대학원'),
  ('법학전문대학원', null, null, 3, '서울 관악구 관악로 1, 서울대학교 17동 법학전문대학원'),
  ('융합과학기술대학원', 3, null, null, '경기 수원시 영통구 광교로 145, 서울대학교 융합과학기술대학원 D동 128호'),
  ('국제농업기술대학원', 2, null, null, '강원특별자치도 평창군 대화면 평창대로 1447, 서울대학교 국제농업기술대학원'),
  ('공학전문대학원', 1, 1, null, '서울 관악구 관악로 1, 서울대학교 38동 415호 공학전문대학원'),
  ('데이터사이언스대학원', 3, null, null, '서울 관악구 관악로 1, 서울대학교 43동 데이터사이언스대학원'),
  ('대학원', null, null, 3, '서울 관악구 관악로 1, 서울대학교 행정관(60동) 3층 교무과'),
  ('총장선출행정지원단', null, 2, null, '서울 관악구 관악로 1, 서울대학교 153동 506호 총장선출행정지원단'),
  ('교무과', null, 1, null, '서울 관악구 관악로 1, 서울대학교 행정관(60동) 3층'),
  ('학사과', null, 3, null, '서울 관악구 관악로 1, 서울대학교 NH농협두레문예관(67동) 2층'),
  ('학생지원과', 44, 33, 1, '서울 관악구 관악로 1, 서울대학교 NH농협두레문예관(67동) 2층'),
  ('연구정책과', null, null, 1, '서울 관악구 관악로 1, 서울대학교 행정관(60동) 5층'),
  ('장애학생지원센터', null, 3, null, '서울 관악구 관악로 1, 서울대학교 정보화본부(102동) 1층'),
  ('기획과', null, null, 1, '서울 관악구 관악로 1, 서울대학교 행정관(60동) 3층'),
  ('국제처', 2, 18, 2, '서울 관악구 관악로 1, 서울대학교 CJ인터내셔널센터(152동)'),
  ('홍보팀', null, 1, null, '서울 관악구 관악로 1 60동 행정관 (신림동, 서울대학교)'),
  ('소통팀', 3, null, null, '서울 관악구 관악로 1, 서울대학교 행정관(60동) 3층'),
  ('총무과', null, 1, null, '서울 관악구 관악로 1, 서울대학교 행정관(60동) 3층'),
  ('입학본부', null, 6, 1, '서울 관악구 관악로 1, 서울대학교 150동 401호 입학본부'),
  ('창업지원단', 2, null, null, '서울 관악구 관악로 1, 서울대학교 해동학술문화관(32-1동) 201호'),
  ('글로벌사회공헌단', 3, 7, 1, '서울 관악구 관악로 1, 서울대학교 글로벌사회공헌단'),
  ('통일·평화연구원', 1, null, null, '경기 시흥시 서울대학로 173, 서울대학교 교육협력동 9층 통일평화연구원'),
  ('AI연구원', null, 2, null, '서울 관악구 관악로 1, 서울대학교 942동 2층 AI연구원'),
  ('국가미래전략원', null, 2, null, '서울 관악구 관악로 1, 서울대학교 우석경제관(223동) 4층'),
  ('인문학연구원', 2, 2, 1, '서울 관악구 관악로 1, 서울대학교 대림국제관(137-2동) 5층'),
  ('미국학연구소', null, null, 1, '서울 관악구 관악로 1, 서울대학교 인문대학 5동 431-2호'),
  ('사회과학연구원', 2, 3, 1, '서울 관악구 관악로 1, 서울대학교 사회과학대학 16-1동 404호'),
  ('경제연구소', 1, 2, null, '서울 관악구 관악로 1, 서울대학교 우석경제관(223동) 114호'),
  ('언론정보연구소', null, 2, null, '서울 관악구 관악로 1, 서울대학교 64동 103-1호'),
  ('여성연구소', null, 1, 1, '서울 관악구 관악로 1, 서울대학교 16-1동 402호'),
  ('아시아연구소', null, 2, null, '서울 관악구 관악로 1, 서울대학교 101동 아시아연구소'),
  ('기초과학연구원', 2, null, 1, '서울 관악구 관악로 1, 서울대학교 28동 409호'),
  ('이론물리학연구소', 1, 1, null, '서울 관악구 관악로 1, 서울대학교 56동 513호'),
  ('농업생명과학연구원', 1, null, null, '서울 관악구 관악로 1, 서울대학교 농업생명과학대학 200동 2004호'),
  ('법학연구소', 2, 1, 1, '서울 관악구 관악로 1, 서울대학교 17동 208호'),
  ('교육종합연구원', null, null, 1, '서울 관악구 관악로 1, 서울대학교 사범대학 10-1동 410-1호'),
  ('생활과학연구소', null, 2, null, '서울 관악구 관악로 1, 서울대학교 222동 B117호'),
  ('의학연구원', null, null, 1, '서울 종로구 대학로 103, 서울대학교 의과대학 행정관 1층 101호'),
  ('식품바이오융합연구소', null, 2, null, '서울 관악구 관악로 1, 서울대학교 203동 408호'),
  ('중앙도서관', null, 12, null, '서울 관악구 관악로 1, 서울대학교 중앙도서관'),
  ('박물관', 8, 3, 3, '서울 관악구 관악로 1, 서울대학교 70동 박물관'),
  ('보건진료소', 1, 5, null, '서울 관악구 관악로 1, 서울대학교 학생회관(63동) 3층'),
  ('관악사', null, 36, 4, '서울 관악구 관악로 1, 서울대학교 관악학생생활관 900동 313호'),
  ('실험동물자원관리원', 2, 2, null, '서울 관악구 관악로 1, 서울대학교 69동 실험동물자원관리원'),
  ('대학생활문화원', 7, 12, null, '서울 관악구 관악로 1, 서울대학교 학생회관(63동) 5층'),
  ('역사기록관', null, 2, null, '서울 관악구 관악로 1, 서울대학교 융합관(75동) 1층'),
  ('환경안전원', 2, null, null, '서울 관악구 관악로 1, 서울대학교 환경안전원'),
  ('미술관', 3, 2, null, '서울 관악구 관악로 1, 서울대학교 151동 미술관'),
  ('경력개발센터', 7, 2, null, '서울 관악구 관악로 1, 서울대학교 롯데국제교육관(152-1동) 205호'),
  ('평생교육원', null, 2, null, '서울 관악구 관악로 1, 54동 107호 서울대학교 (신림동)'),
  ('대학행정교육원', null, 1, null, '서울 관악구 관악로 1, 서울대학교 57동 106호'),
  ('인권센터', null, 4, 3, '서울 관악구 관악로 1, 서울대학교 우정원(153동) 3층'),
  ('스포츠진흥원', 3, null, null, '서울 관악구 관악로 1, 서울대학교 체육관(71동) 202호'),
  ('문화예술원', 3, null, null, '서울 관악구 관악로 1, 서울대학교 롯데국제교육관 411호'),
  ('학군단', 6, 2, null, '서울 관악구 관악로 1, 서울대학교 66동 2층 학군단'),
  ('대학신문사', 4, 6, null, '서울 관악구 관악로 1, 서울대학교 융합관(75동) 3층 대학신문 편집국');

do $$
declare
  v_seed_count integer;
  v_recruit_total integer;
begin
  select count(*), sum(
    coalesce(type1_count, 0) + coalesce(type2_count, 0) + coalesce(type3_count, 0)
  ) into v_seed_count, v_recruit_total
  from snu_2026_2_national_seed;

  if v_seed_count <> 76 or v_recruit_total <> 1055 then
    raise exception 'SNU seed integrity failure: institutions=%, recruit_total=%',
      v_seed_count, v_recruit_total;
  end if;
end
$$;

-- 이름이 정확히 같은 기존 근로지는 주소와 리뷰를 그대로 쓰고 정규화 키만 보완한다.
update public.worksites w
set normalized_name = coalesce(w.normalized_name, s.workplace_name),
    national_work_term = 'semester',
    updated_at = now()
from snu_2026_2_national_seed s
join public.universities u on u.name = '서울대학교'
where w.university_id = u.id
  and w.type = 'national'
  and w.location_type = 'on_campus'
  and w.deleted_at is null
  and w.workplace_name = s.workplace_name;

-- 없는 기관만 신규 생성한다. 학생지원과/장학복지과, 기획과/시설기획과는 이름이 달라 별도 행이다.
insert into public.worksites (
  university_id, type, location_type, organization_name, workplace_name,
  region, address, normalized_name, national_work_term
)
select u.id, 'national', 'on_campus', '서울대학교(본교) 학부',
       s.workplace_name, null, s.address, s.workplace_name, 'semester'
from snu_2026_2_national_seed s
cross join public.universities u
where u.name = '서울대학교'
  and not exists (
    select 1
    from public.worksites w
    where w.university_id = u.id
      and w.type = 'national'
      and w.location_type = 'on_campus'
      and w.deleted_at is null
      and w.workplace_name = s.workplace_name
  )
on conflict (university_id, type, normalized_name)
  where normalized_name is not null and deleted_at is null
do nothing;

do $$
declare
  v_resolved_count integer;
begin
  select count(*) into v_resolved_count
  from snu_2026_2_national_seed s
  where exists (
    select 1
    from public.worksites w
    join public.universities u on u.id = w.university_id
    where u.name = '서울대학교'
      and w.type = 'national'
      and w.location_type = 'on_campus'
      and w.deleted_at is null
      and w.workplace_name = s.workplace_name
  );

  if v_resolved_count <> 76 then
    raise exception 'Expected 76 resolved SNU worksites, got %', v_resolved_count;
  end if;
end
$$;

-- 서울대 국가근로의 이전 공고는 기록으로 남기되 모집완료로 전환한다.
update public.postings p
set is_active = false,
    updated_at = now()
from public.worksites w
join public.universities u on u.id = w.university_id
where p.worksite_id = w.id
  and u.name = '서울대학교'
  and w.type = 'national'
  and w.location_type = 'on_campus'
  and p.deleted_at is null;

-- 기관별 공고는 하나이며 유형별 모집인원만 한 문자열 안에 나눠 표시한다.
insert into public.postings (
  worksite_id, source, external_id, source_url, title,
  recruit_count, job_description, hourly_wage,
  work_duration_type, recruitment_period_text,
  is_active, is_placeholder, recruit_until, recruit_until_at,
  recruit_until_estimated, manual_override, deadline_basis,
  source_closed_at, source_closed_reason, deleted_at
)
select
  w.id,
  'snu_portal',
  'snu-2026-2:' || s.workplace_name,
  'https://my.snu.ac.kr/p/ST/',
  '2026학년도 2학기 국가근로장학생 모집',
  concat_ws(' · ',
    case when s.type1_count is not null then '유형1 ' || s.type1_count || '명' end,
    case when s.type2_count is not null then '유형2 ' || s.type2_count || '명' end,
    case when s.type3_count is not null then '유형3 ' || s.type3_count || '명' end
  ),
  '-',
  10320,
  'long',
  '2026. 8. 4. ~ 2026. 8. 12. 18:00',
  now() < timestamptz '2026-08-12 18:00:00+09',
  false,
  date '2026-08-12',
  timestamptz '2026-08-12 18:00:00+09',
  false,
  true,
  'human_confirmed',
  null,
  null,
  null
from snu_2026_2_national_seed s
join public.universities u on u.name = '서울대학교'
join public.worksites w
  on w.university_id = u.id
 and w.type = 'national'
 and w.location_type = 'on_campus'
 and w.deleted_at is null
 and w.workplace_name = s.workplace_name
on conflict (source, external_id)
  where source is not null and external_id is not null
do update set
  worksite_id = excluded.worksite_id,
  source_url = excluded.source_url,
  title = excluded.title,
  recruit_count = excluded.recruit_count,
  job_description = excluded.job_description,
  hourly_wage = excluded.hourly_wage,
  work_period_text = null,
  work_time_text = null,
  preference_notes = null,
  extra_notes = null,
  preferred_track = null,
  preferred_college = null,
  preferred_dept = null,
  min_grade = null,
  eligible_degree = null,
  eligible_status = null,
  work_duration_type = excluded.work_duration_type,
  recruitment_period_text = excluded.recruitment_period_text,
  is_active = excluded.is_active,
  is_placeholder = excluded.is_placeholder,
  recruit_until = excluded.recruit_until,
  recruit_until_at = excluded.recruit_until_at,
  recruit_until_estimated = excluded.recruit_until_estimated,
  manual_override = excluded.manual_override,
  deadline_basis = excluded.deadline_basis,
  source_closed_at = null,
  source_closed_reason = null,
  deleted_at = null,
  updated_at = now();

do $$
declare
  v_posting_count integer;
begin
  select count(*) into v_posting_count
  from public.postings p
  where p.source = 'snu_portal'
    and p.external_id like 'snu-2026-2:%'
    and p.deleted_at is null;

  if v_posting_count <> 76 then
    raise exception 'Expected 76 SNU 2026-2 postings, got %', v_posting_count;
  end if;
end
$$;

commit;
