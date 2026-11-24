-- Move five reviewed postings from broad or incorrect assignments to their
-- explicitly named workplaces. Keep the talent-development posting assigned
-- to its team: the graduate library is only that team's physical location.

begin;

insert into public.worksites (
  university_id,
  type,
  location_type,
  organization_name,
  workplace_name,
  normalized_name,
  region,
  address
)
select
  1,
  'school',
  'on_campus',
  '고려대학교(본교)',
  '안암학사 고시동 행정실',
  '안암학사 고시동 행정실',
  null,
  '안암학사 고시동 행정실'
where not exists (
  select 1
  from public.worksites
  where university_id = 1
    and type = 'school'
    and workplace_name = '안암학사 고시동 행정실'
    and deleted_at is null
);

insert into public.worksites (
  university_id,
  type,
  location_type,
  organization_name,
  workplace_name,
  normalized_name,
  region,
  address
)
select
  1,
  'school',
  'on_campus',
  '고려대학교(본교)',
  '전공디자인센터',
  '전공디자인센터',
  null,
  'SK미래관 1층 로비 행사 부스'
where not exists (
  select 1
  from public.worksites
  where university_id = 1
    and type = 'school'
    and workplace_name = '전공디자인센터'
    and deleted_at is null
);

do $$
declare
  engineering_id integer;
  energy_id integer;
  political_id integer;
  exam_dorm_id integer;
  life_college_id integer;
  life_graduate_id integer;
  teaching_id integer;
  training_id integer;
  undergraduate_id integer;
  major_design_id integer;
  talent_id integer;
  candidate_count integer;
