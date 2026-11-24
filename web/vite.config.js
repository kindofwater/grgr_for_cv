import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { rm } from 'node:fs/promises'

// public/ 는 통째로 dist/에 복사된다. 거기 섞인 내부 문서·미사용 파일은
// 공개 배포(grgr.kr)에 나갈 필요가 없으므로 빌드 산출물에서만 제외한다.
// (원본은 리포에 그대로 남음 — 폴더 README 규칙 유지)
const stripFromDist = ['README.md', 'icons.svg']
const stripPublicDocs = () => ({
  name: 'strip-public-docs',
  apply: 'build',
  closeBundle: async () => {
    for (const f of stripFromDist) {
      await rm(new URL(`./dist/${f}`, import.meta.url), { force: true })
    }
  },
})

// https://vite.dev/config/
export default defineConfig({
  plugins: [react(), stripPublicDocs()],
  // 테스트 러너 TZ를 UTC로 고정 — 개발/CI 머신이 KST라 로컬시간 == KST가 되어,
  // 시간대 버그(로컬시간으로 KST 달력일을 구하는 구현)를 테스트가 못 잡는다.
  // 표시/판정은 전부 KST 고정이므로(dates.js·recruit.js) 러너 TZ와 무관해야 정상.
  test: { env: { TZ: 'UTC' } },
})
