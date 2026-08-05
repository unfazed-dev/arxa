// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
import * as buildLoop from './ui/views/main_shell/build/loop/loop_viewmodel.js';
import * as settings from './ui/views/workspace_shell/settings/settings_viewmodel.js';
import * as credentials from './ui/views/workspace_shell/credentials/credential_viewmodel.js';
import * as config from './ui/views/workspace_shell/config/config_viewmodel.js';
import * as plans from './ui/views/workspace_shell/plans/plans_viewmodel.js';
import * as prefs from './ui/common/prefs_viewmodel.js';
import intakeRoutes from './ui/views/main_shell/intake/routes.intake.js';
import designRoutes from './ui/views/main_shell/design/routes.design.js';
import scaffoldRoutes from './ui/views/main_shell/scaffold/routes.scaffold.js';
import appRoutes from './ui/views/app_shell/routes.app.js';

// Landing route of each shell. Required and non-empty — the scaffolder
// cannot derive it, and a shell whose root is unknown gets an invented one.
// Only shells with authored surfaces are listed; declared-but-undesigned
// shells (flows, ship, first) return here once they have a landing screen.
export const shellRoots = {
  intake: '/intake',
  design: '/design',
  scaffold: '/scaffold',
  build: '/build',
  app: '/dashboard',
  workspace: '/workspace',
};

export default [
  ...appRoutes,
  ...intakeRoutes,
  ...designRoutes,
  ...scaffoldRoutes,
  ['GET', '/build', buildLoop.page],
  ['GET', '/build/panel', buildLoop.panel],
  ['GET', '/build/panel/size/:side/:size', buildLoop.panelSize],
  ['POST', '/build/run/control', buildLoop.runControl],
  ['GET', '/build/artifact/:kind/:id', buildLoop.artifact],
  ['GET', '/build/file', buildLoop.file],
  ['GET', '/build/artifact/evidence/surfaces/viewer', buildLoop.evidenceViewer],
  ['GET', '/build/screens/:surface', buildLoop.screenStub],
  ['POST', '/build/stages/:id/control', buildLoop.stageControl],
  ['POST', '/build/messages', buildLoop.sendMessage], // posted-by: c.composerAction (build_facade)
  ['POST', '/build/gates/decide', buildLoop.decide],
  ['GET', '/build/model/:id', buildLoop.model],
  ['GET', '/build/chips/pin', buildLoop.pinChip],
  ['GET', '/build/chips/unpin', buildLoop.unpinChip],
  ['GET', '/workspace', settings.page],
  // workspace.credentials — every key the generated app needs, one surface
  ['GET', '/workspace/credentials', credentials.page],
  ['POST', '/workspace/credentials/set', credentials.set],
  ['POST', '/workspace/credentials/unset', credentials.unset],
  // workspace.config — targets/locale (config.json mirror), credentials summary, prefs
  ['GET', '/workspace/config', config.page],
  ['POST', '/workspace/config/set', config.set],
  // workspace.plans — pricing + entitlement state, with the seeded mock
  // checkout (five outcomes mirroring kit/payments). Sign-out flips the
  // seeded session and routes to /auth; checkout/apply is the seeded
  // PaymentSuccess applied to the account.
  ['GET', '/workspace/plans', plans.page],
  ['POST', '/workspace/plans/signout', plans.signOut],
  ['POST', '/workspace/plans/checkout/apply', plans.applyCheckout],
  ['POST', '/prefs/accent', prefs.setAccent],
  ['POST', '/prefs/font', prefs.setFont],
  ['POST', '/prefs/theme', prefs.setTheme],
  ['POST', '/prefs/jargon', prefs.setJargon],
];
