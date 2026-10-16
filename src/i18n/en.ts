import type { Messages } from './types'

// Inglés de Estados Unidos. Revisado por una editora nativa (octubre de 2026): course, lesson,
// module y subscription; "AVA Campus" sin "the"; sin la palabra "Master", que en inglés suena a
// maestría universitaria.
export const en: Messages = {
  // General
  'app.name': 'Campus',
  'app.loading': 'Loading…',
  'app.skip': 'Skip to content',
  'app.retry': 'Try again',
  'app.back': 'Back',
  'app.language': 'Language',
  'app.languageButton': 'Language: {name} ({code})',
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
  'auth.login.title': 'Sign in to AVA Campus',
  'auth.login.intro': 'Enter the email you used to subscribe to AVA.',
  'auth.login.submit': 'Sign in',
  'auth.login.busy': 'Signing in…',
  'auth.login.forgot': 'Forgot your password?',
  'auth.login.noAccount':
    "Don't have an account yet? The AVA team sets one up when you subscribe and sends you your sign-in details.",
  'auth.forgot.title': 'Reset your password',
  'auth.forgot.intro': "Enter your email and we'll send you a link to create a new password.",
  'auth.forgot.submit': 'Send link',
  'auth.forgot.busy': 'Sending…',
  'auth.forgot.sent':
    "If there's an account with that email, we've sent you a link to reset your password. Don't see it? Check your spam folder.",
  'auth.forgot.noEmail':
    "If it doesn't arrive within a few minutes, contact us through the AVA website and we'll give you a new password.",
  'auth.forgot.backToLogin': 'Back to sign-in',
  'auth.set.title': 'Create your password',
  'auth.set.account': 'Account: {email}',
  'auth.set.new': 'New password',
  'auth.set.repeat': 'Confirm new password',
  'auth.set.ruleLength': 'At least {min} characters',
  'auth.set.ruleMix': 'A mix of letters and numbers',
  'auth.set.ruleMatch': 'Both passwords match',
  'auth.set.ruleOk': 'done',
  'auth.set.rulePending': 'not yet',
  'auth.set.tip': "Don't reuse a password from another site.",
  'auth.set.submit': 'Save and sign in',
  'auth.set.busy': 'Saving…',
  'auth.set.saved': 'Your password is all set.',
  'auth.first.title': 'Choose your password',
  'auth.first.intro':
    'Welcome to AVA! To keep your account safe, replace the password we gave you with one only you know.',
  'auth.link.expired': 'This link has expired or has already been used.',
  'auth.link.invalid': "This link isn't valid.",
  'auth.link.needNew': "You'll need a new link",
  'auth.link.help':
    'You can request a new one using your email address. If you just subscribed and your link expired, contact us.',
  'auth.link.request': 'Get a new link',
  'auth.link.goLogin': 'Sign in',
  'auth.loadError.title': "We couldn't load your account",
  'auth.loadError.body': 'Check your internet connection and try again.',

  // Validation
  'validation.email': 'Enter a valid email address with no spaces.',
  'validation.passwordMissing': 'Enter your password.',
  'validation.passwordShort': 'Your password needs to be at least {min} characters long.',
  'validation.passwordMix': 'Include both letters and numbers in your password.',
  'validation.passwordMatch': "Passwords don't match.",

  // Errors
  'error.generic': 'Something went wrong. Please try again in a few minutes.',
  'error.network': "We're having trouble connecting. Check your internet connection and try again.",
  'error.credentials': 'Incorrect email or password.',
  'error.notConfirmed': "You haven't activated your account yet. Check your inbox for the welcome email from AVA.",
  'error.rateLimit': 'Too many attempts. Please wait a few minutes and try again.',
  'error.emailRateLimit': "We can't send more emails right now. Please wait a few minutes and try again.",
  'error.samePassword': 'Your new password must be different from your current one.',
  'error.weakPassword':
    'That password is too easy to guess or has shown up in a data breach. Please choose a different one.',
  'error.reauth': 'For your security, sign out, sign back in, and change your password right away.',
  'error.session': 'Your session has expired. Please sign in again.',
  'error.banned': 'This account has been suspended.',
  'error.permission': "You don't have access to this content.",
  'error.notFound': "We couldn't find what you were looking for.",

  // No access
  'noAccess.title': "You don't have active access right now",
  'noAccess.body':
    "Your account and progress are still saved, but you can't access the courses right now. If you just paid, it can take a little while to show up. Think this is a mistake? Contact us through the AVA website.",
  'noAccess.site': 'Go to the AVA website',

  // My courses
  'home.hello': 'Hi, {name}',
  'home.helloNoName': 'Hi there',
  'home.intro': 'Choose a course and pick up right where you left off.',
  'home.continue': 'Continue learning',
  'home.empty': "No courses are available yet. We'll email you as soon as they're ready.",
  'home.gifts': 'Bonus courses',
  'home.giftsHelp': 'Exclusive to annual subscribers.',
  'home.locked': 'Not in your subscription',
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
  'course.continue': 'Resume course',
  'course.start': 'Start course',
  'course.review': 'Review from the beginning',
  'course.completed': "You've finished this course. Great work!",
  'course.locked': "This course isn't included in your subscription. The annual subscription unlocks every AVA course.",
  'course.empty': "This course doesn't have any lessons yet.",
  'course.lessonDone': 'Completed',
  'course.module': 'Module {n}',
  'course.notFound': "We couldn't find this course.",
  'course.allCourses': 'My courses',

  // Lesson
  'lesson.video': 'Lesson video: {title}',
  'lesson.loading': 'Loading lesson…',
  'lesson.noVideo': "This lesson has no video. It's all reading and practice.",
  'lesson.resources': 'Materials',
  'lesson.download': 'Download',
  'lesson.downloadBusy': 'Preparing…',
  'lesson.downloadNoAccess': "You don't have access to this material, or it's no longer available.",
  'lesson.downloadMissing': "We couldn't find this file. Let us know through the AVA website so we can fix it.",
  'lesson.openLink': 'Open',
  'lesson.newTab': '(opens in a new tab)',
  'lesson.markDone': 'Mark as complete',
  'lesson.markUndone': 'Mark as incomplete',
  'lesson.marked': 'Lesson complete. Nice work!',
  'lesson.previous': 'Previous lesson',
  'lesson.next': 'Next lesson',
  'lesson.backToCourse': 'Back to course',
  'lesson.notFound': "We couldn't find this lesson.",
  'lesson.draft': "This lesson isn't published yet. Only Núcleo accounts can see it.",
  'lesson.subtitles': "If subtitles are available in your language, they'll turn on automatically.",
  'lesson.outline': 'In this course',

  // File types of the materials
  'file.pdf': 'PDF',
  'file.docx': 'Word',
  'file.xlsx': 'Excel',
  'file.pptx': 'PowerPoint',
  'file.csv': 'CSV',
  'file.png': 'PNG image',
  'file.jpg': 'JPG image',
  'file.txt': 'Text',
  'file.other': 'File',
  'file.link': 'Link',

  // Account
  'account.title': 'My account',
  'account.email': 'Account email',
  'account.access': 'Your access',
  'account.accessPlanUntil': 'Access to every course until {date}',
  'account.accessPlanForever': 'Access to every course, with no end date',
  'account.accessPlanHelp': 'Includes all bonus courses.',
  'account.accessMasterUntil': 'Access to {name} until {date}',
  'account.accessMasterForever': 'Access to {name}, with no end date',
  'account.accessNoRenew': "This access doesn't renew automatically.",
  'account.accessLoadError': "We couldn't load your access details.",
  'account.staff': 'Núcleo account: you can see everything, including unpublished content.',
  'account.languageHelp':
    "AVA Campus will appear in this language. If a course hasn't been translated yet, you'll see it in Spanish.",
  'account.languageSaved': 'Saved to your account.',
  'account.languageError': "We couldn't save it to your account, but it's already set on this device.",
  'account.passwordTitle': 'Change your password',
  'account.passwordSaved': 'Your password has been updated.',
  'account.passwordSubmit': 'Update password',

  // 404
  'notFound.title': "This page doesn't exist",
  'notFound.body': 'The link might have a typo, or the page may have moved.',
}
