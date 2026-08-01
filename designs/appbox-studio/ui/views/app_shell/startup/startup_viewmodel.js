// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
export const surfaceId = 'app.startup';

import * as facade from '../../../../services/facades/app_facade.js';

const VIEW = 'ui/views/app_shell/startup/startup_view.html';

export const page = (c, h) =>
  h.render(c, VIEW, facade.startupContext(h.session(c).data, h.t(c), h.locale(c)));
