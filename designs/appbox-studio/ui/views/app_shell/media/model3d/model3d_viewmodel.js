// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
export const surfaceId = 'app.mediamodel3d';

import * as facade from '../../../../../services/facades/app_facade.js';

const VIEW = 'ui/views/app_shell/media/model3d/model3d_view.html';

export const page = (c, h) =>
  h.render(c, VIEW, { activeShell: 'app', tab: 'demos', playing: true, ...facade.embedContext(c) });

// Auto-rotate toggle as a server round-trip: the stage fragment re-renders
// with/without the auto-rotate attribute. Orbit is the component's own
// camera-controls — declarative, no island.
export const stage = (c, h) =>
  h.render(c, `${VIEW}#stage`, { playing: c.req.query('rotate') !== '0' });
