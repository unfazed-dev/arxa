// appbox:provenance
// generator: app-box  licence: free  project: 662368770980
// Built with app-box (free tier) — https://appbox.dev
// App-shell routes — splash, auth, pairing, dashboard. Same
// [method, path, handler] shape as app.routes.js; wire by spreading into
// its default export next to intakeRoutes/designRoutes.
import * as splash from './splash/splash_viewmodel.js';
import * as auth from './auth/auth_viewmodel.js';
import * as pairing from './pairing/pairing_viewmodel.js';
import * as dashboard from './dashboard/dashboard_viewmodel.js';

export default [
  // app.splash — splash (auto-advances); app.access — desktop sign-in
  ['GET', '/splash', splash.page],
  ['GET', '/auth', auth.page],
  ['POST', '/auth/signin', auth.signIn],

  // app.pairing — the phone/tablet auth view
  ['GET', '/pair', pairing.page],
  ['POST', '/pair/confirm', pairing.confirm],

  // app.dashboard — needs-you strip, project grid, analytics, QR modal, wizard
  ['GET', '/dashboard', dashboard.page],
  ['POST', '/dashboard/gates/decide', dashboard.decide],
  ['POST', '/dashboard/projects', dashboard.createProject],
];
