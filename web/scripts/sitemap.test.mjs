// sitemap.mjs(순수 함수) 단위테스트 — 실행: npm test
import { describe, it, expect } from 'vitest'
import { ORIGIN, STATIC_PATHS, worksitePaths, buildSitemapXml, collectRows, filterReviewed } from './sitemap.mjs'

// 가짜 서버: 전체 rows에서 [offset, offset+cap) 반환 — 요청 limit과 무관하게 서버가 cap으로 자르는 상황 재현
function fakeServer(rows, cap) {
  const calls = []
  const fetchPage = async (offset) => {
    calls.push(offset)
    return rows.slice(offset, offset + cap)
  }
  return { fetchPage, calls }
}

describe('collectRows', () => {
  it('서버가 요청보다 적게(50캡) 반환해도 빠짐없이 이어서 수집한다 — 1,750 버그 회귀 방지', async () => {
    const all = Array.from({ length: 120 }, (_, i) => ({ worksite_id: i + 1 }))
    const { fetchPage } = fakeServer(all, 50)
    const rows = await collectRows(fetchPage)
    expect(rows.map((r) => r.worksite_id)).toEqual(all.map((r) => r.worksite_id)) // 줄무늬 누락 없음
  })

  it('빈 배치를 만나면 종료한다(첫 배치가 비어도 빈 배열)', async () => {
    const { fetchPage } = fakeServer([], 50)
    expect(await collectRows(fetchPage)).toEqual([])
  })

  it('stopWhen이 참인 배치까지 수집하고 다음 페이지는 요청하지 않는다', async () => {
    // review_count 내림차순 정렬 가정: 3,2,1,0,0,0... → 0이 나온 배치에서 멈춤
    const all = [3, 2, 1, 0, 0, 0, 0, 0].map((n, i) => ({ worksite_id: i + 1, review_count: n }))
    const { fetchPage, calls } = fakeServer(all, 4)
    const rows = await collectRows(fetchPage, { stopWhen: (batch) => Number(batch[batch.length - 1]?.review_count) === 0 })
    expect(rows).toHaveLength(4)      // 첫 배치(3,2,1,0)까지만
    expect(calls).toEqual([0])        // 두 번째 페이지 요청 안 함
  })

  it('maxPages 안전 상한을 넘기면 멈춘다(무한 루프 방지)', async () => {
    const stuck = async () => [{ worksite_id: 1 }]   // offset 무시하고 항상 1행 반환하는 고장난 서버
    const rows = await collectRows(stuck, { maxPages: 5 })
    expect(rows).toHaveLength(5)
  })
})

describe('filterReviewed', () => {
  it('review_count가 1 이상인 행만 남긴다', () => {
    expect(
      filterReviewed([
        { worksite_id: 1, review_count: 2 },
        { worksite_id: 2, review_count: 0 },
        { worksite_id: 3, review_count: null },
        { worksite_id: 4 },
        { worksite_id: 5, review_count: 1 },
      ]).map((r) => r.worksite_id),
    ).toEqual([1, 5])
  })
})

describe('worksitePaths', () => {
  it('검색 RPC flat 행(worksite_id)을 /worksite/:id 경로로 변환한다', () => {
    expect(worksitePaths([{ worksite_id: 3 }, { worksite_id: 12 }])).toEqual([
      '/worksite/3',
      '/worksite/12',
    ])
  })

  it('중복 id는 하나로 합치고 id 오름차순으로 정렬한다', () => {
    expect(worksitePaths([{ worksite_id: 12 }, { worksite_id: 3 }, { worksite_id: 12 }])).toEqual([
      '/worksite/3',
      '/worksite/12',
    ])
  })

  it('유효하지 않은 id(null·음수·비숫자)는 걸러낸다', () => {
    expect(
      worksitePaths([{ worksite_id: null }, { worksite_id: -1 }, { worksite_id: 'abc' }, { worksite_id: 7 }, {}]),
    ).toEqual(['/worksite/7'])
  })

  it('빈 입력(null·[])이면 빈 배열', () => {
    expect(worksitePaths(null)).toEqual([])
    expect(worksitePaths([])).toEqual([])
  })
})

describe('buildSitemapXml', () => {
  it('경로마다 ORIGIN 붙인 <url><loc> 항목을 만든다', () => {
    const xml = buildSitemapXml(['/home', '/worksite/3'])
    expect(xml).toContain(`<loc>${ORIGIN}/home</loc>`)
    expect(xml).toContain(`<loc>${ORIGIN}/worksite/3</loc>`)
  })

  it('sitemap 프로토콜 골격(xml 선언 + urlset xmlns)을 갖춘다', () => {
    const xml = buildSitemapXml(['/home'])
    expect(xml.startsWith('<?xml version="1.0" encoding="UTF-8"?>')).toBe(true)
    expect(xml).toContain('<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">')
    expect(xml.trimEnd().endsWith('</urlset>')).toBe(true)
  })

  it('XML 특수문자(&)는 이스케이프한다', () => {
    expect(buildSitemapXml(['/search?a=1&b=2'])).toContain('/search?a=1&amp;b=2')
  })
})

describe('STATIC_PATHS', () => {
  it('기존 정적 sitemap의 공개 라우트 6개를 유지한다', () => {
    expect(STATIC_PATHS).toEqual(['/home', '/search', '/notice', '/privacy', '/terms', '/contact'])
  })
})
