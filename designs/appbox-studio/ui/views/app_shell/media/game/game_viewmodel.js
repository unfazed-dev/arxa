// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
export const surfaceId = 'app.mediagame';

import * as facade from '../../../../../services/facades/app_facade.js';

const VIEW = 'ui/views/app_shell/media/game/game_view.html';

export const page = (c, h) =>
  h.render(c, VIEW, { activeShell: 'app', tab: 'demos', ...facade.embedContext(c) });
