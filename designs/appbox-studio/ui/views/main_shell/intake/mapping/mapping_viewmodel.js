// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
export const surfaceId = 'intake.mapping';

import * as facade from '../../../../../services/facades/intake_facade.js';

const VIEW = 'ui/views/main_shell/intake/mapping/mapping_view.html';
const S = 'mapping';

export const page = (c, h) =>
  h.render(c, VIEW, { activeShell: 'intake', ...facade.context(h.session(c).data, S, c.req.query('artifact') ?? null, h.prefs(c), h.t(c), h.locale(c), c.req.query('file'), c.req.query('panel')) });

// A file row: open the file in the main panel (?path=, unknown → empty state).
export const file = (c, h) =>
  h.render(c, `${VIEW}#fileSwap`, facade.openFile(h.session(c).data, S, c.req.query('path'), h.prefs(c), h.t(c), h.locale(c)));

// Open an artifact in the main panel.
export const artifact = (c, h) => {
  const ref = `${c.req.param('kind')}/${c.req.param('id')}`;
  return h.render(c, `${VIEW}#panelsSwap`, facade.showArtifact(h.session(c).data, S, ref, h.prefs(c), h.t(c), h.locale(c)));
};

// Composer agent chrome: the model pick swaps the stage.
export const model = (c, h) =>
  h.render(c, `${VIEW}#panelsSwap`, facade.setModel(h.session(c).data, S, c.req.param('id'), h.prefs(c), h.t(c), h.locale(c)));

// Activity panel view switch: ?view=thread|artifacts|files — swaps the body.
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

// The first chat message: depth choice picks one of three question banks.
export const depth = async (c, h) => {
  const form = await h.form(c);
  return h.render(c, `${VIEW}#panelsSwap`, facade.chooseDepth(h.session(c).data, String(form.depth || ''), h.prefs(c), h.t(c), h.locale(c)));
};

// A question card's answer (typed or a suggestion chip).
export const answer = async (c, h) => {
  const form = await h.form(c);
  const text = String(form.text || '').trim();
  if (!text) return h.noContent(c);
  return h.render(c, `${VIEW}#panelsSwap`, facade.answerQuestion(h.session(c).data, String(form.q || ''), text, h.prefs(c), h.t(c), h.locale(c)));
};

// A question card's skip affordance.
export const skip = async (c, h) => {
  const form = await h.form(c);
  return h.render(c, `${VIEW}#panelsSwap`, facade.skipQuestion(h.session(c).data, String(form.q || ''), h.prefs(c), h.t(c), h.locale(c)));
};

// Revisit an answered/skipped card: ?q=<id> re-opens its form.
export const edit = (c, h) =>
  h.render(c, `${VIEW}#panelsSwap`, facade.editQuestion(h.session(c).data, c.req.query('q'), h.prefs(c), h.t(c), h.locale(c)));

// The approval gate: the "approve the story map" quick-reply flips seed state.
export const approve = (c, h) =>
  h.render(c, `${VIEW}#panelsSwap`, facade.approveMap(h.session(c).data, h.prefs(c), h.t(c), h.locale(c)));
