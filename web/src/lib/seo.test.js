// seo.js 단위테스트 — 실행: npm test
import { describe, it, expect } from 'vitest'
import {
  DEFAULT_TITLE,
  DEFAULT_DESCRIPTION,
  pageTitle,
  worksiteTitle,
  worksiteDescription,
} from './seo'

describe('pageTitle', () => {
  it('페이지 이름 뒤에 사이트명을 붙인다', () => {
    expect(pageTitle('근장찾기')).toBe('근장찾기 — 근로고래')
  })

  it('이름이 없으면(null·undefined·빈문자) 기본 타이틀', () => {
    expect(pageTitle()).toBe(DEFAULT_TITLE)
    expect(pageTitle(null)).toBe(DEFAULT_TITLE)
    expect(pageTitle('')).toBe(DEFAULT_TITLE)
  })

  it('기본 타이틀은 서비스 설명을 포함한다(모든 페이지 동일 제목 문제 방지 기준점)', () => {
    expect(DEFAULT_TITLE).toBe('근로고래 — 근로장학생 근무지 리뷰·추천')
  })
})

describe('worksiteTitle', () => {
  it('기관명 + 근무지명 + "리뷰"로 조립한다', () => {
    expect(worksiteTitle({ organization_name: '고려대학교', workplace_name: '중앙도서관 행정실' })).toBe(
      '고려대학교 중앙도서관 행정실 리뷰',
    )
  })

  it('기관명이 없으면 근무지명만 사용한다', () => {
    expect(worksiteTitle({ workplace_name: '중앙도서관 행정실' })).toBe('중앙도서관 행정실 리뷰')
  })

  it('둘 다 없으면 null(→ pageTitle이 기본 타이틀로 폴백)', () => {
    expect(worksiteTitle(null)).toBe(null)
    expect(worksiteTitle({})).toBe(null)
  })
})

describe('worksiteDescription', () => {
  it('근무지명이 들어간 설명 문장을 만든다', () => {
    const d = worksiteDescription({ organization_name: '고려대학교', workplace_name: '중앙도서관 행정실' })
    expect(d).toContain('고려대학교 중앙도서관 행정실')
    expect(d).toContain('근무 후기')
  })

  it('이름이 없으면 null(→ PageMeta가 기본 설명으로 폴백)', () => {
    expect(worksiteDescription(null)).toBe(null)
  })
})

describe('DEFAULT_DESCRIPTION', () => {
  it('index.html 정적 meta description과 동일한 문구를 유지한다', () => {
    expect(DEFAULT_DESCRIPTION).toBe(
      '근로장학생을 위한 근무지 리뷰·추천 서비스 근로고래. 실제 근무 후기로 나에게 맞는 근무지를 찾아보세요.',
    )
  })
})
