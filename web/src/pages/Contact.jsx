import { Link } from 'react-router-dom'
import PageMeta from '../components/PageMeta'
import './Legal.css'

// 문의사항 — /contact. 서비스 문의 창구(인스타·이메일) 안내.
// Privacy/Terms와 같은 정적 페이지라 Legal.css 스타일 공유. 푸터에서 링크.
export default function Contact() {
  return (
    <main className="legal-page">
      <PageMeta title="문의사항" />
      <h1>문의사항</h1>
      <p className="legal-intro">
        서비스 이용 중 문의·불편, 제휴·제안 등이 있으시면 아래 창구로 연락 주세요.
        확인하는 대로 답변드리겠습니다.
      </p>

      <section>
        <h2>1:1 문의</h2>
        <ul>
          <li>
            인스타그램:{' '}
            <a href="https://www.instagram.com/grgr_review_official/" target="_blank" rel="noopener noreferrer">
              @grgr_review_official
            </a>
          </li>
          <li>
            이메일: <a href="mailto:bgl0819@korea.ac.kr">bgl0819@korea.ac.kr</a>
          </li>
        </ul>
      </section>

      <section>
        <h2>개인정보 관련 문의</h2>
        <p>
          개인정보 열람·정정·삭제·처리정지 등 개인정보 관련 문의는{' '}
          <Link to="/privacy">개인정보처리방침</Link>의 개인정보 보호책임자에게 연락하실 수 있습니다.
        </p>
      </section>
    </main>
  )
}
