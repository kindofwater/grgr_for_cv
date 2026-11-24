// web/src/lib/semesters.js
export const SEMESTER_ORDER = ['1학기', '여름방학', '2학기', '겨울방학']
// 올해부터 5년 전까지, 총 6개 연도를 리뷰 작성에 허용한다.
export const REVIEW_YEAR_SPAN = 6

// 리뷰 폼 근무 연도(최신순). 오래된 기존 리뷰의 원래 연도만 include로 보존한다.
// lib 계약: 의존성 0 · DOM 금지 · 현재 시간은 now로 주입.
export function reviewFormYearOptions({ now, include = null }) {
  const currentYear = now.getFullYear()
  const options = Array.from(
    { length: REVIEW_YEAR_SPAN },
    (_, index) => currentYear - index,
  )
  const oldestDefaultYear = options[options.length - 1]

  if (
    Number.isInteger(include) &&
    include >= 1 &&
    include < oldestDefaultYear
  ) {
    options.push(include)
  }

  return options
}

export function reviewFormSemesterOptions({ year, now, nationalWorkTerm = null }) {
  const selectedYear = Number(year)
  const currentYear = now.getFullYear()
  const month = now.getMonth() + 1

  let options
  if (selectedYear < currentYear) options = SEMESTER_ORDER
  else if (selectedYear > currentYear) options = []
  else if (month <= 2) options = ['겨울방학']
  else if (month <= 6) options = ['1학기']
  else if (month <= 8) options = ['1학기', '여름방학']
  else options = ['1학기', '여름방학', '2학기']

  if (nationalWorkTerm === 'vacation') {
    return options.filter((semester) => ['여름방학', '겨울방학'].includes(semester))
  }
  if (nationalWorkTerm === 'semester') {
    return options.filter((semester) => ['1학기', '2학기'].includes(semester))
  }
  return options
}
