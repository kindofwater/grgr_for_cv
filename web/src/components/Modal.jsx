import { Dialog } from 'radix-ui'
import './Modal.css'

// 앱의 모든 모달이 통과하는 공용 셸 — 모달을 새로 만들 땐 반드시 이걸 쓴다.
//
// Radix Dialog가 담당(우리가 안 짬): 포커스 트랩 · 배경 스크롤 잠금 · Esc · 닫을 때 포커스 복귀 ·
//   role/aria-modal · Portal.
// 이 파일이 담당: 오버레이(스크림) · 카드 · 폭 · 애니메이션 · 닫힘 정책.
//
// ⚠️ Portal이 모달을 <body> 직속으로 렌더한다 = 모달이 페이지 DOM의 후손이 아니다.
//    그래서 `.home-wrap button`, `.form-wrap button` 같은 페이지 CSS가 모달에 닿지 않는다.
//    모달의 모양은 오직 Modal.css로만 결정된다(어느 페이지에서 띄우든 동일).
//    (역으로: 페이지 CSS에 기대던 것도 안 닿는다. 폰트 등은 Modal.css가 직접 박아야 한다.)
//
// props:
//   open, onOpenChange  — Radix 제어 (열림 상태는 부모가 소유)
//   size        'sm'(320) | 'md'(400) | 'lg'(420·광고)
//   dismissible false면 Esc·배경클릭으로 안 닫힘. 광고 모달 전용 —
//               리워드 어뷰징 방지 사양이라 버그가 아니다. 기본 true.
//   title       스크린리더용 제목(필수 — Radix가 없으면 경고). 화면에 보이려면 titleHidden={false}
//   className   같은 components/ 안의 모달이 카드 모양을 덧칠할 때만 (예: 'ad-modal').
//               ⚠️ pages가 모달에 className을 주입하는 통로로 쓰지 말 것 — 그게 갈라짐의 시작이다.
export default function Modal({
  open,
  onOpenChange,
  size = 'sm',
  dismissible = true,
  title,
  titleHidden = true,
  className = '',
  children,
}) {
  // dismissible=false면 Radix의 닫기 트리거를 전부 막는다
  const block = (e) => { if (!dismissible) e.preventDefault() }

  // aria-describedby={undefined}: 설명 요소를 안 쓴다고 Radix에 명시(안 하면 콘솔 경고)
  return (
    <Dialog.Root open={open} onOpenChange={onOpenChange}>
      <Dialog.Portal>
        <Dialog.Overlay className="modal-overlay" />
        <Dialog.Content
          className={`modal modal-${size}${className ? ' ' + className : ''}`}
          onEscapeKeyDown={block}
          onPointerDownOutside={block}
          onInteractOutside={block}
          aria-describedby={undefined}
        >
          <Dialog.Title className={titleHidden ? 'modal-sr-only' : 'modal-title'}>
            {title}
          </Dialog.Title>
          {children}
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  )
}
