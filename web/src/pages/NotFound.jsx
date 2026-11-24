import { useEffect } from 'react'
import { Link } from 'react-router-dom'
import PageMeta from '../components/PageMeta'
import './NotFound.css'

export default function NotFound() {
  useEffect(() => {
    const previousTitle = document.title
    const existingRobots = document.querySelector('meta[name="robots"]')
    const previousRobots = existingRobots?.getAttribute('content') ?? null
    const robots = existingRobots ?? document.head.appendChild(document.createElement('meta'))

    robots.setAttribute('name', 'robots')
    robots.setAttribute('content', 'noindex,nofollow')
    document.title = '페이지를 찾을 수 없어요 | 근로고래'

    return () => {
      document.title = previousTitle
      if (previousRobots === null) robots.remove()
      else robots.setAttribute('content', previousRobots)
    }
  }, [])

  return (
    <main className="not-found-page">
      <PageMeta title="페이지를 찾을 수 없어요" />
      <div className="not-found-card">
        <div className="not-found-code" aria-hidden="true">404</div>
        <h1>페이지를 찾을 수 없어요</h1>
        <p>주소가 잘못되었거나, 이동 또는 삭제된 페이지예요.</p>
        <div className="not-found-actions">
          <Link className="not-found-primary" to="/home">홈으로 돌아가기</Link>
          <Link className="not-found-secondary" to="/search">근장찾기</Link>
        </div>
      </div>
    </main>
  )
}
