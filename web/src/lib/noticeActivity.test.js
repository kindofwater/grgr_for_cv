import { describe, expect, it } from 'vitest'
import { noticeActivityAt } from './dates'

describe('noticeActivityAt', () => {
  it('uses created_at until a notice has been updated later', () => {
    expect(noticeActivityAt('2026-07-01T00:00:00Z', '2026-07-01T00:00:00Z'))
      .toBe('2026-07-01T00:00:00Z')
    expect(noticeActivityAt('2026-07-01T00:00:00Z', '2026-07-02T00:00:00Z'))
      .toBe('2026-07-02T00:00:00Z')
  })

  it('falls back to created_at when updated_at is absent', () => {
    expect(noticeActivityAt('2026-07-01T00:00:00Z', null)).toBe('2026-07-01T00:00:00Z')
  })
})
