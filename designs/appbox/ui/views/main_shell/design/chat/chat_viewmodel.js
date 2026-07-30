export const surfaceId = 'design.chat';

import * as facade from '../../../../../services/facades/design_facade.js';

const VIEW = 'ui/views/main_shell/design/chat/chat_view.html';

// The retired Screen Chat surface, re-skinned onto the stage layout.
// ?screen=<id> pins a context chip; ?screen=none clears the context.
export const page = (c, h) =>
  h.render(c, VIEW, { activeShell: 'design', ...facade.stageContext(h.session(c).data, { line: 'refine', pin: c.req.query('screen') ?? null }, h.prefs(c), h.t(c), h.locale(c)) });

// Filmstrip thumb / artboard pin / rail card: toggle a screen's context chip
// (?state=toggle|on|off) — one swap re-renders chat chips + canvas outlines.
export const context = (c, h) =>
  h.render(c, `${VIEW}#stageSwap`, facade.toggleContext(h.session(c).data, c.req.param('id'), c.req.query('state') ?? 'toggle', h.prefs(c), h.t(c), h.locale(c)));

// Legacy per-screen pick: now pins the chip and swaps the stage.
export const select = (c, h) =>
  h.render(c, `${VIEW}#stageSwap`, facade.toggleContext(h.session(c).data, c.req.param('id'), 'on', h.prefs(c), h.t(c), h.locale(c)));

// The single composer path: 'draft-all' accepts the one-pass draft, 'approve'
// signs the manifest, anything else refines the pinned screens. The legacy
// per-screen route pins its screen first.
export const send = async (c, h) => {
  const form = await h.form(c);
  const text = String(form.preset || form.text || '').trim();
  if (!text) return h.noContent(c);
  return h.render(c, `${VIEW}#stageSwap`, facade.sendChat(h.session(c).data, text, h.prefs(c), c.req.param('id') ?? null, h.t(c), h.locale(c)));
};

// The close act on the docked chat: unpin all screens, recenter the chat.
export const close = (c, h) =>
  h.render(c, `${VIEW}#stageSwap`, facade.closeChat(h.session(c).data, {}, h.prefs(c), h.t(c), h.locale(c)));

// Composer agent chrome: the model pick swaps the stage.
export const model = (c, h) =>
  h.render(c, `${VIEW}#stageSwap`, facade.setModel(h.session(c).data, c.req.param('id'), {}, h.prefs(c), h.t(c), h.locale(c)));

// The tray trigger: persist the collapse state and answer 204 — the
// checkbox already flipped and animates locally; a swap would replace the
// element mid-transition and kill the animation.
export const tray = (c, h) => {
  facade.setTray(h.session(c).data, c.req.query('state'), {}, {}, h.t(c), h.locale(c));
  return h.noContent(c);
};

// One-tap revert of a checkpoint on a screen.
export const revert = (c, h) =>
  h.render(c, `${VIEW}#revertSwap`, facade.revertCheckpoint(h.session(c).data, c.req.param('id'), c.req.param('cp'), h.prefs(c), h.t(c), h.locale(c)));
