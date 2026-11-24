import { useEffect, useState } from 'react'
import {
  useFloating, autoUpdate, offset, flip, size as floatingSize, FloatingPortal,
} from '@floating-ui/react'
import './Dropdown.css'

/* Floating UI의 refs.setReference / refs.setFloating 는 '안정적인 콜백 ref'라 render에서 ref={}로
   넘기는 게 정상 사용법인데, react-hooks/refs 규칙이 이를 ref.current 접근으로 오인(false positive)함.
   이 컴포넌트는 그 외 ref를 직접 안 쓰므로 파일 단위로만 끈다. */
/* eslint-disable react-hooks/refs */

// 재사용 드롭다운 (네이티브 <select> 대체) — 컨트롤에 붙는 팝업·hover·선택강조·페이드 등장.
// 위치는 Floating UI(useFloating + autoUpdate)가 계산·추적: 스크롤/리사이즈/요소크기 자동 반영(rAF 최적화),
// 아래 공간 없으면 위로 뒤집기(flip)·좌우 화면밖 보정(shift)·폭=컨트롤·높이=가용공간(size).
// 메뉴는 FloatingPortal로 body에 띄워 조상 overflow:hidden(예: auth-card) 클립을 탈출.
// 바깥클릭/Esc 닫기는 직접 처리(가벼운 도입 — Floating UI 상호작용 훅은 안 씀).
// props:
//   value, onChange(value), options([{value,label,dotClass?}] 또는 문자열/숫자 배열),
//   ariaLabel, hasError(빨간 테두리), disabled, size("sm"=컴팩트), label(라벨:값 인라인)
export default function Dropdown({ value, onChange, options, ariaLabel, hasError = false, disabled = false, size, label }) {
  const [open, setOpen] = useState(false)
  const opts = options.map((o) => (o && typeof o === 'object' ? o : { value: o, label: String(o) }))
  const selected = opts.find((o) => String(o.value) === String(value))

  const { refs, floatingStyles, placement } = useFloating({
    strategy: 'absolute',                // 문서 기준(컨트롤과 같은 좌표계)으로 붙임 → 줌+스크롤에도 컨트롤과 함께 이동(안 어긋남)
    transform: false,                    // transform 대신 top/left로 위치 → 줌 시 sub-pixel 어긋남 방지
    placement: 'bottom-start',
    whileElementsMounted: autoUpdate,    // 스크롤/리사이즈/요소크기 변화 자동 추적
    middleware: [
      offset(0),                         // 간격 0 (컨트롤에 붙음)
      flip({ padding: 8 }),              // 아래 공간 없으면 위로 뒤집기 (세로만)
      // shift는 일부러 뺌: 폭이 컨트롤과 같아 이득 없고, 줌+스크롤로 컨트롤이 화면 밖으로 나갈 때
      //   메뉴만 뷰포트 안으로 밀려 컨트롤과 어긋남(붙는 느낌 깨짐) → 항상 컨트롤에 붙도록 유지.
      floatingSize({                     // 폭=컨트롤, 높이=가용공간(최대 280)
        padding: 8,
        apply({ rects, elements, availableHeight }) {
          Object.assign(elements.floating.style, {
            width: `${rects.reference.width}px`,
            maxHeight: `${Math.min(280, availableHeight)}px`,
          })
        },
      }),
    ],
  })

  const isUp = placement.startsWith('top')   // 위로 뒤집혔나 → 붙는 모서리 미러링용

  // 바깥클릭/Esc 닫기 (메뉴는 포털 → reference·floating 둘 다 검사)
  useEffect(() => {
    if (!open) return
    const onDown = (e) => {
      if (refs.reference.current?.contains?.(e.target)) return
      if (refs.floating.current?.contains?.(e.target)) return
      setOpen(false)
    }
    const onKey = (e) => { if (e.key === 'Escape') setOpen(false) }
    document.addEventListener('mousedown', onDown)
    document.addEventListener('keydown', onKey)
    return () => {
      document.removeEventListener('mousedown', onDown)
      document.removeEventListener('keydown', onKey)
    }
  }, [open, refs.reference, refs.floating])

  return (
    <div className={`dd${size === 'sm' ? ' dd-sm' : ''}`} ref={refs.setReference}>
      <button
        type="button"
        className={`dd-btn${open ? ' dd-open' : ''}${open && isUp ? ' dd-open-up' : ''}${hasError ? ' has-error' : ''}`}
        disabled={disabled}
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-label={ariaLabel}
        onClick={() => setOpen((o) => !o)}
      >
        <span className="dd-value">
          {label && <span className="dd-label">{label}</span>}
          {selected?.dotClass && <span className={`dd-dot ${selected.dotClass}`} />}
          <span className="dd-text">{selected?.label ?? ''}</span>
        </span>
        <svg className="dd-caret" viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
          <path d="M6 9l6 6 6-6" />
        </svg>
      </button>
      {open && (
        <FloatingPortal>
          <ul
            ref={refs.setFloating}
            className={`dd-menu${size === 'sm' ? ' dd-menu-sm' : ''}${isUp ? ' dd-menu-up' : ''}`}
            style={floatingStyles}
            role="listbox"
            aria-label={ariaLabel}
          >
            {opts.map((o) => (
              <li
                key={String(o.value)}
                role="option"
                aria-selected={String(o.value) === String(value)}
                className={`dd-item${String(o.value) === String(value) ? ' is-selected' : ''}`}
                onClick={() => { onChange(o.value); setOpen(false) }}
              >
                {o.dotClass && <span className={`dd-dot ${o.dotClass}`} />}
                {o.label}
              </li>
            ))}
          </ul>
        </FloatingPortal>
      )}
    </div>
  )
}
