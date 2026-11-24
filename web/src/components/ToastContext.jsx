import { createContext, useCallback, useContext, useRef, useState } from 'react'
import Toast from './Toast'

// 앱 어디서나 토스트를 띄우는 통로. App.jsx가 <ToastProvider>로 감싼다.
//
// 왜 컨텍스트인가: 예전엔 페이지가 각자 notice 상태를 들고 <Toast>를 렌더했는데,
// AdModal 같은 '컴포넌트'는 토스트를 띄울 방법이 없었다(페이지가 아니라서).
// AuthContext와 같은 자리·같은 방식이라 새 패턴이 아니다.
//
// 쓰는 법:
//   const toast = useToast()
//   toast('신고가 접수되었어요')
//   toast('포인트가 부족해요', 'error')
//   toast('기존에 작성한 리뷰를 불러왔어요.', 'info', 5000)
const ToastContext = createContext(null)

export function ToastProvider({ children }) {
  const [current, setCurrent] = useState(null)   // { message, variant, duration, key }
  const seq = useRef(0)

  const toast = useCallback((message, variant = 'info', duration = 1500) => {
    // key를 매번 새로 줘서 리마운트 → 같은 메시지를 연속으로 띄워도 애니메이션이 다시 돈다.
    // (Symbol은 React key로 못 쓴다 — 문자열/숫자만 허용)
    seq.current += 1
    setCurrent({ message, variant, duration, key: seq.current })
  }, [])

  return (
    <ToastContext.Provider value={toast}>
      {children}
      {current && (
        <Toast
          key={current.key}
          message={current.message}
          variant={current.variant}
          duration={current.duration}
          onClose={() => setCurrent(null)}
        />
      )}
    </ToastContext.Provider>
  )
}

// eslint-disable-next-line react-refresh/only-export-components
export function useToast() {
  const toast = useContext(ToastContext)
  if (!toast) throw new Error('useToast는 <ToastProvider> 안에서만 쓸 수 있어요')
  return toast
}
