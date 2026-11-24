-- 반자동 근무지 정규화:
--   1) 사람이 확정한 표기→정본 근무지 별칭
--   2) 처음 보는 이름·본문 충돌을 적재 전에 보류하는 검토 큐
-- 두 테이블은 service_role 배치 전용이며 프론트에 공개하지 않는다.

begin;

create table if not exists public.worksite_aliases (
  id                bigserial primary key,
  university_id     integer not null references public.universities(id) on delete cascade,
  source            varchar(30) not null default '*',
  alias_name        varchar(200) not null,
  normalized_alias  varchar(200) not null,
  worksite_id       integer not null references public.worksites(id) on delete restrict,
  resolution_method varchar(30) not null default 'human',
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint worksite_aliases_source_check check (source <> ''),
  constraint worksite_aliases_norm_check check (normalized_alias <> ''),
  constraint worksite_aliases_uq unique (university_id, source, normalized_alias)
);

create index if not exists worksite_aliases_worksite_idx
  on public.worksite_aliases(worksite_id);

create table if not exists public.worksite_resolution_queue (
  id                     bigserial primary key,
  university_id          integer not null references public.universities(id) on delete cascade,
  source                 varchar(30) not null,
  external_id            varchar(100) not null,
  raw_worksite_name      varchar(200) not null,
  normalized_worksite    varchar(200) not null,
  title                  varchar(500),
  evidence_text          varchar(1500),
  resolution_reason      varchar(30) not null default 'new_name',
  explicit_worksite_names text[] not null default '{}',
  candidate_worksite_ids integer[] not null default '{}',
  candidate_scores       jsonb not null default '[]'::jsonb,
  status                 varchar(20) not null default 'pending',
  resolved_worksite_id   integer references public.worksites(id) on delete restrict,
  resolution_method      varchar(30),
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  resolved_at            timestamptz,
  constraint worksite_resolution_queue_status_check
    check (status in ('pending', 'resolved', 'skipped')),
  constraint worksite_resolution_queue_source_ext_uq unique (source, external_id)
);

create index if not exists worksite_resolution_queue_pending_idx
  on public.worksite_resolution_queue(status, created_at)
  where status = 'pending';

alter table public.worksite_aliases enable row level security;
alter table public.worksite_resolution_queue enable row level security;

revoke all on table public.worksite_aliases from anon, authenticated;
revoke all on table public.worksite_resolution_queue from anon, authenticated;
revoke all on sequence public.worksite_aliases_id_seq from anon, authenticated;
revoke all on sequence public.worksite_resolution_queue_id_seq from anon, authenticated;

grant all on table public.worksite_aliases to service_role;
grant all on table public.worksite_resolution_queue to service_role;
grant usage, select on sequence public.worksite_aliases_id_seq to service_role;
grant usage, select on sequence public.worksite_resolution_queue_id_seq to service_role;

commit;
