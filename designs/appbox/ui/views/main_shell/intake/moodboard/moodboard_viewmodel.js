export const surfaceId = 'intake.moodboard';

import * as facade from '../../../../../services/facades/intake_facade.js';

const VIEW = 'ui/views/main_shell/intake/moodboard/moodboard_view.html';
const S = 'moodboard';

export const page = (c, h) =>
  h.render(c, VIEW, { activeTab: 'intake', ...facade.context(h.session(c).data, S, c.req.query('artifact') ?? null, h.prefs(c)) });

// Clicking a rail card (or a shot card in the gallery) swaps the canvas.
// ?bar=open also opens the stage bar (the "ask ↩" card action).
export const artifact = (c, h) => {
  const ref = `${c.req.param('kind')}/${c.req.param('id')}`;
  if (c.req.query('bar') === 'open') facade.openBar(h.session(c).data, S, ref);
  return h.render(c, `${VIEW}#canvasSwap`, facade.showArtifact(h.session(c).data, S, ref, h.prefs(c)));
};

// Rail top-bar filter: ?board=<id>|all — re-frames the gallery.
export const filter = (c, h) =>
  h.render(c, `${VIEW}#filterSwap`, facade.setFilter(h.session(c).data, S, 'board', c.req.query('board') ?? 'all', h.prefs(c)));

// The composer: append the user's message and a simulated agent reply.
export const sendMessage = async (c, h) => {
  const form = await h.form(c);
  const text = String(form.preset || form.text || '').trim();
  if (!text) return h.noContent(c);
  return h.render(c, `${VIEW}#messageSwap`, facade.sendMessage(h.session(c).data, S, text, h.prefs(c)));
};

// Stage bar toggle: ?state=open renders the toolbar, ?state=fab the button.
export const bar = (c, h) => {
  const ref = `${c.req.param('kind')}/${c.req.param('id')}`;
  return h.render(c, `${VIEW}#barSwap`, facade.barToggle(h.session(c).data, S, ref, c.req.query('state'), h.prefs(c)));
};

// Stage-bar follow-up: artifact-scoped thread, bar stays open.
export const askArtifact = async (c, h) => {
  const form = await h.form(c);
  const text = String(form.text || '').trim();
  if (!text) return h.noContent(c);
  const ref = `${c.req.param('kind')}/${c.req.param('id')}`;
  return h.render(c, `${VIEW}#scopedSwap`, facade.askArtifact(h.session(c).data, S, ref, text, h.prefs(c)));
};
