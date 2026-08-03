// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
export const surfaceId = 'scaffold.picker';

import * as facade from '../../../../../services/facades/scaffold_facade.js';

const VIEW = 'ui/views/main_shell/scaffold/picker/picker_view.html';

// The template reads `c.*`, but the context is spread top-level, never nested
// under a literal `c` key: the runtime does `bag.c = bag` after merging (see
// runtime/lib/helpers.mjs), so a `c:` we passed would be overwritten and the
// whole facade context silently dropped. Every other viewmodel spreads.
const ctx = (c, h, screen) => ({
  activeShell: 'scaffold',
  ...facade.context(h.session(c).data, h.t(c), h.locale(c), screen || c.req.query('state') || 'success'),
});

/** Session-held selection. Seeded from the fixture on first touch. */
const picked = (c, h) => {
  const s = h.session(c).data;
  if (!Array.isArray(s.scaffoldPicked)) {
    s.scaffoldPicked = facade
      .context(s, h.t(c), h.locale(c))
      .chosen.filter((k) => !k.auto)
      .map((k) => k.id);
  }
  return s;
};

export const page = (c, h) => h.render(c, VIEW, ctx(c, h));

// Panel width grip: s/m/l persisted per side, whole-panel re-render. Mirrors
// the run surface exactly — same shell chrome, same swap target — so the grip
// does not behave differently depending on which scaffold screen you are on.
export const panelSize = (c, h) =>
  h.render(c, `${VIEW}#panelsSwap`, {
    activeShell: 'scaffold',
    ...facade.setPanelSize(
      h.session(c).data,
      c.req.param('panel'),
      c.req.param('size'),
      h.t(c),
      h.locale(c),
      c.req.query('state') || 'success',
    ),
  });

// --- add ---------------------------------------------------------------
// Adding is unconditional: D5 dependency pull-in happens in the facade's
// closure pass, so the caller never has to know what a kit drags along.
export const add = async (c, h) => {
  const form = await h.form(c);
  const kit = String(form.kit || '').trim();
  if (!kit) return h.noContent(c);
  const s = picked(c, h);
  if (!s.scaffoldPicked.includes(kit)) s.scaffoldPicked.push(kit);
  s.pendingRemove = null;
  return h.render(c, `${VIEW}#gridSwap`, ctx(c, h));
};

// --- remove (D2, two steps) --------------------------------------------
// Step 1 stages the removal so the confirm can name the declaring screens
// and the forced fallback. A kit no screen declared still routes through
// here — one path, no silent branch.
export const remove = async (c, h) => {
  const form = await h.form(c);
  const kit = String(form.kit || '').trim();
  if (!kit) return h.noContent(c);
  const s = picked(c, h);
  s.pendingRemove = kit;
  return h.render(c, `${VIEW}#gridSwap`, ctx(c, h));
};

// Step 2 commits it. Essentials and kits others still depend on are refused
// here as well as in the template — the server never trusts the markup.
export const removeConfirm = (c, h) => {
  const s = picked(c, h);
  const kit = c.req.query('kit') || s.pendingRemove;
  const view = facade.context(s, h.t(c), h.locale(c));
  const target = view.kits.find((k) => k.id === kit);
  const blocked = !target || target.essential || (view.confirm && view.confirm.blockedBy.length > 0);
  if (!blocked) s.scaffoldPicked = s.scaffoldPicked.filter((id) => id !== kit);
  s.pendingRemove = null;
  return h.render(c, `${VIEW}#panelsSwap`, ctx(c, h));
};

export const cancelRemove = (c, h) => {
  const s = picked(c, h);
  s.pendingRemove = null;
  return h.render(c, `${VIEW}#gridSwap`, ctx(c, h));
};
