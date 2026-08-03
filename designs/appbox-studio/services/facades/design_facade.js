// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
// DesignFacade — composes the design fixture with session-scoped state
// (pinned context chips, the design thread with
// per-screen checkpoints, manifest approval, drift rechecks) into exactly
// what the design viewmodels need.
// Leveled fixture strings pass through jargon.pick; static leveled copy
// lives in l10n/app_*.arb and is rendered by the runtime t() in the
// templates. The locale comes from the request and picks the per-locale
// fixture, en fallback.
import * as repo from '../repositories/design_repository.js';
import * as proj from '../repositories/project_repository.js';
import * as jargon from './jargon.js';
import * as agent from './agent_menus.js';
import * as fv from './file_views.js';

// Panel width steps, per panel — the shell's own persisted panel sizing.
export const PANEL_SIZES = ['s', 'm', 'l'];
// Panels whose width is server state, keyed by ROLE. Only the activity panel
// persists one; the composer's width is client-only and rides morph (drag.js
// omits data-persist for it). This list was `['left', 'right']` — a position
// whitelist for a value that was always the literal 'left', which would have
// silently rejected the role key and made every drag-release a no-op.
const PERSISTABLE_PANELS = ['activity'];
const panelSizeFor = (d, panel) => (PANEL_SIZES.includes(d.panelSize?.[panel]) ? d.panelSize[panel] : 's');

// All design-tab ephemeral UI state lives behind one namespace so it never
// collides with the build/intake surfaces sharing the session.
// Always drafted: intake hands design a generated design, so the artboard
// canvas with the docked composer IS the default view — no draft-all gate.
export const design = (sessionData) => (sessionData.design ??= { drafted: true });

// Context chip tones — stable per screen (fixture order), so a chip's colour
// always matches its canvas outline regardless of pin order. The first four
// names are chat.css's palette (chips get --ctx AND --ctx-soft there); blue
// and ember extend it in viewer.css for 11 screens with fewer collisions.
const TONES = ['cyan', 'violet', 'olive', 'amber', 'blue', 'ember'];
const toneFor = (id, L) => {
  const i = repo.screens(L).findIndex((s) => s.id === id);
  return TONES[(i < 0 ? 0 : i) % TONES.length];
};

// {label} / {kit} / {summary} / {id} placeholders in fixture reply strings.
const interpolate = (s, screen) =>
  !s ? s
    : s.replaceAll('{label}', screen?.label ?? '')
       .replaceAll('{kit}', String(screen?.kit ?? ''))
       .replaceAll('{summary}', screen?.summary ?? '')
       .replaceAll('{id}', screen?.id ?? '');

const fillReply = (reply, screen) => ({
  text: interpolate(reply.text, screen),
  textBalanced: interpolate(reply.textBalanced, screen),
  textPlain: interpolate(reply.textPlain, screen),
  link: reply.link ? { href: interpolate(reply.link.href, screen), label: reply.link.label } : null,
  checkpoint: reply.checkpoint ?? null,
  checkpointPlain: reply.checkpointPlain ?? null,
  before: reply.before ?? null,
  after: reply.after ?? null,
});

// ---------- the design line (footer panel timeline) ----------
// The design sub-steps, live: artboards (always green — the shell is always
// drafted), inspect · fine-tune (refinement state from pins, thread and
// checkpoints), the approval gate, freeze. Refinement acts move the states;
// the shared timeline macro highlights the first active item.
function timeline(d, L, t) {
  const seededCps = Object.values(repo.checkpoints(L)).flat().length;
  const chatCps = Object.values(d.chatCheckpoints ?? {}).flat().length;
  const refined = seededCps + chatCps > 0;
  const refining = !refined && (contextIds(d, L).length > 0 || (d.designThread ?? []).length > 0);
  const approved = d.approved ?? repo.approval(L).state === 'approved';
  const items = [
    { id: 'artboards', kind: 'stage', label: t('design.timeline.artboards'), state: 'green', href: '/design' },
    { id: 'refine', kind: 'stage', label: t('design.timeline.refine'), state: refined ? 'green' : refining ? 'active' : 'pending', href: '/design/chat' },
    { id: 'design.approval', kind: 'gate', label: t('design.timeline.approval'), state: approved ? 'approved' : refined ? 'active' : 'pending', href: '/design/freeze' },
    { id: 'freeze', kind: 'stage', label: t('design.timeline.freeze'), state: approved ? 'green' : 'pending', href: '/design/freeze' },
  ];
  const withRefs = items.map((i) => ({ ...i, ref: i.id }));
  return { items: withRefs, currentId: (items.find((i) => i.state === 'active') || {}).id ?? null };
}

// ---------- pinned context ----------

const contextIds = (d, L) => (d.context ?? []).filter((id) => repo.screen(id, L));
const pin = (d, id, L) => {
  if (repo.screen(id, L) && !contextIds(d, L).includes(id)) (d.context ??= []).push(id);
  d.trayOpen = true; // pinning auto-expands the composer's context tray
};
const unpin = (d, id, L) => {
  d.context = contextIds(d, L).filter((x) => x !== id);
};

// The composer tray's filmstrip: EVERY screen as a live thumb, horizontally
// scrollable. Flow: a thumb toggles that screen's chat-context chip (base
// scopes the route to the surface being rendered — /design/chat or
// /design/freeze — so the toggle swaps THAT surface's stage). Proto (the
// design canvas only): a thumb picks the wired-app preview's active screen,
// swapping just #design-viewer; the viewer hands those hrefs over as
// protoPicks (the tray lives outside #design-viewer, in #panels).
const filmstripFor = (d, base, L, viewer, noProto) => {
  const ids = contextIds(d, L);
  const picks = !noProto && viewer.protoPicks;
  return repo.screens(L).map((s) => ({
    id: s.id,
    label: repo.screen(s.id, L).label,
    tone: toneFor(s.id, L),
    inContext: ids.includes(s.id),
    dim: ids.length > 0 && !ids.includes(s.id),
    src: `${STUB_BASE}${s.id}?vp=mobile&embed=1&still=1`,
    ...(picks
      ? { protoHref: picks[s.id], active: s.id === viewer.proto.active }
      : { contextHref: `${base}/context/${s.id}?state=toggle` }),
  }));
};

const ctxLabel = (d, L, t) => contextIds(d, L).map((id) => repo.screen(id, L).label).join(' + ') || t('design.ctxFallback');

// ---------- undo / redo (two session stacks: canvas, chat) ----------
// Each entry carries enough to reverse itself in both directions, so the same
// object simply moves between the undo and redo stacks as the user steps back
// and forth. Canvas stack: flow edits (move/add/remove — replayed as project
// flows.json writes) + screen pin/unpin. Chat stack is wired for design-change
// checkpoints (contract §6).
const pushUndo = (d, stack, entry) => {
  (d.undoStacks ??= {}); (d.redoStacks ??= {});
  (d.undoStacks[stack] ??= []).push(entry);
  d.redoStacks[stack] = [];
};
const pushCanvasUndo = (d, entry) => pushUndo(d, 'canvas', entry);

// ---------- flow edit operations (WRITE the project's flows.json) ----------
// A flow is a linear edge list; chainOf derives the screen order by the same
// walk the flows lens renders (head = the edge whose `from` has no incoming
// edge, a seen-set guards a malformed cycle).
const chainOf = (flow) => {
  const edges = flow?.edges ?? [];
  const incoming = new Set(edges.map((e) => e.to));
  let cur = edges.find((e) => !incoming.has(e.from)) ?? edges[0];
  const chain = [];
  const seen = new Set();
  while (cur && !seen.has(cur.from)) {
    seen.add(cur.from);
    chain.push(cur);
    cur = edges.find((e) => e.from === cur.to);
  }
  return chain.length ? [chain[0].from, ...chain.map((e) => e.to)] : [];
};

