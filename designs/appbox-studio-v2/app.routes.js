import * as hub from './ui/views/studio_application_hub/studio_application_hub_viewmodel.js';
import * as startup from './ui/views/studio_startup_shell/studio_startup/studio_startup_viewmodel.js';
import * as unknown from './ui/views/studio_unknown_shell/studio_unknown/studio_unknown_viewmodel.js';
import * as auth from './ui/views/studio_auth_shell/studio_auth/studio_auth_viewmodel.js';
import * as prefs from './ui/common/prefs_viewmodel.js';

// Landing route of each shell. Required and non-empty — the scaffolder cannot
// derive it, and a shell whose root is unknown gets an invented one.
export const shellRoots = {
  studio_application_hub: '/',
  studio_startup_shell: '/startup',
  studio_unknown_shell: '/unknown',
  studio_auth_shell: '/auth',
};

export default [
  ['GET', '/', hub.view],
  ['GET', '/startup', startup.view],
  ['GET', '/startup/progress', startup.progress],
  ['POST', '/startup/proceed', startup.proceed],
  ['GET', '/unknown', unknown.view],
  ['GET', '/auth', auth.view],
  ['POST', '/auth/sign-in', auth.signIn],
  ['POST', '/prefs/accent', prefs.setAccent],
];
