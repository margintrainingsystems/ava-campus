import type { Messages } from './types'

export const en: Messages = {
  // General
  'app.name': 'Campus',
  'app.loading': 'Loading…',
  'app.skip': 'Skip to content',
  'app.retry': 'Try again',
  'app.back': 'Back',
  'app.language': 'Language',
  'app.signOut': 'Sign out',

  // Menu
  'nav.courses': 'My courses',
  'nav.account': 'My account',
  'nav.main': 'Main menu',

  // Access
  'auth.email': 'Email',
  'auth.password': 'Password',
  'auth.show': 'Show',
  'auth.hide': 'Hide',
  'auth.login.title': 'Sign in to the Campus',
  'auth.login.intro': 'Use the email you subscribed to AVA with.',
  'auth.login.submit': 'Sign in',
  'auth.login.busy': 'Signing in…',
  'auth.login.forgot': 'I forgot my password',
  'auth.login.noAccount': "Don't have an account yet? It's created when you subscribe: you'll get an email to sign in.",
  'auth.forgot.title': 'Reset your password',
  'auth.forgot.intro': "Enter your email and we'll send you a link to create a new password.",
  'auth.forgot.submit': 'Send link',
  'auth.forgot.busy': 'Sending…',
  'auth.forgot.sent':
    "If the email belongs to an account, you'll get a link to create a new password. Check your spam folder too.",
  'auth.forgot.backToLogin': 'Back to sign in',
  'auth.set.title': 'Create your password',
  'auth.set.account': 'Account: {email}',
  'auth.set.new': 'New password',
  'auth.set.repeat': 'Repeat the password',
  'auth.set.help': "At least {min} characters, with letters and numbers. Don't reuse a password from another site.",
  'auth.set.submit': 'Save and sign in',
  'auth.set.busy': 'Saving…',
  'auth.set.saved': 'Your password was saved.',
  'auth.link.expired': 'The link expired or was already used.',
  'auth.link.invalid': 'The link is not valid.',
  'auth.link.needNew': 'You need a new link',
  'auth.link.help': 'Request a new link with your email. If you just subscribed and the link expired, write to us.',
  'auth.link.request': 'Request a new link',
  'auth.link.goLogin': 'Go to sign in',
  'auth.loadError.title': "We couldn't load your account",
  'auth.loadError.body': 'Check your internet connection and try again.',

  // Validation
  'validation.email': 'Check the email: it must be a valid address, without spaces.',
  'validation.passwordMissing': 'Enter your password.',
  'validation.passwordShort': 'The password needs at least {min} characters.',
  'validation.passwordMix': 'Use letters and numbers in the password.',
  'validation.passwordMatch': "The two passwords don't match.",

  // Errors
  'error.generic': 'Something went wrong. Try again in a few minutes.',
  'error.network': "Can't reach the server. Check your internet and try again.",
  'error.credentials': "The email or password doesn't match.",
  'error.notConfirmed': "You haven't activated your account yet. Look for the Campus welcome email.",
  'error.rateLimit': 'Too many attempts in a row. Wait a few minutes and try again.',
  'error.emailRateLimit': 'Too many emails were sent in a row. Wait a few minutes and try again.',
  'error.samePassword': 'The new password must be different from the previous one.',
  'error.weakPassword': 'That password is too easy to guess or appeared in data leaks. Choose another one.',
  'error.session': 'Your session expired. Sign in again.',
  'error.banned': 'This account is blocked.',
  'error.permission': "You don't have access to this content.",
  'error.notFound': "We couldn't find what you were looking for.",

  // No access
  'noAccess.title': 'Your subscription is not active',
  'noAccess.body':
    "Your account exists, but it doesn't have an active subscription today. If you just paid, it may take a while to show up. If you think this is a mistake, write to us from the website.",
  'noAccess.site': 'Go to the AVA website',

  // My courses
  'home.hello': 'Hi, {name}',
  'home.helloNoName': 'Hi',
  'home.intro': 'Pick a course to continue where you left off.',
  'home.continue': 'Continue with',
  'home.empty': "There are no published courses yet. We'll email you as soon as they're available.",
  'home.gifts': 'Bonus courses',
  'home.giftsHelp': 'Exclusive to the annual subscription.',
  'home.locked': 'Not included in your plan',
  'home.draft': 'Draft',
  'home.lessons': '{count} lessons',
  'home.lessonsOne': '1 lesson',
  'home.progress': '{done} of {total} lessons completed',
  'home.done': 'Completed',
  'home.start': 'Start',
  'home.resume': 'Continue',
  'home.loadError': "We couldn't load your courses.",

  // Course
  'course.lessonsTitle': 'Course content',
  'course.continue': 'Continue with the next lesson',
  'course.start': 'Start the course',
  'course.review': 'Review from the beginning',
  'course.completed': 'You finished the course!',
  'course.locked':
    "This course isn't included in your subscription. The annual subscription gives you access to every AVA course.",
  'course.empty': "This course doesn't have lessons yet.",
  'course.lessonDone': 'Completed',
  'course.module': 'Module {n}',
  'course.notFound': "We couldn't find this course.",
  'course.allCourses': 'All my courses',

  // Lesson
  'lesson.video': 'Lesson video: {title}',
  'lesson.noVideo': "This lesson doesn't have a video: it's for reading and practice.",
  'lesson.resources': 'Materials',
  'lesson.markDone': 'Mark as completed',
  'lesson.markUndone': 'Mark as not completed',
  'lesson.marked': 'Lesson completed. Nice work!',
  'lesson.previous': 'Previous lesson',
  'lesson.next': 'Next lesson',
  'lesson.backToCourse': 'Back to the course',
  'lesson.notFound': "We couldn't find this lesson.",
  'lesson.draft': "This lesson isn't published yet: only Núcleo accounts can see it.",
  'lesson.subtitles': 'If the video has subtitles in your language, they turn on automatically.',
  'lesson.outline': 'Course lessons',

  // Account
  'account.title': 'My account',
  'account.email': 'Account email',
  'account.access': 'Your access',
  'account.plan': 'Annual subscription: every Master and the bonus courses.',
  'account.masters': 'Included Masters: {names}.',
  'account.staff': 'Núcleo account: you see all content, including unpublished content.',
  'account.until': 'Access until {date}.',
  'account.languageHelp': "The Campus is shown in this language. If a course isn't translated yet, you'll see it in Spanish.",
  'account.passwordTitle': 'Change your password',
  'account.passwordSaved': 'Your password was changed.',
  'account.passwordSubmit': 'Save password',

  // 404
  'notFound.title': "This page doesn't exist",
  'notFound.body': 'The link may be mistyped or the content may have moved.',
}
