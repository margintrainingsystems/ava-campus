# Campus de AVA

El lugar donde estudian quienes se suscriben a AVA: sus cursos, las clases en video, los materiales y su progreso. Es la fase 5 de la hoja de ruta del CRM.

- **Sitio** (`aprendeconava`): la cara pública. El botón "Acceder al Campus" lleva acá cuando se carga el link en Núcleo.
- **Núcleo** (`ava-nucleo`): el panel de la dueña.
- **CRM** (`ava-crm`): donde el equipo registra las suscripciones. Una suscripción activa es lo que da acceso al Campus.

Los cuatro usan el mismo proyecto de Supabase (`mryuhzpenzpyhfidwsup`).

## Qué puede hacer cada alumno

- **Entrar** con email y contraseña. La cuenta no se crea desde el Campus: se crea cuando se registra su suscripción y le llega un email para crear la contraseña.
- **Mis cursos**: los cursos agrupados por Máster, en el orden del sitio, con su progreso y un acceso directo para seguir el último curso que empezó. Los cursos que su plan no incluye se ven, marcados "No incluido en tu plan", sin las clases.
- **Curso**: módulos y clases, con la duración y las clases terminadas. Botón para empezar o seguir con la próxima clase.
- **Clase**: el video, el texto de la clase, los materiales, "Marcar como terminada" (lleva a la clase siguiente) y la lista de clases del curso a un costado.
- **Mi cuenta**: qué incluye su acceso y hasta cuándo, el idioma y el cambio de contraseña.
- **Idioma**: español, inglés o portugués, con un selector siempre a la vista. El Campus arranca en el idioma del navegador; lo que elige la persona queda guardado en su cuenta.

## Quién ve qué

Lo decide la base de datos (RLS), no la pantalla:

| Cuenta | Cursos y módulos | Clases, videos y materiales |
|---|---|---|
| Suscripción anual activa | Todos los publicados | De todos los cursos, incluidos los de regalo |
| Máster suelto activo | Todos los publicados | Solo de los cursos de ese Máster |
| Suscripción dada de baja | Igual que antes | Hasta el fin del año pagado |
| Suscripción vencida o reembolsada, o sin suscripción | Todos los publicados | Ninguna. Ve el aviso "Tu suscripción no está activa" |
| Cuenta de Núcleo (`admins`) | Todos, también los borradores | Todas, también las no publicadas. Puede editar el contenido |

La suscripción se encuentra por el email: el de la cuenta tiene que coincidir con el de la persona en el CRM.

**Videos**: se suben a YouTube como **ocultos** (no listados) y en la clase se guarda solo el id del video (los 11 caracteres después de `v=`). El id solo llega a quien tiene acceso al curso, pero cualquiera que lo consiga puede ver el video en YouTube: ese es el límite de usar videos ocultos. Se reproducen desde `youtube-nocookie.com`. Si el video tiene subtítulos en inglés o portugués, se activan solos para quien usa el Campus en ese idioma.

## Contenido traducible

Todos los textos de cursos, módulos, clases y materiales son traducibles: en la base se guardan como `{"es": "...", "en": "...", "pt": "..."}`. El español es obligatorio; si falta otro idioma, el Campus muestra el español. Los nombres de los Másteres salen de la tabla `masters` del sitio (en español) y sus traducciones de `campus_masters`.

El texto de una clase usa el mismo formato que los textos largos del sitio: renglón vacío = párrafo nuevo, `## ` = título, `- ` = lista, `*texto*` = cursiva.

## Cómo está armado

| Pieza | Detalle |
|---|---|
| Interfaz | React 19 + TypeScript + Vite, igual que el CRM. Se publica en Netlify |
| Datos y login | Supabase, proyecto `mryuhzpenzpyhfidwsup` |
| Seguridad | RLS en cada tabla del Campus. Las clases solo llegan si la cuenta tiene acceso |
| Invitaciones | Edge Function `campus-acceso`, que llama el CRM al registrar un alta |
| Contenido | Se carga desde Núcleo → Cursos del Campus |
| Textos de la interfaz | `src/i18n/es.ts`, `en.ts` y `pt.ts`. Una prueba revisa que los tres tengan las mismas claves |

```
ava-campus/
├── index.html
├── netlify.toml               Publicación y seguridad del navegador (CSP)
├── public/                    Logo, íconos y robots.txt
├── src/
│   ├── auth/                  Sesión y acceso de quien entra
│   ├── components/            Menú, protecciones de ruta, progreso, texto de las clases
│   ├── i18n/                  Textos de la interfaz en español, inglés y portugués
│   ├── lib/                   Supabase, consultas, reglas del catálogo, YouTube y validaciones
│   ├── pages/                 Una pantalla por archivo
│   ├── styles/                Tokens de AVA (los del sitio y el CRM) y estilos del Campus
│   └── test/                  Configuración de las pruebas
└── supabase/
    ├── migrations/            Cambios de la base, en orden
    ├── functions/campus-acceso/  Edge Function de invitaciones al Campus
    └── tests/                 Prueba de acceso contra la base real
```

## Trabajar en tu computadora

Necesitás Node 22 o más nuevo.

```bash
npm install
cp .env.example .env.local
npm run dev
```

El Campus abre en `http://localhost:5174` (el CRM usa el 5173, así pueden andar los dos a la vez).

