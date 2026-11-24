// 리뷰 적립 포인트 (2026-08-08 정책 v2). 서버 RPC write_review_with_points·
// update_review_with_points의 상수와 동일해야 한다 — 바꿀 땐 마이그레이션과 함께.
export const PUBLIC_REVIEW_POINTS = 30
export const ANONYMOUS_REVIEW_POINTS = 20

export function reviewPoints(isAnonymous) {
  return isAnonymous ? ANONYMOUS_REVIEW_POINTS : PUBLIC_REVIEW_POINTS
}

// 포인트 내역 누적 잔액 계산 (순수 함수).
// 입력: 오래된 순 정렬된 [{ amount, ... }]. 출력: 각 항목에 balance(그 시점 누적 잔액) 추가한 새 배열.
export function computeRunningBalance(rowsAsc) {
  let running = 0
  return rowsAsc.map((row) => {
    running += row.amount
    return { ...row, balance: running }
  })
}
