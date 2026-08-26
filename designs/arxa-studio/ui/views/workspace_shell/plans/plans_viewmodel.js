// arxa:provenance
// generator: arxa  licence: free  project: 662368770980
// Built with arxa (free tier) — https://arxa.dev
export const surfaceId = 'workspace.plans';

import * as facade from '../../../../services/facades/app_facade.js';

const VIEW = 'ui/views/workspace_shell/plans/plans_view.html';

// Plans + mock checkout. Both lens params ride the query string — ?state=
// (signedout|free|entitled) and ?pay= (succeed|decline|cancel|error|timeout)
// — exactly the picker's seeded-lens pattern.
export const page = (context, helpers) =>
  helpers.render(context, VIEW, {
    activeShell: 'workspace',
    prefs: helpers.prefs(context),
    project: facade.chromeProject(),
    ...facade.plansContext(helpers.session(context).data, helpers.translate(context), helpers.locale(context), {
      state: context.req.query('state'),
      pay: context.req.query('pay'),
    }),
  });

// Sign-out flips the seeded session to signed-out and routes to /auth — the
// mirror of auth's "any input signs in". 303, so hx-boost follows it.
export const signOut = (context, helpers) => {
  facade.signOut(helpers.session(context).data);
  return context.redirect('/auth', 303);
};

// A seeded checkout attempt: the chosen outcome is persisted in the session
// and the 303 lands back on /workspace/plans, which renders that outcome's
// result panel — the whole journey drives by click, no URL hacking.
export const attemptCheckout = async (context, helpers) => {
  const form = await helpers.form(context);
  facade.attemptCheckout(helpers.session(context).data, String(form.outcome || ''), helpers.locale(context));
  return context.redirect('/workspace/plans', 303);
};

// The seeded PaymentSuccess applied to the account: session flips to the paid
// plan, 303 back to /workspace/plans which now renders the entitled lens.
export const applyCheckout = (context, helpers) => {
  facade.applyUpgrade(helpers.session(context).data, helpers.locale(context));
  return context.redirect('/workspace/plans', 303);
};
