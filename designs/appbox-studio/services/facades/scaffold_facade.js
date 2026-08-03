// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
// ScaffoldFacade — composes the scaffold.picker context. Session-held
// selection (Set of kit ids) layered over the fixture, dependency closure
// re-run on every mutation so D5 auto-includes stay correct after any add or
// remove, and the D2 removal confirm resolved from the fixture's `removal`
// block. Pure projection: no I/O beyond the repository, no client-side JS.
import * as repo from '../repositories/scaffold_repository.js';

// Same derivation the fixture generator uses — the registry declares no
// `depends` field, so topology is the coupling signal. Kept in sync by shape,
// not by import, because the facade must survive a fixture regenerated from a
// newer registry without a code change.
const DEPS = {
  'core-coupled': ['core'],
  'ui-tier': ['core'],
  'app-integration': ['core', 'ui_library'],
};
const dependsOf = (k) => (k.depends && k.depends.length ? k.depends : DEPS[k.topology] || []).filter((d) => d !== k.id);

/** Resolve the closure: hand-picked ids in → {selected, auto} out. */
const closure = (picked, byId) => {
  const selected = new Set(picked);
  const auto = new Set();
  let grew = true;
  while (grew) {
    grew = false;
    for (const id of [...selected]) {
      for (const d of dependsOf(byId[id] || {})) {
        if (!selected.has(d)) { selected.add(d); auto.add(d); grew = true; }
      }
    }
  }
  return { selected, auto };
};

/** The session's picked set, defaulting to the design-detected selection. */
const pickedFrom = (session, locale) => {
  const fixture = repo.kits(locale);
  if (session && Array.isArray(session.scaffoldPicked)) return new Set(session.scaffoldPicked);
  // Default state per brief (a): design-detected kits pre-selected, essentials
  // always on. Never a blank grid.
  //
  // `pickedByDesign` is the pre-closure selection; `selected` is post-closure.
  // Seeding from pickedByDesign lets closure() re-derive dependencies here so
  // they carry the `auto` flag and the D5 "added for you" notice is visible on
  // first paint. Seeding from `selected` would silently include them with no
  // explanation — exactly the opacity D5 exists to prevent.
  return new Set(fixture.filter((k) => k.pickedByDesign).map((k) => k.id));
};

/**
 * context — the `c` object every picker template macro reads.
 *
 * @param session  server-held session (holds scaffoldPicked, pendingRemove)
 * @param t        translator
 * @param locale   active locale
 * @param screen   requested lens state: success | empty | loading | error | notEntitled | signedOut
 */
