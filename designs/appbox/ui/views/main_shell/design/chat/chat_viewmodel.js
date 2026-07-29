export const surfaceId = 'design.chat';

import * as facade from '../../../../../services/facades/design_facade.js';

const VIEW = 'ui/views/main_shell/design/chat/chat_view.html';

// ?screen=<id> deep-links a scoped thread (the prototype's "refine this
// screen →" link); ?screen=none removes the context chip.
export const page = (c, h) =>
  h.render(c, VIEW, { activeTab: 'design', ...facade.chatContext(h.session(c).data, c.req.query('screen') ?? null, h.prefs(c)) });

// Picking a surface swaps the canvas to its thread and re-dims the strip.
export const select = (c, h) =>
  h.render(c, `${VIEW}#selectSwap`, facade.selectScreen(h.session(c).data, c.req.param('id'), h.prefs(c)));

// The composer: append the user's message and a scoped reply; the reply may
// mint a checkpoint for this screen only.
export const send = async (c, h) => {
  const form = await h.form(c);
  const text = String(form.preset || form.text || '').trim();
  if (!text) return h.noContent(c);
  return h.render(c, `${VIEW}#messageSwap`, facade.sendChat(h.session(c).data, c.req.param('id'), text, h.prefs(c)));
};

// One-tap revert of a checkpoint on this screen.
export const revert = (c, h) =>
  h.render(c, `${VIEW}#revertSwap`, facade.revertCheckpoint(h.session(c).data, c.req.param('id'), c.req.param('cp'), h.prefs(c)));