// Rewire rule (the documented deterministic choice): rebuild edges pairwise
// from the new order; a pair already adjacent keeps its edge untouched, a NEW
// pair takes the FROM screen's previous outgoing trigger/action — the trigger
// names what you do ON that screen to advance, so it travels with the screen.
// `memory` (the move undo entry's per-screen trigger snapshot) is consulted
// next, so undoing a move that demoted a screen to chain tail still restores
// the trigger the file no longer carries; continue/push is the last fallback
// (an appended screen, or the old chain head).
// Exported for tools/check-flow-element.mjs, on the check-flow-guard.mjs
// precedent: it is PURE (mutates only the flow object handed to it, never
// reaches writeProjectFixture), so a node self-check can pin the element
// invariant without a server and without touching the live studio on :4319.
export const rewire = (flow, order, memory) => {
  const edges = flow.edges ?? [];
  const byPair = new Map(edges.map((e) => [`${e.from}→${e.to}`, e]));
  const outByFrom = new Map(edges.map((e) => [e.from, e]));
  flow.edges = order.slice(0, -1).map((from, i) => {
    const kept = byPair.get(`${from}→${order[i + 1]}`);
    if (kept) return kept;
    const prev = outByFrom.get(from) ?? memory?.[from];
    // `element` rides with `trigger`: both describe what the user touches to
    // take this edge, so a re-derived edge that kept the trigger but dropped
    // the element would silently downgrade the flow-walk island from an exact
    // match to a fuzzy one. Only re-derived edges pass through here — an
    // unchanged pair is returned whole above.
    //
    // Note this rides with the FROM screen, not with the (from, to) pair, and
    // that is deliberate: `element` selects a control ON `from` (the island
    // gets it as `walkel` and the destination separately as `walk`), so a
    // changed destination does not invalidate it. excise makes the same call
    // for the same reason (:222-224). Both `prev` sources are keyed by `from`,
    // so a carried element can never land on a screen that did not author it.
    //
    // BOTH `prev` sources must therefore be able to yield an element — the
    // memory branch is not a lesser fallback. It used to snapshot
    // `{ trigger, action }` only, which dropped `element` on exactly the path
    // that needs it most: a screen moved to the chain tail has no outgoing edge
    // left in the file, so undo re-derives it from memory alone. See moveMemory.
    return {
      from, to: order[i + 1],
      trigger: prev?.trigger ?? 'continue',
      action: prev?.action ?? 'push',
      ...(prev?.element ? { element: prev.element } : {}),
      // `feedback` rides with the trigger too, and for a second reason: emit
      // DERIVES a feedback from the trigger when none is declared
      // (intake.dart:481), so a re-derived edge that kept the trigger but dropped
      // the feedback would have it re-grown by the next emit — and the answers
      // dual-write would stop round-tripping. Carrying the declared value is the
      // opposite of restating that rule: declared always wins (:480). Copied
      // WHOLE, so the optional `feedback.action` button rides along too.
      ...(prev?.feedback ? { feedback: prev.feedback } : {}),
    };
  });
};

// The per-screen snapshot `rewire` consults as `memory`. Taken BEFORE a move,
// keyed by the edge's `from` screen. Exported so the self-check can build the
// same memory the facade does rather than restating its field list — the whole
// defect this closes was a field list stated in two places and drifting.
//
// It snapshots the WHOLE edge, deliberately, rather than naming the fields it
// wants. `rewire` reads `memory[from]` through exactly the same accessors it
// reads a live edge through (`prev?.trigger`, `prev?.element`, `prev?.feedback`),
// so anything an edge can carry is something the memory must be able to hand
// back. This used to be `{ trigger, action }` only, and that omission is the
// silent `element` dropper: move a screen to the chain TAIL and its outgoing
// edge leaves the file, so undo re-derives that edge from a memory that never
// held the element. Order came back perfect, `element` was gone for good, and
// the answers dual-write shipped the loss to answers.json. Listing fields here
// again would just re-arm the same trap for the next field added to an edge.
export const moveMemory = (flow) =>
  Object.fromEntries((flow?.edges ?? []).map((e) => [e.from, { ...e, action: e.action ?? 'push' }]));

// Would excising screenId leave the flow with any edges? A 0-edge flow is
// INVALID — appboxd/lib/intake.dart:283 hard-errors '$where: edges must be a
// non-empty list (a flow is a chain)' — and it is also a PERMANENT dead end,
// because appendTo bails on `!chain.length` so nothing can ever refill it.
// Removing either screen of a 2-screen flow does exactly that.
//
// Deliberately the POST-EXCISE COUNT, not a `chain.length <= 2` precondition.
// That shorthand is wrong twice over: it also refuses a screen the flow does not
// contain (excise's own no-op case, which changes nothing and so cannot empty
// anything), and it reads as a rule about flow size rather than about the
// invariant it protects. A non-member returns the CURRENT count, which is why it
// stays true. ONE definition, two consumers — the removeFromFlow guard and the
// `canRemove` each flows-lens tile carries — so the greyed-out toolbar button and
// the refusal can never drift apart.
export const canRemoveFrom = (flow, screenId) => {
  const edges = flow?.edges ?? [];
  const incoming = edges.find((e) => e.to === screenId) ?? null;
  const outgoing = edges.find((e) => e.from === screenId) ?? null;
  if (!incoming && !outgoing) return edges.length > 0;
  const rest = edges.filter((e) => e !== incoming && e !== outgoing).length;
  return rest + (incoming && outgoing ? 1 : 0) > 0;
};

// Cut screenId out of the chain, stitching the gap: the incoming edge's from
// links to the outgoing edge's to KEEPING THE INCOMING trigger; removing the
// head/tail just drops the one edge. Returns the undo payload (null when the
// screen is not a member).
const excise = (flow, screenId) => {
  const edges = flow.edges ?? [];
  const incoming = edges.find((e) => e.to === screenId) ?? null;
  const outgoing = edges.find((e) => e.from === screenId) ?? null;
  if (!incoming && !outgoing) return null;
  const at = edges.indexOf(incoming ?? outgoing);
  const rest = edges.filter((e) => e !== incoming && e !== outgoing);
  const stitch = incoming && outgoing
    ? [{
      from: incoming.from, to: outgoing.to,
      trigger: incoming.trigger, action: incoming.action ?? 'push',
      // Same rule as the trigger: the stitch keeps the INCOMING edge's
      // element, because the element lives on the `from` screen and that
      // screen is unchanged by the excision.
      ...(incoming.element ? { element: incoming.element } : {}),
      // ...and its `feedback`, same reason as in rewire: emit re-derives a
      // dropped feedback from the trigger the stitch just kept
      // (intake.dart:481), so dropping it here would break the answers
      // round-trip. Declared wins (:480), so carrying it restates no emit rule,
      // and copying it whole carries any `feedback.action` with it.
      ...(incoming.feedback ? { feedback: incoming.feedback } : {}),
    }]
    : [];
  flow.edges = [...rest.slice(0, at), ...stitch, ...rest.slice(at)];
  return { incoming, outgoing };
};

// Append screenId to the chain's tail: one new edge off the last screen.
const appendTo = (flow, screenId) => {
  const chain = chainOf(flow);
  if (!chain.length || chain.includes(screenId)) return false;
  (flow.edges ??= []).push({ from: chain[chain.length - 1], to: screenId, trigger: 'continue', action: 'push' });
  return true;
};

// Reverse of excise: drop the stitch edge and put the stored incoming/outgoing
// edges back where they were (entry.index = the screen's chain position
// before removal).
const restore = (flow, entry) => {
  const edges = flow.edges ?? [];
  const without = entry.incoming && entry.outgoing
    ? edges.filter((e) => !(e.from === entry.incoming.from && e.to === entry.outgoing.to))
    : [...edges];
  const at = entry.incoming ? Math.max(0, entry.index - 1) : entry.index;
  const back = [entry.incoming, entry.outgoing].filter(Boolean);
  flow.edges = [...without.slice(0, at), ...back, ...without.slice(at)];
};

