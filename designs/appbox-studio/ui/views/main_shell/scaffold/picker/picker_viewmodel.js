// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
export const surfaceId = 'scaffold.picker';

import * as facade from '../../../../../services/facades/scaffold_facade.js';

const VIEW = 'ui/views/main_shell/scaffold/picker/picker_view.html';

// The template reads `context.*`, but the context is spread top-level, never nested
// under a literal `context` key: the runtime does `bag.context = bag` after merging (see
// runtime/lib/helpers.mjs), so a `context:` we passed would be overwritten and the
// whole facade context silently dropped. Every other viewmodel spreads.
const ctx = (context, helpers, screen) => ({
  activeShell: 'scaffold',
  ...facade.context(helpers.session(context).data, helpers.translate(context), helpers.locale(context), screen || context.req.query('state')),
});

/** Session-held selection. Seeded from the fixture on first touch. */
const picked = (context, helpers) => {
  const s = helpers.session(context).data;
  if (!Array.isArray(s.scaffoldPicked)) {
    s.scaffoldPicked = facade
      .context(s, helpers.translate(context), helpers.locale(context))
      .chosen.filter((k) => !k.auto)
      .map((k) => k.id);
  }
  return s;
};

export const page = (context, helpers) => helpers.render(context, VIEW, ctx(context, helpers));

// Panel width grip: s/m/l persisted per side, whole-panel re-render. Mirrors
// the run surface exactly — same shell chrome, same swap target — so the grip
// does not behave differently depending on which scaffold screen you are on.
export const panelSize = (context, helpers) =>
  helpers.render(context, `${VIEW}#panelsSwap`, {
    activeShell: 'scaffold',
    ...facade.setPanelSize(
      helpers.session(context).data,
      context.req.param('panel'),
      context.req.param('size'),
      helpers.translate(context),
      helpers.locale(context),
      context.req.query('state'),
    ),
  });

// --- composer ----------------------------------------------------------
// The shell mounts a composer on every scaffold surface (_shared.html), and
// scaffold_facade sets its action unconditionally, so this screen posts a
// real form. This is the handler that receives it. Empty input is a no-op
// (204), matching every other composer in the shell; anything else appends a
// turn and swaps the panels back, carrying the lens it was posted from.
export const sendMessage = async (context, helpers) => {
  const form = await helpers.form(context);
  const text = String(form.text || '').trim();
  if (!text) return helpers.noContent(context);
  return helpers.render(context, `${VIEW}#panelsSwap`, {
    activeShell: 'scaffold',
    ...facade.sendMessage(
      helpers.session(context).data,
      text,
      helpers.translate(context),
      helpers.locale(context),
      context.req.query('state'),
    ),
  });
};

// --- add ---------------------------------------------------------------
// Adding is unconditional: D5 dependency pull-in happens in the facade's
// closure pass, so the caller never has to know what a kit drags along.
// D8: every confirmed selection change persists the kit-manifest sidecar.
export const add = async (context, helpers) => {
  const form = await helpers.form(context);
  const kit = String(form.kit || '').trim();
  if (!kit) return helpers.noContent(context);
  const s = picked(context, helpers);
  if (!s.scaffoldPicked.includes(kit)) s.scaffoldPicked.push(kit);
  s.pendingRemove = null;
  await facade.persistKitManifest(s, helpers.translate(context), helpers.locale(context));
  return helpers.render(context, `${VIEW}#gridSwap`, ctx(context, helpers));
};

// --- remove (D2, two steps) --------------------------------------------
// Step 1 stages the removal so the confirm can name the declaring screens
// and the forced fallback. A kit no screen declared still routes through
// here — one path, no silent branch.
export const remove = async (context, helpers) => {
  const form = await helpers.form(context);
  const kit = String(form.kit || '').trim();
  if (!kit) return helpers.noContent(context);
  const s = picked(context, helpers);
  s.pendingRemove = kit;
  return helpers.render(context, `${VIEW}#gridSwap`, ctx(context, helpers));
};

// Step 2 commits it. Essentials and kits others still depend on are refused
// here as well as in the template — the server never trusts the markup.
// D8: a committed removal persists the kit-manifest sidecar; a refused one
// changed nothing, so it writes nothing.
export const removeConfirm = async (context, helpers) => {
  const s = picked(context, helpers);
  const kit = context.req.query('kit') || s.pendingRemove;
  const view = facade.context(s, helpers.translate(context), helpers.locale(context));
  const target = view.kits.find((k) => k.id === kit);
  const blocked = !target || target.essential || (view.confirm && view.confirm.blockedBy.length > 0);
  if (!blocked) {
    s.scaffoldPicked = s.scaffoldPicked.filter((id) => id !== kit);
    await facade.persistKitManifest(s, helpers.translate(context), helpers.locale(context));
  }
  s.pendingRemove = null;
  return helpers.render(context, `${VIEW}#panelsSwap`, ctx(context, helpers));
};

export const cancelRemove = (context, helpers) => {
  const s = picked(context, helpers);
  s.pendingRemove = null;
  return helpers.render(context, `${VIEW}#gridSwap`, ctx(context, helpers));
};
