import './ArrowButton.css'

// 오른쪽 화살표(→) 진행 버튼. 확인/로그인/회원가입/다음 등 "다음 단계로" 액션에 재사용.
// props: onClick, label(aria-label, 기본 '다음'), disabled
// label은 텍스트로도 렌더하되 기본은 숨김(display:none) — 와이드 변형이 필요한 곳(모바일 signup 등)만
// CSS로 .btn-arrow-label을 노출시켜 "다음" 같은 문구가 보이는 버튼이 된다.
export default function ArrowButton({ onClick, label = '다음', disabled = false }) {
  return (
    <button
      type="button"
      className="btn-arrow"
      aria-label={label}
      onClick={onClick}
      disabled={disabled}
    >
      <span className="btn-arrow-label">{label}</span>
      <svg
        viewBox="0 0 24 24"
        width="18"
        height="18"
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
      >
        <path d="M5 12h14"></path>
        <path d="M13 6l6 6-6 6"></path>
      </svg>
    </button>
  )
}
