-- 공고별 근무장소는 공개 상세 RPC뿐 아니라 로그인 사용자의 직접 공고 조회에도 필요하다.
-- 공고별 장소가 있으면 근로지 대표 주소보다 우선 표시한다.

begin;

grant select (work_location)
  on table public.postings to anon, authenticated;

commit;
