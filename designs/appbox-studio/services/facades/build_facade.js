// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
// BuildFacade — composes the run fixture with session-scoped state (gate
// decisions, chat messages, stage/run controls, the open main-panel artifact,
// context chips, the activity panel's active view) into exactly what
// loop_viewmodel needs. Every leveled fixture string passes through the
// jargon facade at the reader's level; static view copy comes in as the
// runtime translator `translate` (helpers.translate(context) — level and locale already bound, l10n/
// app_*.arb). The locale comes from the request (helpers.locale(context)) and picks the
// per-locale fixture, en fallback.
//
// Session-narrated agent messages store a translation KEY + vars (textKey /
// textVars), not a rendered string — the reader's level and locale are
// applied when the thread is composed, so a later jargon/locale switch still
// re-renders them correctly.
//
// The run thread IS the chat: narrative cards render in the composer
// panel, evidence/charts/gates open as main-panel artifacts (chat docks
// right), and gate notes are chat replies carrying a gate context chip —
// there is no second input path.
import * as repo from '../repositories/build_repository.js';
import * as proj from '../repositories/project_repository.js';
import * as jargon from './jargon.js';
import * as agent from './agent_menus.js';
import * as fv from './file_views.js';

// All build-tab session state lives behind one namespace so it never
// collides with the intake/design/app surfaces sharing the session — each
// shell manages its own data (design: sessionData.design, intake: .intake).
const buildSlice = (sd) => (sd.build ??= {});

// Thread filter vocabulary: 'all' shows everything; anything else matches
// the card type derived from the message's artifact ref ('note' = no
// artifact).
export const THREAD_FILTERS = ['all', 'stage', 'gate', 'findings', 'evidence', 'note'];

// Activity panel view registry: run controls, thread filter, artifact
// index, and the seeded commits/files views (real git wiring is a later
// stage — the views say so). Labels render via translate('activityView.<id>').
export const ACTIVITY_VIEWS = [
  { id: 'run', icon: 'play', label: 'run' },
  { id: 'thread', icon: 'messages-square', label: 'thread' },
  { id: 'artifacts', icon: 'package', label: 'artifacts' },
  { id: 'commits', icon: 'git-branch', label: 'commits' },
  { id: 'files', icon: 'folder', label: 'files' },
];
const ACTIVITY_VIEW_IDS = ACTIVITY_VIEWS.map((view) => view.id);

// Panel width steps, per panel — the build shell's own persisted sizing.
const PANEL_SIZES = ['s', 'm', 'l'];
// Panels whose width is server state. Only the activity panel persists one:
// the composer's width is client-only and rides morph (see drag.js data-persist).
const PERSISTABLE_PANELS = ['activity'];
const panelSizeFor = (sd, panel) => (PANEL_SIZES.includes(buildSlice(sd).panelSize?.[panel]) ? buildSlice(sd).panelSize[panel] : 's');

// Where each human gate sits on the timeline: it docks after this stage.
const GATE_AFTER = { 'design.approval': 'design', 'build.acceptance': 'review', 'ship.confirm': 'deploy' };

const pushUser = (sessionData, text) => {
  const extra = (buildSlice(sessionData).extraMessages ??= []);
  const seq = (buildSlice(sessionData).msgSeq = (buildSlice(sessionData).msgSeq ?? 0) + 1);
  extra.push({ id: `u-${seq}`, at: 'now', from: 'user', text });
  return seq;
};

const narrate = (sessionData, message) => {
  const extra = (buildSlice(sessionData).extraMessages ??= []);
  const seq = (buildSlice(sessionData).msgSeq = (buildSlice(sessionData).msgSeq ?? 0) + 1);
  extra.push({ id: `a-${seq}`, at: 'now', from: 'agent', ...message });
};

// Human-gate decisions are the human's act; a POST lands them in the session
// and the facade overlays them onto the fixture's lifecycle.
function gatesWithDecisions(sessionData, activeLocale, translate) {
  const decisions = buildSlice(sessionData).gateDecisions ?? {};
  return repo.humanGates(activeLocale).map((gate) => {
    const decision = decisions[gate.id];
    if (!decision) return gate;
    return {
      ...gate,
      state: decision.decision,
      provenance: {
        by: 'Evan',
        shell: translate('prov.shell'),
        device: translate('prov.machine'),
        method: translate('prov.method'),
        at: translate('prov.justNow'),
        hash: decision.hash,
      },
      note: decision.decision === 'rejected' ? decision.note : null,
    };
  });
}

