export const surfaceId = 'intake.mapping';

import * as facade from '../../../../../services/facades/intake_facade.js';

const VIEW = 'ui/views/main_shell/intake/mapping/mapping_view.html';
const S = 'mapping';

export const page = (c, h) =>
  h.render(c, VIEW, { activeTab: 'intake', ...facade.context(h.session(c).data, S, c.req.query('artifact') ?? null, h.prefs(c)) });

// Open an artifact on the stage — the chat docks right.
export const artifact = (c, h) => {
  const ref = `${c.req.param('kind')}/${c.req.param('id')}`;
  return h.render(c, `${VIEW}#stageSwap`, facade.showArtifact(h.session(c).data, S, ref, h.prefs(c)));
};

// Collapse affordance / context-chip ×: close the artifact, recenter the chat.
export const close = (c, h) =>
  h.render(c, `${VIEW}#stageSwap`, facade.closeArtifact(h.session(c).data, S, h.prefs(c)));

// Left rail view switch: ?view=thread|artifacts|files — swaps the rail body.
export const rail = (c, h) =>
  h.render(c, `${VIEW}#railSwap`, facade.setRailView(h.session(c).data, S, c.req.query('view'), h.prefs(c)));

// The composer: append the user's message and a simulated agent reply.
export const sendMessage = async (c, h) => {
  const form = await h.form(c);
  const text = String(form.preset || form.text || '').trim();
  if (!text) return h.noContent(c);
  return h.render(c, `${VIEW}#stageSwap`, facade.sendMessage(h.session(c).data, S, text, h.prefs(c)));
};

// The first chat message: depth choice picks one of three question banks.
export const depth = async (c, h) => {
  const form = await h.form(c);
  return h.render(c, `${VIEW}#stageSwap`, facade.chooseDepth(h.session(c).data, String(form.depth || ''), h.prefs(c)));
};

// A question card's answer (typed or a suggestion chip).
export const answer = async (c, h) => {
  const form = await h.form(c);
  const text = String(form.text || '').trim();
  if (!text) return h.noContent(c);
  return h.render(c, `${VIEW}#stageSwap`, facade.answerQuestion(h.session(c).data, String(form.q || ''), text, h.prefs(c)));
};

// A question card's skip affordance.
export const skip = async (c, h) => {
  const form = await h.form(c);
  return h.render(c, `${VIEW}#stageSwap`, facade.skipQuestion(h.session(c).data, String(form.q || ''), h.prefs(c)));
};

// Revisit an answered/skipped card: ?q=<id> re-opens its form.
export const edit = (c, h) =>
  h.render(c, `${VIEW}#stageSwap`, facade.editQuestion(h.session(c).data, c.req.query('q'), h.prefs(c)));

// The approval gate: the "approve the story map" quick-reply flips seed state.
export const approve = (c, h) =>
  h.render(c, `${VIEW}#stageSwap`, facade.approveMap(h.session(c).data, h.prefs(c)));
