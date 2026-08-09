// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
export const surfaceId = 'workspace.credentials';

import * as facade from '../../../../services/facades/app_facade.js';

const VIEW = 'ui/views/workspace_shell/credentials/credential_view.html';

export const page = (context, helpers) =>
  helpers.render(context, VIEW, {
    activeShell: 'workspace',
    prefs: helpers.prefs(context),
    project: facade.chromeProject(),
    ...facade.credentialsContext(helpers.session(context).data, helpers.translate(context)),
  });

// Save marks the key held (a boolean in session state — never the value) and
// 303s back, same seeded-mutation pattern as the dashboard gate decisions.
export const set = async (context, helpers) => {
  const form = await helpers.form(context);
  facade.setCredential(helpers.session(context).data, String(form.key || ''), String(form.value || ''));
  return context.redirect('/workspace/credentials', 303);
};

export const unset = async (context, helpers) => {
  const form = await helpers.form(context);
  facade.unsetCredential(helpers.session(context).data, String(form.key || ''));
  return context.redirect('/workspace/credentials', 303);
};
