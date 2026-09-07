// arxa:provenance
// generator: arxa  licence: free  project: 662368770980
// Built with arxa (free tier) — https://arxa.dev
// DesignFacade — composes the design fixture with session-scoped state
// (pinned context chips, the design thread with
// per-screen checkpoints, manifest approval, drift rechecks) into exactly
// what the design viewmodels need.
// Leveled fixture strings pass through jargon.pick; static leveled copy
// lives in l10n/app_*.arb and is rendered by the runtime t() in the
// templates. The locale comes from the request and picks the per-locale
// fixture, en fallback.
import * as repo from '../repositories/studio_design_repository_service.js';
import * as proj from '../../repositories/project_repository.js';
import * as widgets from '../../repositories/widget_repository.js';
import * as texts from '../../repositories/text_repository.js';
import * as jargon from '../../facades/jargon.js';
import * as agent from '../../facades/agent_menus.js';
import * as fv from '../../facades/file_views.js';

// Panel width steps, per panel — the shell's own persisted panel sizing.
export const PANEL_SIZES = ['s', 'm', 'l'];
// Panels whose width is server state, keyed by ROLE. Only the activity panel
// persists one; the composer's width is client-only and rides morph (drag.js
// omits data-persist for it). This list was `['left', 'right']` — a position
// whitelist for a value that was always the literal 'left', which would have
// silently rejected the role key and made every drag-release a no-op.
const PERSISTABLE_PANELS = ['activity'];
const panelSizeFor = (designState, panel) => (PANEL_SIZES.includes(designState.panelSize?.[panel]) ? designState.panelSize[panel] : 's');

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
const toneFor = (id, activeLocale) => {
  const index = repo.screens(activeLocale).findIndex((screen) => screen.id === id);
  return TONES[(index < 0 ? 0 : index) % TONES.length];
};

// {label} / {kit} / {summary} / {id} placeholders in fixture reply strings.
const interpolate = (template, screen) =>
  !template ? template
    : template.replaceAll('{label}', screen?.label ?? '')
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
function timeline(designState, activeLocale, translate) {
  const seededCps = Object.values(repo.checkpoints(activeLocale)).flat().length;
  const chatCps = Object.values(designState.chatCheckpoints ?? {}).flat().length;
  const refined = seededCps + chatCps > 0;
  const refining = !refined && (contextIds(designState, activeLocale).length > 0 || (designState.designThread ?? []).length > 0);
  const approved = designState.approved ?? repo.approval(activeLocale).state === 'approved';
  const items = [
    { id: 'artboards', kind: 'stage', label: translate('design.timeline.artboards'), state: 'green', href: '/design' },
    { id: 'refine', kind: 'stage', label: translate('design.timeline.refine'), state: refined ? 'green' : refining ? 'active' : 'pending', href: '/design/chat' },
    { id: 'design.approval', kind: 'gate', label: translate('design.timeline.approval'), state: approved ? 'approved' : refined ? 'active' : 'pending', href: '/design/freeze' },
    { id: 'freeze', kind: 'stage', label: translate('design.timeline.freeze'), state: approved ? 'green' : 'pending', href: '/design/freeze' },
  ];
  const withRefs = items.map((item) => ({ ...item, ref: item.id }));
  return { items: withRefs, currentId: (items.find((item) => item.state === 'active') || {}).id ?? null };
}

// ---------- pinned context ----------

const contextIds = (designState, activeLocale) => (designState.context ?? []).filter((id) => repo.screen(id, activeLocale));
const pin = (designState, id, activeLocale) => {
  if (repo.screen(id, activeLocale) && !contextIds(designState, activeLocale).includes(id)) (designState.context ??= []).push(id);
  designState.trayOpen = true; // pinning auto-expands the composer's context tray
};
const unpin = (designState, id, activeLocale) => {
  designState.context = contextIds(designState, activeLocale).filter((contextScreenId) => contextScreenId !== id);
};

// The composer tray's filmstrip: EVERY screen as a live thumb, horizontally
// scrollable. Flow: a thumb toggles that screen's chat-context chip (base
// scopes the route to the surface being rendered — /design/chat or
// /design/freeze — so the toggle swaps THAT surface's stage). Proto (the
// design canvas only): a thumb picks the wired-app preview's active screen,
// swapping just #design-viewer; the viewer hands those hrefs over as
// protoPicks (the tray lives outside #design-viewer, in #panels).
const filmstripFor = (designState, base, activeLocale, viewer, noProto) => {
  const ids = contextIds(designState, activeLocale);
  const picks = !noProto && viewer.protoPicks;
  return repo.screens(activeLocale).map((screen) => ({
    id: screen.id,
    label: repo.screen(screen.id, activeLocale).label,
    tone: toneFor(screen.id, activeLocale),
    inContext: ids.includes(screen.id),
    dim: ids.length > 0 && !ids.includes(screen.id),
    src: `${STUB_BASE}${screen.id}?vp=mobile&embed=1&still=1${viewer.theme ? `&theme=${viewer.theme}` : ''}`,
    ...(picks
      ? { protoHref: picks[screen.id], active: screen.id === viewer.proto.active }
      : { contextHref: `${base}/context/${screen.id}?state=toggle` }),
  }));
};

const ctxLabel = (designState, activeLocale, translate) => contextIds(designState, activeLocale).map((id) => repo.screen(id, activeLocale).label).join(' + ') || translate('design.ctxFallback');

// ---------- undo / redo (two session stacks: canvas, chat) ----------
// Each entry carries enough to reverse itself in both directions, so the same
// object simply moves between the undo and redo stacks as the user steps back
// and forth. Canvas stack: flow edits (move/add/remove — replayed as project
// flows.json writes) + screen pin/unpin. Chat stack is wired for design-change
// checkpoints (contract §6).
const pushUndo = (designState, stack, entry) => {
  (designState.undoStacks ??= {}); (designState.redoStacks ??= {});
  (designState.undoStacks[stack] ??= []).push(entry);
  designState.redoStacks[stack] = [];
};
const pushCanvasUndo = (designState, entry) => pushUndo(designState, 'canvas', entry);

