// web/src/lib/searchFilters.test.js
import { describe, it, expect } from 'vitest'
import { buildSearchFilters, countSelectedFilters } from './searchFilters'

const EMPTY = {
  recruit: [],
  type: [],
  location: [],
  region: [],
  duration: [],
  track: [],
  degree: [],
  status: [],
}

describe('buildSearchFilters', () => {
  it('빈 선택은 전부 null', () => {
    expect(buildSearchFilters(EMPTY)).toEqual({
      p_actives: null, p_types: null, p_locations: null, p_regions: null,
      p_durations: null, p_tracks: null, p_degrees: null, p_statuses: null,
    })
  })

  it('모집상태 → boolean 배열 (모집중=true, 모집완료=false)', () => {
    expect(buildSearchFilters({ ...EMPTY, recruit: ['모집중'] }).p_actives).toEqual([true])
    expect(buildSearchFilters({ ...EMPTY, recruit: ['모집완료'] }).p_actives).toEqual([false])
    expect(buildSearchFilters({ ...EMPTY, recruit: ['모집중', '모집완료'] }).p_actives).toEqual([true, false])
  })

  it('유형/교내외 라벨 → enum 값 배열', () => {
    const f = buildSearchFilters({ ...EMPTY, type: ['국가근장', '학교근장'], location: ['교외'] })
    expect(f.p_types).toEqual(['national', 'school'])
    expect(f.p_locations).toEqual(['off_campus'])
  })

  it('지역/우대는 라벨 그대로 passthrough', () => {
    const f = buildSearchFilters({ ...EMPTY, region: ['서울', '경기'], track: ['이공계열'] })
    expect(f.p_regions).toEqual(['서울', '경기'])
    expect(f.p_tracks).toEqual(['이공계열'])
  })

  it('기간 복수선택 → 배열', () => {
    expect(buildSearchFilters({ ...EMPTY, duration: ['단기'] }).p_durations).toEqual(['short'])
    expect(buildSearchFilters({ ...EMPTY, duration: ['장기', '단기'] }).p_durations).toEqual(['long', 'short'])
  })

  it('학위 지원가능 확장', () => {
    expect(buildSearchFilters({ ...EMPTY, degree: ['학부생만'] }).p_degrees).toEqual([0, 2, 3])
    expect(buildSearchFilters({ ...EMPTY, degree: ['대학원생만'] }).p_degrees).toEqual([1, 2, 3])
    expect(buildSearchFilters({ ...EMPTY, degree: ['학부생만', '대학원생만'] }).p_degrees)
      .toEqual([0, 2, 3, 1])
  })

  it('학적 지원가능 확장', () => {
    expect(buildSearchFilters({ ...EMPTY, status: ['재학생만'] }).p_statuses).toEqual([0, 2, 3])
    expect(buildSearchFilters({ ...EMPTY, status: ['휴학생만'] }).p_statuses).toEqual([1, 2, 3])
    expect(buildSearchFilters({ ...EMPTY, status: ['재학생만', '휴학생만'] }).p_statuses)
      .toEqual([0, 2, 3, 1])
  })

  it('선택 개수는 모든 그룹의 현재 선택값을 합산', () => {
    expect(countSelectedFilters({
      ...EMPTY,
      recruit: ['모집중'],
      region: ['서울', '경기'],
      duration: ['장기', '단기'],
    })).toBe(5)
  })
})
