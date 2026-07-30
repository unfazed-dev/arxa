export const surfaceId = 'design.prototype';

import * as facade from '../../../../../services/facades/design_facade.js';

const VIEW = 'ui/views/main_shell/design/prototype/prototype_view.html';

// The design shell opens on the chat: the first agent message offers to draft
// every surface at once. ?screen=<id> deep-links a context pin.
export const page = (c, h) =>
  h.render(c, VIEW, { activeShell: 'design', ...facade.stageContext(h.session(c).data, { line: 'prototype', pin: c.req.query('screen') ?? null }, h.prefs(c), h.locale(c)) });

// Legacy artboard deep-link: pins the screen as chat context, swaps the stage.
export const screen = (c, h) =>
  h.render(c, `${VIEW}#stageSwap`, facade.toggleContext(h.session(c).data, c.req.param('id'), 'on', h.prefs(c), h.locale(c)));

// Rail top-bar epic filter (screens view).
export const rail = (c, h) =>
  h.render(c, `${VIEW}#filterSwap`, facade.setRailFilter(h.session(c).data, c.req.query('epic') ?? 'all', h.prefs(c), h.locale(c)));

// Multi-view rail carousel: screens / artifacts / files body swap.
export const railView = (c, h) =>
  h.render(c, `${VIEW}#railBody`, facade.setRailView(h.session(c).data, c.req.param('view'), h.prefs(c), h.locale(c)));

// The shared design viewer: toolbar acts swap just the viewer block.
export const viewer = (c, h) =>
  h.render(c, `${VIEW}#viewerSwap`, facade.setViewer(h.session(c).data, {
    screen: c.req.query('screen'), vp: c.req.query('vp'), bg: c.req.query('bg'),
    os: c.req.query('os'), mode: c.req.query('mode'),
  }, h.prefs(c), h.locale(c)));
