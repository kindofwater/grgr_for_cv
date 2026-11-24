-- 경영대학 게시 부서에 잘못 묶인 실제 근무지를 원문 기준으로 재배치한다.
--
-- 6760 경영대학행정팀에 있던 4건은 원문상
--   · 경영전문대학원 3건
--   · 경영대학 홍보팀/학장실 1건
-- 이었다. 2026-07-27 수집한 학부 행정실 공고를 경영대학행정팀의 정본으로
-- 옮기고, 띄어쓰기 중복 근무지는 soft-delete한다.

begin;

insert into public.worksites (
  university_id, type, location_type, organization_name,
  workplace_name, normalized_name, region, address
)
select
  1, 'school', 'on_campus', '고려대학교(본교)',
  '경영대학 홍보팀·학장실', '경영대학 홍보팀·학장실', null, '경영본관 102호'
where not exists (
  select 1
  from public.worksites
  where university_id = 1
    and type = 'school'
    and normalized_name = '경영대학 홍보팀·학장실'
    and deleted_at is null
);

do $$
declare
  undergraduate_id integer;
  duplicate_id integer;
  graduate_id integer;
  publicity_id integer;
  unexpected_count integer;
begin
  select id into strict undergraduate_id
  from public.worksites
  where university_id = 1 and type = 'school'
    and workplace_name = '경영대학행정팀' and deleted_at is null;

  select id into strict duplicate_id
  from public.worksites
  where university_id = 1 and type = 'school'
    and workplace_name = '경영대학 행정팀' and deleted_at is null;

  select id into strict graduate_id
  from public.worksites
  where university_id = 1 and type = 'school'
    and workplace_name = '경영전문대학원행정팀' and deleted_at is null;

  select id into strict publicity_id
  from public.worksites
  where university_id = 1 and type = 'school'
    and normalized_name = '경영대학 홍보팀·학장실' and deleted_at is null;

  select count(*) into unexpected_count
  from public.postings
  where worksite_id = duplicate_id
    and deleted_at is null
    and not (
      source = 'everytime_manual'
      and external_id = 'c7789cbd3cf175b481a05b4662c288da'
    );
  if unexpected_count <> 0 then
    raise exception '경영대학 행정팀 중복 행에 예상하지 못한 공고 %건', unexpected_count;
  end if;

  update public.postings
  set worksite_id = graduate_id, updated_at = now()
  where source = 'kupid'
    and external_id in (
      '68bb06e35ca9002d',
      'b60799d968bed92b',
      '073b7b719ee4efa1'
    )
    and worksite_id in (undergraduate_id, graduate_id);

  update public.postings
  set worksite_id = publicity_id, updated_at = now()
  where source = 'kupid'
    and external_id = '53911b0b95a3df81'
    and worksite_id in (undergraduate_id, publicity_id);

  update public.postings
  set worksite_id = undergraduate_id, updated_at = now()
  where source = 'everytime_manual'
    and external_id = 'c7789cbd3cf175b481a05b4662c288da'
    and worksite_id in (duplicate_id, undergraduate_id);

  update public.reviews
  set worksite_id = undergraduate_id, updated_at = now()
  where worksite_id = duplicate_id;

  if exists (
    select 1 from public.postings where worksite_id = duplicate_id
  ) or exists (
    select 1 from public.reviews where worksite_id = duplicate_id
  ) then
    raise exception '경영대학 행정팀 중복 행 병합 후 참조가 남아 있음';
  end if;

  update public.worksites
  set workplace_name = '경영대학행정팀',
      normalized_name = '경영대학행정팀',
      address = '경영본관 103호',
      updated_at = now()
  where id = undergraduate_id;

  update public.worksites
  set workplace_name = '경영전문대학원행정팀',
      normalized_name = '경영전문대학원행정팀',
      address = '경영본관 3층 307호 (경영전문대학원 사무실)',
      updated_at = now()
  where id = graduate_id;

  update public.worksites
  set deleted_at = now(), updated_at = now()
  where id = duplicate_id and deleted_at is null;

  if (select count(*) from public.postings
      where source = 'kupid'
        and external_id in (
          '68bb06e35ca9002d',
          'b60799d968bed92b',
          '073b7b719ee4efa1'
        )
        and worksite_id = graduate_id) <> 3 then
    raise exception '경영전문대학원 공고 재배치 검증 실패';
  end if;

  if (select count(*) from public.postings
      where source = 'kupid'
        and external_id = '53911b0b95a3df81'
        and worksite_id = publicity_id) <> 1 then
    raise exception '경영대학 홍보팀·학장실 공고 재배치 검증 실패';
  end if;

  if (select count(*) from public.postings
      where source = 'everytime_manual'
        and external_id = 'c7789cbd3cf175b481a05b4662c288da'
        and worksite_id = undergraduate_id) <> 1 then
    raise exception '경영대학행정팀 수동 공고 재배치 검증 실패';
  end if;
end
$$;

commit;
