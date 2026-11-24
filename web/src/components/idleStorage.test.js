import { describe, it, expect } from 'vitest'
import { LAST_ACTIVE_KEY, readLastActive, writeLastActive } from './idleStorage'

function memStorage() {
  const m = new Map()
  return {
    getItem: (k) => (m.has(k) ? m.get(k) : null),
    setItem: (k, v) => m.set(k, String(v)),
  }
}

const throwingStorage = {
  getItem: () => { throw new Error('SecurityError') },
  setItem: () => { throw new Error('QuotaExceededError') },
}

describe('idleStorage', () => {
  it('쓴 값을 그대로 읽는다', () => {
    const s = memStorage()
    expect(writeLastActive(s, 'user-1', 123)).toBe(true)
    expect(readLastActive(s)).toBe('{"uid":"user-1","ts":123}')
  })

  it('키가 없으면 null', () => {
    expect(readLastActive(memStorage())).toBe(null)
  })

  it('약속된 키를 쓴다', () => {
    const s = memStorage()
    writeLastActive(s, 'user-1', 1)
    expect(s.getItem(LAST_ACTIVE_KEY)).toBe('{"uid":"user-1","ts":1}')
  })

  it('읽기가 throw해도 크래시하지 않고 null (프라이빗 모드 등)', () => {
    expect(readLastActive(throwingStorage)).toBe(null)
  })

  it('쓰기가 throw해도 크래시하지 않고 false', () => {
    expect(writeLastActive(throwingStorage, 'user-1', 1)).toBe(false)
  })
})
