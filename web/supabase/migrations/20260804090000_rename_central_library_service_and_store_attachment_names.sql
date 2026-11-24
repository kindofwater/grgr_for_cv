-- 목적: 중앙도서관 근무지를 실제 팀명(학술정보서비스팀)으로 정정하고, 학술정보개발팀 공고 1건을
--       제 근무지로 옮긴다. 함께 postings.attachment_names(첨부 표시명만) 컬럼을 신설한다.
-- 날짜: 2026-08-04 · 담당: 배경록
--
-- (원문 영문 주석) Keep the broad Central Library worksite labeled with its actual team,
-- correct the one academic-information-development posting, and retain only
-- attachment display names from future source crawls.
--
-- ⚠️ 첨부는 **표시명만** 저장한다 — 파일 실물과 다운로드 URL은 저장하지 않는다(컬럼 comment 참조).
-- 방어 조건: `into strict`로 대상 근무지가 정확히 1건이 아니면 실패하고, 이미 '중앙도서관
--   학술정보서비스팀'이 있으면 이름 변경을 중단한다. 공고 7207도 검증된 후보가 1건일 때만 옮긴다.
--   → 맨바닥 재구축(db reset)에서 해당 행이 없으면 이 마이그레이션은 실패한다(멱등하지 않음).

begin;

alter table public.postings
  add column if not exists attachment_names jsonb not null default '[]'::jsonb;

alter table public.postings
  drop constraint if exists postings_attachment_names_is_array;

alter table public.postings
  add constraint postings_attachment_names_is_array
  check (jsonb_typeof(attachment_names) = 'array');

do $$
declare
  central_library_id integer;
  academic_information_development_id integer;
  candidate_count integer;
begin
  select id
    into strict central_library_id
  from public.worksites
  where university_id = 1
    and type = 'school'
    and workplace_name = '중앙도서관'
    and deleted_at is null;

  if exists (
    select 1
    from public.worksites
    where university_id = 1
      and type = 'school'
      and workplace_name = '중앙도서관 학술정보서비스팀'
      and deleted_at is null
  ) then
    raise exception '중앙도서관 학술정보서비스팀 근무지가 이미 있어 이름 변경을 중단합니다';
  end if;

  select id
    into strict academic_information_development_id
  from public.worksites
  where university_id = 1
    and type = 'school'
    and workplace_name = '학술정보개발팀'
    and deleted_at is null;

  select count(*)
    into candidate_count
  from public.postings
  where id = 7207
    and source = 'ssc'
    and deleted_at is null
    and worksite_id in (central_library_id, academic_information_development_id);

  if candidate_count <> 1 then
    raise exception '공고 7207 이동을 중단합니다: 검증된 후보가 %건입니다', candidate_count;
  end if;

  update public.postings
  set worksite_id = academic_information_development_id,
      updated_at = now()
  where id = 7207
    and worksite_id = central_library_id;

  update public.worksites
  set workplace_name = '중앙도서관 학술정보서비스팀',
      normalized_name = '중앙도서관 학술정보서비스팀',
      updated_at = now()
  where id = central_library_id;
end
$$;

comment on column public.postings.attachment_names is
  '첨부파일 표시명 배열. 파일 자체와 다운로드 URL은 저장하지 않는다.';

commit;
