// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
export const surfaceId = 'intake.moodboard';

import * as facade from '../../../../../services/facades/intake_facade.js';

const VIEW = 'ui/views/main_shell/intake/moodboard/moodboard_view.html';
const S = 'moodboard';

export const page = (c, h) =>
  h.render(c, VIEW, { activeShell: 'intake', ...facade.context(h.session(c).data, S, c.req.query('artifact') ?? null, h.prefs(c), h.t(c), h.locale(c), c.req.query('file'), c.req.query('panel')) });

// A file row: open the file in the main panel (?path=, unknown → empty state).
export const file = (c, h) =>
  h.render(c, `${VIEW}#fileSwap`, facade.openFile(h.session(c).data, S, c.req.query('path'), h.prefs(c), h.t(c), h.locale(c)));

// Open an artifact in the main panel (gallery ↔ shot detail).
export const artifact = (c, h) => {
  const ref = `${c.req.param('kind')}/${c.req.param('id')}`;
  return h.render(c, `${VIEW}#panelsSwap`, facade.showArtifact(h.session(c).data, S, ref, h.prefs(c), h.t(c), h.locale(c)));
};

// Composer agent chrome: the model pick swaps the stage.
export const model = (c, h) =>
  h.render(c, `${VIEW}#panelsSwap`, facade.setModel(h.session(c).data, S, c.req.param('id'), h.prefs(c), h.t(c), h.locale(c)));

// Activity panel view switch: ?view=thread|artifacts|files.
export const panel = (c, h) =>
  h.render(c, `${VIEW}#activitySwap`, facade.setActivityView(h.session(c).data, S, c.req.query('view'), h.prefs(c), h.t(c), h.locale(c)));

// Panel width grip: s/m/l persisted per side for the whole intake shell.
export const panelSize = (c, h) =>
  h.render(c, `${VIEW}#activityFrameSwap`, facade.setPanelSize(h.session(c).data, S, c.req.param('side'), c.req.param('size'), h.prefs(c), h.t(c), h.locale(c)));

// The composer: append the user's message and a simulated agent reply.
export const sendMessage = async (c, h) => {
  const form = await h.form(c);
  const text = String(form.preset || form.text || '').trim();
  if (!text) return h.noContent(c);
  return h.render(c, `${VIEW}#panelsSwap`, facade.sendMessage(h.session(c).data, S, text, h.prefs(c), h.t(c), h.locale(c)));
};