function stagesWithDecisions(gates, lv, sessionData, activeLocale, translate) {
  const acceptance = gates.find((gate) => gate.id === 'build.acceptance');
  return repo.stages(activeLocale).map((stage) => {
    let out = {
      ...stage,
      summary: jargon.pick(stage, 'summary', lv),
      detail: jargon.pick(stage, 'detail', lv),
      attempts: stage.attempts?.map((attempt) => ({ ...attempt, note: jargon.pick(attempt, 'note', lv) })),
    };
    if (stage.id === 'deploy' && acceptance.state === 'approved') {
      out = {
        ...out,
        state: 'active',
        summary: translate('build.deployUnlocked'),
      };
    }
    if (stage.id === 'deploy' && acceptance.state === 'rejected') {
      out = {
        ...out,
        state: 'held',
        summary: translate('build.deployHeld'),
      };
    }
    // Human stage controls (pause/cancel from the run view) win last.
    const control = buildSlice(sessionData).stageStates?.[stage.id];
    if (control) out = { ...out, state: control.state, summary: translate(control.summaryKey) };
    return out;
  });
}

function runWithState(sessionData, gates, activeLocale, translate) {
  const run = { ...repo.run(activeLocale) };
  const acceptance = gates.find((gate) => gate.id === 'build.acceptance');
  run.pausedByYou = Boolean(buildSlice(sessionData).runControl?.paused);
  if (run.pausedByYou) {
    run.state = 'paused';
    run.stateLabel = translate('build.state.pausedByYou');
  } else if (acceptance.state === 'approved') {
    run.state = 'running';
    run.stateLabel = translate('build.state.running');
  } else if (acceptance.state === 'rejected') {
    run.state = 'held';
    run.stateLabel = translate('build.state.held');
  }
  return run;
}

// The thread card: type (color-coded in the view), lifecycle state, and one
// detail line — resolved from the artifact the message points at.
function cardFor(ref, parts, translate) {
  if (!ref) return { type: 'note' };
  const [kind, id] = ref.split('/');
  switch (kind) {
    case 'stage': {
      const stage = parts.stages.find((candidate) => candidate.id === id);
      if (!stage) return { type: 'stage', ref };
      const when = stage.duration && stage.duration !== '—' ? stage.duration : translate('status.name.queued');
      return { type: 'stage', state: stage.state, detail: translate('build.stageEyebrow', { n: stage.n, total: parts.stages.length, when }), ref };
    }
    case 'gate': {
      const gate = parts.gates.find((candidate) => candidate.id === id);
      if (!gate) return { type: 'gate', ref };
      const detail = gate.state === 'approved' ? translate('build.gateDetail.signed', { at: gate.provenance?.at ?? '' })
        : gate.state === 'rejected' ? translate('build.gateDetail.rejected')
        : gate.state === 'pending' ? translate('build.gateDetail.pending')
        : translate('build.gateDetail.unreachable');
      return { type: 'gate', state: gate.state, gateId: gate.id, detail: `${translate('build.humanGate')} · ${detail}`, ref };
    }
    case 'findings': {
      const list = parts.findings[id] ?? [];
      return { type: 'findings', state: 'red', detail: translate('build.findingsDetail', { count: list.length }), ref };
    }
    case 'evidence': {
      const pass = parts.evidence.filter((evidenceEntry) => evidenceEntry.state === 'pass').length;
      const watch = parts.evidence.length - pass;
      return { type: 'evidence', state: 'pass', detail: translate('build.evidenceDetail', { count: parts.evidence.length, pass, watch }), ref };
    }
    case 'chart':
      return { type: 'chart', detail: translate('build.chartDetail'), ref };
    case 'log':
      return { type: 'log', detail: translate('build.logDetail'), ref };
    default:
      return { type: 'note', ref };
  }
}

function messagesWithSession(sessionData, activeArtifact, lv, parts, filter, activeLocale, translate) {
  const extra = buildSlice(sessionData).extraMessages ?? [];
  const all = [...repo.narrative(activeLocale), ...extra].map((message) => ({
    from: 'agent',
    tone: null,
    artifact: null,
    ...message,
    at: message.at === 'now' ? translate('time.now') : message.at,
    text: message.textKey ? translate(message.textKey, message.textVars) : message.from === 'user' ? message.text : jargon.pick(message, 'text', lv),
    active: message.artifact === activeArtifact,
    card: message.from === 'user' ? { type: 'you' } : cardFor(message.artifact, parts, translate),
  }));
  if (filter === 'all') return all;
  return all.filter((message) => message.card.type === filter);
}

function findingsWithLevel(lv, activeLocale) {
  const byGate = repo.findingsByGate(activeLocale);
  return Object.fromEntries(
    Object.entries(byGate).map(([gate, list]) => [
      gate,
      list.map((finding) => ({
        ...finding,
        expected: jargon.pick(finding, 'expected', lv),
        actual: jargon.pick(finding, 'actual', lv),
        note: jargon.pick(finding, 'note', lv),
      })),
    ]),
  );
}

function evidenceWithLevel(lv, activeLocale, translate = (key) => key) {
  return repo.evidence(activeLocale).map((evidenceEntry) => ({
    ...evidenceEntry,
    chips: jargon.probeChips(evidenceEntry.probe, lv, translate),
    band: jargon.band(jargon.scoreDeltaE(evidenceEntry.probe.deltaE), translate),
  }));
}