begin
  select id into strict engineering_id
  from public.worksites
  where university_id = 1 and type = 'school'
    and workplace_name = '공과대학행정팀' and deleted_at is null;

  select id into strict energy_id
  from public.worksites
  where university_id = 1 and type = 'school'
    and workplace_name = '융합에너지공학과' and deleted_at is null;

  select id into strict political_id
  from public.worksites
  where university_id = 1 and type = 'school'
    and workplace_name = '정경대학행정팀' and deleted_at is null;

  select id into strict exam_dorm_id
  from public.worksites
  where university_id = 1 and type = 'school'
    and workplace_name = '안암학사 고시동 행정실' and deleted_at is null;

  select id into strict life_college_id
  from public.worksites
  where university_id = 1 and type = 'school'
    and workplace_name = '생명과학대학행정팀' and deleted_at is null;

  select id into strict life_graduate_id
  from public.worksites
  where university_id = 1 and type = 'school'
    and workplace_name = '생명환경과학대학원행정실' and deleted_at is null;

  if exists (
    select 1 from public.worksites
    where university_id = 1 and type = 'school'
      and workplace_name = '생명환경과학대학원행정팀'
      and deleted_at is null
  ) then
    raise exception '생명환경과학대학원행정팀 대표명이 이미 별도 근무지로 존재합니다';
  end if;

  select id into strict teaching_id
  from public.worksites
  where university_id = 1 and type = 'school'
    and workplace_name = '교직팀' and deleted_at is null;

  select id into strict training_id
  from public.worksites
  where university_id = 1 and type = 'school'
    and workplace_name = '사범대학 부설 교육연수원' and deleted_at is null;

  select id into strict undergraduate_id
  from public.worksites
  where university_id = 1 and type = 'school'
    and workplace_name = '학부대학행정팀' and deleted_at is null;

  select id into strict major_design_id
  from public.worksites
  where university_id = 1 and type = 'school'
    and workplace_name = '전공디자인센터' and deleted_at is null;

  select id into strict talent_id
  from public.worksites
  where university_id = 1 and type = 'school'
    and workplace_name = '인재양성팀' and deleted_at is null;

  select count(*) into candidate_count
  from public.postings
  where (
    (id in (7513, 7581) and worksite_id = engineering_id
      and raw_text like '%융합에너지공학과%')
    or (id = 7261 and worksite_id = political_id
      and raw_text like '%행정고시동%')
    or (id = 7440 and worksite_id = life_college_id
      and raw_text like '%생명환경과학대학원 행정팀%')
    or (id = 7489 and worksite_id = teaching_id
      and raw_text like '%사범대학 부설 교육연수원%')
    or (id = 7398 and worksite_id = undergraduate_id
      and raw_text like '%전공디자인센터%')
  )
    and source = 'kupid'
    and deleted_at is null;

  if candidate_count <> 6 then
    raise exception '검토된 분리 공고 검증 실패: %건(기대 6건)', candidate_count;
  end if;

  if not exists (
    select 1 from public.postings
    where id = 7605
      and worksite_id = talent_id
      and raw_text like '%대학원혁신본부 인재양성팀%'
      and raw_text like '%대학원도서관 1층 124호%'
      and deleted_at is null
  ) then
    raise exception '인재양성팀 유지 대상 공고 검증 실패';
  end if;

  update public.postings set worksite_id = energy_id, updated_at = now()
  where id in (7513, 7581) and worksite_id = engineering_id
    and source = 'kupid' and deleted_at is null;

  update public.postings set worksite_id = exam_dorm_id, updated_at = now()
  where id = 7261 and worksite_id = political_id
    and source = 'kupid' and deleted_at is null;

  update public.postings set worksite_id = life_graduate_id, updated_at = now()
  where id = 7440 and worksite_id = life_college_id
    and source = 'kupid' and deleted_at is null;

  update public.postings set worksite_id = training_id, updated_at = now()
  where id = 7489 and worksite_id = teaching_id
    and source = 'kupid' and deleted_at is null;

  update public.postings set worksite_id = major_design_id, updated_at = now()
  where id = 7398 and worksite_id = undergraduate_id
    and source = 'kupid' and deleted_at is null;

  update public.worksites
  set workplace_name = '생명환경과학대학원행정팀',
      normalized_name = '생명환경과학대학원행정팀',
      address = '생명과학관 동관 219호',
      updated_at = now()
  where id = life_graduate_id;

  insert into public.worksite_aliases (
    university_id,
    source,
    alias_name,
    normalized_alias,
    worksite_id,
    resolution_method
  )
  values
    (
      1, '*',
      '융합에너지공학과 행정실',
      '융합에너지공학과',
      energy_id,
      'confirmed_rule'
    ),
    (
      1, '*',
      '행정고시동·서울캠퍼스 안암학사 고시동 행정실',
      '안암학사 고시동 행정실',
      exam_dorm_id,
      'confirmed_rule'
    ),
    (
      1, '*',
      '생명환경과학대학원행정실·생명환경과학대학원 행정실',
      '생명환경과학대학원행정팀',
      life_graduate_id,
      'confirmed_rule'
    )
  on conflict (university_id, source, normalized_alias)
  do update
  set alias_name = excluded.alias_name,
      worksite_id = excluded.worksite_id,
      resolution_method = excluded.resolution_method,
      updated_at = now();

  if (
    select count(*) from public.postings
    where id in (7513, 7581) and worksite_id = energy_id
      and deleted_at is null
  ) <> 2 then
    raise exception '융합에너지공학과 공고 분리 검증 실패';
  end if;

  if (
    select count(*) from public.postings
    where id = 7261 and worksite_id = exam_dorm_id and deleted_at is null
  ) <> 1 then
    raise exception '안암학사 고시동 공고 분리 검증 실패';
  end if;

  if (
    select count(*) from public.postings
    where id in (7440, 7632) and worksite_id = life_graduate_id
      and deleted_at is null
  ) <> 2 then
    raise exception '생명환경과학대학원 공고 분리 검증 실패';
  end if;

  if (
    select count(*) from public.postings
    where id = 7489 and worksite_id = training_id and deleted_at is null
  ) <> 1 then
    raise exception '사범대학 부설 교육연수원 공고 분리 검증 실패';
  end if;

  if (
    select count(*) from public.postings
    where id = 7398 and worksite_id = major_design_id and deleted_at is null
  ) <> 1 then
    raise exception '전공디자인센터 공고 분리 검증 실패';
  end if;

  if (
    select count(*) from public.postings
    where id = 7605 and worksite_id = talent_id and deleted_at is null
  ) <> 1 then
    raise exception '인재양성팀 공고 유지 검증 실패';
  end if;
end
$$;

commit;
