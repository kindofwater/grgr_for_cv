// dist/sitemap.xml 생성 엔트리 — `npm run build`가 vite build 뒤에 실행한다.
// anon 키로 공개 검색 RPC(search_worksite_cards)를 호출해 **품질 셋**만 담는다(2026-08-19 결정):
//   ① 학교근장 전부  ② 교내 국가근장(학기중형) 전부  ③ 교외 국가근장(방학형 레거시)은 리뷰 있는 곳만
// 이유: 레거시 교외 6,700여 곳은 KUPID 공고 복제 성격의 빈 페이지라, '가치 낮은 콘텐츠'로
//   애드센스 반려된 사이트가 이를 sitemap으로 들이밀면 품질 평가에 역효과. 밀도 높은 ~250곳만 제출.
//
// ⚠️ 실패해도 빌드는 계속된다(soft-fail): public/sitemap.xml 정적본(공개 라우트 6개)이 그대로 배포됨.
//    빌드 로그의 [sitemap] 경고로만 알 수 있으니 배포 로그를 가끔 확인할 것.
// ⚠️ 검색 RPC는 p_limit을 서버에서 50개로 캡한다(search_rpc_limits_and_timeout 마이그레이션).
//    페이징은 collectRows가 '실제 받은 개수'만큼 전진하므로 캡이 바뀌어도 안전.
// ⚠️ PUBLIC_BROWSE(src/config.js)를 닫으면(다학교 확장 시 anon RPC 회수) 이 스크립트도 함께 무력화됨
//    — 그때 sitemap 전략을 다시 정할 것(로그인 벽 뒤 페이지는 색인 대상도 아님).
// 순수 로직(페이징·필터·경로 조립·XML)은 sitemap.mjs에 있고 단위테스트로 검증한다. 여기는 env·fetch·fs만.
import { readFile, writeFile } from 'node:fs/promises'
import { STATIC_PATHS, worksitePaths, buildSitemapXml, collectRows, filterReviewed } from './sitemap.mjs'

const webRoot = new URL('..', import.meta.url) // = web/
const PER = 50 // 서버 캡과 동일 — 더 크게 요청해도 50개만 옴

// Cloudflare Pages 빌드는 process.env에 있음. 로컬 `npm run build`는 vite처럼 .env.local → .env 폴백.
async function loadEnv() {
  let url = process.env.VITE_SUPABASE_URL
  let key = process.env.VITE_SUPABASE_ANON_KEY
  for (const name of ['.env.local', '.env']) {
    if (url && key) break
    try {
      const text = await readFile(new URL(name, webRoot), 'utf8')
      for (const line of text.split('\n')) {
        const m = line.match(/^\s*(VITE_SUPABASE_URL|VITE_SUPABASE_ANON_KEY)\s*=\s*(\S+)\s*$/)
        if (!m) continue
        if (m[1] === 'VITE_SUPABASE_URL') url ||= m[2]
        else key ||= m[2]
      }
    } catch { /* 파일 없으면 다음 후보 */ }
  }
  return { url, key }
}

// 필터 조합별 fetchPage 생성 — 프론트(searchWorksiteCards)와 동일한 인자 세트(오버로드 모호성 방지)
function pageFetcher(url, key, extra) {
  return async (offset) => {
    const res = await fetch(`${url}/rest/v1/rpc/search_worksite_cards`, {
      method: 'POST',
      headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        p_query: '', p_sort: 'reviews', p_limit: PER, p_offset: offset,
        p_actives: null, p_types: null, p_locations: null, p_regions: null,
        p_durations: null, p_tracks: null, p_degrees: null, p_statuses: null,
        ...extra,
      }),
    })
    if (!res.ok) throw new Error(`RPC ${res.status}: ${(await res.text()).slice(0, 200)}`)
    return res.json()
  }
}

try {
  const { url, key } = await loadEnv()
  if (!url || !key) throw new Error('VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY 없음(빌드 env 또는 .env.local)')

  const school = await collectRows(pageFetcher(url, key, { p_types: ['school'] }))
  const onCampusNational = await collectRows(pageFetcher(url, key, { p_types: ['national'], p_locations: ['on_campus'] }))
  // 리뷰많은순 정렬이므로 review_count 0이 나온 배치에서 조기 종료 — 6,700여 곳을 다 돌지 않는다
  const offCampusReviewed = filterReviewed(
    await collectRows(pageFetcher(url, key, { p_types: ['national'], p_locations: ['off_campus'] }), {
      stopWhen: (batch) => Number(batch[batch.length - 1]?.review_count) === 0,
    }),
  )

  const worksites = worksitePaths([...school, ...onCampusNational, ...offCampusReviewed])
  await writeFile(new URL('dist/sitemap.xml', webRoot), buildSitemapXml([...STATIC_PATHS, ...worksites]))
  console.log(
    `[sitemap] dist/sitemap.xml 생성 완료 — 정적 ${STATIC_PATHS.length} + 근무지 ${worksites.length}`
    + ` (학교 ${school.length} · 교내국가 ${onCampusNational.length} · 리뷰있는 교외 ${offCampusReviewed.length})`,
  )
} catch (e) {
  console.warn(`[sitemap] 생성 실패 — public/sitemap.xml 정적본 유지: ${e.message}`)
}
