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

import { shellProps } from '../studio_startup_shell_viewmodel.js';
import { bootProgress } from '../../../../services/studio_startup_services/facades/studio_startup_facade_service.js';

const VIEW = 'ui/views/studio_startup_shell/studio_startup/studio_startup_view.html';

/** ?step= drives the boot sequence during design review — the prototype carries
 *  structure, not a real boot, so every step state is reachable by hand:
 *  ?step=0 is the first step running, ?step=N freezes the Nth frame.
 *  With no ?step the ceremony renders landed, so the served default walks
 *  straight to the hand-off instead of dead-ending on a disabled trigger.
 *  bootProgress caps this against the step count. */
const ALL_STEPS = Number.MAX_SAFE_INTEGER;
const elapsedOf = (context) => {
  const stepNumber = Number(context.req.query('step'));
  return Number.isInteger(stepNumber) && stepNumber >= 0 ? stepNumber : ALL_STEPS;
};

/** @param {import('hono').Context} context @param {import('../../../../runtime/types').Helpers} helpers */
export const view = (context, helpers) => {
  const translate = helpers.translate(context);
  return helpers.render(context, VIEW, {
    ...shellProps(translate),
    build: translate('buildIdentity'),
    title: translate('startupTitle'),
    subtitle: translate('startupSubtitle'),
    proceedLabel: translate('startupProceed'),
    ...bootProgress(translate, elapsedOf(context)),
    locale: helpers.locale(context),
  });
};

/** @param {import('hono').Context} context @param {import('../../../../runtime/types').Helpers} helpers */
export const progress = (context, helpers) => {
  const translate = helpers.translate(context);
  return helpers.render(context, `${VIEW}#progress`, {
    ...bootProgress(translate, elapsedOf(context)),
    proceedLabel: translate('startupProceed'),
  });
};

/** The one thing that ends the ceremony. Q-v2-1: never implicit. */
/** @param {import('hono').Context} context @param {import('../../../../runtime/types').Helpers} helpers */
export const proceed = (context, helpers) => {
  context.header('HX-Redirect', '/');
  return context.body(null, 204);
};
