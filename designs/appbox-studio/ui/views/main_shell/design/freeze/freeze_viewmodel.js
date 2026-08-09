// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
export const surfaceId = 'design.freeze';

import * as facade from '../../../../../services/facades/design_facade.js';

const VIEW = 'ui/views/main_shell/design/freeze/freeze_view.html';

export const page = (context, helpers) =>
  helpers.render(context, VIEW, { activeShell: 'design', ...facade.freezeContext(helpers.session(context).data, helpers.prefs(context), helpers.translate(context), helpers.locale(context), context.req.query('file'), context.req.query('panel')) });

// A file row: open the file in the main panel (?path=, unknown → freeze cards).
export const file = (context, helpers) => {
  facade.openFile(helpers.session(context).data, context.req.query('path'), helpers.prefs(context), helpers.translate(context), helpers.locale(context));
  return helpers.render(context, `${VIEW}#fileSwap`, facade.freezeContext(helpers.session(context).data, helpers.prefs(context), helpers.translate(context), helpers.locale(context)));
};

// The freeze chat: 'approve' signs the manifest (the human gate that unlocks
// Build); anything else lands in the shared design thread. sendChat mutates
// the session; the response is always the freeze stage rebuilt from
// freezeContext.
export const send = async (context, helpers) => {
  const form = await helpers.form(context);
  const text = String(form.preset || form.text || '').trim();
  if (!text) return helpers.noContent(context);
  facade.sendChat(helpers.session(context).data, text, helpers.prefs(context), null, helpers.translate(context), helpers.locale(context));
  // draftSent explicitly: freeze shares the composer textarea (and therefore
  // its hx-preserve) but renders freezeContext, so sendChat's own flag never
  // reaches the template here. Without it the freeze composer keeps the text
  // it just sent.
  return helpers.render(context, `${VIEW}#panelsSwap`, { ...facade.freezeContext(helpers.session(context).data, helpers.prefs(context), helpers.translate(context), helpers.locale(context)), draftSent: true });
};

// Re-run the drift check: swaps the drift card and toasts the result.
export const recheck = (context, helpers) =>
  helpers.render(context, `${VIEW}#driftSwap`, facade.recheckDrift(helpers.session(context).data, helpers.prefs(context), helpers.translate(context), helpers.locale(context)));

// Filmstrip unpin on THIS surface: toggle the pin, re-render the freeze
// panels (the shared toggle mutates the session; freezeContext rebuilds the
// rest).
export const context = (context, helpers) => {
  facade.toggleContext(helpers.session(context).data, context.req.param('id'), context.req.query('state') ?? 'toggle', helpers.prefs(context), helpers.translate(context), helpers.locale(context));
  return helpers.render(context, `${VIEW}#panelsSwap`, facade.freezeContext(helpers.session(context).data, helpers.prefs(context), helpers.translate(context), helpers.locale(context)));
};

// Composer chrome: mutate the shared agent/tray state, re-render freeze.
export const model = (context, helpers) => {
  facade.setModel(helpers.session(context).data, context.req.param('id'), {}, {}, helpers.translate(context), helpers.locale(context));
  return helpers.render(context, `${VIEW}#panelsSwap`, facade.freezeContext(helpers.session(context).data, helpers.prefs(context), helpers.translate(context), helpers.locale(context)));
};
export const tray = (context, helpers) => {
  facade.setTray(helpers.session(context).data, context.req.query('state'), {}, {}, helpers.translate(context), helpers.locale(context));
  return helpers.noContent(context); // persist only — the checkbox animates locally
};
