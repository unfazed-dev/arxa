// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
// App-shell routes — splash, startup, auth, demos, dashboard. Same
// [method, path, handler] shape as app.routes.js; wire by spreading into
// its default export next to intakeRoutes/designRoutes.
import * as splash from './splash/splash_viewmodel.js';
import * as startup from './startup/startup_viewmodel.js';
import * as auth from './auth/auth_viewmodel.js';
import * as demos from './demos/demos_viewmodel.js';
import * as dashboard from './dashboard/dashboard_viewmodel.js';
import * as credential from './credential/credential_viewmodel.js';
import * as config from './config/config_viewmodel.js';

export default [
  // app.splash — splash (auto-advances); app.startup — loading screen
  // (CSS progress, advances to /auth); app.access — desktop sign-in
  ['GET', '/splash', splash.page],
  ['GET', '/startup', startup.page],
  ['GET', '/auth', auth.page],
  ['POST', '/auth/signin', auth.signIn],

  // app.demos — index of the media-lab demo screens
  ['GET', '/demos', demos.page],

  // app.dashboard — needs-you strip, project grid, analytics, QR modal, wizard
  ['GET', '/dashboard', dashboard.page],
  ['POST', '/dashboard/gates/decide', dashboard.decide],
  ['POST', '/dashboard/projects', dashboard.createProject],

  // app.credentials — every key the generated app needs, one surface
  ['GET', '/credentials', credential.page],
  ['POST', '/credentials/set', credential.set],
  ['POST', '/credentials/unset', credential.unset],

  // app.config — targets/locale (config.json mirror), credentials summary, prefs
  ['GET', '/config', config.page],
  ['POST', '/config/set', config.set],
];
