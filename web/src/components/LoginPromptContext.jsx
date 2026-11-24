import { createContext, useContext, useState } from 'react'
import LoginPromptModal from './LoginPromptModal'

// 앱 전역 로그인 프롬프트 통로(ToastContext와 동형). 잠긴 기능 시도 시 어느 컴포넌트든
// useLoginPrompt().promptLogin() 하면 LoginPromptModal(부드러운 로그인 유도)이 뜬다.
// ⚠️ 명시적 '로그인/회원가입' 버튼은 이거 대신 navigate('/login') 직접(정책: 명시버튼=리다이렉트).
// ⚠️ LoginPromptModal이 useNavigate를 쓰므로 이 Provider는 BrowserRouter 안에 있어야 한다(App.jsx).
const LoginPromptContext = createContext(null)

export function LoginPromptProvider({ children }) {
  const [open, setOpen] = useState(false)
  const promptLogin = () => setOpen(true)
  return (
    <LoginPromptContext.Provider value={{ promptLogin }}>
      {children}
      {open && <LoginPromptModal onClose={() => setOpen(false)} />}
    </LoginPromptContext.Provider>
  )
}

// eslint-disable-next-line react-refresh/only-export-components
export function useLoginPrompt() { return useContext(LoginPromptContext) }
