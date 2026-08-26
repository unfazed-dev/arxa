/// This is the business logic for studio_splash.
///
/// Role: the splash surface — brand only. No boot step logic, no
/// trigger, no state: the splash paints and the startup ceremony takes
/// over (Q-v2-1: splashscreen is a surface, not a shell).
///
/// Requirements:
/// 1. [Splashscreen is a surface, not a shell] — Q-v2-1
/// 2. [Roster law: the splash role] — emit_structure app-shell roster
///
/// Relationships: studio_startup_shell_view.tsx frames this; app.routes.js
/// mounts view.
///
/// History: git log --follow -- ui/views/studio_startup_shell/splash/studio_splash_viewmodel.js

export const surfaceId = 'studio_splash';
export const viewId = 'studio_splash_view';

import { shellProps } from '../studio_startup_shell_viewmodel.js';

const VIEW = 'ui/views/studio_startup_shell/splash/studio_splash_view.html';

/** @param {import('hono').Context} context @param {import('../../../../runtime/types').Helpers} helpers */
export const view = (context, helpers) => {
  const translate = helpers.translate(context);
  return helpers.render(context, VIEW, {
    ...shellProps(translate),
    wordmark: translate('appTitle'),
    locale: helpers.locale(context),
  });
};
