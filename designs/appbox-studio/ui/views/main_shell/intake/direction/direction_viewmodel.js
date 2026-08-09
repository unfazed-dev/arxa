// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
export const surfaceId = 'intake.direction';

import * as facade from '../../../../../services/facades/intake_facade.js';

const VIEW = 'ui/views/main_shell/intake/direction/direction_view.html';
const SURFACE = 'direction';

export const page = (context, helpers) =>
  helpers.render(context, VIEW, { activeShell: 'intake', ...facade.context(helpers.session(context).data, SURFACE, null, helpers.prefs(context), helpers.translate(context), helpers.locale(context), context.req.query('file'), context.req.query('panel')) });

export const file = (context, helpers) =>
  helpers.render(context, `${VIEW}#fileSwap`, facade.openFile(helpers.session(context).data, SURFACE, context.req.query('path'), helpers.prefs(context), helpers.translate(context), helpers.locale(context)));

export const model = (context, helpers) =>
  helpers.render(context, `${VIEW}#panelsSwap`, facade.setModel(helpers.session(context).data, SURFACE, context.req.param('id'), helpers.prefs(context), helpers.translate(context), helpers.locale(context)));

export const panel = (context, helpers) =>
  helpers.render(context, `${VIEW}#activitySwap`, facade.setActivityView(helpers.session(context).data, SURFACE, context.req.query('view'), helpers.prefs(context), helpers.translate(context), helpers.locale(context)));

export const panelSize = (context, helpers) =>
  helpers.render(context, `${VIEW}#activityFrameSwap`, facade.setPanelSize(helpers.session(context).data, SURFACE, context.req.param('panel'), context.req.param('size'), helpers.prefs(context), helpers.translate(context), helpers.locale(context)));

export const sendMessage = async (context, helpers) => {
  const form = await helpers.form(context);
  const text = String(form.preset || form.text || '').trim();
  if (!text) return helpers.noContent(context);
  return helpers.render(context, `${VIEW}#panelsSwap`, facade.sendMessage(helpers.session(context).data, SURFACE, text, helpers.prefs(context), helpers.translate(context), helpers.locale(context)));
};

// The item engine: confirm the prefill / save a correction / skip / revisit /
// accept-all. Corrections post text inputs; one-per-line fields split here.
const lines = (text) => String(text ?? '').split('\n').map((line) => line.trim()).filter(Boolean);

export const confirm = async (context, helpers) => {
  const form = await helpers.form(context);
  return helpers.render(context, `${VIEW}#panelsSwap`, facade.confirmItem(helpers.session(context).data, SURFACE, String(form.item || ''), helpers.prefs(context), helpers.translate(context), helpers.locale(context)));
};

export const save = async (context, helpers) => {
  const form = await helpers.form(context);
  // Corrected values become client-provenance entries, one per line.
  const fields = { values: lines(form.values).map((value) => ({ value, provenance: 'client' })) };
  return helpers.render(context, `${VIEW}#panelsSwap`, facade.saveItem(helpers.session(context).data, SURFACE, String(form.item || ''), fields, helpers.prefs(context), helpers.translate(context), helpers.locale(context)));
};

export const skip = async (context, helpers) => {
  const form = await helpers.form(context);
  return helpers.render(context, `${VIEW}#panelsSwap`, facade.skipItem(helpers.session(context).data, SURFACE, String(form.item || ''), helpers.prefs(context), helpers.translate(context), helpers.locale(context)));
};

export const edit = (context, helpers) =>
  helpers.render(context, `${VIEW}#panelsSwap`, facade.editItem(helpers.session(context).data, SURFACE, context.req.query('item'), helpers.prefs(context), helpers.translate(context), helpers.locale(context)));

export const acceptAll = (context, helpers) =>
  helpers.render(context, `${VIEW}#panelsSwap`, facade.acceptAll(helpers.session(context).data, SURFACE, helpers.prefs(context), helpers.translate(context), helpers.locale(context)));
