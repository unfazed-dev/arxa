/// This is the business logic for studio_auth.
///
/// Role: the auth surface — credentials ceremony. Renders the v1
/// auth-card contract: ?state= (signup|expired) swaps headline/lede/
/// note; the form and the seeded providers stay identical. The POST is
/// a design-medium simulation: any input signs in, the handler
/// acknowledges and routes home — no credential state exists in a
/// fixture.
///
/// Requirements:
/// 1. [Ceremony: consumes session, produces credentials; per-shell
///    manual trigger to proceed] — Q-v2-1
/// 2. [Ceremony shells route bare — never boot-guarded] — R1-R4
/// 3. [Seeded sign-in: any input signs in] — v1 auth contract
///
/// Relationships: studio_auth_facade_service.js -> this ->
/// studio_auth_view.tsx; app.routes.js mounts view + signin.
///
/// History: git log --follow -- ui/views/studio_auth_shell/studio_auth/studio_auth_viewmodel.js

export const surfaceId = 'studio_auth';
export const viewId = 'studio_auth_view';

import { shellProps } from '../studio_auth_shell_viewmodel.js';
import { authContext } from '../../../../services/studio_auth_services/facades/studio_auth_facade_service.js';

const VIEW = 'ui/views/studio_auth_shell/studio_auth/studio_auth_view.html';

/** ?state= selects the card's copy set during design review; the default
 *  is the plain sign-in. Unknown states fall back to default — a typo in
 *  the query never 500s a ceremony. */
const stateOf = (context) => {
  const state = context.req.query('state');
  return state === 'signup' || state === 'expired' ? state : 'default';
};

/** @param {import('hono').Context} context @param {import('../../../../runtime/types').Helpers} helpers */
export const view = (context, helpers) => {
  const translate = helpers.translate(context);
  return helpers.render(context, VIEW, {
    ...shellProps(translate),
    title: translate('authTitle'),
    emailLabel: translate('authEmail'),
    passwordLabel: translate('authPassword'),
    signinLabel: translate('authSignin'),
    orLabel: translate('authOr'),
    auth: authContext(stateOf(context)),
    locale: helpers.locale(context),
  });
};

/** Seeded sign-in. Design medium: acknowledge and route home — the boot
 *  guard takes over from there (an un-booted session bounces to the
 *  startup ceremony, exactly the ceremony order R1 prescribes). */
/** @param {import('hono').Context} context @param {import('../../../../runtime/types').Helpers} helpers */
export const signin = (context, helpers) => context.redirect('/', 303);