// ---------- design viewer (evidence canvas) ----------
// The evidence canvas shows the designed screens as read-only artboards
// (views-lens tiles only, static canvas — no pins, no flows, no per-tile
// tools). Tile heights come from the viewports the design actually authored
// (seed truth).
// B(sessionData).viewer = { bg }.
export const VIEWPORT_WIDTHS = { mobile: 390, tablet: 744, desktop: 1280 };
export const VIEWPORT_HEIGHTS = { mobile: 844, tablet: 1133, desktop: 800 };
export const VIEWER_BGS = ['canvas', 'warm', 'slate'];

// The evidence canvas renders every surface through the stub renderer —
// the app-under-design (Portalo) is design CONTENT, never a live route.
function viewerFor(sessionData, evidence) {
  const viewerState = buildSlice(sessionData).viewer ?? {};
  const screens = evidence.map((evidenceEntry) => {
    const viewports = evidenceEntry.viewports ?? ['mobile'];
    const v0 = viewports[0];
    return {
      id: evidenceEntry.surface, label: evidenceEntry.surface, state: evidenceEntry.state,
      chips: evidenceEntry.chips, viewports,
      primaryWidth: VIEWPORT_WIDTHS[v0] ?? 390,
      // static evidence canvas: no rung switching, tiles render at the first
      // authored rung (same contract field the design facade fills per vp).
      tile: { vp: v0, width: VIEWPORT_WIDTHS[v0] ?? 390, height: VIEWPORT_HEIGHTS[v0] ?? 844 },
    };
  });
  const bg = VIEWER_BGS.includes(viewerState.bg) ? viewerState.bg : 'canvas';
  const base = '/build/artifact/evidence/surfaces/viewer';

  // Viewer href builder: current viewer state merged with overrides, empties
  // dropped — same idiom as the design facade's.
  const withParams = (over) => {
    const merged = { bg, ...over };
    const qs = Object.entries(merged).filter(([, val]) => val != null).map(([key, val]) => `${key}=${val}`).join('&');
    return qs ? `${base}?${qs}` : base;
  };

  return {
    screens, bg, static: true,
    base,
    // Every tile iframes the stub renderer — see the comment above viewerFor.
    stubBase: '/build/screens/',
    // The viewer mounts its controls in the mini panel — a single controller
    // panel (the screens filmstrip is a design-composer concept; the evidence
    // canvas is static). Bar-right cluster: bg swatches only, no devices on a
    // static canvas. No history stacks here — the pair stays disabled
    // (can:false renders without the hx-post).
    miniPanel: {
      bar: {
        devices: null,
        bgs: VIEWER_BGS.map((value) => ({ value, active: value === bg, href: withParams({ bg: value }) })),
      },
      controller: {
        undo: { can: false, href: '/design/undo/canvas' },
        redo: { can: false, href: '/design/redo/canvas' },
      },
    },
  };
}

// The iframe document's context: an honest labelled stand-in for the designer
// artifact the daemon serves in the shipped app. When the CURRENT PROJECT
// ships a bespoke partial for the kind (design/surfaces/<kind>.html), the
// stub renders it with the project's flow context (tabs, next edge) — the
// prototype chrome is flow-driven (project_repository).
import { defaultSwatch } from '../theme_tokens.js';
import { defaultFont } from '../font_tokens.js';
export const screenStub = (surface, vp, prefs = {}, locale = 'en', opts = {}) => {
  const evidenceEntry = repo.evidence(locale).find((candidate) => candidate.surface === surface);
  // No evidence entry (design-content ids like portalo.*): every rung is
  // authored — the design canvas drives the viewport, not the evidence log.
  const authored = evidenceEntry?.viewports ?? ['mobile', 'tablet', 'desktop'];
  const viewport = authored.includes(vp) ? vp : authored[0];
  const kind = surface?.split('.')[1] ?? surface;
  return {
    surface, vp: viewport, width: VIEWPORT_WIDTHS[viewport],
    kind,
    // The viewer's app-theme override wins; otherwise the stub follows the
    // studio theme (= the viewer's "auto"). themeOverride is kept raw so the
    // stub's own nav links (pqs) re-propagate the OVERRIDE only — echoing the
    // resolved theme would pin "auto" to whatever the studio was at render.
    theme: (opts.theme === 'light' || opts.theme === 'dark') ? opts.theme : (prefs.theme ?? 'light'),
    themeOverride: (opts.theme === 'light' || opts.theme === 'dark') ? opts.theme : null,
    // the designed app's swatch — theme.json's default until per-screen
    // swatch switching arrives (the stub used to hardcode cyan).
    accent: opts.accent ?? defaultSwatch(),
    // the designed app's TYPEFACE — fonts.json's default, resolved exactly
    // like accent above and deliberately NOT from prefs.font. The studio's
    // font menu restyles the studio chrome; this stub is a picture of the
    // user's app, and letting the operator's menu choice leak in here would
    // silently re-typeset their design (and every screenshot taken of it).
    font: opts.font ?? defaultFont(),
    embed: opts.embed ?? false,
    inspect: opts.inspect ?? false,
    // still: freeze frame for canvas tiles — partials skip auto-advance
    // (meta refresh) so every screen in a chain stays itself on the canvas.
    still: opts.still ?? false,
    partial: proj.hasPartial(kind) ? `ui/project/${kind}.html` : null,
    tabs: proj.hasPartial(kind) ? proj.tabs() : [],
    // Scoped by the walked flow when there is one. A screen can sit in several
    // flows with different destinations (portalo.home -> checkout in
    // flow-browse-buy, -> account in flow-account); unscoped, nextEdge returns
    // whichever flow happens to be authored first, so the surface's own CTA
    // could point somewhere the walk does not go.
    next: proj.hasPartial(kind) ? proj.nextEdge(surface, opts.walkFlow ?? null) : null,
    // Flow walk island config — only present on the walked tile.
    walk: opts.walk ?? null,
    walkEl: opts.walkEl ?? '',
    walkTrig: opts.walkTrig ?? '',
  };
};

