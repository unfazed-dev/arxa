// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
export const surfaceId = 'app.config';

import * as facade from '../../../../services/facades/app_facade.js';

const VIEW = 'ui/views/app_shell/config/config_view.html';

export const page = (c, h) =>
  h.render(c, VIEW, {
    activeShell: 'app',
    tab: 'config',
    ...facade.embedContext(c),
    ...facade.configContext(h.session(c).data, h.t(c), h.prefs(c)),
  });

// App-config choices persist in session state (the prototype's stand-in for
// config/appbox.config.json) and 303 back, same seeded-mutation pattern as
// the credentials surface.
export const set = async (c, h) => {
  const form = await h.form(c);
  facade.setConfig(h.session(c).data, form);
  return c.redirect('/config', 303);
};
