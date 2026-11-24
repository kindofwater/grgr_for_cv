import { beforeEach, describe, expect, it, vi } from 'vitest'

const { rpc } = vi.hoisted(() => ({ rpc: vi.fn() }))

vi.mock('../supabase', () => ({ supabase: { rpc } }))

import { fetchAdRewardStatus } from './adQueries'

describe('fetchAdRewardStatus', () => {
  beforeEach(() => rpc.mockReset())

  it('returns the current daily ad reward availability without starting an ad view', async () => {
    const status = {
      available: false,
      unavailable_reason: 'CAP_REACHED',
      daily_cap: 1,
      claimed_today: 1,
      remaining_today: 0,
      reward_points: 5,
      cooldown_until: null,
    }
    rpc.mockResolvedValueOnce({ data: status, error: null })

    await expect(fetchAdRewardStatus()).resolves.toEqual(status)
    expect(rpc).toHaveBeenCalledWith('get_ad_reward_status')
  })

  it('propagates status RPC errors', async () => {
    const error = new Error('NO_CONFIG')
    rpc.mockResolvedValueOnce({ data: null, error })

    await expect(fetchAdRewardStatus()).rejects.toBe(error)
  })
})
