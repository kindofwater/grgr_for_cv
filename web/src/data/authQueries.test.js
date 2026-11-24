import { beforeEach, describe, expect, it, vi } from 'vitest'

const { rpc } = vi.hoisted(() => ({ rpc: vi.fn() }))

vi.mock('../supabase', () => ({ supabase: { rpc } }))

import { changeNickname } from './authQueries'

describe('changeNickname', () => {
  beforeEach(() => rpc.mockReset())

  it('trims the nickname and returns the updated nickname with the refreshed wallet', async () => {
    const result = {
      nickname: '새고래',
      point_balance: 15,
      pass_balances: { 0: 1 },
      pass_expires_at: null,
    }
    rpc.mockResolvedValueOnce({ data: result, error: null })

    await expect(changeNickname('  새고래  ')).resolves.toEqual(result)
    expect(rpc).toHaveBeenCalledWith('change_nickname', { p_nickname: '새고래' })
    expect(rpc).toHaveBeenCalledTimes(1)
  })

  it('propagates server validation and balance errors without deducting locally', async () => {
    const error = new Error('INSUFFICIENT_POINTS')
    rpc.mockResolvedValueOnce({ data: null, error })

    await expect(changeNickname('새고래')).rejects.toBe(error)
    expect(rpc).toHaveBeenCalledTimes(1)
  })
})
