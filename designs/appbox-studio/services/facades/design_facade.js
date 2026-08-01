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

// The context filmstrip over the composer: one live thumb per pinned screen.
// base scopes the remove route to the surface being rendered (/design/chat or
// /design/freeze) so the × swaps THAT surface's stage, never another's.
const stripFor = (d, base, L) =>
  contextIds(d, L).map((id) => ({
    id,
    label: repo.screen(id, L).label,
    tone: toneFor(id, L),
    src: `/build/screens/${id}?vp=mobile`,
    removeHref: `${base}/context/${id}?state=off`,
  }));

const ctxLabel = (d, L, t) => contextIds(d, L).map((id) => repo.screen(id, L).label).join(' + ') || t('design.ctxFallback');

// ---------- undo / redo (two session stacks: canvas, chat) ----------
// Each entry carries enough to reverse itself in both directions, so the same
// object simply moves between the undo and redo stacks as the user steps back
// and forth. Canvas stack: artboard moves + screen pin/unpin. Chat stack is
// wired for design-change checkpoints (contract §6); the reverse for a move is
// "restore the previous position" (or auto-grid null).
const pushUndo = (d, stack, entry) => {
  (d.undoStacks ??= {}); (d.redoStacks ??= {});
  (d.undoStacks[stack] ??= []).push(entry);
  d.redoStacks[stack] = [];
};
const pushCanvasUndo = (d, entry) => pushUndo(d, 'canvas', entry);