// Viewer toolbar act: bg is AUTHORITATIVE (every control href echoes it, the
// default elided — absent means "back to default", never "keep"). Same
// contract as the design facade's.
export const setViewer = (sessionData, query, prefs = {}, translate = (key) => key, locale = 'en') => {
  const next = {};
  for (const [key, value] of Object.entries(query)) if (value != null) next[key] = value;
  buildSlice(sessionData).viewer = next;
  return loopContext(sessionData, 'evidence/surfaces', prefs, translate, locale);
};

// The shell timeline: the whole line at a glance, current item highlighted.
function timeline({ stages, gates }) {
  const items = [];
  for (const stage of stages) {
    items.push({ kind: 'stage', id: stage.id, ref: `stage/${stage.id}`, label: stage.label, n: stage.n, state: stage.state });
    for (const gate of gates.filter((candidate) => GATE_AFTER[candidate.id] === stage.id)) {
      items.push({ kind: 'gate', id: gate.id, ref: `gate/${gate.id}`, label: gate.label, state: gate.state });
    }
  }
  const current = items.find((item) => item.kind === 'gate' && item.state === 'pending')
    ?? items.find((item) => item.state === 'active')
    ?? null;
  return { items, currentId: current ? current.ref : null };
}

// ---------- the per-canvas LLM context envelope ----------
// Local: the artifact's own rendered data + its direct links. Global: a thin
// fixed brief. The fixture replies below AND any real model consume this
// same typed envelope — swap the reply generator, keep the structure.
export const contextFor = (sessionData, ref, lv = 'balanced', translate = (key) => key, locale = 'en') => {
  const gates = gatesWithDecisions(sessionData, locale, translate);
  const stages = stagesWithDecisions(gates, lv, sessionData, locale, translate);
  const run = repo.run(locale);
  const brief = {
    run: run.number, project: run.project, state: run.state,
    policy: run.policy,
    timeline: timeline({ stages, gates }).items.map((item) => `${item.kind}:${item.id}=${item.state}`),
    jargon: lv,
  };
  const [kind, id] = (ref || '').split('/');
  let artifact = null;
  const linked = [];
  if (kind === 'stage') {
    artifact = stages.find((stage) => stage.id === id) ?? null;
    if (id === 'coverage') linked.push({ findings: findingsWithLevel(lv, locale).coverage ?? [] });
    if (id === 'deploy') linked.push({ gates: gates.filter((gate) => gate.id !== 'design.approval') });
    if (id === 'design') linked.push({ gate: gates.find((candidateGate) => candidateGate.id === 'design.approval') });
  } else if (kind === 'gate') {
    artifact = gates.find((gate) => gate.id === id) ?? null;
    if (id === 'build.acceptance') linked.push({ evidence: evidenceWithLevel(lv, locale, translate) }, { stage: stages.find((stage) => stage.id === 'deploy') });
    if (id === 'design.approval') linked.push({ stages: stages.filter((stage) => ['design', 'freeze'].includes(stage.id)) });
    if (id === 'ship.confirm') linked.push({ stage: stages.find((stage) => stage.id === 'deploy') });
  } else if (kind === 'findings') {
    artifact = { gate: id, list: findingsWithLevel(lv, locale)[id] ?? [] };
    linked.push({ stage: stages.find((stage) => stage.id === id) });
  } else if (kind === 'chart') {
    artifact = repo.chart(locale);
    linked.push({ stages: stages.map((stage) => ({ id: stage.id, duration: stage.duration, state: stage.state })) });
  } else if (kind === 'evidence') {
    artifact = evidenceWithLevel(lv, locale, translate);
    linked.push({ stage: stages.find((stage) => stage.id === 'freeze') });
  } else if (kind === 'log') {
    artifact = { note: 'the whole line, in order' };
  }
  return { artifact, linked, brief };
};

