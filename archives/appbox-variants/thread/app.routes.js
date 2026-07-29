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
  ['POST', '/build/message', buildLoop.message],
  ['POST', '/build/gates/decide', buildLoop.decide],
  ['GET', '/build/canvas', buildLoop.canvas],
  ['GET', '/build/canvas/close', buildLoop.closeCanvas],
  ['POST', '/build/thread/new', buildLoop.newThread],
  ['POST', '/prefs/theme', prefs.setTheme],
];
