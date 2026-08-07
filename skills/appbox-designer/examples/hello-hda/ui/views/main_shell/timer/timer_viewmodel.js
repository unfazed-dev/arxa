export const surfaceId = 'main.timer';

import { chrome } from '../main_shell_viewmodel.js';

const VIEW = 'ui/views/main_shell/timer/timer_view.html';

/** @param {import('hono').Context} c @param {import('../../../../runtime/types').Helpers} h */
export const page = (c, h) => {
  h.timers.start('rest', 30);
  return h.render(c, VIEW, { ...chrome('timer', h.t(c)), remaining: 30 });
};

/** @param {import('hono').Context} c @param {import('../../../../runtime/types').Helpers} h */
export const tick = (c, h) =>
  h.render(c, `${VIEW}#tick`, { remaining: h.timers.remaining('rest') });

/** @param {import('hono').Context} c @param {import('../../../../runtime/types').Helpers} h */
export const extend = (c, h) => {
  h.timers.extend('rest', 15);
  return tick(c, h);
};

/** @param {import('hono').Context} c @param {import('../../../../runtime/types').Helpers} h */
export const skip = (c, h) => {
  h.timers.stop('rest');
  return h.render(c, `${VIEW}#tick`, { remaining: 0 });
};