// The main panel renders ONE artifact at a time; ref is "kind/id". No ref
// (or an unknown one) means nothing is open — the chat sits centered.
function resolveArtifact(ref, { gates, stages, messages, findings, evidence }, activeLocale) {
  if (!ref) return null;
  const [kind, id] = ref.split('/');
  switch (kind) {
    case 'gate': {
      const gate = gates.find((candidateGate) => candidateGate.id === id);
      if (gate) return { kind, gate, ref };
      break;
    }
    case 'stage': {
      const stage = stages.find((candidateStage) => candidateStage.id === id);
      if (stage) return { kind, stage, stageCount: stages.length, ref };
      break;
    }
    case 'findings': {
      const list = findings[id];
      if (list) return { kind, gate: id, list, ref };
      break;
    }
    case 'chart':
      return { kind, chart: repo.chart(activeLocale), ref };
    case 'log':
      return { kind, messages, ref };
    case 'evidence':
      return { kind, evidence, ref };
  }
  return null;
}

// The pinned gate chip: live only while its gate is still decidable.
const noteGateFor = (sessionData, gates) => {
  const id = buildSlice(sessionData).gateChip;
  if (!id) return null;
  const gate = gates.find((candidate) => candidate.id === id);
  return gate && gate.state === 'pending' ? gate : null;
};

// Composer context chips for cp.frame: the pinned gate (a reject note is
// the next chat message). The open artifact needs no chip — the main panel
// is always visible, there is nothing to close.
const chipsFor = (noteGate, activeLocale, translate) => {
  if (!noteGate) return [];
  return [{
    id: `gate/${noteGate.id}`, label: translate('build.noteChip', { label: noteGate.label.toLowerCase() }),
    tone: 'gate', removeHref: `/build/chips/unpin?ref=gate/${noteGate.id}`,
  }];
};

// The artifacts activity view: everything openable, in pipeline order.
function artifactIndex({ gates, stages }, translate) {
  return [
    ...gates.map((gate) => ({ ref: `gate/${gate.id}`, label: gate.label, kind: 'gate', state: gate.state })),
    ...stages.map((stage) => ({ ref: `stage/${stage.id}`, label: stage.label, kind: 'stage', state: stage.state })),
    { ref: 'findings/coverage', label: translate('build.artifact.findings'), kind: 'findings', state: 'red' },
    { ref: 'evidence/surfaces', label: translate('build.artifact.evidence'), kind: 'evidence', state: 'pass' },
    { ref: 'chart/durations', label: translate('build.artifact.chart'), kind: 'chart', state: null },
    { ref: 'log/full', label: translate('build.artifact.log'), kind: 'log', state: null },
  ];
}

// The empty stage: this project has no build evidence yet. Same key set as
// the loaded context below (the surface's one contract, emptied) so every
// fragment macro renders blank instead of iterating undefined. noEvidence
// is the flag loop_view branches on; the project name comes from the
// project itself, since the run fixture that normally carries it is absent.
const emptyContext = (sessionData = {}, prefs = {}, translate = (key) => key) => {
  const name = proj.currentName();
  return {
    noEvidence: true,
    run: null,
    project: name ? { name } : null,
    composerAction: '/build/messages',
    modelMenu: agent.modelMenuFor(sessionData, '/build', translate),
    threading: false,
    stages: [],
    gates: [],
    counts: { findings: 0, gatesPending: 0, stagesGreen: 0 },
    messages: [],
    filter: 'all',
    timeline: { items: [], currentId: null },
    activeArtifact: null,
    artifact: null,
    fileView: null,
    panel: buildSlice(sessionData).panel ?? 'main',
    viewer: null,
    chips: [],
    noteGate: null,
    suggestions: [],
    placeholder: translate('composer.placeholder.build'),
    activityView: 'run',
    panelSize: panelSizeFor(sessionData, 'activity'),
    panelSizeHref: '/build/panel/size/activity/',
    activityViews: [],
    artifacts: [],
    commits: [],
    files: [],
    jargonLevel: jargon.level(prefs),
  };
};

// Emptiness is a facade question, not a viewmodel one — viewmodels import
// facades only, never repositories. Returns null when the project HAS
// evidence (render the real stage); otherwise the whole context the empty
// stage needs. Callers must check this before entering loopContext: that
// path dereferences the build.acceptance gate unguarded, so an empty gate
// list throws a TypeError straight to a 500.
export const emptyLoopContext = (locale = 'en', sessionData = {}, prefs = {}, translate = (key) => key) =>
  (repo.hasEvidence(locale) ? null : emptyContext(sessionData, prefs, translate));

