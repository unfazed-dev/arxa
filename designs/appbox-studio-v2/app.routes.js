import * as hub from './ui/views/studio_application_hub/studio_application_hub_viewmodel.js';
import * as startup from './ui/views/studio_startup_shell/studio_startup/studio_startup_viewmodel.js';
import * as prefs from './ui/common/prefs_viewmodel.js';

// Landing route of each shell. Required and non-empty — the scaffolder cannot
// derive it, and a shell whose root is unknown gets an invented one.
//
// Shells appear here as they land. Q-v2-5 cuts over ceremony shells one at a
// time behind explicit user validation, so unknown/auth/intake/design are
// absent rather than stubbed: an unbuilt shell is a disabled stage card in the
// hub registry, never a route that resolves to a placeholder.
export const shellRoots = {
  studio_application_hub: '/',
  studio_startup_shell: '/startup',
};

export default [
  ['GET', '/', hub.view],
  ['GET', '/startup', startup.view],
  ['GET', '/startup/progress', startup.progress],
  ['POST', '/startup/proceed', startup.proceed],
  ['POST', '/prefs/accent', prefs.setAccent],
];
