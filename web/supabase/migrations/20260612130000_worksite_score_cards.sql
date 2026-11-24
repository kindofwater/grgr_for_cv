-- 목적: 근장찾기 카드용 항목별 평점·추천율 집계 RPC (get_review_stats는 Home 의존이라 미변경, 신규 함수로 분리)
-- 날짜: 2026-06-12 · 담당: 배경록
-- 비고: 신규 함수 → DROP 불필요. 개별 리뷰 본문/작성자 미반환(집계만). recommend_rate는 score_recommend>=4.0 비율(lib/scores.computeScoreSummary와 동일 규칙).

create or replace function get_worksite_score_cards(worksite_ids int[])
returns table(
  worksite_id    int,
  review_count   bigint,
  avg_recommend  numeric,
  avg_work       numeric,
  avg_growth     numeric,
  avg_vibe       numeric,
  avg_flex       numeric,
  recommend_rate int
)
language sql
security definer
as $$
  select
    worksite_id,
    count(*)                                 as review_count,
    round(avg(score_recommend)::numeric, 1)  as avg_recommend,
    round(avg(score_work)::numeric, 1)       as avg_work,
    round(avg(score_growth)::numeric, 1)     as avg_growth,
    round(avg(score_vibe)::numeric, 1)       as avg_vibe,
    round(avg(score_flex)::numeric, 1)       as avg_flex,
    round(100.0 * count(*) filter (where score_recommend >= 4.0) / count(*))::int as recommend_rate
  from reviews
  where worksite_id = any(worksite_ids)
    and deleted_at is null
  group by worksite_id;
$$;

grant execute on function get_worksite_score_cards(int[]) to anon, authenticated;