export const loopContext = (sessionData = {}, ref = null, prefs = {}, translate = (key) => key, locale = 'en', fileArg, panelArg) => {
  const activeLocale = locale;
  const lv = jargon.level(prefs);
  // Nothing in appboxd writes build evidence yet, so every project reads
  // empty today. Answer before the pipeline shaping below, which assumes a
  // real run: runWithState dereferences the build.acceptance gate, and an
  // empty gate list would throw a TypeError straight to a 500. Every other
  // export funnels through here, so this one guard covers the whole surface.
  if (!repo.hasEvidence(activeLocale)) return emptyContext(sessionData, prefs, translate);
  // The open file (main panel): ?file=<path> opens, ?file=none closes; an
  // artifact open always clears it — the main panel shows one thing.
  if (fileArg === 'none') delete buildSlice(sessionData).currentFile;
  else if (fileArg) { buildSlice(sessionData).currentFile = fileArg; delete buildSlice(sessionData).currentArtifact; }
  const currentFile = buildSlice(sessionData).currentFile ?? null;
  // The panel bar (compact/medium): ?panel= picks the single visible content
  // panel and sticks; default main.
  if (['activity', 'main', 'composer'].includes(panelArg)) buildSlice(sessionData).panel = panelArg;
  const gates = gatesWithDecisions(sessionData, activeLocale, translate);
  const stages = stagesWithDecisions(gates, lv, sessionData, activeLocale, translate);
  const findings = findingsWithLevel(lv, activeLocale);
  const evidence = evidenceWithLevel(lv, activeLocale, translate);
  const parts = { gates, stages, findings, evidence };
  const activeArtifact = currentFile ? null : (ref ?? buildSlice(sessionData).currentArtifact ?? null);
  const filter = THREAD_FILTERS.includes(buildSlice(sessionData).threadFilter) ? buildSlice(sessionData).threadFilter : 'all';
  const messages = messagesWithSession(sessionData, activeArtifact, lv, parts, filter, activeLocale, translate);
  const artifact = resolveArtifact(activeArtifact, { ...parts, messages }, activeLocale);
  const openRef = artifact ? activeArtifact : null;
  const activityView = ACTIVITY_VIEW_IDS.includes(buildSlice(sessionData).activityView) ? buildSlice(sessionData).activityView : 'run';
  const noteGate = noteGateFor(sessionData, gates);
  return {
    run: runWithState(sessionData, gates, activeLocale, translate),
    project: { name: repo.run(activeLocale).project },
    composerAction: '/build/messages',
    modelMenu: agent.modelMenuFor(sessionData, '/build', translate),
    threading: messages.some((message) => message.from === 'user'),
    stages,
    gates,
    counts: repo.counts(activeLocale),
    messages,
    filter,
    timeline: timeline(parts),
    activeArtifact: openRef,
    artifact,
    fileView: currentFile ? fv.fileViewFor(currentFile, '/build?file=none') : null,
    panel: buildSlice(sessionData).panel ?? 'main',
    viewer: openRef === 'evidence/surfaces' ? viewerFor(sessionData, evidence) : null,
    chips: chipsFor(noteGate, activeLocale, translate),
    noteGate,
    suggestions: noteGate
      ? [{ value: translate('build.composer.rejectValue'), label: translate('build.composer.rejectLabel') }]
      : [translate('build.composer.sugCoverage'), translate('build.composer.sugDurations'), translate('build.composer.sugLog')],
    placeholder: noteGate ? translate('composer.placeholder.buildNote') : translate('composer.placeholder.build'),
    activityView,
    panelSize: panelSizeFor(sessionData, 'activity'),
    panelSizeHref: '/build/panel/size/activity/',
    activityViews: ACTIVITY_VIEWS.map((view) => ({ ...view, label: translate('activityView.' + view.id), href: `/build/panel?view=${view.id}`, active: view.id === activityView })),
    artifacts: artifactIndex(parts, translate),
    commits: repo.commits(activeLocale),
    files: repo.files(activeLocale).map((file) => ({ ...file, ...fv.fileLink(file.path, '/build') })),
    jargonLevel: lv,
  };
};

export const showArtifact = (sessionData, ref, prefs = {}, translate = (key) => key, locale = 'en') => {
  buildSlice(sessionData).currentArtifact = ref;
  delete buildSlice(sessionData).currentFile;
  return loopContext(sessionData, ref, prefs, translate, locale);
};

// A file row in the activity panel: open it in the main panel (the mode is
// the server's, from the extension).
export const openFile = (sessionData, path, prefs = {}, translate = (key) => key, locale = 'en') =>
  loopContext(sessionData, null, prefs, translate, locale, path ?? 'none');

// Composer chrome: pick the agent model (shared session state), then
// re-render the loop stage.
export const setModel = (sessionData, id, prefs = {}, translate = (key) => key, locale = 'en') => {
  agent.setModel(sessionData, id);
  return loopContext(sessionData, null, prefs, translate, locale);
};

// ---------- context chips (gate note pin / unpin) ----------

// "Reject with note" pins the gate as a context chip; the composer becomes
// the note input (single input path) and the next message is the rejection.
export const pinChip = (sessionData, ref, prefs = {}, translate = (key) => key, locale = 'en') => {
  const [kind, id] = (ref || '').split('/');
  if (kind === 'gate') {
    const gate = gatesWithDecisions(sessionData, locale, translate).find((candidate) => candidate.id === id);
    if (gate?.state === 'pending') buildSlice(sessionData).gateChip = id;
  }
  return loopContext(sessionData, null, prefs, translate, locale);
};

