# Campus de AVA: guía para Claude Code

Leé el README antes de cambiar algo. Resumen de lo que no se negocia:

- Interfaz en tres idiomas: español rioplatense con voseo (base), inglés y portugués de Brasil. Todo texto visible va en `src/i18n/es.ts`, `en.ts` y `pt.ts`, nunca escrito en un componente. Nada de notas de desarrollo visibles.
- El contenido (cursos, módulos, clases, materiales) es jsonb `{es, en, pt}` con español obligatorio; se muestra con `text()` de `useI18n`, que cae al español.
- La dueña es Aimar Merino. Siempre en femenino.
- Supabase compartido con el sitio, Núcleo y el CRM: proyecto `mryuhzpenzpyhfidwsup`. Tablas del Campus con prefijo `campus_`, RLS obligatorio, helpers en `campus_private`. Nunca tocar tablas del sitio ni del CRM desde una migración del Campus.
- El acceso sale de `crm_subscriptions` (por el email de la cuenta) y lo decide la base. La interfaz solo evita mostrar pantallas vacías.
- Videos en YouTube como ocultos: en la base va solo el id, y solo llega con acceso al curso. Se incrustan desde `youtube-nocookie.com`.
- Cambios de base solo con migraciones nuevas en `supabase/migrations/`. No apliques migraciones a la base real sin que la dueña lo confirme: es la misma base del sitio en producción.
- Nunca pedir ni guardar datos de tarjetas, DNI ni datos sensibles. La `service_role` solo en Edge Functions.
- Diseño: tokens en `src/styles/tokens.css` (los del sitio). Verde como color principal; los acentos de cada Máster solo en detalles. Sin glassmorphism ni métricas inventadas.
- Antes de subir: `npm run check`, `npm run build` y `supabase/tests/campus_fase1_acceso.sql` con `FALLAS: 0`.
- Si falta una definición (precios, certificados, textos legales), preguntale a la dueña. No la completes por tu cuenta.
