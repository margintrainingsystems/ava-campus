import type { Messages } from './types'

// Português do Brasil.
export const pt: Messages = {
  // Geral
  'app.name': 'Campus',
  'app.loading': 'Carregando…',
  'app.skip': 'Pular para o conteúdo',
  'app.retry': 'Tentar de novo',
  'app.back': 'Voltar',
  'app.language': 'Idioma',
  'app.signOut': 'Sair',

  // Menu
  'nav.courses': 'Meus cursos',
  'nav.account': 'Minha conta',
  'nav.main': 'Menu principal',

  // Acesso
  'auth.email': 'E-mail',
  'auth.password': 'Senha',
  'auth.show': 'Mostrar',
  'auth.hide': 'Ocultar',
  'auth.login.title': 'Entrar no Campus',
  'auth.login.intro': 'Use o e-mail com que você assinou a AVA.',
  'auth.login.submit': 'Entrar',
  'auth.login.busy': 'Entrando…',
  'auth.login.forgot': 'Esqueci minha senha',
  'auth.login.noAccount': 'Ainda não tem conta? Ela é criada quando você assina: você recebe um e-mail para entrar.',
  'auth.forgot.title': 'Recuperar a senha',
  'auth.forgot.intro': 'Digite seu e-mail e enviaremos um link para criar uma senha nova.',
  'auth.forgot.submit': 'Enviar link',
  'auth.forgot.busy': 'Enviando…',
  'auth.forgot.sent':
    'Se o e-mail corresponder a uma conta, você receberá um link para criar uma senha nova. Confira também a pasta de spam.',
  'auth.forgot.backToLogin': 'Voltar para entrar',
  'auth.set.title': 'Crie sua senha',
  'auth.set.account': 'Conta: {email}',
  'auth.set.new': 'Senha nova',
  'auth.set.repeat': 'Repita a senha',
  'auth.set.help': 'Pelo menos {min} caracteres, com letras e números. Não use a mesma senha de outro site.',
  'auth.set.submit': 'Salvar e entrar',
  'auth.set.busy': 'Salvando…',
  'auth.set.saved': 'Sua senha foi salva.',
  'auth.link.expired': 'O link expirou ou já foi usado.',
  'auth.link.invalid': 'O link não é válido.',
  'auth.link.needNew': 'Você precisa de um link novo',
  'auth.link.help': 'Peça um link novo com seu e-mail. Se você acabou de assinar e o link expirou, escreva para nós.',
  'auth.link.request': 'Pedir um link novo',
  'auth.link.goLogin': 'Ir para entrar',
  'auth.loadError.title': 'Não conseguimos carregar sua conta',
  'auth.loadError.body': 'Verifique sua conexão com a internet e tente de novo.',

  // Validações
  'validation.email': 'Confira o e-mail: ele precisa ser um endereço válido, sem espaços.',
  'validation.passwordMissing': 'Digite sua senha.',
  'validation.passwordShort': 'A senha precisa ter pelo menos {min} caracteres.',
  'validation.passwordMix': 'Use letras e números na senha.',
  'validation.passwordMatch': 'As duas senhas não coincidem.',

  // Erros
  'error.generic': 'Algo deu errado. Tente de novo em alguns minutos.',
  'error.network': 'Sem conexão com o servidor. Verifique sua internet e tente de novo.',
  'error.credentials': 'O e-mail ou a senha não conferem.',
  'error.notConfirmed': 'Você ainda não ativou sua conta. Procure o e-mail de boas-vindas do Campus.',
  'error.rateLimit': 'Muitas tentativas seguidas. Aguarde alguns minutos e tente de novo.',
  'error.emailRateLimit': 'Muitos e-mails enviados seguidos. Aguarde alguns minutos e tente de novo.',
  'error.samePassword': 'A senha nova precisa ser diferente da anterior.',
  'error.weakPassword': 'Essa senha é muito fácil de adivinhar ou apareceu em vazamentos. Escolha outra.',
  'error.session': 'Sua sessão expirou. Entre de novo.',
  'error.banned': 'Esta conta está bloqueada.',
  'error.permission': 'Você não tem acesso a este conteúdo.',
  'error.notFound': 'Não encontramos o que você procurava.',

  // Sem acesso
  'noAccess.title': 'Sua assinatura não está ativa',
  'noAccess.body':
    'Sua conta existe, mas hoje não tem uma assinatura ativa. Se você acabou de pagar, pode demorar um pouco para aparecer. Se acha que é um erro, escreva para nós pelo site.',
  'noAccess.site': 'Ir para o site da AVA',

  // Meus cursos
  'home.hello': 'Olá, {name}',
  'home.helloNoName': 'Olá',
  'home.intro': 'Escolha um curso para continuar de onde parou.',
  'home.continue': 'Continuar com',
  'home.empty': 'Ainda não há cursos publicados. Avisaremos por e-mail assim que estiverem disponíveis.',
  'home.gifts': 'Cursos de presente',
  'home.giftsHelp': 'Exclusivos da assinatura anual.',
  'home.locked': 'Não incluído no seu plano',
  'home.draft': 'Rascunho',
  'home.lessons': '{count} aulas',
  'home.lessonsOne': '1 aula',
  'home.progress': '{done} de {total} aulas concluídas',
  'home.done': 'Concluído',
  'home.start': 'Começar',
  'home.resume': 'Continuar',
  'home.loadError': 'Não conseguimos carregar seus cursos.',

  // Curso
  'course.lessonsTitle': 'Conteúdo do curso',
  'course.continue': 'Continuar com a próxima aula',
  'course.start': 'Começar o curso',
  'course.review': 'Revisar desde o início',
  'course.completed': 'Você concluiu o curso!',
  'course.locked':
    'Este curso não está incluído na sua assinatura. Com a assinatura anual você acessa todos os cursos da AVA.',
  'course.empty': 'Este curso ainda não tem aulas.',
  'course.lessonDone': 'Concluída',
  'course.module': 'Módulo {n}',
  'course.notFound': 'Não encontramos este curso.',
  'course.allCourses': 'Todos os meus cursos',

  // Aula
  'lesson.video': 'Vídeo da aula: {title}',
  'lesson.noVideo': 'Esta aula não tem vídeo: é de leitura e prática.',
  'lesson.resources': 'Materiais',
  'lesson.markDone': 'Marcar como concluída',
  'lesson.markUndone': 'Marcar como não concluída',
  'lesson.marked': 'Aula concluída. Muito bem!',
  'lesson.previous': 'Aula anterior',
  'lesson.next': 'Próxima aula',
  'lesson.backToCourse': 'Voltar ao curso',
  'lesson.notFound': 'Não encontramos esta aula.',
  'lesson.draft': 'Esta aula ainda não foi publicada: só as contas do Núcleo podem vê-la.',
  'lesson.subtitles': 'Se o vídeo tiver legendas no seu idioma, elas são ativadas automaticamente.',
  'lesson.outline': 'Aulas do curso',

  // Conta
  'account.title': 'Minha conta',
  'account.email': 'E-mail da conta',
  'account.access': 'Seu acesso',
  'account.plan': 'Assinatura anual: todos os Masters e os cursos de presente.',
  'account.masters': 'Masters incluídos: {names}.',
  'account.staff': 'Conta do Núcleo: você vê todo o conteúdo, inclusive o não publicado.',
  'account.until': 'Acesso até {date}.',
  'account.languageHelp': 'O Campus é exibido neste idioma. Se um curso ainda não estiver traduzido, você o verá em espanhol.',
  'account.passwordTitle': 'Alterar a senha',
  'account.passwordSaved': 'Sua senha foi alterada.',
  'account.passwordSubmit': 'Salvar a senha',

  // 404
  'notFound.title': 'Esta página não existe',
  'notFound.body': 'O link pode estar digitado errado ou o conteúdo pode ter mudado de lugar.',
}