// Flow entries replay their file write in both directions (re-deriving edges
// from the CURRENT file, so triggers follow their from screen); pin/chat
// entries stay pure session state.
const applyEntry = async (d, entry, dir) => {
  if (entry.type === 'flow-move' || entry.type === 'flow-add' || entry.type === 'flow-remove') {
    const flows = proj.flows();
    const flow = flows.find((f) => f.id === entry.flowId);
    if (!flow) return;
    if (entry.type === 'flow-move') rewire(flow, dir === 'undo' ? entry.before : entry.after, entry.triggers);
    else if (entry.type === 'flow-add') {
      // This canRemoveFrom is DEFENSIVE, not load-bearing — say so rather than
      // let a future reader assume it protects something. appendTo refuses an
      // empty chain, so a flow-add entry always has an edge left to fall back
      // to and the guard cannot fire here. It exists so that NO replay path can
      // reach the 0-edge state, not because this one could.
      if (dir === 'undo') { if (!canRemoveFrom(flow, entry.screenId)) return; excise(flow, entry.screenId); }
      else appendTo(flow, entry.screenId);
    } else if (dir === 'undo') restore(flow, entry);
    // Redo of a flow-remove re-runs the same excise, so it inherits the same
    // refusal: an entry recorded when the flow was longer must not replay into
    // a chain that has since shrunk to its last edge.
    else if (!canRemoveFrom(flow, entry.screenId)) return;
    else excise(flow, entry.screenId);
    await proj.writeFlowsDual(flows, [entry.flowId]);
  } else if (entry.type === 'pin' || entry.type === 'unpin') {
    // A 'pin' entry means a pin happened: undo unpins, redo re-pins. 'unpin' is
    // the mirror. Membership is toggled directly on d.context (the same array
    // pin()/unpin() maintain) so canUndo/canRedo stay honest about state.
    const wantPinned = entry.type === 'pin' ? dir !== 'undo' : dir === 'undo';
    const has = (d.context ?? []).includes(entry.screenId);
    if (wantPinned && !has) (d.context ??= []).push(entry.screenId);
    if (!wantPinned && has) d.context = d.context.filter((x) => x !== entry.screenId);
  } else if (entry.type === 'chat') {
    // Undo truncates the thread to the pre-message length and stashes the
    // removed messages + checkpoints in the entry for redo to re-append.
    const thread = (d.designThread ??= []);
    if (dir === 'undo') {
      entry.removedMsgs = thread.splice(entry.threadLenBefore);
      entry.removedCps = [];
      for (const { screen, cp } of entry.checkpointIds) {
        const list = d.chatCheckpoints?.[screen] ?? [];
        const found = list.find((x) => x.id === cp);
        if (found) { entry.removedCps.push({ screen, cp: found }); d.chatCheckpoints[screen] = list.filter((x) => x.id !== cp); }
      }
    } else {
      thread.push(...(entry.removedMsgs ?? []));
      for (const { screen, cp } of entry.removedCps ?? []) ((d.chatCheckpoints ??= {})[screen] ??= []).push(cp);
    }
  }
};

// ---------- the shared design viewer (ui/views/main_shell/shared/widgets/design_viewer.html) ----------
// Three lenses over the current project's screens, switched by the `mode`
// viewer param: 'views' (default; legacy mode=flow falls through to it) —
// every screen as a flat wrapping grid in REGISTRY order; 'flows' — one
// dashed row per project flow, tiles in edge-chain order with trigger-labelled
// connectors; 'proto' — the wired-app preview, one screen live at a real rung
// size inside device chrome (screen/vp params; one mobile chrome, no os
// dimension). Per-tile viewer state: `inspect=<screenId>` arms the inspect
// island in that tile's iframe, `live=<screenId>` drops still=1 and makes the
// tile interactive (one live tile at a time by construction — single key).
// The mini panel is a single controller panel (mode/fullscreen/undo-redo) +
// the bar's device rung icons and bg swatches; the screens filmstrip lives in
// the composer tray, where proto mode turns its thumbs into the
// active-screen picker (protoPicks).
const RUNG_VP = { 390: 'mobile', 744: 'tablet', 1280: 'desktop' };
const VP_HEIGHTS = { mobile: 844, tablet: 1133, desktop: 800 };

// Every canvas tile/thumb/proto frame iframes the stub renderer: the
// app-under-design (Portalo) is design CONTENT served by /build/screens,
// never a live studio route.
const STUB_BASE = '/build/screens/';

