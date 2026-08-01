// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
export const surfaceId = 'intake.surfaces';

import * as facade from '../../../../../services/facades/intake_facade.js';

const VIEW = 'ui/views/main_shell/intake/surfaces/surfaces_view.html';
const S = 'surfaces';

export const page = (c, h) =>
  h.render(c, VIEW, { activeShell: 'intake', ...facade.context(h.session(c).data, S, null, h.prefs(c), h.t(c), h.locale(c), c.req.query('file'), c.req.query('panel')) });

export const file = (c, h) =>
  h.render(c, `${VIEW}#fileSwap`, facade.openFile(h.session(c).data, S, c.req.query('path'), h.prefs(c), h.t(c), h.locale(c)));

export const model = (c, h) =>
  h.render(c, `${VIEW}#panelsSwap`, facade.setModel(h.session(c).data, S, c.req.param('id'), h.prefs(c), h.t(c), h.locale(c)));

export const panel = (c, h) =>
  h.render(c, `${VIEW}#activitySwap`, facade.setActivityView(h.session(c).data, S, c.req.query('view'), h.prefs(c), h.t(c), h.locale(c)));

export const panelSize = (c, h) =>
  h.render(c, `${VIEW}#activityFrameSwap`, facade.setPanelSize(h.session(c).data, S, c.req.param('side'), c.req.param('size'), h.prefs(c), h.t(c), h.locale(c)));

export const sendMessage = async (c, h) => {
  const form = await h.form(c);
  const text = String(form.preset || form.text || '').trim();
  if (!text) return h.noContent(c);
  return h.render(c, `${VIEW}#panelsSwap`, facade.sendMessage(h.session(c).data, S, text, h.prefs(c), h.t(c), h.locale(c)));
};

// The item engine: confirm the prefill / save a correction / skip / revisit /
// accept-all. Corrections post text inputs; one-per-line fields split here.
const lines = (v) => String(v ?? '').split('\n').map((s) => s.trim()).filter(Boolean);

export const confirm = async (c, h) => {
  const form = await h.form(c);
  return h.render(c, `${VIEW}#panelsSwap`, facade.confirmItem(h.session(c).data, S, String(form.item || ''), h.prefs(c), h.t(c), h.locale(c)));
};

// Surface groups carry no free-text fields — saving is confirming.
export const save = async (c, h) => {
  const form = await h.form(c);
  return h.render(c, `${VIEW}#panelsSwap`, facade.confirmItem(h.session(c).data, S, String(form.item || ''), h.prefs(c), h.t(c), h.locale(c)));
};

export const skip = async (c, h) => {
  const form = await h.form(c);
  return h.render(c, `${VIEW}#panelsSwap`, facade.skipItem(h.session(c).data, S, String(form.item || ''), h.prefs(c), h.t(c), h.locale(c)));
};

export const edit = (c, h) =>
  h.render(c, `${VIEW}#panelsSwap`, facade.editItem(h.session(c).data, S, c.req.query('item'), h.prefs(c), h.t(c), h.locale(c)));

export const acceptAll = (c, h) =>
  h.render(c, `${VIEW}#panelsSwap`, facade.acceptAll(h.session(c).data, S, h.prefs(c), h.t(c), h.locale(c)));