export const context = (session = {}, t = (k) => k, locale = 'en', screen = 'success') => {
  const all = repo.kits(locale);
  const byId = Object.fromEntries(all.map((k) => [k.id, k]));
  const ent = repo.entitlement(locale);
  const essentials = repo.essentials(locale);
  const states = repo.states(locale);

  // --- entitlement gate (brief (a): signed-out / not-entitled state) --------
  // Signed-out shows the same picker, read-only, with the real kit list
  // visible — the value is legible before the paywall, never a blank wall.
  // Two distinct gates that happen to share one read-only presentation:
  // signed-out is answered by signing in, not-entitled by upgrading. The
  // copy and the CTA must differ, or we send a signed-out user to a paywall.
  const signedOut = screen === 'signedOut' || !ent.signedIn;
  const gated = signedOut || screen === 'notEntitled' || !ent.entitled;
  const gatedReason = signedOut ? 'signedOut' : 'notEntitled';

  const picked = screen === 'empty' ? new Set(essentials) : pickedFrom(session, locale);
  const { selected, auto } = closure(picked, byId);

  const kits = all.map((k) => ({
    ...k,
    selected: selected.has(k.id),
    auto: auto.has(k.id),
    essential: essentials.includes(k.id),
    // Locked = essential (cannot be removed) or auto-included while its
    // dependent is still selected. Both are D5 consequences, not D2 removals.
    locked: essentials.includes(k.id) || auto.has(k.id),
    requiredBy: all.filter((o) => selected.has(o.id) && dependsOf(o).includes(k.id)).map((o) => o.id),
    // Toggle target. add/remove are distinct routes so the remove path can
    // interpose the D2 confirm without a client-side branch.
    href: selected.has(k.id) ? `/main/scaffold/picker/remove?kit=${k.id}` : `/main/scaffold/picker/add?kit=${k.id}`,
    credentialsHref: k.readinessAxis && k.readinessAxis.module
      ? `${ent.credentialsHref}?module=${encodeURIComponent(k.readinessAxis.module)}`
      : ent.credentialsHref,
  }));

  const chosen = kits.filter((k) => k.selected);
  const groupOrder = ['core', 'integrations', 'platform', 'advanced'];
  const groups = groupOrder
    .map((id) => {
      const items = kits.filter((k) => k.group === id);
      return {
        id,
        label: t(`scaffold.picker.group.${id}`),
        kits: items,
        count: items.length,
        selectedCount: items.filter((k) => k.selected).length,
      };
    })
    .filter((g) => g.count > 0);

  // --- D2: pending removal confirm ----------------------------------------
  // Removing a kit a screen declared does not silently break that screen: the
  // confirm names the declaring screens and states the forced fallback.
  const pending = session && session.pendingRemove ? byId[session.pendingRemove] : null;
  const confirm = pending
    ? {
        kit: pending,
        screens: pending.removal.declaringScreens,
        forcesFallback: pending.removal.forcesFallback,
        fallback: pending.removal.fallback,
        // A kit other selected kits depend on cannot be removed at all — the
        // confirm degrades into an explanation.
        blockedBy: kits.filter((k) => k.selected && dependsOf(k).includes(pending.id)).map((k) => k.id),
        confirmHref: `/main/scaffold/picker/remove/confirm?kit=${pending.id}`,
        cancelHref: '/main/scaffold/picker',
      }
    : null;

  // --- D5 notice: what got pulled in on the user's behalf ------------------
  const autoNotice = chosen.filter((k) => k.auto);

  // --- D6: inform-only readiness roll-up -----------------------------------
  // Counted and surfaced, never a gate. The deploy screen owns the hard block.
  const unready = chosen.filter((k) => !k.readinessAxis.ready);

  const counts = {
    total: kits.length,
    selected: chosen.length,
    declared: chosen.filter((k) => k.provenance === 'declared').length,
    inferred: chosen.filter((k) => k.provenance === 'inferred').length,
    requested: chosen.filter((k) => k.provenance === 'requested').length,
    auto: autoNotice.length,
    unready: unready.length,
  };

  const manifest = {
    ...repo.manifest(locale),
    resolved: chosen.map((k) => ({ id: k.id, package: k.package, provenance: k.provenance, auto: k.auto })),
    todos: unready.map((k) => ({ id: k.id, missing: k.readinessAxis.missing })),
  };

  return {
    base: '/main/scaffold/picker',
    // Report the gate we actually applied, so a signedOut lens never reports
    // itself as notEntitled to a probe or a lens validator.
    state: gated ? gatedReason : screen,
    loading: screen === 'loading',
    error: screen === 'error' ? { ...states.error, source: states.error.source } : null,
    gated,
    gatedReason,
    entitlement: {
      ...ent,
      signedIn: !signedOut,
      // Signed-out goes to sign-in; not-entitled goes to the upgrade path.
      // Read only by gatedNotice, so signedOut is the only split that matters.
      ctaHref: signedOut ? ent.signInHref || '/sign-in' : ent.upgradeHref || ent.credentialsHref,
    },
    kits,
    groups,
    chosen,
    counts,
    confirm,
    autoNotice,
    unready,
    manifest,
    // Forward is never blocked by readiness (D6) — only by having nothing.
    canContinue: !gated && chosen.length > 0,
    continueHref: '/main/scaffold/plan',
  };
};

export default { context };
