// Textos de la interfaz en español rioplatense, con voseo. Es el idioma base: en.ts y pt.ts
// tienen que tener exactamente las mismas claves (lo revisa una prueba automática).
// {nombre} entre llaves se reemplaza al mostrar el texto.
export const es = {
  // General
  'app.name': 'Campus',
  'app.loading': 'Cargando…',
  'app.skip': 'Saltar al contenido',
  'app.retry': 'Reintentar',
  'app.back': 'Volver',
  'app.language': 'Idioma',
  'app.signOut': 'Cerrar sesión',

  // Menú
  'nav.courses': 'Mis cursos',
  'nav.account': 'Mi cuenta',
  'nav.main': 'Menú principal',

  // Acceso
  'auth.email': 'Email',
  'auth.password': 'Contraseña',
  'auth.show': 'Mostrar',
  'auth.hide': 'Ocultar',
  'auth.login.title': 'Entrar al Campus',
  'auth.login.intro': 'Usá el email con el que te suscribiste a AVA.',
  'auth.login.submit': 'Entrar',
  'auth.login.busy': 'Entrando…',
  'auth.login.forgot': 'Olvidé mi contraseña',
  'auth.login.noAccount': '¿Todavía no tenés cuenta? Se crea sola cuando te suscribís: te llega un email para entrar.',
  'auth.forgot.title': 'Recuperar la contraseña',
  'auth.forgot.intro': 'Escribí tu email y te mandamos un link para crear una contraseña nueva.',
  'auth.forgot.submit': 'Enviar link',
  'auth.forgot.busy': 'Enviando…',
  'auth.forgot.sent':
    'Si el email corresponde a una cuenta, te llega un link para crear una contraseña nueva. Revisá también la carpeta de spam.',
  'auth.forgot.backToLogin': 'Volver a entrar',
  'auth.set.title': 'Creá tu contraseña',
  'auth.set.account': 'Cuenta: {email}',
  'auth.set.new': 'Contraseña nueva',
  'auth.set.repeat': 'Repetí la contraseña',
  'auth.set.help': 'Al menos {min} caracteres, con letras y números. No uses la misma contraseña de otro sitio.',
  'auth.set.submit': 'Guardar y entrar',
  'auth.set.busy': 'Guardando…',
  'auth.set.saved': 'Guardamos tu contraseña.',
  'auth.link.expired': 'El link venció o ya se usó.',
  'auth.link.invalid': 'El link no es válido.',
  'auth.link.needNew': 'Necesitás un link nuevo',
  'auth.link.help': 'Pedí un link nuevo con tu email. Si te acabás de suscribir y el link venció, escribinos.',
  'auth.link.request': 'Pedir un link nuevo',
  'auth.link.goLogin': 'Ir a entrar',
  'auth.loadError.title': 'No pudimos cargar tu cuenta',
  'auth.loadError.body': 'Revisá tu conexión a internet y probá de nuevo.',

  // Validaciones
  'validation.email': 'Revisá el email: tiene que ser una dirección válida, sin espacios.',
  'validation.passwordMissing': 'Escribí tu contraseña.',
  'validation.passwordShort': 'La contraseña necesita al menos {min} caracteres.',
  'validation.passwordMix': 'Usá letras y números en la contraseña.',
  'validation.passwordMatch': 'Las dos contraseñas no coinciden.',

  // Errores
  'error.generic': 'Algo salió mal. Probá de nuevo en unos minutos.',
  'error.network': 'No hay conexión con el servidor. Revisá tu internet y probá de nuevo.',
  'error.credentials': 'El email o la contraseña no coinciden.',
  'error.notConfirmed': 'Todavía no activaste tu cuenta. Buscá el email de bienvenida del Campus.',
  'error.rateLimit': 'Hiciste muchos intentos seguidos. Esperá unos minutos y probá de nuevo.',
  'error.emailRateLimit': 'Se enviaron muchos emails seguidos. Esperá unos minutos y probá de nuevo.',
  'error.samePassword': 'La contraseña nueva tiene que ser distinta de la anterior.',
  'error.weakPassword': 'Esa contraseña es muy fácil de adivinar o apareció en filtraciones. Elegí otra.',
  'error.session': 'Tu sesión venció. Volvé a entrar.',
  'error.banned': 'Esta cuenta está bloqueada.',
  'error.permission': 'No tenés acceso a este contenido.',
  'error.notFound': 'No encontramos lo que buscabas.',

  // Sin acceso
  'noAccess.title': 'Tu suscripción no está activa',
  'noAccess.body':
    'Tu cuenta existe, pero hoy no tiene una suscripción activa. Si acabás de pagar, puede tardar un rato en aparecer. Si creés que es un error, escribinos desde el sitio.',
  'noAccess.site': 'Ir al sitio de AVA',

  // Mis cursos
  'home.hello': 'Hola, {name}',
  'home.helloNoName': 'Hola',
  'home.intro': 'Elegí un curso para seguir donde lo dejaste.',
  'home.continue': 'Seguir con',
  'home.empty': 'Todavía no hay cursos publicados. Te avisamos por email apenas estén disponibles.',
  'home.gifts': 'Cursos de regalo',
  'home.giftsHelp': 'Exclusivos de la suscripción anual.',
  'home.locked': 'No incluido en tu plan',
  'home.draft': 'Borrador',
  'home.lessons': '{count} clases',
  'home.lessonsOne': '1 clase',
  'home.progress': '{done} de {total} clases terminadas',
  'home.done': 'Terminado',
  'home.start': 'Empezar',
  'home.resume': 'Seguir',
  'home.loadError': 'No pudimos cargar tus cursos.',

  // Curso
  'course.lessonsTitle': 'Contenido del curso',
  'course.continue': 'Seguir con la próxima clase',
  'course.start': 'Empezar el curso',
  'course.review': 'Repasar desde el principio',
  'course.completed': '¡Terminaste el curso!',
  'course.locked':
    'Este curso no está incluido en tu suscripción. Con la suscripción anual accedés a todos los cursos de AVA.',
  'course.empty': 'Este curso todavía no tiene clases.',
  'course.lessonDone': 'Terminada',
  'course.module': 'Módulo {n}',
  'course.notFound': 'No encontramos este curso.',
  'course.allCourses': 'Todos mis cursos',

  // Clase
  'lesson.video': 'Video de la clase: {title}',
  'lesson.noVideo': 'Esta clase no tiene video: es de lectura y práctica.',
  'lesson.resources': 'Materiales',
  'lesson.markDone': 'Marcar como terminada',
  'lesson.markUndone': 'Marcar como no terminada',
  'lesson.marked': 'Clase terminada. ¡Bien ahí!',
  'lesson.previous': 'Clase anterior',
  'lesson.next': 'Próxima clase',
  'lesson.backToCourse': 'Volver al curso',
  'lesson.notFound': 'No encontramos esta clase.',
  'lesson.draft': 'Esta clase todavía no está publicada: solo la ven las cuentas de Núcleo.',
  'lesson.subtitles': 'Si el video tiene subtítulos en tu idioma, se activan solos.',
  'lesson.outline': 'Clases del curso',

  // Cuenta
  'account.title': 'Mi cuenta',
  'account.email': 'Email de la cuenta',
  'account.access': 'Tu acceso',
  'account.plan': 'Suscripción anual: todos los Másteres y los cursos de regalo.',
  'account.masters': 'Másteres incluidos: {names}.',
  'account.staff': 'Cuenta de Núcleo: ves todo el contenido, también lo no publicado.',
  'account.until': 'Acceso hasta el {date}.',
  'account.languageHelp': 'El Campus se muestra en este idioma. Si un curso todavía no está traducido, lo ves en español.',
  'account.passwordTitle': 'Cambiar la contraseña',
  'account.passwordSaved': 'Cambiamos tu contraseña.',
  'account.passwordSubmit': 'Guardar la contraseña',

  // 404
  'notFound.title': 'Esta página no existe',
  'notFound.body': 'Puede que el link esté mal escrito o que el contenido se haya movido.',
} as const
