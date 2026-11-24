/// 라우트별 문서 title·meta description 반영. 각 페이지가 <PageMeta title="…" />로 선언.
/// SEO(색인 품질) 목적: 예전엔 모든 라우트가 index.html의 "근로고래" 제목 하나였음 — Googlebot은
/// JS 렌더 후의 document.title을 색인하므로 이 방식으로 페이지별 제목이 잡힌다.
/// React 19의 <title> 호이스팅 대신 DOM 직접 갱신을 쓰는 이유: index.html에 정적 <title>이
/// 이미 있어 중복 태그가 생기는 엣지를 피하고, GA page_view(document.title 사용)와도 맞물리게.
/// 언마운트 시 복원은 안 한다 — 모든 라우트 페이지가 각자 PageMeta를 렌더하는 게 전제
/// (title 생략 = 기본 타이틀로 리셋). 새 페이지를 만들면 PageMeta도 함께 넣을 것.
import { useEffect } from 'react'
import { DEFAULT_DESCRIPTION, pageTitle } from '../lib/seo'

export default function PageMeta({ title, description }) {
  useEffect(() => {
    document.title = pageTitle(title)
    // index.html의 정적 meta를 교체(생성 아님) — 항상 존재. description 없으면 기본 문구로 리셋.
    const meta = document.querySelector('meta[name="description"]')
    if (meta) meta.setAttribute('content', description || DEFAULT_DESCRIPTION)
  }, [title, description])
  return null
}
