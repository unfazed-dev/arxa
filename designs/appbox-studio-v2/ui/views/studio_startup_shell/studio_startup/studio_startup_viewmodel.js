// Role: the startup surface — boot ceremony. Reports boot progress and gates
//   the hand-off to the hub behind a manual trigger. Nothing self-advances:
//   the step frame comes from ?step=, the hand-off from the trigger.
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
 *  structure, not a real boot, so every step state is reachable by hand:
 *  ?step=0 is the first step running, ?step=N freezes the Nth frame.
 *  With no ?step the ceremony renders landed, so the served default walks
 *  straight to the hand-off instead of dead-ending on a disabled trigger.
 *  bootProgress caps this against the step count. */
const ALL_STEPS = Number.MAX_SAFE_INTEGER;
const elapsedOf = (c) => {
  const n = Number(c.req.query('step'));
  return Number.isInteger(n) && n >= 0 ? n : ALL_STEPS;
};

/** @param {import('hono').Context} c @param {import('../../../../runtime/types').Helpers} h */
export const view = (c, h) => {
  const t = h.t(c);
  return h.render(c, VIEW, {
    ...chrome(t),
    build: t('buildIdentity'),
    title: t('startupTitle'),
    subtitle: t('startupSubtitle'),
    proceedLabel: t('startupProceed'),
    ...bootProgress(t, elapsedOf(c)),
    locale: h.locale(c),
  });
};

/** @param {import('hono').Context} c @param {import('../../../../runtime/types').Helpers} h */
export const progress = (c, h) => {
  const t = h.t(c);
  return h.render(c, `${VIEW}#progress`, {
    ...bootProgress(t, elapsedOf(c)),
    proceedLabel: t('startupProceed'),
  });
};

/** The one thing that ends the ceremony. Q-v2-1: never implicit. */
/** @param {import('hono').Context} c @param {import('../../../../runtime/types').Helpers} h */
export const proceed = (c, h) => {
  c.header('HX-Redirect', '/');
  return c.body(null, 204);
};
