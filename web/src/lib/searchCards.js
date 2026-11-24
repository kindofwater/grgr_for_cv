// 근장찾기(서버 검색) 순수 헬퍼. data/worksiteQueries가 사용. UI/DB 의존 없음.

// LIKE 와일드카드(%, _, \) 이스케이프 — RPC ilike '%q%'에서 의도치 않은 패턴/매칭 방지.
// (Postgres ilike 기본 escape는 백슬래시. 인젝션은 파라미터 바인딩이라 별개로 안전.)
export function escapeLike(text) {
  return String(text ?? '').replace(/[\\%_]/g, (ch) => '\\' + ch)
}

// 정렬 드롭다운 라벨 → RPC p_sort 값.
export function sortKeyToParam(label) {
  return label === '리뷰 많은 순' ? 'reviews' : 'recommend'
}

// search_worksite_cards의 flat 행 → ResultCard가 쓰는 {worksite, posting, stats, is_active} 모양.
// is_active는 검색 RPC가 서버 시각으로 계산한 최종값이다. 클라이언트가 날짜만 보고
// 다시 계산하면 시각 마감(예: 18:00)을 자정까지 모집중으로 되돌리는 문제가 생긴다.
export function toCard(row) {
  const hasReview = Number(row.review_count) > 0
  return {
    is_active: Boolean(row.is_active),
    worksite: {
      id: row.worksite_id,
      organization_name: row.organization_name,
      workplace_name: row.workplace_name,
      region: row.region,
      address: row.address,
      type: row.type,
      location_type: row.location_type,
      view_count: row.view_count,
    },
    posting: {
      preferred_track: row.preferred_track,
      eligible_degree: row.eligible_degree,
      eligible_status: row.eligible_status,
      work_duration_type: row.work_duration_type,
    },
    stats: hasReview ? {
      worksite_id: row.worksite_id,
      review_count: Number(row.review_count),
      avg_recommend: row.avg_recommend,
      avg_work: row.avg_work,
      avg_growth: row.avg_growth,
      avg_vibe: row.avg_vibe,
      avg_flex: row.avg_flex,
      recommend_rate: row.recommend_rate,
    } : null,
  }
}

// 드롭다운 주소 표시: address 있으면 address, 없으면 region 폴백.
export function suggestionAddress(s) {
  return (s.address && String(s.address).trim()) ? s.address : (s.region ?? '')
}