function viewerFor(d, L, t) {
  const v = d.viewer ?? {};
  const ids = contextIds(d, L);
  const base = '/design/viewer';
  const contextBase = '/design/chat/context/';

  const vp = ['mobile', 'tablet', 'desktop'].includes(v.vp) ? v.vp : 'mobile';

  // Tile order is the project REGISTRY order (the views lens is a flat grid
  // over it); the tile data itself comes from the design-stage fixture
  // (rungs/kit/state). Fallback: fixture order when no project is overlaid.
  const fixture = repo.screens(L);
  let registryIds = [];
  try { registryIds = proj.registry().map((e) => e.id); } catch { /* artifact-only serving */ }
  const ordered = registryIds.length
    ? registryIds.map((id) => fixture.find((s) => s.id === id)).filter(Boolean)
    : fixture;

  const bg = ['canvas', 'warm', 'slate'].includes(v.bg) ? v.bg : 'canvas';
  const mode = ['views', 'flows', 'proto'].includes(v.mode) ? v.mode : 'views';
  const active = ordered.some((s) => s.id === v.screen) ? v.screen : ordered[0]?.id;
  // Per-tile params: the screen id they name, else null (unknown ids drop).
  const inspect = ordered.some((s) => s.id === v.inspect) ? v.inspect : null;
  // Flow mode is FLOWS-ONLY. A stale `?live=<id>` carried into views (a shared
  // URL, a lens switch that kept the param) must not paint .is-live on a views
  // tile: pointer-events:auto, interactive, and no close control reachable
  // because the tool that offers one only renders in flows.
  //
  // This clamp is ONE of two independent protections — the other is that the
  // views-lens screens entries below carry no `live` field at all. Either alone
  // is sufficient, which is worth knowing before "simplifying" one away:
  // probe-flowwalk's "stale walk params cannot arm a views tile" only goes red
  // when BOTH are removed (verified by removing each, then both). They are kept
  // because they do different jobs — this one also stops `live=` persisting
  // into every views href via withParams, which the structural one does not.
  const live = mode === 'flows' && ordered.some((s) => s.id === v.live) ? v.live : null;

  // The flow WALK: which flow row is being walked, and which screen in its
  // chain is the current step. `live` above is only "this tile is interactive";
  // the walk is what makes the ROW track a position, which is the whole point —
  // the destination is well-defined here because the row names the flow, and
  // ambiguous anywhere else (portalo.home advances to checkout in
  // flow-browse-buy and to account in flow-account).
  const walkFlow = mode === 'flows' && typeof v.flow === 'string' && v.flow ? v.flow : null;
  const walkStep = walkFlow && ordered.some((s) => s.id === v.step) ? v.step : null;

  // Device rungs as mini-bar icon buttons (lucide names, picked up by the
  // server's template icon scan). One mobile chrome — no os dimension.
  const DEVICES = [
    { key: 'mobile', icon: 'smartphone' },
    { key: 'tablet', icon: 'tablet' },
    { key: 'desktop', icon: 'monitor' },
  ];

  // Viewer href builder: current viewer state merged with overrides, empties
  // dropped — so a controller toggle href only flips the one param it names.
  // Defaults (views mode, mobile rung) stay out of the URL.
  const withParams = (over) => {
    const merged = {
      bg, inspect, live,
      mode: mode === 'views' ? null : mode,
      screen: active,
      vp: vp === 'mobile' ? null : vp,
      flow: walkFlow, step: walkStep,
      ...over,
    };
    const qs = Object.entries(merged).filter(([, val]) => val != null).map(([k, val]) => `${k}=${val}`).join('&');
    return qs ? `${base}?${qs}` : base;
  };

  const screens = ordered.map((s) => {
    const viewports = s.rungs.map((r) => ({ vp: RUNG_VP[r.width] ?? 'mobile', width: r.width, rung: r.rung, note: r.note, shot: r.shot }));
    // Tile dims at the CURRENT rung (fallback: the screen's first authored
    // rung; heights fall back to the rung default).
    const te = viewports.find((e) => e.vp === vp) ?? viewports[0];
    const tile = te ? { vp: te.vp, width: te.width, height: te.height ?? VP_HEIGHTS[te.vp] } : null;
    return {
      id: s.id, label: s.label, state: s.state,
      inContext: ids.includes(s.id),
      dim: ids.length > 0 && !ids.includes(s.id),
      tone: toneFor(s.id, L),
      chips: [{ text: `${s.kit}%`, title: t('design.kitChipTitle', { kit: s.kit, id: s.id }) }],
      viewports,
      primaryWidth: viewports[0]?.width ?? 390,
      tile,
      // Per-tile hover toolbar state + toggle hrefs (inspect toggles off when
      // re-clicked).
      //
      // NO live/walk fields here on purpose. This is the views-lens entry, and
      // the views lens has no interactive mode: its destination would have to
      // come from nextEdge without a flow to scope it, which is a guess. The
      // flows builder below adds `live`/`liveHref`/`walk*` PER ROW, where the
      // row names the flow and the answer is well-defined. Leaving them off
      // here makes the old unsound behaviour structurally unreachable rather
      // than merely unrendered.
      inspecting: s.id === inspect,
      inspectHref: withParams({ inspect: s.id === inspect ? null : s.id }),
      // ---- explode column joins (views lens, column 2) ----
      // The element INVENTORY is deliberately absent: `data-el` values are
      // templated (`data-el="card:{{ t('portalo.cat.' ~ pair[0]) }}"` inside a
      // {% for %}, and the tab bar arrives via {% include %}), so the only
      // honest source is the rendered DOM, which explode.js reads same-origin.
      // What the DOM canNOT know is authored project data — that is these two.
      //
      // Every outgoing edge, not just the ones with `element`: the island
      // matches exact `element` first and falls back to fuzzy `trigger`,
      // exactly as flowwalk.js does. Two lenses, one matching rule.
      fires: proj.edgesFrom(s.id),
      kits: proj.registryEntry(s.id)?.kits ?? [],
    };
  });

  // Flows lens rows: one ordered tile chain per project flow. Chain order =
  // edge-chain order starting from the edge whose `from` has no incoming edge
  // (a cycle guard keeps a malformed file from looping forever). A screen in
  // several flows appears once per row — tiles are shallow copies of the
  // views-lens entries plus `conn`, the trigger label on the connector to the
  // NEXT tile (null on the last).
  const tileById = Object.fromEntries(screens.map((s) => [s.id, s]));
  let flows = [];
  try {
    flows = proj.flows().map((f) => {
      const edges = f.edges ?? [];
      const incoming = new Set(edges.map((e) => e.to));
      let cur = edges.find((e) => !incoming.has(e.from)) ?? edges[0];
      const chain = [];
      const seen = new Set();
      while (cur && !seen.has(cur.from)) {
        seen.add(cur.from);
        chain.push(cur);
        cur = edges.find((e) => e.from === cur.to);
      }
      const chainIds = chain.length ? [chain[0].from, ...chain.map((e) => e.to)] : [];
      // Walk state is PER ROW. Arming a walk without naming a screen starts at
      // the chain head rather than nowhere, so `?flow=<id>` alone is valid.
      const walking = f.id === walkFlow;
      const stepId = walking ? (chainIds.includes(walkStep) ? walkStep : chainIds[0]) : null;
      return {
        id: f.id, name: f.name, walking,
        tiles: chainIds
          .map((id, i) => {
            const t = tileById[id];
            if (!t) return null;
            const isStep = walking && id === stepId;
            const edge = i < chain.length ? chain[i] : null;
            return {
              ...t,
              conn: edge ? edge.trigger : null,
              // Can this tile's remove control do anything? False on both tiles
              // of a 2-screen flow, where removing either would leave 0 edges —
              // an invalid flow that nothing can refill. The SAME helper backs
              // removeFromFlow's refusal, so the greyed-out button and the
              // server's answer are one decision, not two that can disagree.
              canRemove: canRemoveFrom(f, id),
              // `live` = this tile is the current step, so it renders
              // interactive (still=1 dropped). Only ever true inside the
              // walked row — a screen in two flows cannot be "live" in both.
              live: isStep,
              liveHref: withParams({ flow: f.id, step: id, live: id }),
              liveCloseHref: withParams({ flow: null, step: null, live: null }),
              // The next step in THIS row. Null on the last tile — the walk
              // ends rather than wrapping. This is what the tile-chrome
              // advance control and the flow-walk island both target.
              advanceHref: edge ? withParams({ flow: f.id, step: edge.to, live: edge.to }) : null,
              // Row end only: the OTHER flows that continue from this screen.
              // This is the whole of the inter-flow story — flows are joined by
              // shared ids, so the terminal screen of one row is the head of
              // another and the hand-off needs no authored key. A list, never a
              // single value: portalo.home hands off to two flows, and picking
              // for the user would be the same guess that scoping nextEdge
              // removed. Empty on every non-terminal tile.
              // The toast this TRANSITION raises (D2's second axis). It hangs
              // off the edge, not off either screen, because a toast is a
              // consequence of moving — `states` on a screen says how that
              // screen can look instead of its content, which is a different
              // question. Null when the edge raises nothing; most do not.
              feedback: edge?.feedback ?? null,
              handoffs: edge ? [] : proj.handoffs(id, f.id).map((h) => ({
                ...h,
                // Continue in that flow AT THIS SCREEN — it is the head of the
                // target row, so the walk lands where the eye already is.
                href: withParams({ flow: h.flow, step: id, live: id }),
              })),
              // What fires this edge, for the island's click matcher:
              // `element` is the authored join to a data-el value, `trigger`
              // is the prose fallback it fuzzy-matches when element is absent.
              edge: edge ? { to: edge.to, trigger: edge.trigger, element: edge.element ?? null } : null,
              // Extra stub query for the walked tile: the island inside the
              // iframe needs the PARENT url to advance to, plus what to match
              // a click against. Built here because encodeURIComponent in a
              // nunjucks expression is where this would quietly break.
              // `advance` is a plain viewer GET, so the island can hand it
              // straight to the parent's htmx — no new endpoint to keep in
              // sync with the viewer's param list.
              // `walkflow` also scopes the stub's OWN `next` edge, so the
              // surface's built-in CTA (auth.html hrefs to next.to) points at
              // the same screen the walk advances to. Without it nextEdge
              // falls back to first-match-across-all-flows and the two can
              // disagree inside the same tile.
              walkQs: edge
                ? `&walkflow=${encodeURIComponent(f.id)}`
                  + `&walk=${encodeURIComponent(withParams({ flow: f.id, step: edge.to, live: edge.to }))}`
                  + `&walkel=${encodeURIComponent(edge.element ?? '')}`
                  + `&walktrig=${encodeURIComponent(edge.trigger ?? '')}`
                : '',
            };
          })
          .filter(Boolean),
      };
    });
  } catch { /* no project overlaid — the flows lens renders empty */ }

  // The wired-app lens: device chrome around the live render at the real
  // rung size. Only produced in proto mode.
  const proto = mode === 'proto' ? {
    active, vp,
    src: `${STUB_BASE}${active}?vp=${vp}&embed=1`,
  } : null;

  // Kept even though the viewer's own filmstrip no longer reads it (that strip
  // is VIEWS-ONLY now, so it never renders in proto): freeze's composer tray
  // builds a strip outside #design-viewer and still consumes these hrefs.
  const protoPicks = mode === 'proto' ? Object.fromEntries(screens.map((s) => [s.id, withParams({ screen: s.id })])) : null;

  const miniPanel = {
    // The bar-right cluster (always mounted): device rung icons in ALL
    // lenses (in views/flows they re-render the tiles at that rung) + bg
    // swatches in every mode, a divider between the groups.
    bar: {
      devices: DEVICES.map((d) => ({ ...d, active: d.key === vp, href: withParams({ vp: d.key === 'mobile' ? null : d.key }) })),
      bgs: ['canvas', 'warm', 'slate'].map((value) => ({ value, active: value === bg, href: withParams({ bg: value }) })),
    },
    controller: {
      modes: ['views', 'flows', 'proto'].map((key) => ({ key, active: key === mode, href: withParams({ mode: key === 'views' ? null : key }) })),
      undo: { can: (d.undoStacks?.canvas?.length ?? 0) > 0, href: '/design/undo/canvas' },
      redo: { can: (d.redoStacks?.canvas?.length ?? 0) > 0, href: '/design/redo/canvas' },
    },
  };

  return {
    inspect, live, active,
    screens, flows, bg,
    mode, proto, vp,
    // The screens filmstrip: the viewer's RIGHT-HAND COLUMN in the VIEWS lens
    // only (design_viewer.html) — not a mini-panel member any more, and
    // deliberately absent in flows and proto. Same builder the composer tray
    // uses. contextBase is '<surface>/context/', so the surface prefix it
    // wants is that minus the trailing segment — the viewer only mounts on
    // /design.
    //
    // Consequence of the views-only gate: this strip was ALSO proto's only
    // active-screen picker, so proto now shows whatever screen the facade
    // defaults to. Give proto its own picker if that becomes a problem —
    // protoPicks below still carries the hrefs.
    filmstrip: mode === 'views' ? filmstripFor(d, contextBase.replace(/\/context\/$/, ''), L, { protoPicks, proto }, false) : null,
    // Proto-mode screen picks. No longer read by the viewer's own strip (see
    // above), but freeze's composer tray still builds one outside
    // #design-viewer, so the viewer keeps handing the hrefs over.
    protoPicks,
    base, stubBase: STUB_BASE, contextBase,
    miniPanel,
    undoRedo: {
      canvas: { canUndo: (d.undoStacks?.canvas?.length ?? 0) > 0, canRedo: (d.redoStacks?.canvas?.length ?? 0) > 0 },
      chat:   { canUndo: (d.undoStacks?.chat?.length ?? 0) > 0, canRedo: (d.redoStacks?.chat?.length ?? 0) > 0 },
    },
    elements: (d.elementContext ?? []).map((e) => ({ ...e, removeHref: `${contextBase}element/remove?screen=${encodeURIComponent(e.screenId)}&name=${encodeURIComponent(e.name)}` })),
  };
}

