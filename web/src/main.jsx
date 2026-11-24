// React app을 DOM에 렌더링하는 시작점, 건들지 마셈! 주로 이곳 문제가 아님.

import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.jsx'

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
