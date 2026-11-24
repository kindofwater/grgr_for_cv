import { describe, it, expect } from 'vitest'
import { selectPostings, summarizeJob, limitRecentPostings, hasJobDescription } from './postings'

describe('selectPostings (Fable #3 단일 정본)', () => {
  it('비-placeholder 중 첫째가 대표, 나머지가 목록', () => {
    const ps = [{ id: 1, is_placeholder: false }, { id: 2, is_placeholder: false }, { id: 3, is_placeholder: false }]
    const { representative, others } = selectPostings(ps)
    expect(representative.id).toBe(1)
    expect(others.map((p) => p.id)).toEqual([2, 3])
  })
  it('placeholder는 대표·목록에서 제외', () => {
    const ps = [{ id: 1, is_placeholder: false }, { id: 2, is_placeholder: true }]
    const { representative, others } = selectPostings(ps)
    expect(representative.id).toBe(1)
    expect(others).toEqual([])
  })
  it('전부 placeholder(국가근로)면 대표는 폴백, 목록은 빔', () => {
    const { representative, others } = selectPostings([{ id: 9, is_placeholder: true }])
    expect(representative.id).toBe(9)
    expect(others).toEqual([])
  })
  it('빈·널 입력이면 대표 null·목록 빔', () => {
    expect(selectPostings([])).toEqual({ representative: null, others: [] })
    expect(selectPostings(null)).toEqual({ representative: null, others: [] })
    expect(selectPostings(undefined)).toEqual({ representative: null, others: [] })
  })
})

describe('limitRecentPostings (최신순 최대 5개)', () => {
  it('호출자가 넘긴 최신순 배열에서 앞 5개만 유지', () => {
    const ps = Array.from({ length: 7 }, (_, i) => ({ id: i + 1 }))
    expect(limitRecentPostings(ps).map((p) => p.id)).toEqual([1, 2, 3, 4, 5])
  })
  it('limit 인자를 바꿀 수 있고 음수면 빈 배열', () => {
    const ps = [{ id: 1 }, { id: 2 }, { id: 3 }]
    expect(limitRecentPostings(ps, 2).map((p) => p.id)).toEqual([1, 2])
    expect(limitRecentPostings(ps, -1)).toEqual([])
  })
  it('빈·널 입력은 빈 배열', () => {
    expect(limitRecentPostings([])).toEqual([])
    expect(limitRecentPostings(null)).toEqual([])
  })
})

describe('hasJobDescription (직무 없는 공고는 목록에서 제외 — "(직무 미상)" 줄 방지)', () => {
  it('직무 텍스트가 있으면 true', () => {
    expect(hasJobDescription({ job_description: '의료공제 업무 지원' })).toBe(true)
  })
  it('없거나 공백뿐이면 false — 근로시간 등 다른 필드가 있어도 제외', () => {
    expect(hasJobDescription({ job_description: null, work_time_text: '09:00~17:30' })).toBe(false)
    expect(hasJobDescription({ job_description: '  ' })).toBe(false)
    expect(hasJobDescription({})).toBe(false)
    expect(hasJobDescription(null)).toBe(false)
  })
})

describe('summarizeJob', () => {
  it('40자 이하는 그대로', () => {
    expect(summarizeJob({ job_description: '행정 보조' })).toBe('행정 보조')
  })
  it('40자 초과는 잘리고 … 붙음', () => {
    const out = summarizeJob({ job_description: '가'.repeat(50) })
    expect(out.length).toBe(41)
    expect(out.endsWith('…')).toBe(true)
  })
  it('개행·연속 공백은 한 칸으로 축약', () => {
    expect(summarizeJob({ job_description: '실험실\n\n  조교' })).toBe('실험실 조교')
  })
  it('비면 (직무 미상)', () => {
    expect(summarizeJob({ job_description: '' })).toBe('(직무 미상)')
    expect(summarizeJob({})).toBe('(직무 미상)')
    expect(summarizeJob(null)).toBe('(직무 미상)')
  })
})
