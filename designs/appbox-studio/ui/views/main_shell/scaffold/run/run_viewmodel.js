// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
export const surfaceId = 'scaffold.run';

import * as facade from '../../../../../services/facades/scaffold_run_facade.js';

const VIEW = 'ui/views/main_shell/scaffold/run/run_view.html';

/** The template reads `c.*`; the facade builds it, the viewmodel wraps it. */
const ctx = (c, h, screen) => ({
  activeShell: 'scaffold',
  c: facade.context(h.session(c).data, h.t(c), h.locale(c), screen || c.req.query('state') || 'completed'),
});

// The receipt is a READ surface: ?state= picks which recorded outcome is being
// read. There is deliberately no POST that "starts" a run here — the scaffold
// is a synchronous deterministic transform (D24), so arriving with a result IS
// the event. Nothing on this screen polls, ticks, or animates.
export const page = (c, h) => h.render(c, VIEW, ctx(c, h));

// Panel width grip: s/m/l persisted per side, whole-panel re-render.
export const panelSize = (c, h) =>
  h.render(c, `${VIEW}#panelsSwap`, {
    activeShell: 'scaffold',
    c: facade.setPanelSize(
      h.session(c).data,
      c.req.param('panel'),
      c.req.param('size'),
      h.t(c),
      h.locale(c),
      c.req.query('state') || 'completed',
    ),
  });