// Viewer toolbar act: the state keys (bg/inspect/live/mode/screen/vp) are
// AUTHORITATIVE — every control href echoes the whole viewer state
// (withParams), with defaults elided from the URL, so an absent key means
// "back to default", never "keep". Merging would strand every non-default
// value (a canvas chip sends no mode=, so a merged mode:'proto' could never
// flip back).
export const setViewer = (sessionData, query, prefs = {}, t = (k) => k, locale = 'en') => {
  const d = design(sessionData);
  const next = {};
  for (const [k, v] of Object.entries(query)) if (v != null) next[k] = v;
  d.viewer = next;
  return stageContext(sessionData, {}, prefs, t, locale);
};

// ---------- the design thread (seeded history + session messages) ----------

const allCheckpoints = (d, screenId, L) =>
  [...(repo.checkpoints(L)[screenId] ?? []), ...(d.chatCheckpoints?.[screenId] ?? [])]
    .map((cp) => ({ ...cp, reverted: (d.reverted ?? []).includes(cp.id) }));

function threadFor(d, lv, L) {
  return [...repo.designThread(L), ...(d.designThread ?? [])].map((m) => ({
    ...m,
    text: m.from === 'user' ? m.text : jargon.pick(m, 'text', lv),
    link: m.link ?? null,
    cps: (m.cps ?? [])
      .map(({ screen, cp }) => {
        const found = allCheckpoints(d, screen, L).find((x) => x.id === cp);
        return found ? { screen, ...found, summary: jargon.pick(found, 'summary', lv) } : null;
      })
      .filter(Boolean),
  }));
}

// ---------- the stage context (prototype / chat share it) ----------

// Suggestion chips: values are posted back as user text (they render in the
// thread), so both value and label come from the catalog.
const refineSuggestions = (t) => [
  { value: t('design.sug.editLayout.value'), label: t('design.sug.editLayout.label') },
  { value: t('design.sug.restyle.value'), label: t('design.sug.restyle.label') },
  { value: t('design.sug.adjustStates.value'), label: t('design.sug.adjustStates.label') },
  { value: t('design.sug.regenerate.value'), label: t('design.sug.regenerate.label') },
];

function screenCard(s, d, L, t) {
  const checkpoints = (repo.checkpoints(L)[s.id] ?? []).length + (d.chatCheckpoints?.[s.id] ?? []).length;
  return {
    type: 'screen', state: s.state, threadCount: checkpoints,
    detail: t('design.screenCardDetail', { rungs: s.rungs.length, kit: s.kit, wire: s.wire }),
  };
}

// opts: { line (timeline current id), pin (screenId | 'none'), base (route
// prefix for the strip × and the close act — the surface being rendered) }
// ── The inspector pane (D14–D17) ────────────────────────────────────────────
//
// The split of responsibility here is forced, not stylistic. Everything about
// an ELEMENT comes from the client; everything about a SCREEN comes from the
// server. `data-el="hero:{{ t('portalo.product.aurelia') }}"` is unresolved
// server-side and per-locale — the same wall that keeps an element inventory
// out of the views lens above — so the island measures the rendered node and
// POSTs what it read, and this file renders what it was told plus the joins
// only the server can make (registry, flows, chat context).
//
// The server therefore owns exactly three things the client cannot: the
// `inferred` provenance flags, `pinned`, and the hrefs.
const CONTEXT_BASE = '/design/chat/context/';

const elementCard = (d, p, L) => {
  // role falls back to the data-el prefix — the same fallback inspect.js used
  // to do in the overlay. The fallback IS the inference, which is why the flag
  // is computed here: the island posts the attribute or nothing, and never
  // claims a provenance it cannot know.
  const roleValue = p.role || String(p.name ?? '').split(':')[0] || '';
  return {
    name: p.name,
    kind: p.kind ?? '',
    screenId: p.screen,
    tone: toneFor(p.screen, L),
    role: { value: roleValue, inferred: !p.role && !!roleValue },
    style: p.style || null,
    motion: p.motion || null,
    // D9's fn derivation lives in the Dart lint, which reads SOURCE. Nothing
    // here can infer a function from a rendered node, so an absent fn is
    // reported absent rather than guessed — a wrong provenance flag is worse
    // than a missing card line.
    fn: p.fn ? { value: p.fn, inferred: false } : null,
    pinned: (d.elementContext ?? []).some((e) => e.screenId === p.screen && e.name === p.name),
    pinHref: `${CONTEXT_BASE}element`,
    unpinHref: `${CONTEXT_BASE}element/remove?screen=${encodeURIComponent(p.screen)}&name=${encodeURIComponent(p.name)}`,
  };
};

const screenCardFor = (d, L, fallbackScreenId = null) => {
  // fallbackScreenId is the viewer's currently-active screen (viewerFor's
  // `active`) — inspectorScreenId only gets set by a real element hover
  // (selectElement), so without this fallback the pane stays 'empty' until
  // the user hovers an element at least once. D17 specifies the screen card
  // for "nothing hovered/locked", i.e. the moment the pane opens, not after.
  const id = d.inspectorScreenId ?? fallbackScreenId ?? null;
  const entry = id ? proj.registryEntry(id) : null;
  if (!entry) return null;
  const edges = [];
  for (const f of proj.flows()) {
    for (const e of f.edges ?? []) {
      if (e.from !== id) continue;
      edges.push({
        flow: f.id,
        flowLabel: f.label ?? f.id,
        trigger: e.trigger ?? '',
        to: e.to,
        element: e.element ?? null,
      });
    }
  }
  // epic/state are NOT registry fields — the registry carries
  // {id,label,shell,comp,route,surface,states,kits}. They live on the screens
  // repo, so they are joined from there; reading entry.epic would render a
  // permanently blank row that looks like "this screen has no epic".
  const screen = repo.screens(L).find((s) => s.id === id) ?? {};
  return {
    id,
    label: entry.label ?? id,
    epic: screen.epic ?? '',
    state: screen.state ?? '',
    tone: toneFor(id, L),
    // All 'declared': deriving states from kits needs the kit→state map, which
    // is authored in the designer's kit-catalog and mirrored in Dart. Marking
    // a declared state 'derived' here would be a guess, so nothing is.
    states: (entry.states ?? []).map((n) => ({ name: n, source: 'declared' })),
    // Empty until the kit→state map is readable from JS. An empty list renders
    // no section, which is the honest result — NOT "nothing is missing".
    missingStates: [],
    kits: (entry.kits ?? []).map((k) => ({ id: k, label: k })),
    edges,
    // null, deliberately: annotation coverage counts [data-el] occurrences in
    // SOURCE, and those values are templated (see the wall above). The Dart
    // lint computes this; this file would have to guess. null renders nothing.
    annotations: null,
  };
};

