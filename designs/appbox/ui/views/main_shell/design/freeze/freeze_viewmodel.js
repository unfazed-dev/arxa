export const surfaceId = 'design.freeze';

import * as facade from '../../../../../services/facades/design_facade.js';

const VIEW = 'ui/views/main_shell/design/freeze/freeze_view.html';

export const page = (c, h) =>
  h.render(c, VIEW, { activeShell: 'design', ...facade.freezeContext(h.session(c).data, h.prefs(c), h.locale(c)) });

// The freeze chat: 'approve' signs the manifest (the human gate that unlocks
// Build); anything else lands in the shared design thread. sendChat mutates
// the session; the response is always the freeze stage rebuilt from
// freezeContext.
export const send = async (c, h) => {
  const form = await h.form(c);
  const text = String(form.preset || form.text || '').trim();
  if (!text) return h.noContent(c);
  facade.sendChat(h.session(c).data, text, h.prefs(c), h.locale(c));
  return h.render(c, `${VIEW}#stageSwap`, facade.freezeContext(h.session(c).data, h.prefs(c), h.locale(c)));
};

// Re-run the drift check: swaps the drift card and toasts the result.
export const recheck = (c, h) =>
  h.render(c, `${VIEW}#driftSwap`, facade.recheckDrift(h.session(c).data, h.prefs(c), h.locale(c)));

// Filmstrip close on THIS surface: toggle the pin, re-render the freeze stage
// (the shared toggle mutates the session; freezeContext rebuilds the rest).
export const context = (c, h) => {
  facade.toggleContext(h.session(c).data, c.req.param('id'), c.req.query('state') ?? 'toggle', h.prefs(c), h.locale(c));
  return h.render(c, `${VIEW}#stageSwap`, facade.freezeContext(h.session(c).data, h.prefs(c), h.locale(c)));
};

// The close act: unpin everything, recenter the chat beside the freeze canvas.
export const close = (c, h) => {
  facade.closeChat(h.session(c).data, {}, {}, h.locale(c));
  return h.render(c, `${VIEW}#stageSwap`, facade.freezeContext(h.session(c).data, h.prefs(c), h.locale(c)));
};

// Composer chrome: mutate the shared agent/tray state, re-render freeze.
export const model = (c, h) => {
  facade.setModel(h.session(c).data, c.req.param('id'), {}, {}, h.locale(c));
  return h.render(c, `${VIEW}#stageSwap`, facade.freezeContext(h.session(c).data, h.prefs(c), h.locale(c)));
};
export const tray = (c, h) => {
  facade.setTray(h.session(c).data, c.req.query('state'), {}, {}, h.locale(c));
  return h.noContent(c); // persist only — the checkbox animates locally
};
