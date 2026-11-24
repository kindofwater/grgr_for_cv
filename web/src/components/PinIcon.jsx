import './PinIcon.css'

// 고정(공지) 표시용 압정 아이콘. 빨간 이모지(📌) 대신 톤 맞춘 단색 SVG.
// 색·크기는 PinIcon.css의 `.pin-icon`에서 한 곳으로 관리(바꾸려면 거기만 수정).
export default function PinIcon({ className = '', size = 13 }) {
  return (
    <svg
      className={`pin-icon ${className}`.trim()}
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="currentColor"
      aria-hidden="true"
    >
      <path d="M9 2a1 1 0 0 0 0 2h.3l.73 6.5-2.46 2.02A1 1 0 0 0 8 14.5h3V21a1 1 0 0 0 2 0v-6.5h3a1 1 0 0 0 .43-1.98l-2.46-2.02L14.7 4H15a1 1 0 1 0 0-2H9z" />
    </svg>
  )
}