const inspectorFor = (d, L, fallbackScreenId = null, active = true) => {
  // `active` (activityView === 'inspector') gates the expensive path: since
  // the #47 fix, screenCardFor almost always resolves an id (fallbackScreenId
  // is nearly always set) and walks proj.flows() — a fresh disk read+parse —
  // to build the edges list. That cost is only worth paying when the pane is
  // actually visible; every other render (canvas edits, chat, flow moves)
  // would otherwise redo it for nothing. `c.inspector` is consumed ONLY by
  // inspector_pane.html, so a cheap placeholder here is unobserved elsewhere
  // — it does not need to be exact, only present (see the comment at its
  // call site on why the key itself can never be conditional).
  if (!active) {
    return { mode: 'empty', locked: !!d.inspectorLock, element: null, screen: null, unlockHref: '/design/inspector/unlock', hint: null };
  }
  const shown = d.inspectorLock ?? d.inspectorHover ?? null;
  const element = shown && shown.name ? elementCard(d, shown, L) : null;
  const screen = element ? null : screenCardFor(d, L, fallbackScreenId);
  return {
    mode: element ? 'element' : screen ? 'screen' : 'empty',
    locked: !!d.inspectorLock,
    element,
    screen,
    unlockHref: '/design/inspector/unlock',
    hint: null,
  };
};

// The island fires one request per element change. While locked, a hover must
// cost nothing: return the stage unchanged so the pane re-renders identically
// and the morph is a no-op.
export const selectElement = (sessionData, payload = {}, prefs = {}, t = (k) => k, locale = 'en') => {
  const d = design(sessionData);
  // "Locked wins" (D16): while a lock is held a hover changes NOTHING. The lock
  // is a deliberate pick; an element merely brushed past while it is held must
  // not displace it — and must not become what unlock falls back to either.
  if (d.inspectorLock && payload.lock !== '1') return stageContext(sessionData, {}, prefs, t, locale);
  const p = {
    screen: payload.screen ?? '',
    name: payload.name ?? '',
    kind: payload.kind ?? '',
    role: payload.role ?? '',
    style: payload.style ?? '',
    motion: payload.motion ?? '',
    fn: payload.fn ?? '',
  };
  if (payload.lock === '1') d.inspectorLock = p; else d.inspectorHover = p;
  // Remembered so the screen card still has a subject once the pointer leaves
  // every element — mode 'screen' is the state between hovers, not a dead end.
  if (p.screen) d.inspectorScreenId = p.screen;
  return stageContext(sessionData, {}, prefs, t, locale);
};

// Clears the lock, KEEPS the hover — D16: the lock is session state precisely
// so it survives htmx morphs, and clearing it should fall back to live hover
// rather than to empty.
export const unlockInspector = (sessionData, prefs = {}, t = (k) => k, locale = 'en') => {
  const d = design(sessionData);
  // Promote the lock into the hover slot before dropping it. Unlocking should
  // LEAVE the element you were studying on screen and resume live tracking from
  // the NEXT hover — not blank the pane back to the screen card. Without this,
  // locking an element that was never hovered first (the island posts lock=1 on
  // a click, and a click need not be preceded by a hover post) left nothing to
  // fall back to, so unlock emptied the pane.
  if (d.inspectorLock) d.inspectorHover = d.inspectorLock;
  delete d.inspectorLock;
  return stageContext(sessionData, {}, prefs, t, locale);
};

export const stageContext = (sessionData = {}, opts = {}, prefs = {}, t = (k) => k, locale = 'en') => {
  const L = locale;
  const lv = jargon.level(prefs);
  const d = design(sessionData);
  if (opts.pin === 'none') d.context = [];
  else if (opts.pin) pin(d, opts.pin, L);
  const base = opts.base ?? '/design/chat';
  // The open file (main panel): ?file=<path> opens, ?file=none closes — the
  // main panel shows the file until then (pins refine, they don't look).
  if (opts.file === 'none') d.currentFile = null;
  else if (opts.file) d.currentFile = opts.file;
  const fileBase = opts.fileBase ?? '/design';
  // The panel bar (compact/medium): ?panel= picks the single visible content
  // panel and sticks; default main.
  if (['activity', 'main', 'composer'].includes(opts.panel)) d.panel = opts.panel;

  const drafted = d.drafted === true;
  const ids = contextIds(d, L);
  const filter = d.activityFilter ?? 'all';
  const activityView = ['screens', 'artifacts', 'files', 'inspector'].includes(d.activityView) ? d.activityView : 'screens';
  const thread = threadFor(d, lv, L);
  const viewer = viewerFor(d, L, t);
  const screens = repo.screens(L)
    .filter((s) => filter === 'all' || s.epic === filter)
    .map((s) => ({
      ...s,
      summary: jargon.pick(s, 'summary', lv),
      inContext: ids.includes(s.id),
      tone: toneFor(s.id, L),
      card: screenCard(s, d, L, t),
    }));
  return {
    // rungsLabel precomputed: fragment imports re-execute page blocks with an
    // empty context, and a join filter on undefined throws — plain access is safe.
    run: { ...repo.run(L), rungsLabel: repo.run(L).policy.rungs.join('/') },
    project: { name: repo.run(L).project },
    counts: repo.counts(L),
    epics: repo.epics(L),
    filter,
    activityView,
    activityLabel: t('activityView.' + activityView),
    panelSize: panelSizeFor(d, 'activity'),
    panelSizeHref: '/design/panel/size/activity/',
    panelSizePx: d.panelSizePx?.activity ?? null,
    activityViews: [
      { id: 'screens', icon: 'layout-grid', href: '/design/panel/screens' },
      { id: 'artifacts', icon: 'package', href: '/design/panel/artifacts' },
      { id: 'files', icon: 'folder', href: '/design/panel/files' },
      // The inspector renders from prototype_view.html#inspectorSwap, not from
      // _shared.html#activityBody, so it carries its OWN href rather than
      // riding the /design/panel/:view map like the other three.
      { id: 'inspector', icon: 'scan-search', href: '/design/inspector' },
    ].map((v) => ({ ...v, label: t('activityView.' + v.id), active: v.id === activityView })),
    // D14–D17. Present on EVERY render: the pane re-renders from fragment
    // swaps that carry the whole stage context, so it must never be
    // conditional on activityView.
    inspector: inspectorFor(d, L, viewer.active, activityView === 'inspector'),
    screens,
    artifacts: repo.artifacts(L),
    files: repo.files(L).map((f) => ({ ...f, ...fv.fileLink(f.path, fileBase) })),
    fileView: d.currentFile ? fv.fileViewFor(d.currentFile, `${fileBase}?file=none`) : null,
    panel: d.panel ?? 'main',
    drafted,
    threading: thread.some((m) => m.from === 'user'),
    stageEyebrow: t('design.chat.eyebrow'),
    composerAction: '/design/chat/messages',
    modelMenu: agent.modelMenuFor(sessionData, base, t),
    tray: { open: d.trayOpen !== false, toggleHref: `${base}/tray?state=toggle` },
    // The tray's filmstrip: every screen as a thumb (see filmstripFor). Only
    // on surfaces with NO design viewer — the canvas surfaces float the strip
    // over the views canvas instead (viewerFor -> viewer.filmstrip), and two
    // copies would be two sets of thumb iframes for the same screens.
    // Freeze opts in (composerStrip); its stage has a composer and no viewer.
    // The tray head summarizes the PINNED subset ("first +N"); null when the
    // context is empty — the filmstrip still renders, nothing dimmed.
    filmstrip: opts.composerStrip ? filmstripFor(d, base, L, viewer, opts.noProto) : null,
    trayContext: ids.length ? { first: ids[0], extra: ids.length - 1 } : null,
    // The pinned screens themselves, one chip each — what the composer SAYS
    // about the context now that the thumbs live in the viewer. Same tone as
    // the screen's canvas tile and filmstrip thumb (toneFor is id-keyed, so
    // the three agree by construction, not by copying a value around).
    // removeHref is base-scoped like the filmstrip's toggle, so the unpin
    // swaps the surface being rendered rather than always /design/chat.
    contextChips: ids.map((id) => ({
      id,
      label: repo.screen(id, L).label,
      tone: toneFor(id, L),
      removeHref: `${base}/context/${id}?state=off`,
    })),
    viewer,
    // The shared composer reads these at stage level (composer.html: element
    // chips in the tray, the chat undo/redo pair) — the viewer keeps its own
    // copies for the mini panel (contract §1).
    elements: viewer.elements,
    undoRedo: viewer.undoRedo,
    thread,
    suggestions: refineSuggestions(t),
    placeholder: t('composer.placeholder.refine', { label: ctxLabel(d, L, t) }),
    timeline: timeline(d, L, t),
    jargonLevel: lv,
  };
};

