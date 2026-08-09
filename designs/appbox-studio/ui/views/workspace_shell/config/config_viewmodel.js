// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
export const surfaceId = 'workspace.config';

import * as facade from '../../../../services/facades/app_facade.js';

const VIEW = 'ui/views/workspace_shell/config/config_view.html';

export const page = (context, helpers) =>
  helpers.render(context, VIEW, {
    activeShell: 'workspace',
    prefs: helpers.prefs(context),
    project: facade.chromeProject(),
    ...facade.configContext(helpers.session(context).data, helpers.translate(context), helpers.prefs(context)),
  });

// App-config choices persist in session state (the prototype's stand-in for
// config/appbox.config.json) and 303 back, same seeded-mutation pattern as
// the credentials surface.
export const set = async (context, helpers) => {
  const form = await helpers.form(context);
  facade.setConfig(helpers.session(context).data, form);
  return context.redirect('/workspace/config', 303);
};
