// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
export const surfaceId = 'design.chat';

import * as facade from '../../../../../services/facades/design_facade.js';

const VIEW = 'ui/views/main_shell/design/chat/chat_view.html';

// The retired Screen Chat surface, re-skinned onto the stage layout.
// ?screen=<id> pins a context chip; ?screen=none clears the context.
export const page = (c, h) =>
  h.render(c, VIEW, { activeShell: 'design', ...facade.stageContext(h.session(c).data, { line: 'refine', pin: c.req.query('screen') ?? null, file: c.req.query('file'), panel: c.req.query('panel') }, h.prefs(c), h.t(c), h.locale(c)) });

// Filmstrip thumb / artboard pin / activity card: toggle a screen's context chip
// (?state=toggle|on|off) — one swap re-renders chat chips + canvas outlines.
export const context = (c, h) =>
  h.render(c, `${VIEW}#panelsSwap`, facade.toggleContext(h.session(c).data, c.req.param('id'), c.req.query('state') ?? 'toggle', h.prefs(c), h.t(c), h.locale(c)));

// Element context chips (inspect.js picks): pin/unpin an element by its data-el
// name. Both swap the whole stage — the composer tray lives there alongside the
// screen chips, and the canvas keeps rendering uninterrupted.
export const elementContext = async (c, h) => {
  const form = await h.form(c);
  return h.render(c, `${VIEW}#panelsSwap`, facade.pinElement(h.session(c).data, form.screen, form.name, form.kind, h.prefs(c), h.t(c), h.locale(c), form.instance));
};

// Element context chip remove (GET — the composer chip's hx-get). Reads query
// params so no form body is needed.
export const elementContextRemove = (c, h) =>
  h.render(c, `${VIEW}#panelsSwap`, facade.unpinElement(h.session(c).data, c.req.query('screen'), c.req.query('name'), h.prefs(c), h.t(c), h.locale(c)));

// Bulk pin from the marquee selection (drag.js POSTs ids=a,b,c).
export const bulkContext = async (c, h) => {
  const form = await h.form(c);
  const ids = c.req.query('ids') || form.ids || '';
  return h.render(c, `${VIEW}#panelsSwap`, facade.bulkPin(h.session(c).data, ids, h.prefs(c), h.t(c), h.locale(c)));
};

// Legacy per-screen pick: now pins the chip and swaps the stage.
export const select = (c, h) =>
  h.render(c, `${VIEW}#panelsSwap`, facade.toggleContext(h.session(c).data, c.req.param('id'), 'on', h.prefs(c), h.t(c), h.locale(c)));

// The single composer path: 'approve' signs the manifest, anything else
// refines the pinned screens. The legacy per-screen route pins its screen first.
export const send = async (c, h) => {
  const form = await h.form(c);
  const text = String(form.preset || form.text || '').trim();
  if (!text) return h.noContent(c);
  // The drawer-mounted composer (Screen Reveal-Drawer plan): ?screen= pins
  // the drawer's screen first (screen-scoped send), ?drawer= routes the
  // response back to that drawer's own container instead of #panels.
  const pin = c.req.param('id') ?? c.req.query('screen') ?? null;
  const data = facade.sendChat(h.session(c).data, text, h.prefs(c), pin, h.t(c), h.locale(c));
  const drawer = c.req.query('drawer');
  if (drawer) {
    // draftSent is read per composer INSTANCE (composer.html drops
    // hx-preserve on the render that follows a send); only the drawer's own
    // spec gets it — the panel composer keeps any half-typed draft.
    const spec = data.viewer?.drawers?.[drawer]?.composer;
    if (spec) spec.draftSent = true;
    return h.render(c, `${VIEW}#drawerSwap`, { ...data, drawerScreen: drawer });
  }
  return h.render(c, `${VIEW}#panelsSwap`, data);
};

// Composer agent chrome: the model pick swaps the stage.
export const model = (c, h) =>
  h.render(c, `${VIEW}#panelsSwap`, facade.setModel(h.session(c).data, c.req.param('id'), {}, h.prefs(c), h.t(c), h.locale(c)));

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