// Context pin toggle from the filmstrip / artboard chrome / activity card.
// state: 'toggle' | 'on' | 'off'.
export const toggleContext = (sessionData, screenId, state = 'toggle', prefs = {}, t = (k) => k, locale = 'en') => {
  const d = design(sessionData);
  const wasIn = contextIds(d, locale).includes(screenId);
  const on = state === 'toggle' ? !wasIn : state === 'on';
  if (on) pin(d, screenId, locale); else unpin(d, screenId, locale);
  if (on !== wasIn) pushCanvasUndo(d, { type: on ? 'pin' : 'unpin', screenId });
  return stageContext(sessionData, {}, prefs, t, locale);
};

// Bulk pin from the marquee selection (drag.js POSTs a comma-separated id list).
export const bulkPin = (sessionData, idsCsv, prefs = {}, t = (k) => k, locale = 'en') => {
  const d = design(sessionData);
  for (const id of idsCsv.split(',').map((s) => s.trim()).filter(Boolean)) {
    if (repo.screen(id, locale)) {
      pin(d, id, locale);
      pushCanvasUndo(d, { type: 'pin', screenId: id });
    }
  }
  return stageContext(sessionData, {}, prefs, t, locale);
};

// Composer chrome: pick the agent model, or collapse/expand the context
// tray. Both mutate session state; callers re-render their own surface
// context (freeze ignores the returned stage context).
export const setModel = (sessionData, id, opts = {}, prefs = {}, t = (k) => k, locale = 'en') => {
  agent.setModel(sessionData, id);
  return stageContext(sessionData, opts, prefs, t, locale);
};

export const setTray = (sessionData, state, opts = {}, prefs = {}, t = (k) => k, locale = 'en') => {
  const d = design(sessionData);
  // the checkbox already flipped locally — mirror it (toggling, never an
  // absolute state: a stale absolute href would desync on double-click)
  d.trayOpen = state === 'toggle' ? !(d.trayOpen !== false) : state !== 'off';
  return stageContext(sessionData, opts, prefs, t, locale);
};

// A file row in the activity panel: open it in the main panel (the mode is
// the server's, from the extension).
export const openFile = (sessionData, path, prefs = {}, t = (k) => k, locale = 'en') =>
  stageContext(sessionData, { file: path ?? 'none' }, prefs, t, locale);

export const setActivityFilter = (sessionData, filter, prefs = {}, t = (k) => k, locale = 'en') => {
  design(sessionData).activityFilter = filter;
  return stageContext(sessionData, {}, prefs, t, locale);
};

export const setActivityView = (sessionData, view, prefs = {}, t = (k) => k, locale = 'en') => {
  design(sessionData).activityView = view;
  return stageContext(sessionData, {}, prefs, t, locale);
};

// Panel width grip: cycle persisted per panel (the shell's own sizing state).
export const setPanelSize = (sessionData, panel, size, prefs = {}, t = (k) => k, locale = 'en') => {
  if (PERSISTABLE_PANELS.includes(panel) && PANEL_SIZES.includes(size)) {
    (design(sessionData).panelSize ??= {})[panel] = size;
  }
  return stageContext(sessionData, {}, prefs, t, locale);
};

// Panel drag handle: px width persisted per panel.
//
// The band here is a SANITY GUARD against a malformed POST, not the panel's
// real limits — those are its CSS min/max width, which the server cannot read
// and does not need to: drag.js clamps to them before posting and `min-width`
// re-clamps on render, so every legitimate value already falls inside this
// band. Do not treat these numbers as the layout's limits; that confusion is
// what made the drag readout count down to a width no panel could render.
export const setPanelSizePx = (sessionData, panel, width, prefs = {}, t = (k) => k, locale = 'en') => {
  const d = design(sessionData);
  const w = Number(width);
  // A junk width is DROPPED, not defaulted. The old `|| 280` persisted a width
  // below every panel's floor, so the stored number and the rendered panel
  // disagreed permanently — and silently, because min-width quietly fixes the
  // render while the session keeps the bad value.
  if (Number.isFinite(w)) (d.panelSizePx ??= {})[panel] = Math.max(200, Math.min(600, w));
  return stageContext(sessionData, {}, prefs, t, locale);
};

// Move a screen inside a flow — a one-step nudge (dir -1|1, no-op at the row
// ends) from the tile toolbar, or a drop-to-index from the axis-locked row
// drag (index counts slots among the OTHER tiles, so splice-out-then-insert
// lands it exactly there). Writes the project's flows.json and records the
// before/after order arrays for undo/redo replay.
export const moveInFlow = async (sessionData, flowId, screenId, to = {}, prefs = {}, t = (k) => k, locale = 'en') => {
  const d = design(sessionData);
  try {
    const flows = proj.flows();
    const flow = flows.find((f) => f.id === flowId);
    const chain = chainOf(flow);
    const i = chain.indexOf(screenId);
    let j = i;
    if (Number.isInteger(to.index)) j = Math.max(0, Math.min(chain.length - 1, to.index));
    else if (to.dir === -1 || to.dir === 1) j = i + to.dir;
    if (flow && i >= 0 && j !== i && j >= 0 && j < chain.length) {
      const before = [...chain];
      const after = [...chain];
      after.splice(i, 1);
      after.splice(j, 0, screenId);
      // Per-screen trigger snapshot taken BEFORE the rewire: a screen demoted
      // to chain tail drops its outgoing edge from the file, and undo replays
      // by re-deriving from the then-current file — this memory lets that
      // replay restore the trigger verbatim (see rewire).
      const triggers = moveMemory(flow);
      rewire(flow, after, triggers);
      await proj.writeFlowsDual(flows, [flowId]);
      pushCanvasUndo(d, { type: 'flow-move', flowId, before, after, triggers });
    }
  } catch { /* no project overlaid / unknown flow — no-op re-render */ }
  return stageContext(sessionData, {}, prefs, t, locale);
};

// Append a screen to a flow's chain (views-lens add-to-flow menu). No-op when
// already a member.
export const addToFlow = async (sessionData, flowId, screenId, prefs = {}, t = (k) => k, locale = 'en') => {
  const d = design(sessionData);
  try {
    const flows = proj.flows();
    const flow = flows.find((f) => f.id === flowId);
    if (flow && proj.registryEntry(screenId) && appendTo(flow, screenId)) {
      await proj.writeFlowsDual(flows, [flowId]);
      pushCanvasUndo(d, { type: 'flow-add', flowId, screenId });
    }
  } catch { /* no project overlaid / unknown flow — no-op re-render */ }
  return stageContext(sessionData, {}, prefs, t, locale);
};

// Remove a screen from a flow, stitching the chain (see excise). The undo
// entry keeps the removed edges so undo restores them verbatim.
export const removeFromFlow = async (sessionData, flowId, screenId, prefs = {}, t = (k) => k, locale = 'en') => {
  const d = design(sessionData);
  try {
    const flows = proj.flows();
    const flow = flows.find((f) => f.id === flowId);
    const index = chainOf(flow).indexOf(screenId);
    // REFUSED when the removal would empty the chain — no write, unchanged
    // viewmodel. The tile's `canRemove` (same helper) greys the button out first,
    // but this is the one that has to hold: a 0-edge flow cannot be undone into
    // existence again (see canRemoveFrom).
    const removed = flow && canRemoveFrom(flow, screenId) ? excise(flow, screenId) : null;
    if (removed) {
      await proj.writeFlowsDual(flows, [flowId]);
      pushCanvasUndo(d, { type: 'flow-remove', flowId, screenId, index, ...removed });
    }
  } catch { /* no project overlaid / unknown flow — no-op re-render */ }
  return stageContext(sessionData, {}, prefs, t, locale);
};

// Element context chips: independent of screen chips in the composer tray. A
// pin dedupes on (screenId, name) and auto-opens the tray. These do NOT touch
// the canvas undo stack — element-scoped checkpoints (contract §6) are a
// separate slice; this just maintains the tray membership.
export const pinElement = (sessionData, screenId, name, kind, prefs, t, locale) => {
  const d = design(sessionData);
  const el = (d.elementContext ??= []);
  if (!el.some((e) => e.screenId === screenId && e.name === name)) {
    el.push({ screenId, name, kind, tone: toneFor(screenId, locale) });
    d.trayOpen = true;
  }
  return stageContext(sessionData, {}, prefs, t, locale);
};

