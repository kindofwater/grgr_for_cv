import { describe, it, expect } from 'vitest'
import { colleges, departments, UNIV_EMAIL_KEYS, univIndexFromEmail, universitiesForEmail } from './profileOptions'

describe('univIndexFromEmail', () => {
  it('korea.ac.kr → 0 (고려대)', () => {
    expect(univIndexFromEmail('user@korea.ac.kr')).toBe(0)
  })
  it('snu.ac.kr → 1 (서울대)', () => {
    expect(univIndexFromEmail('2022320143@snu.ac.kr')).toBe(1)
  })
  it('대소문자 무관 — @ 바로 뒤 라벨만 본다', () => {
    expect(univIndexFromEmail('a@SNU.AC.KR')).toBe(1)
    expect(univIndexFromEmail('a@Korea.ac.kr')).toBe(0)
  })
  it('미매칭 도메인·비정상 입력 → 0 (기본 고려대)', () => {
    expect(univIndexFromEmail('a@yonsei.ac.kr')).toBe(0)
    expect(univIndexFromEmail('golbaeng-i')).toBe(0)
    expect(univIndexFromEmail('')).toBe(0)
    expect(univIndexFromEmail(undefined)).toBe(0)
    expect(univIndexFromEmail(null)).toBe(0)
  })
})

describe('universitiesForEmail', () => {
  const UNIS = [
    { id: 1, name: '고려대학교', campus: '서울', email_domain: 'korea.ac.kr' },
    { id: 2, name: '고려대학교', campus: '세종', email_domain: 'korea.ac.kr' },
    { id: 3, name: '서울대학교', campus: null, email_domain: 'snu.ac.kr' },
  ]
  it('도메인 일치 행만 — 같은 도메인 복수 캠퍼스는 모두 반환', () => {
    expect(universitiesForEmail(UNIS, 'a@korea.ac.kr').map((u) => u.id)).toEqual([1, 2])
    expect(universitiesForEmail(UNIS, '2022320143@snu.ac.kr').map((u) => u.id)).toEqual([3])
  })
  it('대소문자·공백 무관', () => {
    expect(universitiesForEmail(UNIS, 'a@SNU.AC.KR').map((u) => u.id)).toEqual([3])
  })
  it('미등록 도메인·비정상 입력 → 고려대 캠퍼스들로 폴백 (univIndexFromEmail 기본 0과 같은 정책)', () => {
    expect(universitiesForEmail(UNIS, 'a@yonsei.ac.kr').map((u) => u.id)).toEqual([1, 2])
    expect(universitiesForEmail(UNIS, 'golbaeng-i').map((u) => u.id)).toEqual([1, 2])
    expect(universitiesForEmail(UNIS, '').map((u) => u.id)).toEqual([1, 2])
    expect(universitiesForEmail(UNIS, null).map((u) => u.id)).toEqual([1, 2])
  })
  it('고려대 행 자체가 없으면(폴백 불가) 빈 배열', () => {
    expect(universitiesForEmail([{ id: 3, name: '서울대학교', campus: null, email_domain: 'snu.ac.kr' }], 'a@yonsei.ac.kr')).toEqual([])
    expect(universitiesForEmail(null, 'a@korea.ac.kr')).toEqual([])
  })
})

describe('colleges/departments 이중 배열 구조', () => {
  it('1차 index(대학)가 UNIV_EMAIL_KEYS와 병렬', () => {
    expect(colleges.length).toBe(UNIV_EMAIL_KEYS.length)
    expect(departments.length).toBe(UNIV_EMAIL_KEYS.length)
  })
  it('각 대학에서 단과대 수 = 학과 배열 수 (2차 index 병렬)', () => {
    colleges.forEach((cs, u) => {
      expect(departments[u].length).toBe(cs.length)
    })
  })
  it('규모 고정: 고려대 19단과대/67학과 · 서울대 16단과대/91학과', () => {
    expect(colleges[0].length).toBe(19)
    expect(departments[0].flat().length).toBe(67)
    expect(colleges[1].length).toBe(16)
    expect(departments[1].flat().length).toBe(91)
  })
  it('모든 학과 항목은 비어있지 않은 문자열', () => {
    departments.flat(2).forEach((d) => {
      expect(typeof d).toBe('string')
      expect(d.length).toBeGreaterThan(0)
    })
  })
})
