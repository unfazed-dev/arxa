export const surfaceId = 'intake.brief';

import * as facade from '../../../../../services/facades/intake_facade.js';

const VIEW = 'ui/views/main_shell/intake/brief/brief_view.html';
const S = 'brief';

export const page = (c, h) =>
  h.render(c, VIEW, { activeShell: 'intake', ...facade.context(h.session(c).data, S, c.req.query('artifact') ?? null, h.prefs(c), h.t(c), h.locale(c)) });

// Open an artifact on the stage (doc ↔ surface inventory) — chat docks right.
export const artifact = (c, h) => {
  const ref = `${c.req.param('kind')}/${c.req.param('id')}`;
  return h.render(c, `${VIEW}#stageSwap`, facade.showArtifact(h.session(c).data, S, ref, h.prefs(c), h.t(c), h.locale(c)));
};

// Collapse affordance / context-chip unpin: close the artifact, recenter the chat.
export const close = (c, h) =>
  h.render(c, `${VIEW}#stageSwap`, facade.closeArtifact(h.session(c).data, S, h.prefs(c), h.t(c), h.locale(c)));

// Composer agent chrome: the model pick swaps the stage.
export const model = (c, h) =>
  h.render(c, `${VIEW}#stageSwap`, facade.setModel(h.session(c).data, S, c.req.param('id'), h.prefs(c), h.t(c), h.locale(c)));

// Left rail view switch: ?view=thread|artifacts|files.
export const rail = (c, h) =>
  h.render(c, `${VIEW}#railSwap`, facade.setRailView(h.session(c).data, S, c.req.query('view'), h.prefs(c), h.t(c), h.locale(c)));

// The composer: append the user's message and a simulated agent reply.
export const sendMessage = async (c, h) => {
  const form = await h.form(c);
  const text = String(form.preset || form.text || '').trim();
  if (!text) return h.noContent(c);
  return h.render(c, `${VIEW}#stageSwap`, facade.sendMessage(h.session(c).data, S, text, h.prefs(c), h.t(c), h.locale(c)));
};