export const unpinElement = (sessionData, screenId, name, prefs, t, locale) => {
  const d = design(sessionData);
  d.elementContext = (d.elementContext ?? []).filter((e) => !(e.screenId === screenId && e.name === name));
  return stageContext(sessionData, {}, prefs, t, locale);
};

// Undo / redo walk the two session stacks. Popping an entry, applying its
// reverse, and re-pushing onto the opposite stack is the whole mechanic — the
// entry object travels with the user as they step back and forth. Async:
// replaying a flow entry rewrites the project's flows.json. The stack param
// is a URL segment: anything but canvas|chat is a no-op re-render (it must
// not mint junk stack keys in the session).
const STACKS = ['canvas', 'chat'];
export const undo = async (sessionData, stack, prefs = {}, t = (k) => k, locale = 'en') => {
  const d = design(sessionData);
  if (!STACKS.includes(stack)) return stageContext(sessionData, {}, prefs, t, locale);
  (d.undoStacks ??= {}); (d.redoStacks ??= {});
  const entry = (d.undoStacks[stack] ??= []).pop();
  if (entry) {
    await applyEntry(d, entry, 'undo');
    (d.redoStacks[stack] ??= []).push(entry);
  }
  return stageContext(sessionData, {}, prefs, t, locale);
};

export const redo = async (sessionData, stack, prefs = {}, t = (k) => k, locale = 'en') => {
  const d = design(sessionData);
  if (!STACKS.includes(stack)) return stageContext(sessionData, {}, prefs, t, locale);
  (d.undoStacks ??= {}); (d.redoStacks ??= {});
  const entry = (d.redoStacks[stack] ??= []).pop();
  if (entry) {
    await applyEntry(d, entry, 'redo');
    (d.undoStacks[stack] ??= []).push(entry);
  }
  return stageContext(sessionData, {}, prefs, t, locale);
};

// The single composer path (chat-Centric Layout: no inputs outside the chat).
// 'approve' signs the manifest; any other text refines the pinned screens and
// may mint one checkpoint per pinned screen.
export const sendChat = (sessionData, text, prefs = {}, pinId = null, t = (k) => k, locale = 'en') => {
  const L = locale;
  const d = design(sessionData);
  if (pinId) pin(d, pinId, L);
  const thread = (d.designThread ??= []);

  // draftSent marks the ONE render that follows a send. The composer textarea
  // is hx-preserve'd so an unrelated swap cannot discard a half-typed message;
  // preserved unconditionally it would also survive the send, leaving the text
  // the user just sent sitting in the box ready to be sent twice. Every exit
  // from this function consumes the text, so every exit clears the flag's
  // absence.
  if (text === 'approve') {
    return { ...approveManifest(sessionData, prefs, t, L), draftSent: true };
  }

  const threadLenBefore = thread.length;
  thread.push({ at: 'now', from: 'user', text });
  const ids = contextIds(d, L);
  if (!ids.length) {
    thread.push({ at: 'now', from: 'agent', text: repo.noContext(L).text, textPlain: repo.noContext(L).textPlain });
    pushUndo(d, 'chat', { type: 'chat', threadLenBefore, checkpointIds: [] });
    return { ...stageContext(sessionData, {}, prefs, t, L), draftSent: true };
  }

  const first = repo.screen(ids[0], L);
  const scope = { label: ctxLabel(d, L, t), kit: first.kit, id: ids[0], summary: '' };
  const lower = text.toLowerCase();
  const found = repo.chatReplies(L).find((r) => r.match.some((k) => lower.includes(k)));
  const reply = fillReply(found ?? repo.chatFallback(L), scope);

  // Each message checkpoints the in-context screens only (story map → Chat).
  let cps = [];
  if (reply.checkpoint) {
    cps = ids.map((screenId) => {
      const list = (d.chatCheckpoints ??= {})[screenId] ??= [];
      const n = (repo.checkpoints(L)[screenId] ?? []).length + list.length + 1;
      const cpId = `cp-${n}`;
      list.push({
        id: cpId, n, at: 'now',
        summary: reply.checkpoint,
        summaryPlain: reply.checkpointPlain ?? reply.checkpoint,
        before: reply.before, after: reply.after,
      });
      return { screen: screenId, cp: cpId };
    });
  }
  thread.push({ at: 'now', from: 'agent', text: reply.text, textBalanced: reply.textBalanced, textPlain: reply.textPlain, link: reply.link, cps });
  pushUndo(d, 'chat', { type: 'chat', threadLenBefore, checkpointIds: cps });
  return { ...stageContext(sessionData, {}, prefs, t, L), draftSent: true };
};

// One-tap revert: the checkpoint stays rendered as history, flagged reverted,
// and the act is logged into the thread — the thread is the design's history.
export const revertCheckpoint = (sessionData, screenId, cpId, prefs = {}, t = (k) => k, locale = 'en') => {
  const d = design(sessionData);
  const cp = allCheckpoints(d, screenId, locale).find((x) => x.id === cpId);
  if (cp && !(d.reverted ??= []).includes(cpId)) {
    d.reverted.push(cpId);
    (d.designThread ??= []).push({ at: 'now', from: 'agent', kind: 'event', text: t('design.revertEvent', { screen: screenId, cp: cpId, summary: cp.summary }) });
  }
  return stageContext(sessionData, {}, prefs, t, locale);
};

// ---------- freeze & trace surface ----------

export const freezeContext = (sessionData = {}, prefs = {}, t = (k) => k, locale = 'en', fileArg) => {
  const L = locale;
  // composerStrip: freeze renders a composer but NO design viewer, so the
  // filmstrip stays in its tray (every /design canvas surface docks it under
  // the viewer's mini panel instead).
  const stage = stageContext(sessionData, { line: 'freeze', base: '/design/freeze', fileBase: '/design/freeze', file: fileArg, noProto: true, composerStrip: true }, prefs, t, L);
  const lv = stage.jargonLevel;
  const d = design(sessionData);
  const ap = repo.approval(L);
  const approved = d.approved ?? ap.state === 'approved';
  const manifest = { ...repo.manifest(L), structure: jargon.pick(repo.manifest(L), 'structure', lv) };
  const rechecks = d.driftRechecks ?? 0;
  return {
    ...stage,
    // Element chips and the chat undo/redo pair stay off the freeze composer:
    // their hrefs live under /design/chat + /design/undo and answer with the
    // prototype stage markup — fine on /design surfaces, a wrong-surface swap
    // here. Re-enable once those hrefs are base-scoped like the filmstrip's.
    elements: null,
    undoRedo: null,
    stageEyebrow: t('design.freeze.eyebrow'),
    composerAction: '/design/freeze/messages',
    suggestions: [{ value: 'approve', label: ap.chip }, ...refineSuggestions(t)],
    placeholder: approved ? t('composer.placeholder.freeze') : t('composer.placeholder.freezeApprove'),
    manifest,
    approval: {
      approved,
      lede: jargon.pick(ap, 'lede', lv),
      note: jargon.pick(ap, approved ? 'approvedNote' : 'pendingNote', lv),
    },
    trace: repo.trace(L).map((e) => ({ ...e, text: jargon.pick(e, 'text', lv) })),
    traceability: repo.traceability(L),
    drift: {
      ...repo.drift(L),
      history: repo.drift(L).history.map((e) => ({ ...e, text: jargon.pick(e, 'text', lv) })),
    },
    rechecks,
    toast: rechecks ? t('drift.recheckToast', { n: rechecks + 1, matched: repo.drift(L).matched }) : null,
  };
};

// The human gate: approving the frozen manifest unlocks the Build stage.
// Idempotent — the act and the confirmation both land in the design thread.
export const approveManifest = (sessionData, prefs = {}, t = (k) => k, locale = 'en') => {
  const d = design(sessionData);
  const thread = (d.designThread ??= []);
  thread.push({ at: 'now', from: 'user', text: repo.approval(locale).chip });
  d.approved = true;
  thread.push({ at: 'now', from: 'agent', text: repo.approval(locale).confirm, textPlain: repo.approval(locale).confirmPlain });
  return freezeContext(sessionData, prefs, t, locale);
};

export const recheckDrift = (sessionData, prefs = {}, t = (k) => k, locale = 'en') => {
  const d = design(sessionData);
  d.driftRechecks = (d.driftRechecks ?? 0) + 1;
  return freezeContext(sessionData, prefs, t, locale);
};
