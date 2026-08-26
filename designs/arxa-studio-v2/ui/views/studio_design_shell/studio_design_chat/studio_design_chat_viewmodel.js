// arxa:provenance
// generator: arxa  licence: free  project: 662368770980
// Built with arxa (free tier) — https://arxa.dev
export const surfaceId = 'studio_design_chat';

import * as facade from '../../../../services/studio_design_services/facades/studio_design_facade_service.js';
import { abxResolveShellView } from '../anatomy_flag.js';

const VIEW = 'ui/views/studio_design_shell/studio_design_chat/studio_design_chat_view.html';
const VIEW_ANATOMY = 'ui/views/main_shell/design/anatomy/chat/chat_view.html';

// Q13 parallel-run: resolve the shell template once per request and use the
// result in EVERY render below — page and fragment handlers must agree, or a
// legacy fragment lands in an anatomy page as a silent hybrid (finding 8).
const shellView = (context) => abxResolveShellView(context, 'chat', VIEW, VIEW_ANATOMY);

// The retired Screen Chat surface, re-skinned onto the stage layout.
// ?screen=<id> pins a context chip; ?screen=none clears the context.
export const page = (context, helpers) =>
  helpers.render(context, shellView(context), { activeShell: 'design', ...facade.stageContext(helpers.session(context).data, { line: 'refine', pin: context.req.query('screen') ?? null, file: context.req.query('file'), panel: context.req.query('panel') }, helpers.prefs(context), helpers.translate(context), helpers.locale(context)) });

// Filmstrip thumb / artboard pin / activity card: toggle a screen's context chip
// (?state=toggle|on|off) — one swap re-renders chat chips + canvas outlines.
export const context = (context, helpers) =>
  helpers.render(context, `${shellView(context)}#panelsSwap`, facade.toggleContext(helpers.session(context).data, context.req.param('id'), context.req.query('state') ?? 'toggle', helpers.prefs(context), helpers.translate(context), helpers.locale(context)));

// Element context chips (inspect.js picks): pin/unpin an element by its data-el
// name. Both swap the whole stage — the composer tray lives there alongside the
// screen chips, and the canvas keeps rendering uninterrupted.
export const elementContext = async (context, helpers) => {
  const form = await helpers.form(context);
  return helpers.render(context, `${shellView(context)}#panelsSwap`, facade.pinElement(helpers.session(context).data, form.screen, form.name, form.kind, helpers.prefs(context), helpers.translate(context), helpers.locale(context), form.instance));
};

// Element context chip remove (GET — the composer chip's hx-get). Reads query
// params so no form body is needed.
export const elementContextRemove = (context, helpers) =>
  helpers.render(context, `${shellView(context)}#panelsSwap`, facade.unpinElement(helpers.session(context).data, context.req.query('screen'), context.req.query('name'), helpers.prefs(context), helpers.translate(context), helpers.locale(context)));

// Bulk pin from the marquee selection (drag.js POSTs ids=a,b,context).
export const bulkContext = async (context, helpers) => {
  const form = await helpers.form(context);
  const ids = context.req.query('ids') || form.ids || '';
  return helpers.render(context, `${shellView(context)}#panelsSwap`, facade.bulkPin(helpers.session(context).data, ids, helpers.prefs(context), helpers.translate(context), helpers.locale(context)));
};

// Legacy per-screen pick: now pins the chip and swaps the stage.
export const select = (context, helpers) =>
  helpers.render(context, `${shellView(context)}#panelsSwap`, facade.toggleContext(helpers.session(context).data, context.req.param('id'), 'on', helpers.prefs(context), helpers.translate(context), helpers.locale(context)));

// The single composer path: 'approve' signs the manifest, anything else
// refines the pinned screens. The legacy per-screen route pins its screen first.
export const send = async (context, helpers) => {
  const form = await helpers.form(context);
  const text = String(form.preset || form.text || '').trim();
  if (!text) return helpers.noContent(context);
  // The drawer-mounted composer (Screen Reveal-Drawer plan): ?screen= pins
  // the drawer's screen first (screen-scoped send), ?drawer= routes the
  // response back to that drawer's own container instead of #panels.
  const pin = context.req.param('id') ?? context.req.query('screen') ?? null;
  const data = facade.sendChat(helpers.session(context).data, text, helpers.prefs(context), pin, helpers.translate(context), helpers.locale(context));
  const resolvedShellView = shellView(context); // one resolution for both render paths below
  const drawer = context.req.query('drawer');
  if (drawer) {
    // draftSent is read per composer INSTANCE (composer.html drops
    // hx-preserve on the render that follows a send); only the drawer's own
    // spec gets it — the panel composer keeps any half-typed draft.
    const spec = data.viewer?.drawers?.[drawer]?.composer;
    if (spec) spec.draftSent = true;
    return helpers.render(context, `${resolvedShellView}#drawerSwap`, { ...data, drawerScreen: drawer });
  }
  return helpers.render(context, `${resolvedShellView}#panelsSwap`, data);
};

// Composer agent chrome: the model pick swaps the stage.
export const model = (context, helpers) =>
  helpers.render(context, `${shellView(context)}#panelsSwap`, facade.setModel(helpers.session(context).data, context.req.param('id'), {}, helpers.prefs(context), helpers.translate(context), helpers.locale(context)));

// The tray trigger: persist the collapse state and answer 204 — the
// checkbox already flipped and animates locally; a swap would replace the
// element mid-transition and kill the animation.
export const tray = (context, helpers) => {
  facade.setTray(helpers.session(context).data, context.req.query('state'), {}, {}, helpers.translate(context), helpers.locale(context));
  return helpers.noContent(context);
};

// One-tap revert of a checkpoint on a screen.
export const revert = (context, helpers) =>
  helpers.render(context, `${shellView(context)}#revertSwap`, facade.revertCheckpoint(helpers.session(context).data, context.req.param('id'), context.req.param('cp'), helpers.prefs(context), helpers.translate(context), helpers.locale(context)));
