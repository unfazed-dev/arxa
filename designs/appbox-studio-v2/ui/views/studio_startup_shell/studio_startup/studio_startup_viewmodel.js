/// This is the business logic for studio_startup.
///
/// Role: the startup surface — boot ceremony. Reports boot progress and
/// gates the hand-off to the hub behind a manual trigger. Nothing
/// self-advances: the step frame comes from ?step=, the hand-off from
/// the trigger. Proceed stamps the session booted and honors the boot
/// guard's validated ?to return-to (default: the hub root).
///
/// Requirements:
/// 1. [Splashscreen is a surface, not a shell; advancement is
/// user-triggered, never implicit] — Q-v2-1
/// 2. [Boot guard with return-to; hub owns /] — R1, R3
/// (docs/plans/studio-v2-boot-sequence-wiring.md)
///
/// Relationships: studio_startup_facade_service.js -> this ->
/// studio_startup_view.tsx (+ its #progress Named Fragment);
/// ui/common/boot_guard_viewmodel.js supplies bootTarget/markBooted.
///
/// History: git log --follow -- ui/views/studio_startup_shell/studio_startup/studio_startup_viewmodel.js

export const surfaceId = 'studio_startup';
export const viewId = 'studio_startup_view';

import { shellProps } from '../studio_startup_shell_viewmodel.js';
import { bootProgress } from '../../../../services/studio_startup_services/facades/studio_startup_facade_service.js';
import { bootTarget, markBooted } from '../../../common/boot_guard_viewmodel.js';

const VIEW = 'ui/views/studio_startup_shell/studio_startup/studio_startup_view.html';

/** The proceed endpoint, carrying the validated return-to so the trigger
 *  lands where the guard bounced the session from. Bare when the target is
 *  the default hub root. */
const proceedHrefOf = (context) => {
  const to = bootTarget(context);
  return to === '/' ? '/startup/proceed' : `/startup/proceed?to=${encodeURIComponent(to)}`;
};

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
    proceedHref: proceedHrefOf(context),
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
    proceedHref: proceedHrefOf(context),
  });
};

/** The one thing that ends the ceremony. Q-v2-1: never implicit. Stamps the
 *  boot cookie and hands off to the guard-validated target (R3). */
/** @param {import('hono').Context} context @param {import('../../../../runtime/types').Helpers} helpers */
export const proceed = (context, helpers) => {
  markBooted(context);
  context.header('HX-Redirect', bootTarget(context));
  return context.body(null, 204);
};