// ---------- flow edit operations (WRITE the project's flows.json) ----------
// A flow is a linear edge list; chainOf derives the screen order by the same
// walk the flows lens renders (head = the edge whose `from` has no incoming
// edge, a seen-set guards a malformed cycle).
const chainOf = (flow) => {
  const edges = flow?.edges ?? [];
  const incoming = new Set(edges.map((edge) => edge.to));
  let cur = edges.find((edge) => !incoming.has(edge.from)) ?? edges[0];
  const chain = [];
  const seen = new Set();
  while (cur && !seen.has(cur.from)) {
    seen.add(cur.from);
    chain.push(cur);
    cur = edges.find((edge) => edge.from === cur.to);
  }
  return chain.length ? [chain[0].from, ...chain.map((edge) => edge.to)] : [];
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
  const byPair = new Map(edges.map((edge) => [`${edge.from}→${edge.to}`, edge]));
  const outByFrom = new Map(edges.map((edge) => [edge.from, edge]));
  flow.edges = order.slice(0, -1).map((from, index) => {
    const kept = byPair.get(`${from}→${order[index + 1]}`);
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
      from, to: order[index + 1],
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
  Object.fromEntries((flow?.edges ?? []).map((edge) => [edge.from, { ...edge, action: edge.action ?? 'push' }]));

// Would excising screenId leave the flow with any edges? A 0-edge flow is
// INVALID — arxa/lib/intake.dart:283 hard-errors '$where: edges must be a
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
  const incoming = edges.find((edge) => edge.to === screenId) ?? null;
  const outgoing = edges.find((edge) => edge.from === screenId) ?? null;
  if (!incoming && !outgoing) return edges.length > 0;
  const rest = edges.filter((edge) => edge !== incoming && edge !== outgoing).length;
  return rest + (incoming && outgoing ? 1 : 0) > 0;
};

// Cut screenId out of the chain, stitching the gap: the incoming edge's from
// links to the outgoing edge's to KEEPING THE INCOMING trigger; removing the
// head/tail just drops the one edge. Returns the undo payload (null when the
// screen is not a member).
const excise = (flow, screenId) => {
  const edges = flow.edges ?? [];
  const incoming = edges.find((edge) => edge.to === screenId) ?? null;
  const outgoing = edges.find((edge) => edge.from === screenId) ?? null;
  if (!incoming && !outgoing) return null;
  const at = edges.indexOf(incoming ?? outgoing);
  const rest = edges.filter((edge) => edge !== incoming && edge !== outgoing);
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
    ? edges.filter((edge) => !(edge.from === entry.incoming.from && edge.to === entry.outgoing.to))
    : [...edges];
  const at = entry.incoming ? Math.max(0, entry.index - 1) : entry.index;
  const back = [entry.incoming, entry.outgoing].filter(Boolean);
  flow.edges = [...without.slice(0, at), ...back, ...without.slice(at)];
};

// Flow entries replay their file write in both directions (re-deriving edges
// from the CURRENT file, so triggers follow their from screen); pin/chat
// entries stay pure session state.
const applyEntry = async (designState, entry, dir) => {
  if (entry.type === 'flow-move' || entry.type === 'flow-add' || entry.type === 'flow-remove') {
    const flows = proj.flows();
    const flow = flows.find((candidateFlow) => candidateFlow.id === entry.flowId);
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
    const has = (designState.context ?? []).includes(entry.screenId);
    if (wantPinned && !has) (designState.context ??= []).push(entry.screenId);
    if (!wantPinned && has) designState.context = designState.context.filter((contextScreenId) => contextScreenId !== entry.screenId);
  } else if (entry.type === 'chat') {
    // Undo truncates the thread to the pre-message length and stashes the
    // removed messages + checkpoints in the entry for redo to re-append.
    const thread = (designState.designThread ??= []);
    if (dir === 'undo') {
      entry.removedMsgs = thread.splice(entry.threadLenBefore);
      entry.removedCps = [];
      for (const { screen, cp } of entry.checkpointIds) {
        const list = designState.chatCheckpoints?.[screen] ?? [];
        const found = list.find((checkpoint) => checkpoint.id === cp);
        if (found) { entry.removedCps.push({ screen, cp: found }); designState.chatCheckpoints[screen] = list.filter((checkpoint) => checkpoint.id !== cp); }
      }
    } else {
      thread.push(...(entry.removedMsgs ?? []));
      for (const { screen, cp } of entry.removedCps ?? []) ((designState.chatCheckpoints ??= {})[screen] ??= []).push(cp);
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

function viewerFor(designState, activeLocale, translate) {
  const viewerState = designState.viewer ?? {};
  const ids = contextIds(designState, activeLocale);
  const base = '/design/viewer';
  const contextBase = '/design/chat/context/';

  const vp = ['mobile', 'tablet', 'desktop'].includes(viewerState.vp) ? viewerState.vp : 'mobile';

  // Tile order is the project REGISTRY order (the views lens is a flat grid
  // over it); the tile data itself comes from the design-stage fixture
  // (rungs/kit/state). Fallback: fixture order when no project is overlaid.
  const fixture = repo.screens(activeLocale);
  let registryIds = [];
  try { registryIds = proj.registry().map((entry) => entry.id); } catch { /* artifact-only serving */ }
  const ordered = registryIds.length
    ? registryIds.map((id) => fixture.find((screen) => screen.id === id)).filter(Boolean)
    : fixture;

  const bg = ['canvas', 'warm', 'ink'].includes(viewerState.bg) ? viewerState.bg : 'canvas';
  // Canvas app theme OVERRIDE: light/dark restyle the designed app's stubs
  // ONLY (never the studio chrome); null = auto — the stubs keep following
  // the studio theme, which is screenStub's default (build_facade), so auto
  // stays out of every URL like the other elided defaults below.
  const theme = ['light', 'dark'].includes(viewerState.theme) ? viewerState.theme : null;
  const mode = ['views', 'flows', 'proto'].includes(viewerState.mode) ? viewerState.mode : 'views';
  const active = ordered.some((screen) => screen.id === viewerState.screen) ? viewerState.screen : ordered[0]?.id;
  // Per-tile params: the screen id they name, else null (unknown ids drop).
  const inspect = ordered.some((screen) => screen.id === viewerState.inspect) ? viewerState.inspect : null;
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
  const live = mode === 'flows' && ordered.some((screen) => screen.id === viewerState.live) ? viewerState.live : null;

  // The flow WALK: which flow row is being walked, and which screen in its
  // chain is the current step. `live` above is only "this tile is interactive";
  // the walk is what makes the ROW track a position, which is the whole point —
  // the destination is well-defined here because the row names the flow, and
  // ambiguous anywhere else (portalo.home advances to checkout in
  // flow-browse-buy and to account in flow-account).
  const walkFlow = mode === 'flows' && typeof viewerState.flow === 'string' && viewerState.flow ? viewerState.flow : null;
  const walkStep = walkFlow && ordered.some((screen) => screen.id === viewerState.step) ? viewerState.step : null;

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
      bg, theme, inspect, live,
      mode: mode === 'views' ? null : mode,
      screen: active,
      vp: vp === 'mobile' ? null : vp,
      flow: walkFlow, step: walkStep,
      ...over,
    };
    const qs = Object.entries(merged).filter(([, val]) => val != null).map(([key, val]) => `${key}=${val}`).join('&');
    return qs ? `${base}?${qs}` : base;
  };

  const screens = ordered.map((screen) => {
    const viewports = screen.rungs.map((rung) => ({ vp: RUNG_VP[rung.width] ?? 'mobile', width: rung.width, rung: rung.rung, note: rung.note, shot: rung.shot }));
    // Tile dims at the CURRENT rung (fallback: the screen's first authored
    // rung; heights fall back to the rung default).
    const te = viewports.find((viewport) => viewport.vp === vp) ?? viewports[0];
    const tile = te ? { vp: te.vp, width: te.width, height: te.height ?? VP_HEIGHTS[te.vp] } : null;
    return {
      id: screen.id, label: screen.label, state: screen.state,
      inContext: ids.includes(screen.id),
      dim: ids.length > 0 && !ids.includes(screen.id),
      tone: toneFor(screen.id, activeLocale),
      chips: [{ text: `${screen.kit}%`, title: translate('design.kitChipTitle', { kit: screen.kit, id: screen.id }) }],
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
      inspecting: screen.id === inspect,
      inspectHref: withParams({ inspect: screen.id === inspect ? null : screen.id }),
    };
  });

  // Flows lens rows: one ordered tile chain per project flow. Chain order =
  // edge-chain order starting from the edge whose `from` has no incoming edge
  // (a cycle guard keeps a malformed file from looping forever). A screen in
  // several flows appears once per row — tiles are shallow copies of the
  // views-lens entries plus `conn`, the trigger label on the connector to the
  // NEXT tile (null on the last).
  const tileById = Object.fromEntries(screens.map((screen) => [screen.id, screen]));
  let flows = [];
  try {
    flows = proj.flows().map((flow) => {
      const edges = flow.edges ?? [];
      const incoming = new Set(edges.map((edge) => edge.to));
      let cur = edges.find((edge) => !incoming.has(edge.from)) ?? edges[0];
      const chain = [];
      const seen = new Set();
      while (cur && !seen.has(cur.from)) {
        seen.add(cur.from);
        chain.push(cur);
        cur = edges.find((edge) => edge.from === cur.to);
      }
      const chainIds = chain.length ? [chain[0].from, ...chain.map((edge) => edge.to)] : [];
      // Walk state is PER ROW. Arming a walk without naming a screen starts at
      // the chain head rather than nowhere, so `?flow=<id>` alone is valid.
      const walking = flow.id === walkFlow;
      const stepId = walking ? (chainIds.includes(walkStep) ? walkStep : chainIds[0]) : null;
      return {
        id: flow.id, name: flow.name, walking,
        tiles: chainIds
          .map((id, index) => {
            const tile = tileById[id];
            if (!tile) return null;
            const isStep = walking && id === stepId;
            const edge = index < chain.length ? chain[index] : null;
            return {
              ...tile,
              conn: edge ? edge.trigger : null,
              // Can this tile's remove control do anything? False on both tiles
              // of a 2-screen flow, where removing either would leave 0 edges —
              // an invalid flow that nothing can refill. The SAME helper backs
              // removeFromFlow's refusal, so the greyed-out button and the
              // server's answer are one decision, not two that can disagree.
              canRemove: canRemoveFrom(flow, id),
              // `live` = this tile is the current step, so it renders
              // interactive (still=1 dropped). Only ever true inside the
              // walked row — a screen in two flows cannot be "live" in both.
              live: isStep,
              liveHref: withParams({ flow: flow.id, step: id, live: id }),
              liveCloseHref: withParams({ flow: null, step: null, live: null }),
              // The next step in THIS row. Null on the last tile — the walk
              // ends rather than wrapping. This is what the tile-chrome
              // advance control and the flow-walk island both target.
              advanceHref: edge ? withParams({ flow: flow.id, step: edge.to, live: edge.to }) : null,
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
              handoffs: edge ? [] : proj.handoffs(id, flow.id).map((handoff) => ({
                ...handoff,
                // Continue in that flow AT THIS SCREEN — it is the head of the
                // target row, so the walk lands where the eye already is.
                href: withParams({ flow: handoff.flow, step: id, live: id }),
              })),
              // What fires this edge, for the island's click matcher:
              // `element` is the authored join to a data-el value, `trigger`
              // is the prose fallback it fuzzy-matches when element is absent.
              edge: edge ? { to: edge.to, trigger: edge.trigger, element: edge.element ?? null } : null,
              // Extra stub query for the walked tile: the island inside the
              // iframe needs the PARENT url to advance to, plus what to match
              // a click against. Built here because encodeURIComponent in a
              // template expression is where this would quietly break.
              // `advance` is a plain viewer GET, so the island can hand it
              // straight to the parent's htmx — no new endpoint to keep in
              // sync with the viewer's param list.
              // `walkflow` also scopes the stub's OWN `next` edge, so the
              // surface's built-in CTA (auth.html hrefs to next.to) points at
              // the same screen the walk advances to. Without it nextEdge
              // falls back to first-match-across-all-flows and the two can
              // disagree inside the same tile.
              walkQs: edge
                ? `&walkflow=${encodeURIComponent(flow.id)}`
                  + `&walk=${encodeURIComponent(withParams({ flow: flow.id, step: edge.to, live: edge.to }))}`
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
    src: `${STUB_BASE}${active}?vp=${vp}&embed=1${theme ? `&theme=${theme}` : ''}`,
  } : null;

  // Kept even though the viewer's own filmstrip no longer reads it (that strip
  // is VIEWS-ONLY now, so it never renders in proto): freeze's composer tray
  // builds a strip outside #design-viewer and still consumes these hrefs.
  const protoPicks = mode === 'proto' ? Object.fromEntries(screens.map((screen) => [screen.id, withParams({ screen: screen.id })])) : null;

  // Canvas appearance cluster — rendered in the viewer's TOP bar
  // (design_viewer.html topbar), not the mini panel: the app-theme segmented
  // control (auto follows the studio theme; light/dark override the stubs
  // only) and the bg swatches, moved up from the mini-panel bar when the
  // top bar's duplicate undo/redo pair was retired (the bottom controller
  // keeps the only history buttons).
  const themes = ['auto', 'light', 'dark'].map((key) => ({ key, active: (theme ?? 'auto') === key, href: withParams({ theme: key === 'auto' ? null : key }) }));
  const bgs = ['canvas', 'warm', 'ink'].map((value) => ({ value, active: value === bg, href: withParams({ bg: value }) }));

  const miniPanel = {
    // The bar-right cluster (always mounted): device rung icons in ALL
    // lenses (in views/flows they re-render the tiles at that rung). The bg
    // swatches moved to the viewer topbar (`bgs` above).
    bar: {
      devices: DEVICES.map((designState) => ({ ...designState, active: designState.key === vp, href: withParams({ vp: designState.key === 'mobile' ? null : designState.key }) })),
    },
    controller: {
      modes: ['views', 'flows', 'proto'].map((key) => ({ key, active: key === mode, href: withParams({ mode: key === 'views' ? null : key }) })),
      undo: { can: (designState.undoStacks?.canvas?.length ?? 0) > 0, href: '/design/undo/canvas' },
      redo: { can: (designState.redoStacks?.canvas?.length ?? 0) > 0, href: '/design/redo/canvas' },
    },
  };

  return {
    inspect, live, active,
    screens, flows, bg, theme, themes, bgs,
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
    filmstrip: mode === 'views' ? filmstripFor(designState, contextBase.replace(/\/context\/$/, ''), activeLocale, { protoPicks, proto, theme }, false) : null,
    // Proto-mode screen picks. No longer read by the viewer's own strip (see
    // above), but freeze's composer tray still builds one outside
    // #design-viewer, so the viewer keeps handing the hrefs over.
    protoPicks,
    base, stubBase: STUB_BASE, contextBase,
    miniPanel,
    undoRedo: {
      canvas: { canUndo: (designState.undoStacks?.canvas?.length ?? 0) > 0, canRedo: (designState.redoStacks?.canvas?.length ?? 0) > 0 },
      chat:   { canUndo: (designState.undoStacks?.chat?.length ?? 0) > 0, canRedo: (designState.redoStacks?.chat?.length ?? 0) > 0 },
    },
    elements: (designState.elementContext ?? []).map((elementRef) => ({ ...elementRef, removeHref: `${contextBase}element/remove?screen=${encodeURIComponent(elementRef.screenId)}&name=${encodeURIComponent(elementRef.name)}` })),
    // Widget-manager selection (components column, views lens): rendered
    // inline in the selected screen's editor slot so a full viewer morph
    // keeps the open editor — same session-survival reasoning as the
    // inspector lock (D16).
    wedit: widgetEditorContext(designState, translate),
    // Edit arming (D2). Disarmed is the default and the safe state: tiles
    // keep interact-in-place (tap/scroll/hover reach the app under design).
    // Armed, a tile click SELECTS the widget instead of reaching the app —
    // the two readings of a click are mutually exclusive, so the mode is
    // explicit rather than inferred from a modifier key. Session state, so a
    // viewer morph never silently disarms mid-edit (D16's reasoning).
    weditArmed: !!designState.weditArmed,
    weditArmHref: '/design/widget/arm',
    // Per-screen reveal-drawer (Screen Reveal-Drawer plan, increment 2). Keyed
    // by screen id because the template renders one card per screen and needs
    // its own drawer state; a list would force an O(n) lookup per row in the
    // template language. Views lens only: the drawer
    // is the screen card's own back panel, and only the views lens renders one
    // card per designed screen.
    drawers: mode === 'views' ? drawerContexts(designState, screens, translate, activeLocale) : null,
  };
}

// Viewer toolbar act: the state keys (bg/inspect/live/mode/screen/vp) are
// AUTHORITATIVE — every control href echoes the whole viewer state
// (withParams), with defaults elided from the URL, so an absent key means
// "back to default", never "keep". Merging would strand every non-default
// value (a canvas chip sends no mode=, so a merged mode:'proto' could never
// flip back).
export const setViewer = (sessionData, query, prefs = {}, translate = (key) => key, locale = 'en') => {
  const designState = design(sessionData);
  const next = {};
  for (const [key, value] of Object.entries(query)) if (value != null) next[key] = value;
  designState.viewer = next;
  return stageContext(sessionData, {}, prefs, translate, locale);
};

// ---------- the per-screen reveal-drawer (Screen Reveal-Drawer plan) --------
// Session-scoped VIEW state only (D8): closed by default, Composer first-open,
// per-screen memory of open/tab within the session, nothing persisted to
// project files. It lives under d.drawer, NOT d.viewer — setViewer REPLACES
// d.viewer wholesale on every toolbar act, and an open drawer must survive a
// rung/bg/theme toggle.
const DRAWER_TABS = ['composer', 'tools', 'logic'];
const drawerEntry = (designState, id) => ({ open: false, tab: 'composer', ...(designState.drawer?.[id] ?? {}) });

export const setDrawer = (sessionData, screenId, { state, tab } = {}, prefs = {}, translate = (key) => key, locale = 'en') => {
  const designState = design(sessionData);
  const cur = drawerEntry(designState, screenId);
  const next = { ...cur };
  if (state != null) next.open = state === 'toggle' ? !cur.open : state === 'on';
  // A tab pick implies the drawer is out — the tabs are unreachable tucked.
  if (tab != null && DRAWER_TABS.includes(tab)) { next.tab = tab; next.open = true; }
  (designState.drawer ??= {})[screenId] = next;
  return stageContext(sessionData, {}, prefs, translate, locale);
};

// One drawer context per views-lens screen. The composer spec mounts the SAME
// reusable card as the composer panel (composer.html field), with a distinct
// scope + swapTarget so two instances cannot collide on one page: every swap
// this instance issues lands in its own container, routed by ?drawer=<id>
// (the viewmodels render `#drawerSwap` when they see it). Undo/redo ride the
// same global chat stack; only the RESPONSE routing is screen-scoped.
const drawerContexts = (designState, screens, translate, activeLocale = 'en') =>
  Object.fromEntries(screens.map((screen) => {
    const st = drawerEntry(designState, screen.id);
    const slug = screen.id.replace(/\./g, '-');
    const base = `/design/drawer/${screen.id}`;
    const chat = {
      canUndo: (designState.undoStacks?.chat?.length ?? 0) > 0,
      canRedo: (designState.redoStacks?.chat?.length ?? 0) > 0,
    };
    return [screen.id, {
      ...st,
      slug,
      toggleHref: `${base}?state=toggle`,
      tabs: DRAWER_TABS.map((key) => ({ key, active: key === st.tab, href: `${base}?tab=${key}` })),
      // Built only while THIS screen's drawer shows Tools: each entry costs
      // source reads (one resolveWidget per addressable widget), and a tab
      // the session has never picked must not pay them.
      tools: st.tab === 'tools' ? toolsContext(designState, screen, translate, activeLocale) : null,
      logic: st.tab === 'logic' ? logicContext(designState, screen, translate, activeLocale) : null,
      composer: {
        // ?screen= pins this screen before the send (screen-scoped send);
        // ?drawer= routes the response back to this drawer's container.
        composerAction: `/design/chat/messages?screen=${encodeURIComponent(screen.id)}&drawer=${encodeURIComponent(screen.id)}`,
        placeholder: translate('composer.placeholder.refine', { label: screen.label ?? screen.id }),
        suggestions: refineSuggestions(translate),
        // No model menu / filmstrip / chips / tray body: their hrefs all swap
        // the composer's target, and rendering them here would demand a
        // drawer-scoped route per control for chrome the drawer does not need.
        modelMenu: null,
        filmstrip: null,
        contextChips: null,
        trayContext: null,
        elements: null,
        tray: { open: false, toggleHref: '' },
        undoRedo: { chat },
        undoHref: `/design/undo/chat?drawer=${encodeURIComponent(screen.id)}`,
        redoHref: `/design/redo/chat?drawer=${encodeURIComponent(screen.id)}`,
        swapTarget: `#dv-drawer-${slug}`,
      },
    }];
  }));

// ---------- the design thread (seeded history + session messages) ----------

const allCheckpoints = (designState, screenId, activeLocale) =>
  [...(repo.checkpoints(activeLocale)[screenId] ?? []), ...(designState.chatCheckpoints?.[screenId] ?? [])]
    .map((cp) => ({ ...cp, reverted: (designState.reverted ?? []).includes(cp.id) }));

function threadFor(designState, lv, activeLocale) {
  return [...repo.designThread(activeLocale), ...(designState.designThread ?? [])].map((message) => ({
    ...message,
    text: message.from === 'user' ? message.text : jargon.pick(message, 'text', lv),
    link: message.link ?? null,
    cps: (message.cps ?? [])
      .map(({ screen, cp }) => {
        const found = allCheckpoints(designState, screen, activeLocale).find((checkpoint) => checkpoint.id === cp);
        return found ? { screen, ...found, summary: jargon.pick(found, 'summary', lv) } : null;
      })
      .filter(Boolean),
  }));
}

// ---------- the stage context (prototype / chat share it) ----------

// Suggestion chips: values are posted back as user text (they render in the
// thread), so both value and label come from the catalog.
const refineSuggestions = (translate) => [
  { value: translate('design.sug.editLayout.value'), label: translate('design.sug.editLayout.label') },
  { value: translate('design.sug.restyle.value'), label: translate('design.sug.restyle.label') },
  { value: translate('design.sug.adjustStates.value'), label: translate('design.sug.adjustStates.label') },
  { value: translate('design.sug.regenerate.value'), label: translate('design.sug.regenerate.label') },
];

function screenCard(screen, designState, activeLocale, translate) {
  const checkpoints = (repo.checkpoints(activeLocale)[screen.id] ?? []).length + (designState.chatCheckpoints?.[screen.id] ?? []).length;
  return {
    type: 'screen', state: screen.state, threadCount: checkpoints,
    detail: translate('design.screenCardDetail', { rungs: screen.rungs.length, kit: screen.kit, wire: screen.wire }),
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

const elementCard = (designState, elementSelection, activeLocale) => {
  // role falls back to the data-el prefix — the same fallback inspect.js used
  // to do in the overlay. The fallback IS the inference, which is why the flag
  // is computed here: the island posts the attribute or nothing, and never
  // claims a provenance it cannot know.
  const roleValue = elementSelection.role || String(elementSelection.name ?? '').split(':')[0] || '';
  // The ancestor chain (outermost→innermost) the island walked to reach this
  // element. Each crumb except the last gets a selectHref that POSTs back to
  // /design/inspector/select — clicking an ancestor selects+locks it. The
  // href is built here because the facade owns all hrefs (see header comment).
  const rawChain = Array.isArray(elementSelection.chain) ? elementSelection.chain : [];
  const lastIdx = rawChain.length - 1;
  const chain = rawChain.map((rawCrumb, index) => {
    const crumb = { el: rawCrumb?.el ?? '', inferred: !!rawCrumb?.inferred, selectHref: null };
    if (index === lastIdx) return crumb;
    const qs = new URLSearchParams();
    if (crumb.el) qs.set('name', crumb.el);
    if (rawCrumb?.role) qs.set('role', rawCrumb.role);
    if (elementSelection.screen) qs.set('screen', elementSelection.screen);
    if (crumb.inferred) qs.set('inferred', '1');
    qs.set('lock', '1');
    crumb.selectHref = `/design/inspector/select?${qs.toString()}`;
    return crumb;
  });
  return {
    name: elementSelection.name,
    kind: elementSelection.kind ?? '',
    instance: elementSelection.instance ?? '',
    instanceCount: elementSelection.instanceCount ?? '',
    screenId: elementSelection.screen,
    tone: toneFor(elementSelection.screen, activeLocale),
    // True when the island had no data-el to read — identity was inferred from
    // tag/text, not declared. A card-level marker distinct from per-field
    // inference (role.inferred etc.).
    inferred: !!elementSelection.inferred,
    chain,
    role: { value: roleValue, inferred: !elementSelection.role && !!roleValue },
    style: elementSelection.style || null,
    motion: elementSelection.motion || null,
    // D9's fn derivation lives in the Dart lint, which reads SOURCE. Nothing
    // here can infer a function from a rendered node, so an absent fn is
    // reported absent rather than guessed — a wrong provenance flag is worse
    // than a missing card line.
    fn: elementSelection.fn ? { value: elementSelection.fn, inferred: false } : null,
    pinned: (designState.elementContext ?? []).some((elementRef) => elementRef.screenId === elementSelection.screen && elementRef.name === elementSelection.name),
    pinHref: `${CONTEXT_BASE}element`,
    unpinHref: `${CONTEXT_BASE}element/remove?screen=${encodeURIComponent(elementSelection.screen)}&name=${encodeURIComponent(elementSelection.name)}`,
  };
};

const screenCardFor = (designState, activeLocale, fallbackScreenId = null) => {
  // fallbackScreenId is the viewer's currently-active screen (viewerFor's
  // `active`) — inspectorScreenId only gets set by a real element hover
  // (selectElement), so without this fallback the pane stays 'empty' until
  // the user hovers an element at least once. D17 specifies the screen card
  // for "nothing hovered/locked", i.e. the moment the pane opens, not after.
  const id = designState.inspectorScreenId ?? fallbackScreenId ?? null;
  const entry = id ? proj.registryEntry(id) : null;
  if (!entry) return null;
  const edges = [];
  for (const flow of proj.flows()) {
    for (const edge of flow.edges ?? []) {
      if (edge.from !== id) continue;
      edges.push({
        flow: flow.id,
        flowLabel: flow.label ?? flow.id,
        trigger: edge.trigger ?? '',
        to: edge.to,
        element: edge.element ?? null,
      });
    }
  }
  // epic/state are NOT registry fields — the registry carries
  // {id,label,shell,comp,route,surface,states,kits}. They live on the screens
  // repo, so they are joined from there; reading entry.epic would render a
  // permanently blank row that looks like "this screen has no epic".
  const screen = repo.screens(activeLocale).find((candidateScreen) => candidateScreen.id === id) ?? {};
  return {
    id,
    label: entry.label ?? id,
    epic: screen.epic ?? '',
    state: screen.state ?? '',
    tone: toneFor(id, activeLocale),
    // All 'declared': deriving states from kits needs the kit→state map, which
    // is authored in the designer's kit-catalog and mirrored in Dart. Marking
    // a declared state 'derived' here would be a guess, so nothing is.
    states: (entry.states ?? []).map((stateName) => ({ name: stateName, source: 'declared' })),
    // Empty until the kit→state map is readable from JS. An empty list renders
    // no section, which is the honest result — NOT "nothing is missing".
    missingStates: [],
    kits: (entry.kits ?? []).map((kitId) => ({ id: kitId, label: kitId })),
    edges,
    // null, deliberately: annotation coverage counts [data-el] occurrences in
    // SOURCE, and those values are templated (see the wall above). The Dart
    // lint computes this; this file would have to guess. null renders nothing.
    annotations: null,
  };
};

const inspectorFor = (designState, activeLocale, fallbackScreenId = null, active = true) => {
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
    return { mode: 'empty', locked: !!designState.inspectorLock, element: null, screen: null, unlockHref: '/design/inspector/unlock', hint: null };
  }
  const shown = designState.inspectorLock ?? designState.inspectorHover ?? null;
  const element = shown && shown.name ? elementCard(designState, shown, activeLocale) : null;
  const screen = element ? null : screenCardFor(designState, activeLocale, fallbackScreenId);
  return {
    mode: element ? 'element' : screen ? 'screen' : 'empty',
    locked: !!designState.inspectorLock,
    element,
    screen,
    unlockHref: '/design/inspector/unlock',
    hint: null,
  };
};

// The island fires one request per element change. While locked, a hover must
// cost nothing: return the stage unchanged so the pane re-renders identically
// and the morph is a no-op.
export const selectElement = (sessionData, payload = {}, prefs = {}, translate = (key) => key, locale = 'en') => {
  const designState = design(sessionData);
  // "Locked wins" (D16): while a lock is held a hover changes NOTHING. The lock
  // is a deliberate pick; an element merely brushed past while it is held must
  // not displace it — and must not become what unlock falls back to either.
  if (designState.inspectorLock && payload.lock !== '1') return stageContext(sessionData, {}, prefs, translate, locale);
  // chain is a JSON string from the island (a trust boundary) — guard the
  // parse so a malformed body can never crash the selection path.
  let chain = [];
  try { chain = JSON.parse(payload.chain || '[]'); } catch (_) { chain = []; }
  if (!Array.isArray(chain)) chain = [];
  const elementSelection = {
    screen: payload.screen ?? '',
    name: payload.name ?? '',
    kind: payload.kind ?? '',
    role: payload.role ?? '',
    style: payload.style ?? '',
    motion: payload.motion ?? '',
    fn: payload.fn ?? '',
    inferred: payload.inferred === '1',
    chain,
    instance: payload.instance ?? '',
    instanceCount: payload.instanceCount ?? '',
  };
  if (payload.lock === '1') designState.inspectorLock = elementSelection; else designState.inspectorHover = elementSelection;
  // Remembered so the screen card still has a subject once the pointer leaves
  // every element — mode 'screen' is the state between hovers, not a dead end.
  if (elementSelection.screen) designState.inspectorScreenId = elementSelection.screen;
  return stageContext(sessionData, {}, prefs, translate, locale);
};

// Clears the lock, KEEPS the hover — D16: the lock is session state precisely
// so it survives htmx morphs, and clearing it should fall back to live hover
// rather than to empty.
export const unlockInspector = (sessionData, prefs = {}, translate = (key) => key, locale = 'en') => {
  const designState = design(sessionData);
  // Promote the lock into the hover slot before dropping it. Unlocking should
  // LEAVE the element you were studying on screen and resume live tracking from
  // the NEXT hover — not blank the pane back to the screen card. Without this,
  // locking an element that was never hovered first (the island posts lock=1 on
  // a click, and a click need not be preceded by a hover post) left nothing to
  // fall back to, so unlock emptied the pane.
  if (designState.inspectorLock) designState.inspectorHover = designState.inspectorLock;
  delete designState.inspectorLock;
  return stageContext(sessionData, {}, prefs, translate, locale);
};

// ---------- widget manager (components column, views lens only) ----------
// The k spacing steps the editor may write: the widgets.css Auto Layout
// contract (data-gap/data-pad: 4|8|12|16|24), the designer-side subset of the
// kit scale (kPad*/kGap* in kit_app_constants.dart). Scale-level enforcement
// by decision: the NUMBERS are the contract — the Dart constant names stay
// kit-internal — and anything off-scale is rejected below, never written.
const K_STEPS = [4, 8, 12, 16, 24];
// Per-axis sizing modes: the widgets.css Auto Layout contract's OWN values
// ([data-resize-x|y]="hug|fill|fixed"), not a parallel vocabulary. Fixed is a
// MODE, not a measurement — the contract carries no size-bearing attribute
// (no data-w/data-h), so an edge-drag commits `fixed` and the pixel figure it
// snapped to lives only in the drag preview. Inventing a size attr here would
// fork the contract, so we don't.
const RESIZE_MODES = ['hug', 'fill', 'fixed'];
// One table = one enforcement point. Every writable attribute names its own
// legal values, so a mode never validates against the k scale (and vice
// versa); anything not listed is a 400 at the facade, never written.
const W_ATTR_VALUES = {
  'data-pad': K_STEPS.map(String),
  'data-gap': K_STEPS.map(String),
  'data-resize-x': RESIZE_MODES,
  'data-resize-y': RESIZE_MODES,
};
const W_ATTRS = Object.keys(W_ATTR_VALUES);

export const widgetEditorContext = (designState, translate = (key) => key) => {
  const sel = designState.widgetSel;
  if (!sel) return { sel: null };
  const widget = widgets.resolveWidget(sel.screen, sel.kind, sel.index ?? 0);
  if (!widget) return { sel: null };
  // posting a chip's own current value toggles the attribute OFF (val ''):
  // one control, no separate "clear" affordance per attribute.
  const step = (attr) => K_STEPS.map((stepOption) => ({
    v: stepOption,
    on: (widget.attrs[attr] ?? '') === String(stepOption),
    val: (widget.attrs[attr] ?? '') === String(stepOption) ? '' : String(stepOption),
  }));
  // Same toggle-off rule as the k chips: re-posting the active mode clears
  // the attribute, so "no explicit mode" stays reachable without a second
  // control. Keeps the editor's whole vocabulary one interaction shape.
  const mode = (attr) => RESIZE_MODES.map((modeOption) => ({
    m: modeOption,
    on: (widget.attrs[attr] ?? '') === modeOption,
    val: (widget.attrs[attr] ?? '') === modeOption ? '' : modeOption,
  }));
  return {
    sel: { ...sel, name: sel.name ?? '' },
    file: widget.file,
    tag: widget.tag,
    attrs: widget.attrs,
    screens: widgets.screensUsing(widget.file),
    pads: step('data-pad'),
    gaps: step('data-gap'),
    resizeX: mode('data-resize-x'),
    resizeY: mode('data-resize-y'),
    attrHref: '/design/widget/attr',
    clearHref: '/design/widget/clear',
  };
};

// Edit arming toggle (viewer toolbar). Returns the whole stage: arming flips
// how every tile reads a click, and the tiles are rendered by the viewer, so
// a partial swap would leave stale tiles armed. Disarming also drops the
// selection — a lingering editor for a widget you can no longer click is a
// dead panel, and "disarm" reads as "leave edit mode" to a user.
export const armWidgetEdit = (sessionData, prefs = {}, translate = (key) => key, locale = 'en') => {
  const designState = design(sessionData);
  if (designState.weditArmed) { delete designState.weditArmed; delete designState.widgetSel; } else designState.weditArmed = 1;
  return stageContext(sessionData, {}, prefs, translate, locale);
};

// Posted by canvas.js on an armed tile click and by the drawer Tools strip.
// Selection is session state so it survives viewer morphs.
//
// Returns the full stageContext, exactly like armWidgetEdit above, because
// selection has to reach TWO places: the editor fragment AND the canvas body's
// data-wedit-sel that drag.js hangs the resize handles off. The slim
// widgetEditorContext only fed the former, so the editor opened while the
// handles stayed invisible.
export const selectWidget = (sessionData, payload = {}, prefs = {}, translate = (key) => key, locale = 'en') => {
  const designState = design(sessionData);
  designState.widgetSel = {
    screen: payload.screen ?? '',
    kind: payload.kind ?? '',
    name: payload.name ?? '',
    index: Number(payload.index ?? 0) || 0,
  };
  return stageContext(sessionData, {}, prefs, translate, locale);
};

// Full context for the same reason: dropping the selection has to drop
// data-wedit-sel from the canvas, or the handles outlive the selection.
export const clearWidget = (sessionData, prefs = {}, translate = (key) => key, locale = 'en') => {
  const designState = design(sessionData);
  delete designState.widgetSel;
  return stageContext(sessionData, {}, prefs, translate, locale);
};

// Write-through: mutates the widget's SOURCE element (its definition), so
// every screen composing it re-renders on the watcher reload — cross-screen
// sync is emergent, not plumbed. Off-scale values are a 400, not a clamp:
// clamping would silently teach users a scale that isn't the contract.
export const setWidgetAttr = async (sessionData, payload = {}, translate = (key) => key) => {
  const designState = design(sessionData);
  const sel = designState.widgetSel;
  const attr = String(payload.attr ?? '');
  const value = String(payload.value ?? '');
  if (!sel || !W_ATTRS.includes(attr) || (value !== '' && !W_ATTR_VALUES[attr].includes(value))) {
    const err = new Error('off-contract widget attr');
    err.status = 400;
    throw err;
  }
  await widgets.setWidgetAttr(sel.screen, sel.kind, sel.index ?? 0, attr, value);
  return widgetEditorContext(designState, translate);
};

// ---------- the Tools tab (Screen Reveal-Drawer plan, increment 3) ----------
// ONE shared selection state (D5): d.widgetSel — the same session key an
// armed canvas click writes through selectWidget — is the only selection the
// drawer consumes, and the strip below posts the same /design/widget/select
// route. No parallel vocabulary: a Tools pick arms the same canvas handles
// and vice versa.
const toolsContext = (designState, screen, translate, activeLocale = 'en') => {
  const selRaw = designState.widgetSel ?? null;
  const sel = selRaw && selRaw.screen === screen.id ? selRaw : null;
  // The hierarchy strip (D5): this screen's addressable widgets, enumerated
  // with resolveWidget's own rule so the strip can never offer a selection
  // the editor cannot resolve.
  const strip = widgets.widgetsOn(screen.id).map((widget) => ({
    ...widget,
    on: !!sel && sel.kind === widget.kind && (sel.index ?? 0) === widget.index,
  }));
  const base = {
    strip,
    selectHref: '/design/widget/select',
    // Selection parked on ANOTHER screen: named, not blanked — an empty pane
    // that secretly depends on which screen was clicked last reads as broken.
    elsewhere: selRaw && !sel ? selRaw.screen : null,
  };
  if (!sel) return { ...base, sel: null };
  const wed = widgetEditorContext(designState, translate);
  if (!wed.sel) return { ...base, sel: null };
  // Attributes the source element declares beyond the writable contract
  // (data-layout, data-flow, …): shown read-only WITH the reason (D7 —
  // unresolvable renders read-only, never a dead control).
  const roAttrs = Object.entries(wed.attrs ?? {})
    .filter(([attributeName]) => !W_ATTRS.includes(attributeName))
    .map(([attr, value]) => ({ attr, value }));
  return { ...base, sel: wed.sel, wedit: wed, roAttrs, copy: copyContext(sel, translate, activeLocale) };
};

// Copy provenance for the Tools tab, one honest class per D7: editable where
// the pipeline can address the owner (a project-declared ARB key in the
// CURRENT locale, or a literal in the surface partial), read-only WITH THE
// REASON otherwise. The classes come from text_repository.classify — this
// only phrases them.
const copyContext = (sel, translate, activeLocale = 'en') => {
  let provenance = null;
  try { provenance = texts.textProvenance(sel.screen, sel.kind, sel.index ?? 0); } catch { provenance = null; }
  if (!provenance) return { editable: false, text: null, reason: translate('viewer.tools.noCopy') };
  const textHref = '/design/widget/text';
  if (provenance.source === 'arb') {
    const value = texts.arbValue(provenance.key, activeLocale);
    // Key resolves from the artifact's base catalogue (or another locale):
    // writing would mint an override the user has not asked for, which
    // text_repository gates behind allowOverride — so reported, not written.
    if (value == null) return { editable: false, text: null, reason: translate('viewer.tools.roOverride', { key: provenance.key }) };
    return { editable: true, text: value, note: translate('viewer.tools.copyArb', { key: provenance.key }), textHref };
  }
  if (provenance.source === 'literal') return { editable: true, text: provenance.text, note: translate('viewer.tools.copyLiteral', { file: provenance.file }), textHref };
  if (provenance.source === 'bound') return { editable: false, text: provenance.text, reason: translate('viewer.tools.roBound', { expr: provenance.expr }) };
  return { editable: false, text: provenance.text, reason: translate('viewer.tools.roMixed') };
};

// ---------- the Logic tab (Screen Reveal-Drawer plan, increment 4) ----------
// D6: a deterministic connection graph from repo facts only — the registry
// entry (route / build class / kits / states), the flows (edgesFrom), and the
// source element's own inspect annotations (data-inspect-role/fn, read by
// widget_repository). The edge join is the EXACT authored `element` match
// only: the fuzzy trigger fallback flowwalk.js uses is a click matcher for
// prose triggers, and a graph that guesses is worse than one that admits it
// cannot know. What the facts cannot prove renders an honest state — 'unwired' when
// a static data-el is named by no flow edge, 'unknown' when the data-el is
// templated and static analysis cannot resolve it. No LLM, no fabricated
// edges; the widget-logic probe asserts the fabrication-free shape.
// Selection is the same shared d.widgetSel the Tools tab consumes (D5): it
// only MARKS the matching row here, no parallel mechanism.
const logicContext = (designState, screen, translate, activeLocale = 'en') => {
  const reg = proj.registryEntry(screen.id) ?? {};
  const edges = proj.edgesFrom(screen.id);
  const selRaw = designState.widgetSel ?? null;
  const sel = selRaw && selRaw.screen === screen.id ? selRaw : null;
  const labelOf = (id) => proj.registryEntry(id)?.label ?? id;
  return {
    screen: {
      route: reg.route ?? null,
      comp: reg.comp ?? null,
      kits: reg.kits ?? [],
      states: reg.states ?? [],
      // Screen-level wiring: edges that name no element belong to the screen
      // (chrome taps, auto-advance). Element-named edges are attributed to
      // their widget below, so nothing renders twice.
      edges: edges.filter((edge) => !edge.element).map((edge) => ({ ...edge, toLabel: labelOf(edge.to) })),
    },
    widgets: widgets.widgetsOn(screen.id).map((widget) => {
      // Templated means static analysis cannot resolve the name: `{{ }}`
      // (mustache-style seeds) OR `${ }` (TSX template-literal data-el, the
      // form the scaffolder emits for localized labels). Missing either
      // marker classified interpolated buttons 'unwired' — a fabricated
      // certainty; 'unknown' is the honest state.
      const templated = !widget.el || widget.el.includes('{{') || widget.el.includes('${');
      const edge = templated ? null : edges.find((candidateEdge) => candidateEdge.element === widget.el) ?? null;
      return {
        kind: widget.kind, index: widget.index, el: widget.el ?? null,
        role: widget.inspect?.role ?? null,
        fn: widget.inspect?.fn ?? null,
        wiring: edge ? 'edge' : templated ? 'unknown' : 'unwired',
        edge: edge ? { ...edge, toLabel: labelOf(edge.to) } : null,
        on: !!sel && sel.kind === widget.kind && (sel.index ?? 0) === widget.index,
      };
    }),
  };
};

// Copy write-through (increment 3): the provenance-routed text pipeline D7
// names as the proven pattern. The locale is the one being VIEWED — editing
// the string on screen must not silently rewrite another catalogue. Refused
// classes are a 400 carrying the classifier's own reason, mirror of
// setWidgetAttr: the write path never learns to guess.
export const setWidgetCopy = async (sessionData, payload = {}, prefs = {}, translate = (key) => key, locale = 'en') => {
  const designState = design(sessionData);
  const sel = designState.widgetSel;
  if (!sel) {
    const err = new Error('no widget selected');
    err.status = 400;
    throw err;
  }
  try {
    await texts.setWidgetText(sel.screen, sel.kind, sel.index ?? 0, String(payload.value ?? ''), locale);
  } catch (error) {
    // Classified refusals and unroutable targets are user-visible facts, not
    // crashes; a failed project WRITE (the fetch inside) stays a 500.
    if (error.provenance || /^no catalogue|^widget not found/.test(String(error.message))) error.status = 400;
    throw error;
  }
  return stageContext(sessionData, {}, prefs, translate, locale);
};

export const stageContext = (sessionData = {}, opts = {}, prefs = {}, translate = (key) => key, locale = 'en') => {
  const activeLocale = locale;
  const lv = jargon.level(prefs);
  const designState = design(sessionData);
  if (opts.pin === 'none') designState.context = [];
  else if (opts.pin) pin(designState, opts.pin, activeLocale);
  const base = opts.base ?? '/design/chat';
  // The open file (main panel): ?file=<path> opens, ?file=none closes — the
  // main panel shows the file until then (pins refine, they don't look).
  if (opts.file === 'none') designState.currentFile = null;
  else if (opts.file) designState.currentFile = opts.file;
  const fileBase = opts.fileBase ?? '/design';
  // The panel bar (compact/medium): ?panel= picks the single visible content
  // panel and sticks; default main.
  if (['activity', 'main', 'composer'].includes(opts.panel)) designState.panel = opts.panel;

  const drafted = designState.drafted === true;
  const ids = contextIds(designState, activeLocale);
  const filter = designState.activityFilter ?? 'all';
  const activityView = ['screens', 'artifacts', 'files', 'inspector'].includes(designState.activityView) ? designState.activityView : 'screens';
  const thread = threadFor(designState, lv, activeLocale);
  const viewer = viewerFor(designState, activeLocale, translate);
  const screens = repo.screens(activeLocale)
    .filter((screen) => filter === 'all' || screen.epic === filter)
    .map((screen) => ({
      ...screen,
      summary: jargon.pick(screen, 'summary', lv),
      inContext: ids.includes(screen.id),
      tone: toneFor(screen.id, activeLocale),
      card: screenCard(screen, designState, activeLocale, translate),
    }));
  return {
    // rungsLabel precomputed: fragment imports re-execute page blocks with an
    // empty context, and a join filter on undefined throws — plain access is safe.
    run: { ...repo.run(activeLocale), rungsLabel: repo.run(activeLocale).policy.rungs.join('/') },
    project: { name: repo.run(activeLocale).project },
    counts: repo.counts(activeLocale),
    epics: repo.epics(activeLocale),
    filter,
    activityView,
    activityLabel: translate('activityView.' + activityView),
    panelSize: panelSizeFor(designState, 'activity'),
    panelSizeHref: '/design/panel/size/activity/',
    panelSizePx: designState.panelSizePx?.activity ?? null,
    activityViews: [
      { id: 'screens', icon: 'layout-grid', href: '/design/panel/screens' },
      { id: 'artifacts', icon: 'package', href: '/design/panel/artifacts' },
      { id: 'files', icon: 'folder', href: '/design/panel/files' },
      // The inspector renders from prototype_view.html#inspectorSwap, not from
      // _shared.html#activityBody, so it carries its OWN href rather than
      // riding the /design/panel/:view map like the other three.
      { id: 'inspector', icon: 'scan-search', href: '/design/inspector' },
    ].map((viewOption) => ({ ...viewOption, label: translate('activityView.' + viewOption.id), active: viewOption.id === activityView })),
    // D14–D17. Present on EVERY render: the pane re-renders from fragment
    // swaps that carry the whole stage context, so it must never be
    // conditional on activityView.
    inspector: inspectorFor(designState, activeLocale, viewer.active, activityView === 'inspector'),
    screens,
    artifacts: repo.artifacts(activeLocale),
    files: repo.files(activeLocale).map((flow) => ({ ...flow, ...fv.fileLink(flow.path, fileBase) })),
    fileView: designState.currentFile ? fv.fileViewFor(designState.currentFile, `${fileBase}?file=none`) : null,
    panel: designState.panel ?? 'main',
    drafted,
    threading: thread.some((message) => message.from === 'user'),
    stageEyebrow: translate('design.chat.eyebrow'),
    composerAction: '/design/chat/messages',
    modelMenu: agent.modelMenuFor(sessionData, base, translate),
    tray: { open: designState.trayOpen !== false, toggleHref: `${base}/tray?state=toggle` },
    // The tray's filmstrip: every screen as a thumb (see filmstripFor). Only
    // on surfaces with NO design viewer — the canvas surfaces float the strip
    // over the views canvas instead (viewerFor -> viewer.filmstrip), and two
    // copies would be two sets of thumb iframes for the same screens.
    // Freeze opts in (composerStrip); its stage has a composer and no viewer.
    // The tray head summarizes the PINNED subset ("first +N"); null when the
    // context is empty — the filmstrip still renders, nothing dimmed.
    filmstrip: opts.composerStrip ? filmstripFor(designState, base, activeLocale, viewer, opts.noProto) : null,
    trayContext: ids.length ? { first: ids[0], extra: ids.length - 1 } : null,
    // The pinned screens themselves, one chip each — what the composer SAYS
    // about the context now that the thumbs live in the viewer. Same tone as
    // the screen's canvas tile and filmstrip thumb (toneFor is id-keyed, so
    // the three agree by construction, not by copying a value around).
    // removeHref is base-scoped like the filmstrip's toggle, so the unpin
    // swaps the surface being rendered rather than always /design/chat.
    contextChips: ids.map((id) => ({
      id,
      label: repo.screen(id, activeLocale).label,
      tone: toneFor(id, activeLocale),
      removeHref: `${base}/context/${id}?state=off`,
    })),
    viewer,
    // The shared composer reads these at stage level (composer.html: element
    // chips in the tray, the chat undo/redo pair) — the viewer keeps its own
    // copies for the mini panel (contract §1).
    elements: viewer.elements,
    undoRedo: viewer.undoRedo,
    thread,
    suggestions: refineSuggestions(translate),
    placeholder: translate('composer.placeholder.refine', { label: ctxLabel(designState, activeLocale, translate) }),
    timeline: timeline(designState, activeLocale, translate),
    jargonLevel: lv,
  };
};

// Context pin toggle from the filmstrip / artboard chrome / activity card.
// state: 'toggle' | 'on' | 'off'.
export const toggleContext = (sessionData, screenId, state = 'toggle', prefs = {}, translate = (key) => key, locale = 'en') => {
  const designState = design(sessionData);
  const wasIn = contextIds(designState, locale).includes(screenId);
  const on = state === 'toggle' ? !wasIn : state === 'on';
  if (on) pin(designState, screenId, locale); else unpin(designState, screenId, locale);
  if (on !== wasIn) pushCanvasUndo(designState, { type: on ? 'pin' : 'unpin', screenId });
  return stageContext(sessionData, {}, prefs, translate, locale);
};

// Bulk pin from the marquee selection (drag.js POSTs a comma-separated id list).
export const bulkPin = (sessionData, idsCsv, prefs = {}, translate = (key) => key, locale = 'en') => {
  const designState = design(sessionData);
  for (const id of idsCsv.split(',').map((idText) => idText.trim()).filter(Boolean)) {
    if (repo.screen(id, locale)) {
      pin(designState, id, locale);
      pushCanvasUndo(designState, { type: 'pin', screenId: id });
    }
  }
  return stageContext(sessionData, {}, prefs, translate, locale);
};

// Composer chrome: pick the agent model, or collapse/expand the context
// tray. Both mutate session state; callers re-render their own surface
// context (freeze ignores the returned stage context).
export const setModel = (sessionData, id, opts = {}, prefs = {}, translate = (key) => key, locale = 'en') => {
  agent.setModel(sessionData, id);
  return stageContext(sessionData, opts, prefs, translate, locale);
};

export const setTray = (sessionData, state, opts = {}, prefs = {}, translate = (key) => key, locale = 'en') => {
  const designState = design(sessionData);
  // the checkbox already flipped locally — mirror it (toggling, never an
  // absolute state: a stale absolute href would desync on double-click)
  designState.trayOpen = state === 'toggle' ? !(designState.trayOpen !== false) : state !== 'off';
  return stageContext(sessionData, opts, prefs, translate, locale);
};

// A file row in the activity panel: open it in the main panel (the mode is
// the server's, from the extension).
export const openFile = (sessionData, path, prefs = {}, translate = (key) => key, locale = 'en') =>
  stageContext(sessionData, { file: path ?? 'none' }, prefs, translate, locale);

export const setActivityFilter = (sessionData, filter, prefs = {}, translate = (key) => key, locale = 'en') => {
  design(sessionData).activityFilter = filter;
  return stageContext(sessionData, {}, prefs, translate, locale);
};

export const setActivityView = (sessionData, view, prefs = {}, translate = (key) => key, locale = 'en') => {
  design(sessionData).activityView = view;
  return stageContext(sessionData, {}, prefs, translate, locale);
};

// Panel width grip: cycle persisted per panel (the shell's own sizing state).
export const setPanelSize = (sessionData, panel, size, prefs = {}, translate = (key) => key, locale = 'en') => {
  if (PERSISTABLE_PANELS.includes(panel) && PANEL_SIZES.includes(size)) {
    (design(sessionData).panelSize ??= {})[panel] = size;
  }
  return stageContext(sessionData, {}, prefs, translate, locale);
};

// Panel drag handle: px width persisted per panel.
//
// The band here is a SANITY GUARD against a malformed POST, not the panel's
// real limits — those are its CSS min/max width, which the server cannot read
// and does not need to: drag.js clamps to them before posting and `min-width`
// re-clamps on render, so every legitimate value already falls inside this
// band. Do not treat these numbers as the layout's limits; that confusion is
// what made the drag readout count down to a width no panel could render.
export const setPanelSizePx = (sessionData, panel, width, prefs = {}, translate = (key) => key, locale = 'en') => {
  const designState = design(sessionData);
  const widthValue = Number(width);
  // A junk width is DROPPED, not defaulted. The old `|| 280` persisted a width
  // below every panel's floor, so the stored number and the rendered panel
  // disagreed permanently — and silently, because min-width quietly fixes the
  // render while the session keeps the bad value.
  if (Number.isFinite(widthValue)) (designState.panelSizePx ??= {})[panel] = Math.max(200, Math.min(600, widthValue));
  return stageContext(sessionData, {}, prefs, translate, locale);
};

// Move a screen inside a flow — a one-step nudge (dir -1|1, no-op at the row
// ends) from the tile toolbar, or a drop-to-index from the axis-locked row
// drag (index counts slots among the OTHER tiles, so splice-out-then-insert
// lands it exactly there). Writes the project's flows.json and records the
// before/after order arrays for undo/redo replay.
export const moveInFlow = async (sessionData, flowId, screenId, to = {}, prefs = {}, translate = (key) => key, locale = 'en') => {
  const designState = design(sessionData);
  try {
    const flows = proj.flows();
    const flow = flows.find((candidateFlow) => candidateFlow.id === flowId);
    const chain = chainOf(flow);
    const index = chain.indexOf(screenId);
    let scanIndex = index;
    if (Number.isInteger(to.index)) scanIndex = Math.max(0, Math.min(chain.length - 1, to.index));
    else if (to.dir === -1 || to.dir === 1) scanIndex = index + to.dir;
    if (flow && index >= 0 && scanIndex !== index && scanIndex >= 0 && scanIndex < chain.length) {
      const before = [...chain];
      const after = [...chain];
      after.splice(index, 1);
      after.splice(scanIndex, 0, screenId);
      // Per-screen trigger snapshot taken BEFORE the rewire: a screen demoted
      // to chain tail drops its outgoing edge from the file, and undo replays
      // by re-deriving from the then-current file — this memory lets that
      // replay restore the trigger verbatim (see rewire).
      const triggers = moveMemory(flow);
      rewire(flow, after, triggers);
      await proj.writeFlowsDual(flows, [flowId]);
      pushCanvasUndo(designState, { type: 'flow-move', flowId, before, after, triggers });
    }
  } catch { /* no project overlaid / unknown flow — no-op re-render */ }
  return stageContext(sessionData, {}, prefs, translate, locale);
};

// Append a screen to a flow's chain (views-lens add-to-flow menu). No-op when
// already a member.
export const addToFlow = async (sessionData, flowId, screenId, prefs = {}, translate = (key) => key, locale = 'en') => {
  const designState = design(sessionData);
  try {
    const flows = proj.flows();
    const flow = flows.find((candidateFlow) => candidateFlow.id === flowId);
    if (flow && proj.registryEntry(screenId) && appendTo(flow, screenId)) {
      await proj.writeFlowsDual(flows, [flowId]);
      pushCanvasUndo(designState, { type: 'flow-add', flowId, screenId });
    }
  } catch { /* no project overlaid / unknown flow — no-op re-render */ }
  return stageContext(sessionData, {}, prefs, translate, locale);
};

// Remove a screen from a flow, stitching the chain (see excise). The undo
// entry keeps the removed edges so undo restores them verbatim.
export const removeFromFlow = async (sessionData, flowId, screenId, prefs = {}, translate = (key) => key, locale = 'en') => {
  const designState = design(sessionData);
  try {
    const flows = proj.flows();
    const flow = flows.find((candidateFlow) => candidateFlow.id === flowId);
    const index = chainOf(flow).indexOf(screenId);
    // REFUSED when the removal would empty the chain — no write, unchanged
    // viewmodel. The tile's `canRemove` (same helper) greys the button out first,
    // but this is the one that has to hold: a 0-edge flow cannot be undone into
    // existence again (see canRemoveFrom).
    const removed = flow && canRemoveFrom(flow, screenId) ? excise(flow, screenId) : null;
    if (removed) {
      await proj.writeFlowsDual(flows, [flowId]);
      pushCanvasUndo(designState, { type: 'flow-remove', flowId, screenId, index, ...removed });
    }
  } catch { /* no project overlaid / unknown flow — no-op re-render */ }
  return stageContext(sessionData, {}, prefs, translate, locale);
};

// Element context chips: independent of screen chips in the composer tray. A
// pin dedupes on (screenId, name) and auto-opens the tray. These do NOT touch
// the canvas undo stack — element-scoped checkpoints (contract §6) are a
// separate slice; this just maintains the tray membership.
export const pinElement = (sessionData, screenId, name, kind, prefs, translate, locale, instance) => {
  const designState = design(sessionData);
  const el = (designState.elementContext ??= []);
  if (!el.some((elementRef) => elementRef.screenId === screenId && elementRef.name === name)) {
    el.push({ screenId, name, kind, instance: instance || '', tone: toneFor(screenId, locale) });
    designState.trayOpen = true;
  }
  return stageContext(sessionData, {}, prefs, translate, locale);
};

export const unpinElement = (sessionData, screenId, name, prefs, translate, locale) => {
  const designState = design(sessionData);
  designState.elementContext = (designState.elementContext ?? []).filter((elementRef) => !(elementRef.screenId === screenId && elementRef.name === name));
  return stageContext(sessionData, {}, prefs, translate, locale);
};

// Undo / redo walk the two session stacks. Popping an entry, applying its
// reverse, and re-pushing onto the opposite stack is the whole mechanic — the
// entry object travels with the user as they step back and forth. Async:
// replaying a flow entry rewrites the project's flows.json. The stack param
// is a URL segment: anything but canvas|chat is a no-op re-render (it must
// not mint junk stack keys in the session).
const STACKS = ['canvas', 'chat'];
export const undo = async (sessionData, stack, prefs = {}, translate = (key) => key, locale = 'en') => {
  const designState = design(sessionData);
  if (!STACKS.includes(stack)) return stageContext(sessionData, {}, prefs, translate, locale);
  (designState.undoStacks ??= {}); (designState.redoStacks ??= {});
  const entry = (designState.undoStacks[stack] ??= []).pop();
  if (entry) {
    await applyEntry(designState, entry, 'undo');
    (designState.redoStacks[stack] ??= []).push(entry);
  }
  return stageContext(sessionData, {}, prefs, translate, locale);
};

export const redo = async (sessionData, stack, prefs = {}, translate = (key) => key, locale = 'en') => {
  const designState = design(sessionData);
  if (!STACKS.includes(stack)) return stageContext(sessionData, {}, prefs, translate, locale);
  (designState.undoStacks ??= {}); (designState.redoStacks ??= {});
  const entry = (designState.redoStacks[stack] ??= []).pop();
  if (entry) {
    await applyEntry(designState, entry, 'redo');
    (designState.undoStacks[stack] ??= []).push(entry);
  }
  return stageContext(sessionData, {}, prefs, translate, locale);
};

// The single composer path (chat-Centric Layout: no inputs outside the chat).
// 'approve' signs the manifest; any other text refines the pinned screens and
// may mint one checkpoint per pinned screen.
export const sendChat = (sessionData, text, prefs = {}, pinId = null, translate = (key) => key, locale = 'en') => {
  const activeLocale = locale;
  const designState = design(sessionData);
  if (pinId) pin(designState, pinId, activeLocale);
  const thread = (designState.designThread ??= []);

  // draftSent marks the ONE render that follows a send. The composer textarea
  // is hx-preserve'd so an unrelated swap cannot discard a half-typed message;
  // preserved unconditionally it would also survive the send, leaving the text
  // the user just sent sitting in the box ready to be sent twice. Every exit
  // from this function consumes the text, so every exit clears the flag's
  // absence.
  if (text === 'approve') {
    return { ...approveManifest(sessionData, prefs, translate, activeLocale), draftSent: true };
  }

  const threadLenBefore = thread.length;
  thread.push({ at: 'now', from: 'user', text });
  const ids = contextIds(designState, activeLocale);
  if (!ids.length) {
    thread.push({ at: 'now', from: 'agent', text: repo.noContext(activeLocale).text, textPlain: repo.noContext(activeLocale).textPlain });
    pushUndo(designState, 'chat', { type: 'chat', threadLenBefore, checkpointIds: [] });
    return { ...stageContext(sessionData, {}, prefs, translate, activeLocale), draftSent: true };
  }

  const first = repo.screen(ids[0], activeLocale);
  const scope = { label: ctxLabel(designState, activeLocale, translate), kit: first.kit, id: ids[0], summary: '' };
  const lower = text.toLowerCase();
  const found = repo.chatReplies(activeLocale).find((replyRule) => replyRule.match.some((key) => lower.includes(key)));
  const reply = fillReply(found ?? repo.chatFallback(activeLocale), scope);

  // Each message checkpoints the in-context screens only (story map → Chat).
  let cps = [];
  if (reply.checkpoint) {
    cps = ids.map((screenId) => {
      const list = (designState.chatCheckpoints ??= {})[screenId] ??= [];
      const count = (repo.checkpoints(activeLocale)[screenId] ?? []).length + list.length + 1;
      const cpId = `cp-${count}`;
      list.push({
        id: cpId, n: count, at: 'now',
        summary: reply.checkpoint,
        summaryPlain: reply.checkpointPlain ?? reply.checkpoint,
        before: reply.before, after: reply.after,
      });
      return { screen: screenId, cp: cpId };
    });
  }
  thread.push({ at: 'now', from: 'agent', text: reply.text, textBalanced: reply.textBalanced, textPlain: reply.textPlain, link: reply.link, cps });
  pushUndo(designState, 'chat', { type: 'chat', threadLenBefore, checkpointIds: cps });
  return { ...stageContext(sessionData, {}, prefs, translate, activeLocale), draftSent: true };
};

// One-tap revert: the checkpoint stays rendered as history, flagged reverted,
// and the act is logged into the thread — the thread is the design's history.
export const revertCheckpoint = (sessionData, screenId, cpId, prefs = {}, translate = (key) => key, locale = 'en') => {
  const designState = design(sessionData);
  const cp = allCheckpoints(designState, screenId, locale).find((checkpoint) => checkpoint.id === cpId);
  if (cp && !(designState.reverted ??= []).includes(cpId)) {
    designState.reverted.push(cpId);
    (designState.designThread ??= []).push({ at: 'now', from: 'agent', kind: 'event', text: translate('design.revertEvent', { screen: screenId, cp: cpId, summary: cp.summary }) });
  }
  return stageContext(sessionData, {}, prefs, translate, locale);
};

// ---------- freeze & trace surface ----------

export const freezeContext = (sessionData = {}, prefs = {}, translate = (key) => key, locale = 'en', fileArg) => {
  const activeLocale = locale;
  // composerStrip: freeze renders a composer but NO design viewer, so the
  // filmstrip stays in its tray (every /design canvas surface docks it under
  // the viewer's mini panel instead).
  const stage = stageContext(sessionData, { line: 'freeze', base: '/design/freeze', fileBase: '/design/freeze', file: fileArg, noProto: true, composerStrip: true }, prefs, translate, activeLocale);
  const lv = stage.jargonLevel;
  const designState = design(sessionData);
  const ap = repo.approval(activeLocale);
  const approved = designState.approved ?? ap.state === 'approved';
  const manifest = { ...repo.manifest(activeLocale), structure: jargon.pick(repo.manifest(activeLocale), 'structure', lv) };
  const rechecks = designState.driftRechecks ?? 0;
  return {
    ...stage,
    // Element chips and the chat undo/redo pair stay off the freeze composer:
    // their hrefs live under /design/chat + /design/undo and answer with the
    // prototype stage markup — fine on /design surfaces, a wrong-surface swap
    // here. Re-enable once those hrefs are base-scoped like the filmstrip's.
    elements: null,
    undoRedo: null,
    stageEyebrow: translate('design.freeze.eyebrow'),
    composerAction: '/design/freeze/messages',
    suggestions: [{ value: 'approve', label: ap.chip }, ...refineSuggestions(translate)],
    placeholder: approved ? translate('composer.placeholder.freeze') : translate('composer.placeholder.freezeApprove'),
    manifest,
    approval: {
      approved,
      lede: jargon.pick(ap, 'lede', lv),
      note: jargon.pick(ap, approved ? 'approvedNote' : 'pendingNote', lv),
    },
    trace: repo.trace(activeLocale).map((entry) => ({ ...entry, text: jargon.pick(entry, 'text', lv) })),
    traceability: repo.traceability(activeLocale),
    drift: {
      ...repo.drift(activeLocale),
      history: repo.drift(activeLocale).history.map((entry) => ({ ...entry, text: jargon.pick(entry, 'text', lv) })),
    },
    rechecks,
    toast: rechecks ? translate('drift.recheckToast', { n: rechecks + 1, matched: repo.drift(activeLocale).matched }) : null,
  };
};

// The human gate: approving the frozen manifest unlocks the Build stage.
// Idempotent — the act and the confirmation both land in the design thread.
export const approveManifest = (sessionData, prefs = {}, translate = (key) => key, locale = 'en') => {
  const designState = design(sessionData);
  const thread = (designState.designThread ??= []);
  thread.push({ at: 'now', from: 'user', text: repo.approval(locale).chip });
  designState.approved = true;
  thread.push({ at: 'now', from: 'agent', text: repo.approval(locale).confirm, textPlain: repo.approval(locale).confirmPlain });
  return freezeContext(sessionData, prefs, translate, locale);
};

export const recheckDrift = (sessionData, prefs = {}, translate = (key) => key, locale = 'en') => {
  const designState = design(sessionData);
  designState.driftRechecks = (designState.driftRechecks ?? 0) + 1;
  return freezeContext(sessionData, prefs, translate, locale);
};

