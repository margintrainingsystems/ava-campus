import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import { App } from './App'
import { AuthProvider } from './auth/AuthProvider'
import { ToastProvider } from './components/Toast'
import { I18nProvider } from './i18n/I18nProvider'
import './styles/tokens.css'
import './styles/base.css'
import './styles/campus.css'

const root = document.getElementById('root')
if (!root) throw new Error('Falta el elemento #root en index.html')

createRoot(root).render(
  <StrictMode>
    <BrowserRouter>
      <I18nProvider>
        <ToastProvider>
          <AuthProvider>
            <App />
          </AuthProvider>
        </ToastProvider>
      </I18nProvider>
    </BrowserRouter>
  </StrictMode>,
)
