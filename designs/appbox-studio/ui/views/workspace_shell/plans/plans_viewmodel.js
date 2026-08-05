// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
export const surfaceId = 'workspace.plans';

import * as facade from '../../../../services/facades/app_facade.js';

const VIEW = 'ui/views/workspace_shell/plans/plans_view.html';

// Plans + mock checkout. Both lens params ride the query string — ?state=
// (signedout|free|entitled) and ?pay= (succeed|decline|cancel|error|timeout)
// — exactly the picker's seeded-lens pattern.
export const page = (c, h) =>
  h.render(c, VIEW, {
    activeShell: 'workspace',
    prefs: h.prefs(c),
    project: facade.chromeProject(),
    ...facade.plansContext(h.session(c).data, h.t(c), h.locale(c), {
      state: c.req.query('state'),
      pay: c.req.query('pay'),
    }),
  });

// Sign-out flips the seeded session to signed-out and routes to /auth — the
// mirror of auth's "any input signs in". 303, so hx-boost follows it.
export const signOut = (c, h) => {
  facade.signOut(h.session(c).data);
  return c.redirect('/auth', 303);
};

// The seeded PaymentSuccess applied to the account: session flips to the paid
// plan, 303 back to /workspace/plans which now renders the entitled lens.
export const applyCheckout = (c, h) => {
  facade.applyUpgrade(h.session(c).data, h.locale(c));
  return c.redirect('/workspace/plans', 303);
};