export const unpinChip = (sessionData, ref, prefs = {}, translate = (key) => key, locale = 'en') => {
  const [kind, id] = (ref || '').split('/');
  if (kind === 'gate' && buildSlice(sessionData).gateChip === id) delete buildSlice(sessionData).gateChip;
  return loopContext(sessionData, null, prefs, translate, locale);
};

// Activity panel view switching: run / thread / artifacts / commits / files.
export const setActivityView = (sessionData, view, prefs = {}, translate = (key) => key, locale = 'en') => {
  buildSlice(sessionData).activityView = ACTIVITY_VIEW_IDS.includes(view) ? view : 'run';
  return loopContext(sessionData, null, prefs, translate, locale);
};

// Thread filter (thread view): all | stage | gate | findings | evidence | note.
export const setThreadFilter = (sessionData, filter, prefs = {}, translate = (key) => key, locale = 'en') => {
  buildSlice(sessionData).threadFilter = THREAD_FILTERS.includes(filter) ? filter : 'all';
  return loopContext(sessionData, null, prefs, translate, locale);
};

// Panel width grip: cycle persisted per panel (the shell's own sizing state).
export const setPanelSize = (sessionData, panel, size, prefs = {}, translate = (key) => key, locale = 'en') => {
  if (PERSISTABLE_PANELS.includes(panel) && PANEL_SIZES.includes(size)) {
    (buildSlice(sessionData).panelSize ??= {})[panel] = size;
  }
  return loopContext(sessionData, null, prefs, translate, locale);
};

// The composer round-trip: append the user's message, then a simulated
// agent reply; the reply may pull a new artifact onto the canvas.
// With a gate chip pinned, the message IS the reject note + decision.
export const sendMessage = (sessionData, text, prefs = {}, translate = (key) => key, locale = 'en') => {
  const lv = jargon.level(prefs);

  if (buildSlice(sessionData).gateChip) {
    const gateId = buildSlice(sessionData).gateChip;
    delete buildSlice(sessionData).gateChip;
    const gate = gatesWithDecisions(sessionData, locale, translate).find((candidateGate) => candidateGate.id === gateId);
    if (gate?.state === 'pending') {
      pushUser(sessionData, text);
      return decide(sessionData, gateId, 'rejected', text, prefs, translate, locale);
    }
    // The gate was decided elsewhere — the stale chip drops, the message
    // falls through as an ordinary one.
  }

  pushUser(sessionData, text);
  const lower = text.toLowerCase();
  const ref = buildSlice(sessionData).currentArtifact ?? null;

  // Typed run-ops (pause / cancel / resume) scope to the open stage canvas —
  // the follow-up-with-context-chip replacement for the retired stage bar.
  if (ref) {
    const op = typedOp(sessionData, ref, lower, lv, translate, locale);
    if (op) {
      narrate(sessionData, { textKey: op.replyKey, textVars: op.replyVars, artifact: ref, tone: null });
      const ctx = loopContext(sessionData, ref, prefs, translate, locale);
      ctx.opFired = op.fired;
      return ctx;
    }
  }

  const reply = repo.replies(locale).find((candidateReply) => candidateReply.match.some((keyword) => lower.includes(keyword)))
    ?? (ref ? scopedReply(contextFor(sessionData, ref, lv, translate, locale), locale, translate) : repo.replyFallback(locale));
  narrate(sessionData, {
    text: reply.text, textBalanced: reply.textBalanced, textPlain: reply.textPlain,
    textKey: reply.textKey, textVars: reply.textVars,
    artifact: reply.artifact ?? null, tone: reply.artifact ? 'action' : null,
  });

  const nextRef = reply.artifact ?? ref;
  return nextRef ? showArtifact(sessionData, nextRef, prefs, translate, locale) : loopContext(sessionData, null, prefs, translate, locale);
};

// The scoped fallback: answer from the canvas's own envelope. Computed
// replies come back as translation keys + vars (rendered at read time);
// fixture fallbacks carry their per-locale strings directly.
function scopedReply(env, activeLocale, translate) {
  const artifact = env.artifact;
  if (!artifact) return { ...repo.replyFallback(activeLocale) };
  if (artifact.summary !== undefined) return { textKey: 'build.reply.summary', textVars: { label: artifact.label, summary: artifact.summary, detail: artifact.detail ?? '' } };
  if (artifact.context) return { textKey: 'build.reply.context', textVars: { label: artifact.label, context: artifact.context } };
  if (artifact.list) return { textKey: 'build.reply.findings', textVars: { count: artifact.list.length, gate: artifact.gate } };
  if (Array.isArray(artifact)) {
    const watch = artifact.filter((evidenceEntry) => evidenceEntry.state === 'watch').length;
    return { textKey: 'build.reply.evidence', textVars: { count: artifact.length, pass: artifact.length - watch, watch } };
  }
  if (artifact.bars) return { textKey: 'build.reply.chart' };
  return { ...repo.replyFallback(activeLocale) };
}