const applyEntry = (d, entry, dir) => {
  if (entry.type === 'move') {
    const pos = dir === 'undo' ? entry.from : entry.to;
    if (pos) (d.artboardLayout ??= {})[entry.screenId] = { ...pos };
    else delete d.artboardLayout?.[entry.screenId];
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
// Two lenses over the screen registry, switched by the `mode` viewer param:
// 'flow' — every screen as a draggable tile grouped by shell; 'proto' — the
// wired-app preview, one screen live at a real rung size inside device
// chrome (screen/vp/os params). The mini panel (screens/controller/actions)
// + undo/redo + element chips are always produced; in proto mode the
// Screens panel picks the active screen instead of toggling chat context.
const RUNG_VP = { 390: 'mobile', 744: 'tablet', 1280: 'desktop' };

function viewerFor(d, L, t) {
  const v = d.viewer ?? {};
  const ids = contextIds(d, L);
  const base = '/design/viewer';
  const contextBase = '/design/chat/context/';

  const screens = repo.screens(L).map((s) => {
    const viewports = s.rungs.map((r) => ({ vp: RUNG_VP[r.width] ?? 'mobile', width: r.width, rung: r.rung, note: r.note, shot: r.shot }));
    return {
      id: s.id, label: s.label, state: s.state,
      inContext: ids.includes(s.id),
      dim: ids.length > 0 && !ids.includes(s.id),
      tone: toneFor(s.id, L),
      chips: [{ text: `${s.kit}%`, title: t('design.kitChipTitle', { kit: s.kit, id: s.id }) }],
      viewports,
      // shell drives flow tile grouping; the fixture has no shell field, so
      // derive it from the screen id prefix (e.g. "design.chat" → "design").
      shell: s.shell ?? s.id.split('.')[0],
      layout: d.artboardLayout?.[s.id] ?? null,
      primaryWidth: viewports[0]?.width ?? 390,
    };
  });

  const bg = ['canvas', 'warm', 'slate'].includes(v.bg) ? v.bg : 'canvas';
  const panel = ['screens', 'controller', 'actions'].includes(v.panel) ? v.panel : 'screens';
  const inspect = v.inspect === '1';
  const mode = v.mode === 'proto' ? 'proto' : 'flow';
  const active = screens.some((s) => s.id === v.screen) ? v.screen : screens[0]?.id;
  const vp = ['mobile', 'tablet', 'desktop'].includes(v.vp) ? v.vp : 'mobile';
  const os = ['ios', 'android'].includes(v.os) ? v.os : 'ios';

  // Viewer href builder: current viewer state merged with overrides, empties
  // dropped — so a controller toggle href only flips the one param it names.
  // Defaults (flow mode, mobile rung, ios chrome) stay out of the URL.
  const withParams = (over) => {
    const merged = {
      bg, inspect: inspect ? '1' : null,
      mode: mode === 'flow' ? null : mode,
      screen: active,
      vp: vp === 'mobile' ? null : vp,
      os: os === 'ios' ? null : os,
      ...over,
    };
    const qs = Object.entries(merged).filter(([, val]) => val != null).map(([k, val]) => `${k}=${val}`).join('&');
    return qs ? `${base}?${qs}` : base;
  };

  // The wired-app lens: device chrome around the live render at the real
  // rung size. Only produced in proto mode.
  const proto = mode === 'proto' ? {
    active, vp, os,
    src: `/build/screens/${active}?vp=${vp}&embed=1`,
    rungs: ['mobile', 'tablet', 'desktop'].map((key) => ({ key, active: key === vp, href: withParams({ vp: key === 'mobile' ? null : key }) })),
    oss: vp === 'mobile'
      ? ['ios', 'android'].map((key) => ({ key, active: key === os, href: withParams({ os: key === 'ios' ? null : key }) }))
      : null,
  } : null;

  const miniPanel = {
    activePanel: panel,
    screens: screens.map((s) => ({
      id: s.id, label: s.label, tone: s.tone, inContext: s.inContext, dim: s.dim,
      src: `/build/screens/${s.id}?vp=mobile&embed=1`,
      // flow: a thumb toggles chat context; proto: it picks the active screen.
      ...(mode === 'proto'
        ? { protoHref: withParams({ screen: s.id }), active: s.id === active }
        : { contextHref: `${contextBase}${s.id}?state=toggle` }),
    })),
    controller: {
      inspectOn: inspect,
      inspectHref: withParams({ inspect: inspect ? null : '1' }),
      modes: ['flow', 'proto'].map((key) => ({ key, active: key === mode, href: withParams({ mode: key === 'flow' ? null : key }) })),
      bgs: ['canvas', 'warm', 'slate'].map((value) => ({ value, active: value === bg, href: withParams({ bg: value }) })),
      undo: { can: (d.undoStacks?.canvas?.length ?? 0) > 0, href: '/design/undo/canvas' },
      redo: { can: (d.redoStacks?.canvas?.length ?? 0) > 0, href: '/design/redo/canvas' },
    },
    actions: {
      selectedCount: 0,            // updated client-side by drag.js marquee
      bulkPinHref: '/design/chat/context/bulk',
      simHref: null,               // sim toggle (placeholder)
    },
  };

  return {
    inspect,
    screens, bg,
    mode, proto,
    strip: true,
    base, stubBase: '/build/screens/', contextBase,
    miniPanel,
    undoRedo: {
      canvas: { canUndo: (d.undoStacks?.canvas?.length ?? 0) > 0, canRedo: (d.redoStacks?.canvas?.length ?? 0) > 0 },
      chat:   { canUndo: (d.undoStacks?.chat?.length ?? 0) > 0, canRedo: (d.redoStacks?.chat?.length ?? 0) > 0 },
    },
    elements: (d.elementContext ?? []).map((e) => ({ ...e, removeHref: `${contextBase}element/remove?screen=${encodeURIComponent(e.screenId)}&name=${encodeURIComponent(e.name)}` })),
  };
}

// Viewer toolbar act: the state keys (bg/inspect/mode/screen/vp/os) are
// AUTHORITATIVE — every control href echoes the whole viewer state
// (withParams / the panel-tab q echo), with defaults elided from the URL, so
// an absent key means "back to default", never "keep". Merging would strand
// every non-default value (a canvas chip sends no mode=, so a merged
// mode:'proto' could never flip back). panel is the one sticky key: the
// controller chips don't repeat it, so it survives a mode/bg/vp toggle.
export const setViewer = (sessionData, query, prefs = {}, t = (k) => k, locale = 'en') => {
  const d = design(sessionData);
  const next = {};
  for (const [k, v] of Object.entries(query)) if (v != null) next[k] = v;
  const panel = next.panel ?? d.viewer?.panel;
  d.viewer = panel ? { ...next, panel } : next;
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
    strip: stripFor(d, base, L),
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

// Artboard tile drag: persist {x, y} on drop and record a reversible move on
// the canvas undo stack (prev lets undo restore the prior position / auto-grid).
export const setArtboardLayout = (sessionData, screenId, x, y, prefs, t, locale) => {
  const d = design(sessionData);
  const prev = d.artboardLayout?.[screenId] ? { ...d.artboardLayout[screenId] } : null;
  (d.artboardLayout ??= {})[screenId] = { x, y };
  pushCanvasUndo(d, { type: 'move', screenId, from: prev, to: { x, y } });
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
// entry object travels with the user as they step back and forth. The stack
// param is a URL segment: anything but canvas|chat is a no-op re-render (it
// must not mint junk stack keys in the session).
const STACKS = ['canvas', 'chat'];
export const undo = (sessionData, stack, prefs = {}, t = (k) => k, locale = 'en') => {
  const d = design(sessionData);
  if (!STACKS.includes(stack)) return stageContext(sessionData, {}, prefs, t, locale);
  (d.undoStacks ??= {}); (d.redoStacks ??= {});
  const entry = (d.undoStacks[stack] ??= []).pop();
  if (entry) {
    applyEntry(d, entry, 'undo');
    (d.redoStacks[stack] ??= []).push(entry);
  }
  return stageContext(sessionData, {}, prefs, t, locale);
};

export const redo = (sessionData, stack, prefs = {}, t = (k) => k, locale = 'en') => {
  const d = design(sessionData);
  if (!STACKS.includes(stack)) return stageContext(sessionData, {}, prefs, t, locale);
  (d.undoStacks ??= {}); (d.redoStacks ??= {});
  const entry = (d.redoStacks[stack] ??= []).pop();
  if (entry) {
    applyEntry(d, entry, 'redo');
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
  const stage = stageContext(sessionData, { line: 'freeze', base: '/design/freeze', fileBase: '/design/freeze', file: fileArg }, prefs, t, L);
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
    // here. Re-enable once those hrefs are base-scoped like the strip's.
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
