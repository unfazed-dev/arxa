// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
export const surfaceId = 'scaffold.run';

import * as facade from '../../../../../services/facades/scaffold_run_facade.js';

const VIEW = 'ui/views/main_shell/scaffold/run/run_view.html';

/** The template reads `context.*`, and the renderer binds the render payload itself
 *  as `context` — so the facade result is SPREAD here, never nested under a `context` key.
 *  Nesting renders every `context.*` as undefined while `translate()` keeps working, which
 *  looks like a dead facade but is really an unreachable one. */
const ctx = (context, helpers, screen) => ({
  activeShell: 'scaffold',
  ...facade.context(helpers.session(context).data, helpers.translate(context), helpers.locale(context), screen || context.req.query('state') || 'completed'),
});

// The receipt is a READ surface: ?state= picks which recorded outcome is being
// read. There is deliberately no POST that "starts" a run here — the scaffold
// is a synchronous deterministic transform (D24), so arriving with a result IS
// the event. Nothing on this screen polls, ticks, or animates.
export const page = (context, helpers) => helpers.render(context, VIEW, ctx(context, helpers));

// The composer records the user's own words onto the receipt thread; the
// facade adds no reply. Empty text answers 204 so htmx swaps nothing, which is
// the same contract the intake and design composers already use.
export const sendMessage = async (context, helpers) => {
  const form = await helpers.form(context);
  const text = String(form.text || '').trim();
  if (!text) return helpers.noContent(context);
  return helpers.render(context, `${VIEW}#panelsSwap`, {
    activeShell: 'scaffold',
    ...facade.sendMessage(
      helpers.session(context).data,
      text,
      helpers.translate(context),
      helpers.locale(context),
      context.req.query('state') || 'completed',
    ),
  });
};

// Panel width grip: s/m/l persisted per side, whole-panel re-render.
export const panelSize = (context, helpers) =>
  helpers.render(context, `${VIEW}#panelsSwap`, {
    activeShell: 'scaffold',
    ...facade.setPanelSize(
      helpers.session(context).data,
      context.req.param('panel'),
      context.req.param('size'),
      helpers.translate(context),
      helpers.locale(context),
      context.req.query('state') || 'completed',
    ),
  });
