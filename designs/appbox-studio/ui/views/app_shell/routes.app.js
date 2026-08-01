// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
// App-shell routes — the studio's own chrome: splash (auto-advances), auth,
// dashboard. Same [method, path, handler] shape as app.routes.js; wire by
// spreading into its default export next to intakeRoutes/designRoutes.
import * as splash from './splash/splash_viewmodel.js';
import * as startup from './startup/startup_viewmodel.js';
import * as auth from './auth/auth_viewmodel.js';
import * as dashboard from './dashboard/dashboard_viewmodel.js';

export default [
  // The studio home: root lands on the dashboard.
  ['GET', '/', dashboard.root],
  // app.splash — splash (auto-advances to startup); app.startup — loading;
  // app.access — desktop sign-in
  ['GET', '/splash', splash.page],
  ['GET', '/startup', startup.page],
  ['GET', '/auth', auth.page],
  ['POST', '/auth/signin', auth.signIn],

  // app.dashboard — needs-you strip, LIVE ~/.appbox project grid, analytics,
  // QR modal, wizard
  ['GET', '/dashboard', dashboard.page],
  ['POST', '/dashboard/gates/decide', dashboard.decide],
  ['POST', '/dashboard/projects', dashboard.createProject],
  ['POST', '/dashboard/projects/use', dashboard.useProject],
];
