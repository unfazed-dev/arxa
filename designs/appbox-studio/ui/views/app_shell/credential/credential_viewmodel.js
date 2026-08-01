// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
export const surfaceId = 'app.credentials';

import * as facade from '../../../../services/facades/app_facade.js';

const VIEW = 'ui/views/app_shell/credential/credential_view.html';

export const page = (c, h) =>
  h.render(c, VIEW, { activeShell: 'app', ...facade.credentialsContext(h.session(c).data, h.t(c)) });

// Save marks the key held (a boolean in session state — never the value) and
// 303s back, same seeded-mutation pattern as the dashboard gate decisions.
export const set = async (c, h) => {
  const form = await h.form(c);
  facade.setCredential(h.session(c).data, String(form.key || ''), String(form.value || ''));
  return c.redirect('/credentials', 303);
};

export const unset = async (c, h) => {
  const form = await h.form(c);
  facade.unsetCredential(h.session(c).data, String(form.key || ''));
  return c.redirect('/credentials', 303);
};
