import * as mainShell from './ui/views/main_shell/main_shell_viewmodel.js';
import * as buildLoop from './ui/views/main_shell/build/loop/loop_viewmodel.js';
import * as prefs from './ui/common/prefs_viewmodel.js';

// Landing route of each tab. Required and non-empty — the scaffolder
// cannot derive it, and a tab whose root is unknown gets an invented one.
export const tabRoots = {
  intake: '/',
  design: '/design',
  build: '/build',
  flows: '/flows',
  ship: '/ship',
  access: '/access',
  workspace: '/workspace',
  first: '/first',
};

export default [
  ['GET', '/', mainShell.page],
  ['GET', '/build', buildLoop.page],
  ['GET', '/build/findings', buildLoop.findings],
  ['POST', '/build/gates/:gate/decision', buildLoop.decideGate],
  ['POST', '/build/run/start', buildLoop.startRun],
  ['POST', '/prefs/accent', prefs.setAccent],
  ['POST', '/prefs/theme', prefs.setTheme],
];
