import { Route, Routes } from 'react-router-dom'
import { AppLayout } from './components/AppLayout'
import { RequireStudent } from './components/Guards'
import { AccountPage } from './pages/AccountPage'
import { CoursePage } from './pages/CoursePage'
import { ForgotPasswordPage } from './pages/ForgotPasswordPage'
import { HomePage } from './pages/HomePage'
import { LessonPage } from './pages/LessonPage'
import { LoginPage } from './pages/LoginPage'
import { NotFoundPage } from './pages/NotFoundPage'
import { SetPasswordPage } from './pages/SetPasswordPage'

export function App() {
  return (
    <Routes>
      <Route path="/ingresar" element={<LoginPage />} />
      <Route path="/recuperar" element={<ForgotPasswordPage />} />
      <Route path="/definir-contrasena" element={<SetPasswordPage />} />
      <Route
        element={
          <RequireStudent>
            <AppLayout />
          </RequireStudent>
        }
      >
        <Route index element={<HomePage />} />
        <Route path="cursos/:slug" element={<CoursePage />} />
        <Route path="cursos/:slug/clases/:lessonId" element={<LessonPage />} />
        <Route path="cuenta" element={<AccountPage />} />
        <Route path="*" element={<NotFoundPage />} />
      </Route>
    </Routes>
  )
}
