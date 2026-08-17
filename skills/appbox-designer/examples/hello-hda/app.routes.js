import * as home from './ui/views/main_shell/home/home_viewmodel.js';
import * as timer from './ui/views/main_shell/timer/timer_viewmodel.js';
import * as prefs from './ui/common/prefs_viewmodel.js';

// Landing route of each shell. Required and non-empty — the scaffolder
// cannot derive it, and a shell whose root is unknown gets an invented one.
export const shellRoots = {
  main: '/',
};

export default [
  ['GET', '/', home.page],
  ['GET', '/timer', timer.page],
  ['GET', '/timer/tick', timer.tick],
  ['POST', '/timer/extend', timer.extend], // posted-by: ActionButton (timer_view.sections.tsx) — hx attrs ride widget props
  ['POST', '/timer/skip', timer.skip], // posted-by: ActionButton (timer_view.sections.tsx) — hx attrs ride widget props
  ['POST', '/prefs/accent', prefs.setAccent], // posted-by: HxForm (home_view.sections.tsx) — hx attrs ride widget props
];
