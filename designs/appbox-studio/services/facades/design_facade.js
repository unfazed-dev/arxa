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

// Panel width steps, per side — the shell's own persisted panel sizing.
export const PANEL_SIZES = ['s', 'm', 'l'];
const panelSizeFor = (d, side) => (PANEL_SIZES.includes(d.panelSize?.[side]) ? d.panelSize[side] : 's');

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
const rewire = (flow, order, memory) => {
  const edges = flow.edges ?? [];
  const byPair = new Map(edges.map((e) => [`${e.from}→${e.to}`, e]));
  const outByFrom = new Map(edges.map((e) => [e.from, e]));
  flow.edges = order.slice(0, -1).map((from, i) => {
    const kept = byPair.get(`${from}→${order[i + 1]}`);
    if (kept) return kept;
    const prev = outByFrom.get(from) ?? memory?.[from];
    return { from, to: order[i + 1], trigger: prev?.trigger ?? 'continue', action: prev?.action ?? 'push' };
  });
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
    ? [{ from: incoming.from, to: outgoing.to, trigger: incoming.trigger, action: incoming.action ?? 'push' }]
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
      if (dir === 'undo') excise(flow, entry.screenId); else appendTo(flow, entry.screenId);
    } else if (dir === 'undo') restore(flow, entry);
    else excise(flow, entry.screenId);
    await proj.writeFlows(flows);
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

// ---------- the shared design viewer (ui/common/design_viewer.html) ----------
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
  const live = ordered.some((s) => s.id === v.live) ? v.live : null;

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
      // re-clicked; live has an explicit on-tile close).
      inspecting: s.id === inspect,
      live: s.id === live,
      inspectHref: withParams({ inspect: s.id === inspect ? null : s.id }),
      liveHref: withParams({ live: s.id }),
      liveCloseHref: withParams({ live: null }),
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
      return {
        id: f.id, name: f.name,
        tiles: chainIds
          .map((id, i) => (tileById[id] ? { ...tileById[id], conn: i < chain.length ? chain[i].trigger : null } : null))
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
    inspect, live,
    screens, flows, bg,
    mode, proto, vp,
    // Proto-mode screen picks for the composer tray's filmstrip (the tray
    // lives outside #design-viewer, so the viewer hands the hrefs over).
    protoPicks: mode === 'proto' ? Object.fromEntries(screens.map((s) => [s.id, withParams({ screen: s.id })])) : null,
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
  const activityView = ['screens', 'artifacts', 'files'].includes(d.activityView) ? d.activityView : 'screens';
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
    panelSize: panelSizeFor(d, 'left'),
    panelSizeHref: '/design/panel/size/left/',
    panelSizePx: d.panelSizePx?.left ?? null,
    activityViews: [
      { id: 'screens', icon: 'layout-grid' },
      { id: 'artifacts', icon: 'package' },
      { id: 'files', icon: 'folder' },
    ].map((v) => ({ ...v, label: t('activityView.' + v.id), href: `/design/panel/${v.id}`, active: v.id === activityView })),
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
    // The tray's filmstrip: every screen as a thumb (see filmstripFor). The
    // tray head summarizes the PINNED subset ("first +N"); null when the
    // context is empty — the filmstrip still renders, nothing dimmed.
    filmstrip: filmstripFor(d, base, L, viewer, opts.noProto),
    trayContext: ids.length ? { first: ids[0], extra: ids.length - 1 } : null,
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

// Panel width grip: cycle persisted per side (the shell's own sizing state).
export const setPanelSize = (sessionData, side, size, prefs = {}, t = (k) => k, locale = 'en') => {
  if (['left', 'right'].includes(side) && PANEL_SIZES.includes(size)) {
    (design(sessionData).panelSize ??= {})[side] = size;
  }
  return stageContext(sessionData, {}, prefs, t, locale);
};

// Panel drag handle: px width persisted per side, clamped to a sane band.
export const setPanelSizePx = (sessionData, side, width, prefs = {}, t = (k) => k, locale = 'en') => {
  const d = design(sessionData);
  (d.panelSizePx ??= {})[side] = Math.max(200, Math.min(600, Number(width) || 280));
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
      const triggers = Object.fromEntries((flow.edges ?? []).map((e) => [e.from, { trigger: e.trigger, action: e.action ?? 'push' }]));
      rewire(flow, after, triggers);
      await proj.writeFlows(flows);
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
      await proj.writeFlows(flows);
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
    const removed = flow ? excise(flow, screenId) : null;
    if (removed) {
      await proj.writeFlows(flows);
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

  if (text === 'approve') return approveManifest(sessionData, prefs, t, L);

  const threadLenBefore = thread.length;
  thread.push({ at: 'now', from: 'user', text });
  const ids = contextIds(d, L);
  if (!ids.length) {
    thread.push({ at: 'now', from: 'agent', text: repo.noContext(L).text, textPlain: repo.noContext(L).textPlain });
    pushUndo(d, 'chat', { type: 'chat', threadLenBefore, checkpointIds: [] });
    return stageContext(sessionData, {}, prefs, t, L);
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
  return stageContext(sessionData, {}, prefs, t, L);
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
  const stage = stageContext(sessionData, { line: 'freeze', base: '/design/freeze', fileBase: '/design/freeze', file: fileArg, noProto: true }, prefs, t, L);
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
