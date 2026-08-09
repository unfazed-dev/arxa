// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
// ScaffoldFacade — composes the scaffold.picker context. Session-held
// selection (Set of kit ids) layered over the fixture, dependency closure
// re-run on every mutation so D5 auto-includes stay correct after any add or
// remove, and the D2 removal confirm resolved from the fixture's `removal`
// block. Pure projection: no I/O beyond the repository, no client-side JS.
import * as repo from '../repositories/scaffold_repository.js';
// The gate and the header chip read the REAL seeded session (sign-in,
// checkout-apply, sign-out all flip it) — the app shell owns those session
// keys, so the shape is read through its one helper, never re-derived here.
import { accountState } from './app_facade.js';

// Same derivation the fixture generator uses — the registry declares no
// `depends` field, so topology is the coupling signal. Kept in sync by shape,
// not by import, because the facade must survive a fixture regenerated from a
// newer registry without a code change.
const DEPS = {
  'core-coupled': ['core'],
  'ui-tier': ['core'],
  'app-integration': ['core', 'ui_library'],
};
const dependsOf = (kit) => (kit.depends && kit.depends.length ? kit.depends : DEPS[kit.topology] || []).filter((dependencyId) => dependencyId !== kit.id);

/** Resolve the closure: hand-picked ids in → {selected, auto} out. */
const closure = (picked, byId) => {
  const selected = new Set(picked);
  const auto = new Set();
  let grew = true;
  while (grew) {
    grew = false;
    for (const id of [...selected]) {
      for (const dependencyId of dependsOf(byId[id] || {})) {
        if (!selected.has(dependencyId)) { selected.add(dependencyId); auto.add(dependencyId); grew = true; }
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
  return new Set(fixture.filter((kit) => kit.pickedByDesign).map((kit) => kit.id));
};

/**
 * context — the `c` object every picker template macro reads.
 *
 * @param session  server-held session (holds scaffoldPicked, pendingRemove)
 * @param t        translator
 * @param locale   active locale
 * @param screen  requested lens state: success | empty | loading | error | notEntitled | signedout
 *
 * Lens tokens arrive from `?state=` and are matched case-insensitively. The
 * repo spells this vocabulary two ways — the registry and the lens probes use
 * lowercase `signedout`, this facade emitted camelCase `signedOut` — and an
 * exact match silently fell through to `success`, rendering an ungated picker
 * for a signed-out probe. Normalise the input; keep `gatedReason` camelCase,
 * which is what the view and the l10n keys already branch on.
 *
 * `?state=` is a DEBUG OVERRIDE: any explicit value renders exactly that lens
 * (gate states included) regardless of session. With NO override the gate
 * follows the real seeded session — signed-out → signedOut gate, signed-in
 * without a plan → notEntitled gate, entitled → ungated.
 */
export const context = (session = {}, translate = (key) => key, locale = 'en', screen) => {
  const all = repo.kits(locale);
  const byId = Object.fromEntries(all.map((kit) => [kit.id, kit]));
  const ent = repo.entitlement(locale);
  const essentials = repo.essentials(locale);
  const states = repo.states(locale);

  // --- entitlement gate (brief (a): signed-out / not-entitled state) --------
  // Signed-out shows the same picker, read-only, with the real kit list
  // visible — the value is legible before the paywall, never a blank wall.
  // Two distinct gates that happen to share one read-only presentation:
  // signed-out is answered by signing in, not-entitled by upgrading. The
  // copy and the CTA must differ, or we send a signed-out user to a paywall.
  const lens = String(screen ?? '').toLowerCase();
  const gateOverride = lens === 'signedout' || lens === 'notentitled';
  const acct = accountState(session);
  // An explicit non-gate lens keeps the fixture's seeded entitlement (the
  // debug override); gate lenses force theirs; no lens → the session.
  const effSignedIn = gateOverride ? lens === 'notentitled' : lens !== '' || acct.signedIn;
  const effEntitled = gateOverride ? false : lens !== '' || acct.entitled;
  const signedOut = !effSignedIn;
  const gated = !effSignedIn || !effEntitled;
  const gatedReason = signedOut ? 'signedOut' : 'notEntitled';

  const picked = lens === 'empty' ? new Set(essentials) : pickedFrom(session, locale);
  const { selected, auto } = closure(picked, byId);

  const kits = all.map((kit) => ({
    ...kit,
    selected: selected.has(kit.id),
    auto: auto.has(kit.id),
    essential: essentials.includes(kit.id),
    // Locked = essential (cannot be removed) or auto-included while its
    // dependent is still selected. Both are D5 consequences, not D2 removals.
    locked: essentials.includes(kit.id) || auto.has(kit.id),
    requiredBy: all.filter((otherKit) => selected.has(otherKit.id) && dependsOf(otherKit).includes(kit.id)).map((otherKit) => otherKit.id),
    // Toggle target. add/remove are distinct routes so the remove path can
    // interpose the D2 confirm without a client-side branch.
    href: selected.has(kit.id) ? `/scaffold/remove?kit=${kit.id}` : `/scaffold/add?kit=${kit.id}`,
    credentialsHref: kit.readinessAxis && kit.readinessAxis.module
      ? `${ent.credentialsHref}?module=${encodeURIComponent(kit.readinessAxis.module)}`
      : ent.credentialsHref,
  }));

  const chosen = kits.filter((kit) => kit.selected);
  const groupOrder = ['core', 'integrations', 'platform', 'advanced'];
  const groups = groupOrder
    .map((id) => {
      const items = kits.filter((kit) => kit.group === id);
      return {
        id,
        label: translate(`scaffold.picker.group.${id}`),
        kits: items,
        count: items.length,
        selectedCount: items.filter((kit) => kit.selected).length,
      };
    })
    .filter((group) => group.count > 0);

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
        blockedBy: kits.filter((kit) => kit.selected && dependsOf(kit).includes(pending.id)).map((kit) => kit.id),
        confirmHref: `/scaffold/remove/confirm?kit=${pending.id}`,
        // Not '/scaffold': cancelling has to clear the staged removal on the
        // server (picker.cancelRemove). Pointing this at the page would
        // re-render with pendingRemove still set — cancel that never cancels.
        cancelHref: '/scaffold/remove/cancel',
      }
    : null;

  // --- D5 notice: what got pulled in on the user's behalf ------------------
  const autoNotice = chosen.filter((kit) => kit.auto);

  // --- D6: inform-only readiness roll-up -----------------------------------
  // Counted and surfaced, never a gate. The deploy screen owns the hard block.
  const unready = chosen.filter((kit) => !kit.readinessAxis.ready);

  const counts = {
    total: kits.length,
    selected: chosen.length,
    declared: chosen.filter((kit) => kit.provenance === 'declared').length,
    inferred: chosen.filter((kit) => kit.provenance === 'inferred').length,
    requested: chosen.filter((kit) => kit.provenance === 'requested').length,
    auto: autoNotice.length,
    unready: unready.length,
  };

  const manifest = {
    ...repo.manifest(locale),
    resolved: chosen.map((kit) => ({ id: kit.id, package: kit.package, provenance: kit.provenance, auto: kit.auto })),
    todos: unready.map((kit) => ({ id: kit.id, missing: kit.readinessAxis.missing })),
  };

  return {
    // --- shell chrome (read by ui/views/main_shell/scaffold/_shared.html) ---
    // The scaffold shell composes its own panel row; a surface hosted in it
    // must fill the fields that composition reads. Every one is set
    // explicitly, including the empty cases: a missing `c.thread` renders a
    // composer with nothing above it and no error, which reads as "there is
    // nothing to say here" instead of "this facade forgot to say it".
    panel: session.scaffoldPanel || 'main',
    // Store is the map (`setPanelSize` below writes scaffoldPanelSize[panel]);
    // emit is the resolved scalar for the one panel the shell resizes — the
    // same store-map/emit-scalar split as run's facade (panelSizeFor). The
    // shared chrome reads `panelSize`/`panelSizeHref`; the `panelSizes` map
    // had zero consumers. (Applied by team lead; picker-screen's fix, owners
    // unreachable at time of landing.)
    panelSize: PANEL_SIZES.includes(session.scaffoldPanelSize?.activity)
      ? session.scaffoldPanelSize.activity
      : 's',
    panelSizeHref: '/scaffold/panel/size/activity/',
    stageEyebrow: translate('scaffold.picker.eyebrow'),
    // The chips are the pinned context the composer carries: what is picked,
    // and how much of it still wants keys. Counts, not prose — the grid is
    // the place that explains itself.
    chips: [
      { label: translate('scaffold.picker.chip.selected', { count: chosen.length }) },
      ...(unready.length ? [{ label: translate('scaffold.picker.chip.unready', { count: unready.length }) }] : []),
    ],
    // The two opening rows are orientation and are always present; anything
    // the user has actually said follows them, in order. The session slot is
    // the same persistence shape as `scaffoldPanelSize` above — a plain field
    // on session data, so a re-render at any lens replays the same thread.
    thread: [
      { kind: 'event', text: translate('scaffold.picker.thread.detected', { count: counts.declared + counts.inferred }) },
      { from: 'agent', text: translate('scaffold.picker.thread.help') },
      ...(session.scaffoldThread || []),
    ],
    activity: {
      label: translate('scaffold.picker.activity.label'),
      views: [],
      // The selection, in the order the grid shows it, each row naming WHY it
      // is in the list — the same provenance vocabulary as the badge (D4), so
      // the panel and the card never disagree about a kit.
      // The label is `k.id`, exactly what kitCard's <h3> prints. Translating
      // it here would make the panel and the card name the same kit two
      // different ways; the display-name gap is real but it is one gap, and
      // it gets closed in both places at once or not at all.
      items: chosen.map((kit) => ({
        label: kit.id,
        meta: translate(`scaffold.picker.prov.${kit.provenance}`),
        active: !kit.readinessAxis.ready,
      })),
    },
    // The composer form lives in the shell's composition, not in this screen.
    // It posts here; the binding is the shell's to declare.
    // needs-route: POST /scaffold/messages (see routes.scaffold.js)
    composerAction: '/scaffold/messages',

    base: '/scaffold',
    // Report the gate we actually applied, so a signedOut lens never reports
    // itself as notEntitled to a probe or a lens validator.
    state: gated ? gatedReason : lens || 'success',
    loading: lens === 'loading',
    error: lens === 'error' ? { ...states.error, source: states.error.source } : null,
    gated,
    gatedReason,
    entitlement: {
      ...ent,
      signedIn: effSignedIn,
      // Session-derived (or the debug override's): the header chip reads this
      // to pick Sign in / Upgrade / plan badge.
      entitled: effEntitled,
      plan: acct.plan || ent.plan,
      // Signed-out goes to auth; not-entitled goes to the upgrade path. Read
      // by gatedNotice and the shell header's account chip, so signedOut is
      // the only split that matters. /auth and /workspace/plans both resolve.
      ctaHref: signedOut ? ent.signInHref || '/auth' : ent.upgradeHref || '/workspace/plans',
      // The account/plans surface is the header chip's destination in every
      // signed-in state — entitled or not.
      accountHref: '/workspace/plans',
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
    // Forward is the run receipt — the only bound next step in this shell.
    continueHref: '/scaffold/run',
  };
};

// Panel width grip: s/m/l persisted per side, whole-panel re-render. Same
// shape as the run surface's, because it is the same shell chrome; the sizes
// live under a picker-scoped session key so the two surfaces do not fight.
const PERSISTABLE_PANELS = ['composer', 'activity'];
const PANEL_SIZES = ['s', 'm', 'l'];

export const setPanelSize = (session = {}, panel, size, translate = (key) => key, locale = 'en', screen = 'success') => {
  if (PERSISTABLE_PANELS.includes(panel) && PANEL_SIZES.includes(size)) {
    (session.scaffoldPanelSize ??= {})[panel] = size;
  }
  return context(session, translate, locale, screen);
};

/**
 * Append a user turn and the agent's acknowledgement to the picker thread.
 *
 * Same argument order as `setPanelSize` — session first, `screen` last — so
 * the POST re-render keeps the lens it was posted from. Dropping `screen`
 * here would collapse all six states to `success` on every message, which no
 * selftest would catch: the route would still answer 200.
 *
 * The reply is a fixed acknowledgement from the ARB rather than a generated
 * one. This screen picks kits; it has no reply corpus of its own (unlike
 * intake, whose `replies`/`replyFallback` come from its repository), and
 * inventing one here would put words in the agent's mouth that no seed backs.
 */
export const sendMessage = (session = {}, text, translate = (key) => key, locale = 'en', screen = 'success') => {
  const body = String(text ?? '').trim();
  if (body) {
    const seq = (session.scaffoldThreadSeq = (session.scaffoldThreadSeq || 0) + 1);
    (session.scaffoldThread ??= []).push(
      { id: `u-${seq}`, from: 'user', text: body },
      // `t()` may return a lazy message object rather than a string. It
      // stringifies correctly on the request that creates it, so the newest
      // reply always looks right; but the session round-trips through JSON,
      // so an unresolved value replays as "[object Object]" on every later
      // render — every reply except the last one. Resolve the scalar before
      // storing it. Same store-map/emit-resolved-scalar split that
      // `panelSizeFor` was built for one screen over.
      { id: `a-${seq}`, from: 'agent', text: String(translate('scaffold.picker.thread.reply')) },
    );
  }
  return context(session, translate, locale, screen);
};

export default { context, setPanelSize };

/**
 * D8: persist the picker-confirmed selection as the kit-manifest.json sidecar
 * beside the project's frozen structure.json. Called by the mutation routes
 * (add / removeConfirm) AFTER the session selection changes, so the sidecar
 * always reflects the last confirmed set — scaffold is the single
 * authoritative merge point (D1), and only this set reaches the build.
 *
 * The sidecar carries the two sections D8 pins — `wishlist` (intake intent)
 * and `resolved` (picker-confirmed, provenance-labeled) — plus the D6
 * readiness `todos`. The descriptive fixture keys (`path`/`beside`/`sections`)
 * stay in the fixture: the sidecar IS the file they describe.
 *
 * Same argument order as `setPanelSize`/`sendMessage` (D36 local canon),
 * minus `screen`: the persisted set never depends on the preview lens.
 * Async — the write goes through the project's one confined write channel;
 * a failure throws (the widget writes' contract), because a picker that
 * confirms a set it cannot persist would silently ship the wrong kits.
 */
export const persistKitManifest = async (session = {}, translate = (key) => key, locale = 'en') => {
  const manifest = context(session, translate, locale).manifest;
  await repo.writeKitManifest({ wishlist: manifest.wishlist, resolved: manifest.resolved, todos: manifest.todos });
};
