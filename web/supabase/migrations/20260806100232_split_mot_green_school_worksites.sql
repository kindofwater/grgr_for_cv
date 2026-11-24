-- 목적: 공동 포털 게시부서로 합쳐진 기술경영전문대학원·그린스쿨 근무지를 실제 행정실 기준으로 분리한다.
-- 날짜: 2026-08-06 · 담당: Codex

begin;

do $$
declare
  mot_id integer;
  green_id integer;
  verified_count integer;
begin
  select id into strict mot_id
  from public.worksites
  where id = 6767
    and university_id = 1
    and type = 'school'
    and workplace_name = '공학대학원·에너지환경대학원(그린스쿨)·기술경영전문대학원행정팀'
    and address = '창의관 201호'
    and deleted_at is null;

  select id into strict green_id
  from public.worksites
  where id = 6813
    and university_id = 1
    and type = 'school'
    and workplace_name = '에너지환경대학원(그린스쿨)행정팀'
    and address like '%KU R&D센터 520호%'
    and deleted_at is null;

  if exists (
    select 1
    from public.worksites
    where university_id = 1
      and type = 'school'
      and id not in (mot_id, green_id)
      and deleted_at is null
      and normalized_name in (
        '기술경영전문대학원 행정실',
        '에너지환경대학원(그린스쿨) 행정실'
      )
  ) then
    raise exception '분리 대상의 공식 행정실명이 이미 다른 활성 근무지에 존재합니다';
  end if;

  if exists (
    select 1
    from public.reviews
    where worksite_id = mot_id
      and deleted_at is null
  ) then
    raise exception '공동 근무지에 리뷰가 생겨 자동 분리할 수 없습니다';
  end if;

  select count(*) into verified_count
  from public.postings
  where worksite_id = mot_id
    and deleted_at is null
    and (
      (
        id in (7467, 7528, 7651)
        and source = 'kupid'
        and raw_text like '%기술경영전문대학원%'
      )
      or (
        id = 7640
        and source = 'kupid'
        and external_id = '466de834f2762b74'
        and raw_text like '%에너지환경대학원(그린스쿨)행정실%'
        and raw_text like '%KU R&D센터 520호%'
      )
    );

  if verified_count <> 4 then
    raise exception '대학원별 과거 공고 근거 검증 실패: %건(기대 4건)', verified_count;
  end if;

  if exists (
    select 1
    from public.postings
    where worksite_id = mot_id
      and deleted_at is null
      and id not in (7467, 7528, 7640, 7651)
      and not (
        source = 'everytime_manual'
        and external_id = 'everytime:2026-08-05-1452:mot-work-study'
        and title like '%기술경영전문대학원%'
      )
  ) then
    raise exception '공동 근무지에 분류하지 않은 공고가 존재합니다';
  end if;

  update public.worksites
  set workplace_name = '기술경영전문대학원 행정실',
      normalized_name = '기술경영전문대학원 행정실',
      address = '창의관 201호',
      updated_at = now()
  where id = mot_id;

  update public.worksites
  set workplace_name = '에너지환경대학원(그린스쿨) 행정실',
      normalized_name = '에너지환경대학원(그린스쿨) 행정실',
      address = 'KU R&D센터 520호',
      updated_at = now()
  where id = green_id;

  update public.postings
  set worksite_id = green_id,
      updated_at = now()
  where id = 7640
    and worksite_id = mot_id
    and source = 'kupid'
    and external_id = '466de834f2762b74'
    and deleted_at is null;

  update public.postings
  set work_department = '기술경영전문대학원 행정실',
      work_location = '창의관 201호',
      updated_at = now()
  where worksite_id = mot_id
    and source = 'everytime_manual'
    and external_id = 'everytime:2026-08-05-1452:mot-work-study'
    and deleted_at is null;

  if (
    select count(*)
    from public.postings
    where worksite_id = mot_id
      and id in (7467, 7528, 7651)
      and deleted_at is null
  ) <> 3 then
    raise exception '기술경영전문대학원 과거 공고 분리 후 검증 실패';
  end if;

  if exists (
    select 1
    from public.postings
    where source = 'everytime_manual'
      and external_id = 'everytime:2026-08-05-1452:mot-work-study'
      and deleted_at is null
      and (
        worksite_id <> mot_id
        or work_department <> '기술경영전문대학원 행정실'
        or work_location <> '창의관 201호'
      )
  ) then
    raise exception '현재 기술경영전문대학원 수동 공고 연결 검증 실패';
  end if;

  if not exists (
    select 1
    from public.postings
    where id = 7640
      and worksite_id = green_id
      and source = 'kupid'
      and external_id = '466de834f2762b74'
      and deleted_at is null
  ) then
    raise exception '그린스쿨 과거 공고 이동 검증 실패';
  end if;
end
$$;

commit;