// Shared stage-control overlay (button POST and typed op land here). The
// summary is a translation KEY — the reader's level/locale apply at render.
function applyStageControl(sessionData, stageId, action) {
  if (action === 'resume') delete (buildSlice(sessionData).stageStates ??= {})[stageId];
  else if (action === 'pause' || action === 'cancel') {
    (buildSlice(sessionData).stageStates ??= {})[stageId] = {
      state: action === 'pause' ? 'held' : 'cancelled',
      summaryKey: action === 'pause' ? 'build.stage.pausedByYou' : 'build.stage.cancelledByYou',
    };
  }
}

const opEvent = {
  pause: 'build.op.paused',
  cancel: 'build.op.cancelled',
  resume: 'build.op.resumed',
};

// Typed ops from the chat: pause/hold, cancel/stop/kill, resume/continue —
// only when the open stage's current state actually offers the action.
function typedOp(sessionData, ref, lower, lv, translate, activeLocale) {
  const [kind, id] = ref.split('/');
  if (kind !== 'stage') return null;
  const wants = /\b(pause|hold)\b/.test(lower) ? 'pause'
    : /\b(cancel|stop|kill)\b/.test(lower) ? 'cancel'
    : /\b(resume|continue|unpause)\b/.test(lower) ? 'resume'
    : null;
  if (!wants) return null;
  const stages = stagesWithDecisions(gatesWithDecisions(sessionData, activeLocale, translate), lv, sessionData, activeLocale, translate);
  const stage = stages.find((candidate) => candidate.id === id);
  if (!stage) return null;
  const offered = wants === 'pause' ? ['active', 'queued'].includes(stage.state)
    : wants === 'cancel' ? ['active', 'queued', 'held'].includes(stage.state)
    : stage.state === 'held';
  if (!offered) {
    return { fired: false, replyKey: 'build.op.notOffered', replyVars: { op: wants, label: stage.label, state: translate('status.name.' + stage.state) } };
  }
  applyStageControl(sessionData, id, wants);
  const replyKey = wants === 'cancel' ? 'build.op.doneCancelled' : wants === 'pause' ? 'build.op.donePaused' : 'build.op.doneResumed';
  return { fired: true, replyKey, replyVars: { label: stage.label } };
}

// Stage control from the run view: pause holds a stage, resume releases it,
// cancel takes it off the line. Narrated to the chat — the thread is the
// run's history.
export const stageControl = (sessionData, stageId, action, prefs = {}, translate = (key) => key, locale = 'en') => {
  const stage = repo.stages(locale).find((candidateStage) => candidateStage.id === stageId);
  const label = stage ? stage.label : stageId;
  if (stage) applyStageControl(sessionData, stageId, action);
  narrate(sessionData, {
    textKey: opEvent[action],
    textVars: { label },
    text: `${label} ${action}.`,
    artifact: stage ? `stage/${stageId}` : null,
    tone: action === 'cancel' ? 'fail' : action === 'pause' ? 'warn' : 'action',
  });
  return showArtifact(sessionData, stage ? `stage/${stageId}` : (buildSlice(sessionData).currentArtifact ?? null), prefs, translate, locale);
};

// Run control from the run view: pause holds the whole line.
export const runControl = (sessionData, action, prefs = {}, translate = (key) => key, locale = 'en') => {
  if (action === 'pause') buildSlice(sessionData).runControl = { paused: true };
  else delete buildSlice(sessionData).runControl;
  narrate(sessionData, {
    textKey: action === 'pause' ? 'build.op.runPaused' : 'build.op.runResumed',
    artifact: null,
    tone: action === 'pause' ? 'warn' : 'action',
  });
  return loopContext(sessionData, null, prefs, translate, locale);
};

// Gate decision: record it, mint provenance, narrate the consequence to the
// chat. The note arrives either as the form field (legacy) or — via the
// pinned gate chip — as the user's chat message itself.
export const decide = (sessionData, gateId, decision, note, prefs = {}, translate = (key) => key, locale = 'en') => {
  const decisions = (buildSlice(sessionData).gateDecisions ??= {});
  decisions[gateId] = {
    decision,
    note: note || null,
    hash: decision === 'approved' ? 'c71b…e9d2' : '88d0…f4a6',
  };
  const gate = repo.humanGates(locale).find((candidateGate) => candidateGate.id === gateId);
  const label = gate ? gate.label.toLowerCase() : gateId;
  const hash = decisions[gateId].hash;
  narrate(sessionData, {
    textKey: decision === 'approved' ? 'build.decide.approved' : 'build.decide.rejected',
    textVars: { label, hash },
    artifact: `gate/${gateId}`,
    tone: decision === 'approved' ? 'action' : 'fail',
  });
  return showArtifact(sessionData, `gate/${gateId}`, prefs, translate, locale);
};
