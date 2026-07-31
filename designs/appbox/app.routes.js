// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
import * as mainShell from './ui/views/main_shell/main_shell_viewmodel.js';
import * as buildLoop from './ui/views/main_shell/build/loop/loop_viewmodel.js';
import * as settings from './ui/views/workspace_shell/settings/settings_viewmodel.js';
import * as prefs from './ui/common/prefs_viewmodel.js';
import intakeRoutes from './ui/views/main_shell/intake/routes.intake.js';
import designRoutes from './ui/views/main_shell/design/routes.design.js';
import appRoutes from './ui/views/app_shell/routes.app.js';

// Landing route of each shell. Required and non-empty — the scaffolder
// cannot derive it, and a shell whose root is unknown gets an invented one.
// Only shells with authored surfaces are listed; declared-but-undesigned
// shells (flows, ship, first) return here once they have a landing screen.
export const shellRoots = {
  intake: '/intake',
  design: '/design',
  build: '/build',
  app: '/dashboard',
  workspace: '/workspace',
};

export default [
  ['GET', '/', mainShell.page],
  ...appRoutes,
  ...intakeRoutes,
  ...designRoutes,
  ['GET', '/build', buildLoop.page],
  ['GET', '/build/panel', buildLoop.panel],
  ['GET', '/build/panel/size/:side/:size', buildLoop.panelSize],
  ['POST', '/build/run/control', buildLoop.runControl],
  ['GET', '/build/artifact/:kind/:id', buildLoop.artifact],
  ['GET', '/build/file', buildLoop.file],
  ['GET', '/build/artifact/evidence/surfaces/viewer', buildLoop.evidenceViewer],
  ['GET', '/build/screens/:surface', buildLoop.screenStub],
  ['POST', '/build/artifact/:kind/:id/messages', buildLoop.askArtifact],
  ['POST', '/build/stages/:id/control', buildLoop.stageControl],
  ['POST', '/build/messages', buildLoop.sendMessage],
  ['POST', '/build/gates/decide', buildLoop.decide],
  ['GET', '/build/model/:id', buildLoop.model],
  ['GET', '/build/chips/pin', buildLoop.pinChip],
  ['GET', '/build/chips/unpin', buildLoop.unpinChip],
  ['GET', '/workspace', settings.page],
  ['POST', '/prefs/accent', prefs.setAccent],
  ['POST', '/prefs/theme', prefs.setTheme],
  ['POST', '/prefs/jargon', prefs.setJargon],
];
