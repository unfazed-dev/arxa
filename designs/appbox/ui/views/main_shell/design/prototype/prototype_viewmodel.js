export const surfaceId = 'design.prototype';

import * as facade from '../../../../../services/facades/design_facade.js';

const VIEW = 'ui/views/main_shell/design/prototype/prototype_view.html';

export const page = (c, h) =>
  h.render(c, VIEW, { activeTab: 'design', ...facade.protoContext(h.session(c).data, c.req.query('screen') ?? null, h.prefs(c)) });

// Clicking an artboard card swaps the canvas to that screen.
// ?bar=open also opens the stage bar (the "ask ↩" card action); the bar's
// open state lives in the session (barOpenFor) so it survives swaps.
export const screen = (c, h) => {
  const id = c.req.param('id');
  if (c.req.query('bar') === 'open') facade.design(h.session(c).data).barOpenFor = id;
  return h.render(c, `${VIEW}#canvasSwap`, facade.showScreen(h.session(c).data, id, h.prefs(c)));
};

// Rail top-bar filter: ?epic=<epic>|all.
export const rail = (c, h) =>
  h.render(c, `${VIEW}#filterSwap`, facade.setRailFilter(h.session(c).data, c.req.query('epic') ?? 'all', h.prefs(c)));

// The shared design viewer: toolbar and strip acts swap just the viewer block.
export const viewer = (c, h) =>
  h.render(c, `${VIEW}#viewerSwap`, facade.setViewer(h.session(c).data, {
    screen: c.req.query('screen'), vp: c.req.query('vp'), bg: c.req.query('bg'),
    os: c.req.query('os'), mode: c.req.query('mode'),
  }, h.prefs(c)));

// Stage bar toggle: ?state=open renders the toolbar, ?state=fab the button.
export const bar = (c, h) => {
  const id = c.req.param('id');
  facade.design(h.session(c).data).barOpenFor = c.req.query('state') === 'fab' ? null : id;
  return h.render(c, `${VIEW}#barSwap`, facade.protoContext(h.session(c).data, id, h.prefs(c)));
};

// Stage-bar follow-up: artboard-scoped thread, bar stays open.
export const askScreen = async (c, h) => {
  const form = await h.form(c);
  const text = String(form.text || '').trim();
  if (!text) return h.noContent(c);
  return h.render(c, `${VIEW}#scopedSwap`, facade.askScreen(h.session(c).data, c.req.param('id'), text, h.prefs(c)));
};
