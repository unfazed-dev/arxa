// Role: the startup surface — boot ceremony. Polls boot progress and gates the
//   hand-off to the hub behind a manual trigger.
// Requirements: Q-v2-1 (splashscreen is a surface, not a shell; advancement is
//   user-triggered, never implicit).
// Relationships: studio_startup_facade_service.js -> this ->
//   studio_startup_view.tsx (+ its #progress Named Fragment).
// History: created for studio v2.

export const surfaceId = 'studio_startup';
export const viewId = 'studio_startup_view';

import { chrome } from '../studio_startup_shell_viewmodel.js';
import { bootProgress } from '../../../../services/studio_startup_services/facades/studio_startup_facade_service.js';

const VIEW = 'ui/views/studio_startup_shell/studio_startup/studio_startup_view.html';

/** ?step= drives the boot sequence during design review — the prototype carries
 *  structure, not a real boot, so every step state is reachable by hand. */
const elapsedOf = (c) => {
  const n = Number(c.req.query('step'));
  return Number.isInteger(n) && n >= 0 ? n : 0;
};

/** @param {import('hono').Context} c @param {import('../../../../runtime/types').Helpers} h */
export const view = (c, h) => {
  const t = h.t(c);
  return h.render(c, VIEW, {
    ...chrome(t),
    build: t('buildIdentity'),
    ...bootProgress(t, elapsedOf(c)),
    locale: h.locale(c),
  });
};

/** @param {import('hono').Context} c @param {import('../../../../runtime/types').Helpers} h */
export const progress = (c, h) =>
  h.render(c, `${VIEW}#progress`, bootProgress(h.t(c), elapsedOf(c)));

/** @param {import('hono').Context} c @param {import('../../../../runtime/types').Helpers} h */
export const proceed = (c, h) => {
  c.header('HX-Redirect', '/');
  return c.body(null, 204);
};
