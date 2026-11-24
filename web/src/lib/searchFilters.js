// 고급검색 선택(UI 라벨) → search_worksite_cards RPC 필터 파라미터. 순수함수. UI/DB 의존 없음.

const RECRUIT_MAP = { '모집중': true, '모집완료': false }
const TYPE_MAP = { '국가근장': 'national', '학교근장': 'school' }
const LOC_MAP = { '교외': 'off_campus', '교내': 'on_campus' }
const DUR_MAP = { '단기': 'short', '장기': 'long' }
// 학위/학적: "지원 가능" 의미 — 반대 전용만 제외(2=둘다·3=미정 포함)
const DEGREE_MAP = { '학부생만': [0, 2, 3], '대학원생만': [1, 2, 3] }
const STATUS_MAP = { '재학생만': [0, 2, 3], '휴학생만': [1, 2, 3] }

// 빈 배열 → null
function arr(a) { return a && a.length ? a : null }
// 라벨 배열 → 값 배열(매핑), 매핑 없는 건 제외
function mapArr(labels, map) {
  const vals = (labels ?? []).map((l) => map[l]).filter((v) => v != null)
  return vals.length ? vals : null
}
// 라벨 배열 → 배열 값들을 펼쳐 중복 제거
function expandMapArr(labels, map) {
  const vals = (labels ?? []).flatMap((l) => map[l] ?? [])
  return vals.length ? [...new Set(vals)] : null
}

export function countSelectedFilters(selection) {
  return Object.values(selection ?? {}).reduce(
    (total, values) => total + (Array.isArray(values) ? values.length : 0),
    0,
  )
}

export function buildSearchFilters(selection) {
  const s = selection ?? {}
  return {
    p_actives: mapArr(s.recruit, RECRUIT_MAP),
    p_types: mapArr(s.type, TYPE_MAP),
    p_locations: mapArr(s.location, LOC_MAP),
    p_regions: arr(s.region),                      // 라벨=값
    p_durations: mapArr(s.duration, DUR_MAP),
    p_tracks: arr(s.track),                         // 라벨=값
    p_degrees: expandMapArr(s.degree, DEGREE_MAP),
    p_statuses: expandMapArr(s.status, STATUS_MAP),
  }
}
