export const surfaceId = 'main.timer';

import { chrome } from '../main_shell_viewmodel.js';

const VIEW = 'ui/views/main_shell/timer/timer_view.html';

/** @param {import('hono').Context} c @param {import('../../../../runtime/types').Helpers} h */
export const page = (context, helpers) => {
  helpers.timers.start('rest', 30);
  return helpers.render(context, VIEW, { ...chrome('timer', helpers.translate(context)), remaining: 30 });
};

// The rung comes from the request (?rung=desktop) so the fragment re-renders
// the SAME rung's element the swap replaces — each factor variant mounts its
// own timer (rung-suffixed id), and the asking element names itself.
/** @param {import('hono').Context} c @param {import('../../../../runtime/types').Helpers} h */
export const tick = (context, helpers) =>
  helpers.render(context, `${VIEW}#tick`, {
    remaining: helpers.timers.remaining('rest'),
    rung: context.req.query('rung'),
  });

/** @param {import('hono').Context} c @param {import('../../../../runtime/types').Helpers} h */
export const extend = (context, helpers) => {
  helpers.timers.extend('rest', 15);
  return tick(context, helpers);
};

/** @param {import('hono').Context} c @param {import('../../../../runtime/types').Helpers} h */
export const skip = (context, helpers) => {
  helpers.timers.stop('rest');
  return tick(context, helpers);
};
