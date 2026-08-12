import * as dashboard from './ui/views/studio_dashboard_shell/studio_dashboard/studio_dashboard_viewmodel.js';
import * as startup from './ui/views/studio_startup_shell/studio_startup/studio_startup_viewmodel.js';
import * as unknown from './ui/views/studio_unknown_shell/studio_unknown/studio_unknown_viewmodel.js';
import * as preferences from './ui/common/preferences_viewmodel.js';

// Landing route of each shell. Required and non-empty — the scaffolder cannot
// derive it, and a shell whose root is unknown gets an invented one.
//
// Shells appear here as they land. Q-v2-5 cuts over ceremony shells one at a
// time behind explicit user validation, so auth/intake/design are
// absent rather than stubbed: an unbuilt shell is a disabled stage card in the
// dashboard registry, never a route that resolves to a placeholder.
export const shellRoots = {
  studio_dashboard_shell: '/',
  studio_startup_shell: '/startup',
  studio_unknown_shell: '/unknown',
};

export default [
  ['GET', '/', dashboard.view],
  ['POST', '/gates/decide', dashboard.decideGate],
  ['POST', '/projects/use', dashboard.useProject],
  ['POST', '/projects/create', dashboard.createProject],
  ['GET', '/startup', startup.view],
  ['GET', '/unknown', unknown.view],
  ['GET', '/startup/progress', startup.progress],
  ['POST', '/startup/proceed', startup.proceed],
  ['POST', '/preferences/accent', preferences.setAccent],
];
