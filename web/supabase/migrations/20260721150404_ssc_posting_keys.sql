-- 목적: SSC/KUPID 공고 멱등 UPSERT용 외부키·정규화키·수동수정 플래그 추가
-- 날짜: 2026-07-21 · 담당: 배경록
-- 비고: spec docs/superpowers/specs/2026-07-21-ssc-job-crawler-design.md §4.5
--       additive(기존 데이터 무영향). normalized_name 백필은 로더가 수행(Python 정규화 정본).

begin;

-- postings: 공고 외부키 + 수동수정 보호 플래그
alter table postings add column if not exists source          varchar(20);
alter table postings add column if not exists external_id     varchar(100);
alter table postings add column if not exists manual_override boolean not null default false;

-- 같은 외부 공고 재적재 시 갱신(중복 방지). NULL(레거시/수동 행)은 유니크에서 제외.
create unique index if not exists postings_source_extid_uq
  on postings (source, external_id)
  where source is not null and external_id is not null;

-- worksites: 소스 간 매칭용 정규화 이름키. 소프트삭제 행은 키를 반납(deleted_at is null).
alter table worksites add column if not exists normalized_name varchar(200);

create unique index if not exists worksites_norm_uq
  on worksites (university_id, type, normalized_name)
  where normalized_name is not null and deleted_at is null;

commit;