| Comando | Qué hace |
|---|---|
| `npm run dev` | Levanta el Campus en modo desarrollo |
| `npm run build` | Revisa los tipos y arma la versión para publicar en `dist/` |
| `npm run test` | Corre las pruebas automáticas |
| `npm run lint` | Revisa el código con ESLint |
| `npm run check` | Tipos, lint y pruebas juntos. Correlo antes de cada commit |

## Base de datos

Las tablas del Campus usan el prefijo `campus_` y las funciones internas viven en el schema `campus_private`. Ninguna migración del Campus toca tablas del sitio, de Núcleo ni del CRM.

| Tabla | Para qué |
|---|---|
| `campus_masters` | Traducciones del nombre y la descripción de cada Máster |
| `campus_courses` | Cursos: Máster (vacío = curso de regalo, solo para la suscripción anual), dirección (`slug`), título, resumen, orden y si está publicado |
| `campus_modules` | Módulos de cada curso, en orden |
| `campus_lessons` | Clases: título, texto, id del video de YouTube, duración, orden y si está publicada |
| `campus_lesson_resources` | Materiales de cada clase: nombre y link `https://` |
| `campus_progress` | Clases terminadas por cada cuenta |

Funciones:

- `campus_me()`: nombre, si es cuenta de Núcleo, si tiene la suscripción anual, qué Másteres sueltos tiene y hasta cuándo. Solo de la propia cuenta.
- `campus_course_lesson_counts()`: cuántas clases publicadas tiene cada curso, sin títulos ni videos.
- `campus_invite_target(suscripción)`: email y nombre de la persona de una suscripción. Solo para el equipo del CRM con "Gestionar suscripciones"; la usa la Edge Function.
- `campus_private.has_course_access(curso)` y `has_lesson_access(clase)`: las usan las políticas RLS.

### Probar los permisos

`supabase/tests/campus_fase1_acceso.sql` simula una suscripción anual, un Máster suelto, una baja vigente, una baja vencida, una suscripción vencida, la cuenta de Núcleo y un visitante anónimo (32 reglas). Termina con un error a propósito para que Postgres revierta todo. Correlo en el SQL Editor de Supabase: el mensaje tiene que decir `FALLAS: 0`.

## Edge Function `campus-acceso`

Acción `invitar` con `subscription_id` (y opcionalmente `locale`: `es`, `en` o `pt`). La llama el CRM al registrar un alta y con el botón "Invitar al Campus" de cada suscripción.

- La base revisa el permiso: quien llama tiene que ser del equipo del CRM con "Gestionar suscripciones".
- Si la persona ya tiene una cuenta activa en AVA, no manda nada: entra al Campus con su contraseña de siempre.
- Si no, le manda la invitación con el link a `CAMPUS_URL/definir-contrasena` y guarda el idioma en la cuenta.
- Registra cada invitación en la auditoría del CRM.

Para publicarla con la CLI: `supabase functions deploy campus-acceso`.

## Emails de Supabase

El proyecto de Supabase tiene una sola plantilla de cada email para el CRM, Núcleo y el Campus. Las de `supabase/templates/` cambian solas según la cuenta:

- `invitacion.html` ("Invite user"): a un alumno le llega la bienvenida al Campus en su idioma; a alguien del equipo, la invitación al CRM de siempre. Asunto: `Tu acceso a AVA · Your AVA access · Seu acesso à AVA`.
- `recuperar-contrasena.html` ("Reset password"): en el idioma del alumno; para el equipo y Núcleo, en español como antes.

Se pegan a mano en Supabase → Authentication → Emails → Templates. Las copias de `ava-crm/supabase/templates/` son las mismas.

## Estado

- Migración aplicada en Supabase (versión `20261001005016`) y prueba de permisos con `FALLAS: 0`.
- Edge Function `campus-acceso` publicada.
- CRM: la invitación sale sola al registrar un alta, y se puede mandar o reenviar desde cada suscripción.
- Núcleo: sección **Cursos del Campus** para cargar todo el contenido.

## Pendiente antes de abrir el Campus

Estos pasos se hacen desde los paneles de Netlify y Supabase; las herramientas de Claude no llegan a ellos.

1. **Publicar en Netlify**: Add new site → Import an existing project → `margintrainingsystems/ava-campus`. Netlify lee `netlify.toml`. Nombre del sitio: `ava-campus` (la dirección queda `https://ava-campus.netlify.app`) o conectar `campus.aprendeconava.com`. Si la dirección cambia, cargá `CAMPUS_URL` en los secretos de la Edge Function y actualizá las URLs de redirección.
2. **Supabase → Authentication → URL Configuration → Redirect URLs**: agregá `https://ava-campus.netlify.app/definir-contrasena` y `http://localhost:5174/definir-contrasena`.
3. **Supabase → Authentication → Emails → Templates**: pegá las dos plantillas de `supabase/templates/` (ver arriba).
4. **Sitio**: cargar el link del Campus en Núcleo → Contenido del sitio → Textos generales → Campus.
5. **Contenido**: subir los videos a YouTube como ocultos y cargar los cursos desde Núcleo → Campus.

## Hoja de ruta del Campus

| Fase | Entrega |
|---|---|
| 1 | Acceso por suscripción, cursos, módulos, clases con video, materiales, progreso, tres idiomas. **Hecha**, falta publicar en Netlify |
| 2 | Edición del contenido desde Núcleo (Cursos del Campus) e invitación desde el CRM. **Hecha** |
| 3 | Certificados por curso y por Máster, con QR de verificación en el sitio |
| 4 | Asistente virtual por curso y enlace a la comunidad de Discord por Máster |
