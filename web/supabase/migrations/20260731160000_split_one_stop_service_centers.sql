-- ONE-STOP서비스센터의 독립 근로 운영 단위를 인문·사회계, 자연계,
-- 의료공제로 분리한다. 기존 일반 근로지는 의료공제 주소를 가진 행이므로
-- 의료공제 근로지로 이름을 바로잡고, 확인된 자연계 리뷰를 이전한다.

begin;

do $$
declare
  medical_id integer;
  humanities_id integer;
  natural_id integer;
  candidate_count integer;
begin
  select count(*), min(id)
    into candidate_count, medical_id
  from public.worksites
  where university_id = 1
    and type = 'school'
    and workplace_name = 'ONE-STOP서비스센터'
    and deleted_at is null;

  if candidate_count <> 1 then
    raise exception '활성 ONE-STOP서비스센터 검증 실패: %건(기대 1건)', candidate_count;
  end if;

  -- 현재 행의 주소(B112)는 의료공제 사무실이므로 이 행을 의료공제로 보존한다.
  update public.worksites
  set workplace_name = 'ONE-STOP서비스센터(의료공제)',
      normalized_name = 'one-stop서비스센터(의료공제)',
      address = '중앙광장 지하 1층 B112호',
      updated_at = now()
  where id = medical_id;

  -- 7월 27일 분리 후 숨겼던 행을 재사용해 참조 이력을 안정적으로 유지한다.
  select count(*), min(id)
    into candidate_count, humanities_id
  from public.worksites
  where university_id = 1
    and type = 'school'
    and workplace_name = '중앙광장 지하 ONE-STOP서비스센터';

  if candidate_count > 1 then
    raise exception '기존 인문·사회계 ONE-STOP 후보가 중복입니다: %건', candidate_count;
  elsif candidate_count = 1 then
    update public.worksites
    set workplace_name = 'ONE-STOP서비스센터(인문·사회계)',
        normalized_name = 'one-stop서비스센터(인문·사회계)',
        organization_name = '고려대학교(본교)',
        location_type = 'on_campus',
        address = '중앙광장 지하 1층 B111호',
        deleted_at = null,
        updated_at = now()
    where id = humanities_id;
  else
    insert into public.worksites (
      university_id, type, location_type, organization_name,
      workplace_name, normalized_name, region, address
    ) values (
      1, 'school', 'on_campus', '고려대학교(본교)',
      'ONE-STOP서비스센터(인문·사회계)',
      'one-stop서비스센터(인문·사회계)',
      null, '중앙광장 지하 1층 B111호'
    ) returning id into humanities_id;
  end if;

  select count(*), min(id)
    into candidate_count, natural_id
  from public.worksites
  where university_id = 1
    and type = 'school'
    and workplace_name = '자연계 ONE-STOP서비스센터';

  if candidate_count > 1 then
    raise exception '기존 자연계 ONE-STOP 후보가 중복입니다: %건', candidate_count;
  elsif candidate_count = 1 then
    update public.worksites
    set workplace_name = 'ONE-STOP서비스센터(자연계)',
        normalized_name = 'one-stop서비스센터(자연계)',
        organization_name = '고려대학교(본교)',
        location_type = 'on_campus',
        address = '하나스퀘어 지하 1층 B107호',
        deleted_at = null,
        updated_at = now()
    where id = natural_id;
  else
    insert into public.worksites (
      university_id, type, location_type, organization_name,
      workplace_name, normalized_name, region, address
    ) values (
      1, 'school', 'on_campus', '고려대학교(본교)',
      'ONE-STOP서비스센터(자연계)',
      'one-stop서비스센터(자연계)',
      null, '하나스퀘어 지하 1층 B107호'
    ) returning id into natural_id;
  end if;

  -- 제목/본문에 자연계가 명시된 공고를 먼저 자연계로 옮긴다.
  update public.postings
  set worksite_id = natural_id,
      updated_at = now()
  where worksite_id = medical_id
    and deleted_at is null
    and (
      regexp_replace(lower(coalesce(title, '') || ' ' || coalesce(raw_text, '')), '\s+', '', 'g')
        like '%one-stop서비스센터(자연계)%'
      or regexp_replace(lower(coalesce(title, '') || ' ' || coalesce(raw_text, '')), '\s+', '', 'g')
        like '%자연계one-stop서비스센터%'
    );

  -- 의료공제 표기가 없는 일반 ONE-STOP 공고는 인문·사회계 창구 공고다.
  update public.postings
  set worksite_id = humanities_id,
      updated_at = now()
  where worksite_id = medical_id
    and deleted_at is null
    and regexp_replace(lower(coalesce(title, '') || ' ' || coalesce(raw_text, '')), '\s+', '', 'g')
          not like '%의료공제%';

  -- 문의로 실제 근무지가 확인된 현재 리뷰 1건만 자연계로 이전한다.
  if not exists (
    select 1
    from public.reviews
    where id = 62
      and worksite_id = medical_id
      and deleted_at is null
  ) then
    raise exception '자연계 이전 대상 리뷰(id=62) 검증 실패';
  end if;

  update public.reviews
  set worksite_id = natural_id,
      updated_at = now()
  where id = 62
    and worksite_id = medical_id
    and deleted_at is null;

  if (select count(*) from public.worksites
      where id in (medical_id, humanities_id, natural_id)
        and deleted_at is null) <> 3 then
    raise exception 'ONE-STOP서비스센터 3개 근로지 생성 검증 실패';
  end if;

  if (select count(*) from public.reviews
      where id = 62 and worksite_id = natural_id and deleted_at is null) <> 1 then
    raise exception '자연계 리뷰 이전 검증 실패';
  end if;
end
$$;

commit;
