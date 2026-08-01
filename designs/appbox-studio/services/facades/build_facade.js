// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
// BuildFacade — composes the run fixture with session-scoped state (gate
// decisions, chat messages, stage/run controls, the open main-panel artifact,
// context chips, the activity panel's active view) into exactly what
// loop_viewmodel needs. Every leveled fixture string passes through the
// jargon facade at the reader's level; static view copy comes in as the
// runtime translator `t` (h.t(c) — level and locale already bound, l10n/
// app_*.arb). The locale comes from the request (h.locale(c)) and picks the
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
const B = (sd) => (sd.build ??= {});

// Thread filter vocabulary: 'all' shows everything; anything else matches
// the card type derived from the message's artifact ref ('note' = no
// artifact).
export const THREAD_FILTERS = ['all', 'stage', 'gate', 'findings', 'evidence', 'note'];

// Activity panel view registry: run controls, thread filter, artifact
// index, and the seeded commits/files views (real git wiring is a later
// stage — the views say so). Labels render via t('activityView.<id>').
export const ACTIVITY_VIEWS = [
  { id: 'run', icon: 'play', label: 'run' },
  { id: 'thread', icon: 'messages-square', label: 'thread' },
  { id: 'artifacts', icon: 'package', label: 'artifacts' },
  { id: 'commits', icon: 'git-branch', label: 'commits' },
  { id: 'files', icon: 'folder', label: 'files' },
];
const ACTIVITY_VIEW_IDS = ACTIVITY_VIEWS.map((v) => v.id);

// Panel width steps, per side — the build shell's own persisted sizing.
const PANEL_SIZES = ['s', 'm', 'l'];
const panelSizeFor = (sd, side) => (PANEL_SIZES.includes(B(sd).panelSize?.[side]) ? B(sd).panelSize[side] : 's');

// Where each human gate sits on the timeline: it docks after this stage.
const GATE_AFTER = { 'design.approval': 'design', 'build.acceptance': 'review', 'ship.confirm': 'deploy' };

const pushUser = (sessionData, text) => {
  const extra = (B(sessionData).extraMessages ??= []);
  const seq = (B(sessionData).msgSeq = (B(sessionData).msgSeq ?? 0) + 1);
  extra.push({ id: `u-${seq}`, at: 'now', from: 'user', text });
  return seq;
};

const narrate = (sessionData, m) => {
  const extra = (B(sessionData).extraMessages ??= []);
  const seq = (B(sessionData).msgSeq = (B(sessionData).msgSeq ?? 0) + 1);
  extra.push({ id: `a-${seq}`, at: 'now', from: 'agent', ...m });
};

// Human-gate decisions are the human's act; a POST lands them in the session
// and the facade overlays them onto the fixture's lifecycle.
function gatesWithDecisions(sessionData, L, t) {
  const decisions = B(sessionData).gateDecisions ?? {};
  return repo.humanGates(L).map((g) => {
    const d = decisions[g.id];
    if (!d) return g;
    return {
      ...g,
      state: d.decision,
      provenance: {
        by: 'Evan',
        shell: t('prov.shell'),
        device: t('prov.machine'),
        method: t('prov.method'),
        at: t('prov.justNow'),
        hash: d.hash,
      },
      note: d.decision === 'rejected' ? d.note : null,
    };
  });
}

function stagesWithDecisions(gates, lv, sessionData, L, t) {
  const acceptance = gates.find((g) => g.id === 'build.acceptance');
  return repo.stages(L).map((s) => {
    let out = {
      ...s,
      summary: jargon.pick(s, 'summary', lv),
      detail: jargon.pick(s, 'detail', lv),
      attempts: s.attempts?.map((a) => ({ ...a, note: jargon.pick(a, 'note', lv) })),
    };
    if (s.id === 'deploy' && acceptance.state === 'approved') {
      out = {
        ...out,
        state: 'active',
        summary: t('build.deployUnlocked'),
      };
    }
    if (s.id === 'deploy' && acceptance.state === 'rejected') {
      out = {
        ...out,
        state: 'held',
        summary: t('build.deployHeld'),
      };
    }
    // Human stage controls (pause/cancel from the run view) win last.
    const control = B(sessionData).stageStates?.[s.id];
    if (control) out = { ...out, state: control.state, summary: t(control.summaryKey) };
    return out;
  });
}

function runWithState(sessionData, gates, L, t) {
  const run = { ...repo.run(L) };
  const acceptance = gates.find((g) => g.id === 'build.acceptance');
  run.pausedByYou = Boolean(B(sessionData).runControl?.paused);
  if (run.pausedByYou) {
    run.state = 'paused';
    run.stateLabel = t('build.state.pausedByYou');
  } else if (acceptance.state === 'approved') {
    run.state = 'running';
    run.stateLabel = t('build.state.running');
  } else if (acceptance.state === 'rejected') {
    run.state = 'held';
    run.stateLabel = t('build.state.held');
  }
  return run;
}

// The thread card: type (color-coded in the view), lifecycle state, and one
// detail line — resolved from the artifact the message points at.
function cardFor(ref, parts, t) {
  if (!ref) return { type: 'note' };
  const [kind, id] = ref.split('/');
  switch (kind) {
    case 'stage': {
      const s = parts.stages.find((x) => x.id === id);
      if (!s) return { type: 'stage', ref };
      const when = s.duration && s.duration !== '—' ? s.duration : t('status.name.queued');
      return { type: 'stage', state: s.state, detail: t('build.stageEyebrow', { n: s.n, total: parts.stages.length, when }), ref };
    }
    case 'gate': {
      const g = parts.gates.find((x) => x.id === id);
      if (!g) return { type: 'gate', ref };
      const detail = g.state === 'approved' ? t('build.gateDetail.signed', { at: g.provenance?.at ?? '' })
        : g.state === 'rejected' ? t('build.gateDetail.rejected')
        : g.state === 'pending' ? t('build.gateDetail.pending')
        : t('build.gateDetail.unreachable');
      return { type: 'gate', state: g.state, gateId: g.id, detail: `${t('build.humanGate')} · ${detail}`, ref };
    }
    case 'findings': {
      const list = parts.findings[id] ?? [];
      return { type: 'findings', state: 'red', detail: t('build.findingsDetail', { count: list.length }), ref };
    }
    case 'evidence': {
      const pass = parts.evidence.filter((e) => e.state === 'pass').length;
      const watch = parts.evidence.length - pass;
      return { type: 'evidence', state: 'pass', detail: t('build.evidenceDetail', { count: parts.evidence.length, pass, watch }), ref };
    }
    case 'chart':
      return { type: 'chart', detail: t('build.chartDetail'), ref };
    case 'log':
      return { type: 'log', detail: t('build.logDetail'), ref };
    default:
      return { type: 'note', ref };
  }
}

function messagesWithSession(sessionData, activeArtifact, lv, parts, filter, L, t) {
  const extra = B(sessionData).extraMessages ?? [];
  const all = [...repo.narrative(L), ...extra].map((m) => ({
    from: 'agent',
    tone: null,
    artifact: null,
    ...m,
    at: m.at === 'now' ? t('time.now') : m.at,
    text: m.textKey ? t(m.textKey, m.textVars) : m.from === 'user' ? m.text : jargon.pick(m, 'text', lv),
    active: m.artifact === activeArtifact,
    card: m.from === 'user' ? { type: 'you' } : cardFor(m.artifact, parts, t),
  }));
  if (filter === 'all') return all;
  return all.filter((m) => m.card.type === filter);
}

function findingsWithLevel(lv, L) {
  const byGate = repo.findingsByGate(L);
  return Object.fromEntries(
    Object.entries(byGate).map(([gate, list]) => [
      gate,
      list.map((f) => ({
        ...f,
        expected: jargon.pick(f, 'expected', lv),
        actual: jargon.pick(f, 'actual', lv),
        note: jargon.pick(f, 'note', lv),
      })),
    ]),
  );
}

function evidenceWithLevel(lv, L, t = (k) => k) {
  return repo.evidence(L).map((e) => ({
    ...e,
    chips: jargon.probeChips(e.probe, lv, t),
    band: jargon.band(jargon.scoreDeltaE(e.probe.deltaE), t),
  }));
}

// ---------- design viewer (evidence canvas) ----------
// The evidence canvas shows the designed screens as read-only artboards
// (flow tiles, static canvas — no pins, no drag). Tile heights come from the
// viewports the design actually authored (seed truth).
// B(sessionData).viewer = { bg, inspect }.
export const VIEWPORT_WIDTHS = { mobile: 390, tablet: 744, desktop: 1280 };
export const VIEWPORT_HEIGHTS = { mobile: 844, tablet: 1133, desktop: 800 };
export const VIEWER_BGS = ['canvas', 'warm', 'slate'];

// The evidence canvas renders every surface through the stub renderer —
// the app-under-design (Portalo) is design CONTENT, never a live route.
function viewerFor(sessionData, evidence) {
  const v = B(sessionData).viewer ?? {};
  const screens = evidence.map((e) => {
    const viewports = e.viewports ?? ['mobile'];
    const v0 = viewports[0];
    return {
      id: e.surface, label: e.surface, state: e.state,
      chips: e.chips, viewports,
      shell: e.surface?.split('.')[0] ?? 'app',
      primaryWidth: VIEWPORT_WIDTHS[v0] ?? 390,
      // static evidence canvas: no rung switching, tiles render at the first
      // authored rung (same contract field the design facade fills per vp).
      tile: { vp: v0, width: VIEWPORT_WIDTHS[v0] ?? 390, height: VIEWPORT_HEIGHTS[v0] ?? 844 },
    };
  });
  const bg = VIEWER_BGS.includes(v.bg) ? v.bg : 'canvas';
  const base = '/build/artifact/evidence/surfaces/viewer';
  const inspect = v.inspect === '1';

  // Viewer href builder: current viewer state merged with overrides, empties
  // dropped — same idiom as the design facade's.
  const withParams = (over) => {
    const merged = { bg, inspect: inspect ? '1' : null, ...over };
    const qs = Object.entries(merged).filter(([, val]) => val != null).map(([k, val]) => `${k}=${val}`).join('&');
    return qs ? `${base}?${qs}` : base;
  };

  return {
    screens, bg, inspect, strip: true, static: true,
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
        inspectOn: inspect,
        inspectHref: withParams({ inspect: inspect ? null : '1' }),
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
export const screenStub = (surface, vp, prefs = {}, locale = 'en', opts = {}) => {
  const e = repo.evidence(locale).find((x) => x.surface === surface);
  // No evidence entry (design-content ids like portalo.*): every rung is
  // authored — the design canvas drives the viewport, not the evidence log.
  const authored = e?.viewports ?? ['mobile', 'tablet', 'desktop'];
  const v = authored.includes(vp) ? vp : authored[0];
  const kind = surface?.split('.')[1] ?? surface;
  return {
    surface, vp: v, width: VIEWPORT_WIDTHS[v],
    kind,
    theme: prefs.theme ?? 'light',
    embed: opts.embed ?? false,
    inspect: opts.inspect ?? false,
    // still: freeze frame for canvas tiles — partials skip auto-advance
    // (meta refresh) so every screen in a chain stays itself on the canvas.
    still: opts.still ?? false,
    partial: proj.hasPartial(kind) ? `ui/project/${kind}.html` : null,
    tabs: proj.hasPartial(kind) ? proj.tabs() : [],
    next: proj.hasPartial(kind) ? proj.nextEdge(surface) : null,
  };
};

// Viewer toolbar act: bg/inspect are AUTHORITATIVE (every control href echoes
// both, defaults elided — absent means "back to default", never "keep";
// merging would strand inspect:'1' on forever). Same contract as the design
// facade's.
export const setViewer = (sessionData, query, prefs = {}, t = (k) => k, locale = 'en') => {
  const next = {};
  for (const [k, v] of Object.entries(query)) if (v != null) next[k] = v;
  B(sessionData).viewer = next;
  return loopContext(sessionData, 'evidence/surfaces', prefs, t, locale);
};

// The shell timeline: the whole line at a glance, current item highlighted.
function timeline({ stages, gates }) {
  const items = [];
  for (const s of stages) {
    items.push({ kind: 'stage', id: s.id, ref: `stage/${s.id}`, label: s.label, n: s.n, state: s.state });
    for (const g of gates.filter((x) => GATE_AFTER[x.id] === s.id)) {
      items.push({ kind: 'gate', id: g.id, ref: `gate/${g.id}`, label: g.label, state: g.state });
    }
  }
  const current = items.find((i) => i.kind === 'gate' && i.state === 'pending')
    ?? items.find((i) => i.state === 'active')
    ?? null;
  return { items, currentId: current ? current.ref : null };
}

// ---------- the per-canvas LLM context envelope ----------
// Local: the artifact's own rendered data + its direct links. Global: a thin
// fixed brief. The fixture replies below AND any real model consume this
// same typed envelope — swap the reply generator, keep the structure.
export const contextFor = (sessionData, ref, lv = 'balanced', t = (k) => k, locale = 'en') => {
  const gates = gatesWithDecisions(sessionData, locale, t);
  const stages = stagesWithDecisions(gates, lv, sessionData, locale, t);
  const run = repo.run(locale);
  const brief = {
    run: run.number, project: run.project, state: run.state,
    policy: run.policy,
    timeline: timeline({ stages, gates }).items.map((i) => `${i.kind}:${i.id}=${i.state}`),
    jargon: lv,
  };
  const [kind, id] = (ref || '').split('/');
  let artifact = null;
  const linked = [];
  if (kind === 'stage') {
    artifact = stages.find((s) => s.id === id) ?? null;
    if (id === 'coverage') linked.push({ findings: findingsWithLevel(lv, locale).coverage ?? [] });
    if (id === 'deploy') linked.push({ gates: gates.filter((g) => g.id !== 'design.approval') });
    if (id === 'design') linked.push({ gate: gates.find((g) => g.id === 'design.approval') });
  } else if (kind === 'gate') {
    artifact = gates.find((g) => g.id === id) ?? null;
    if (id === 'build.acceptance') linked.push({ evidence: evidenceWithLevel(lv, locale, t) }, { stage: stages.find((s) => s.id === 'deploy') });
    if (id === 'design.approval') linked.push({ stages: stages.filter((s) => ['design', 'freeze'].includes(s.id)) });
    if (id === 'ship.confirm') linked.push({ stage: stages.find((s) => s.id === 'deploy') });
  } else if (kind === 'findings') {
    artifact = { gate: id, list: findingsWithLevel(lv, locale)[id] ?? [] };
    linked.push({ stage: stages.find((s) => s.id === id) });
  } else if (kind === 'chart') {
    artifact = repo.chart(locale);
    linked.push({ stages: stages.map((s) => ({ id: s.id, duration: s.duration, state: s.state })) });
  } else if (kind === 'evidence') {
    artifact = evidenceWithLevel(lv, locale, t);
    linked.push({ stage: stages.find((s) => s.id === 'freeze') });
  } else if (kind === 'log') {
    artifact = { note: 'the whole line, in order' };
  }
  return { artifact, linked, brief };
};

// The main panel renders ONE artifact at a time; ref is "kind/id". No ref
// (or an unknown one) means nothing is open — the chat sits centered.
function resolveArtifact(ref, { gates, stages, messages, findings, evidence }, L) {
  if (!ref) return null;
  const [kind, id] = ref.split('/');
  switch (kind) {
    case 'gate': {
      const gate = gates.find((g) => g.id === id);
      if (gate) return { kind, gate, ref };
      break;
    }
    case 'stage': {
      const stage = stages.find((s) => s.id === id);
      if (stage) return { kind, stage, stageCount: stages.length, ref };
      break;
    }
    case 'findings': {
      const list = findings[id];
      if (list) return { kind, gate: id, list, ref };
      break;
    }
    case 'chart':
      return { kind, chart: repo.chart(L), ref };
    case 'log':
      return { kind, messages, ref };
    case 'evidence':
      return { kind, evidence, ref };
  }
  return null;
}

// The pinned gate chip: live only while its gate is still decidable.
const noteGateFor = (sessionData, gates) => {
  const id = B(sessionData).gateChip;
  if (!id) return null;
  const g = gates.find((x) => x.id === id);
  return g && g.state === 'pending' ? g : null;
};

// Composer context chips for cp.frame: the pinned gate (a reject note is
// the next chat message). The open artifact needs no chip — the main panel
// is always visible, there is nothing to close.
const chipsFor = (noteGate, L, t) => {
  if (!noteGate) return [];
  return [{
    id: `gate/${noteGate.id}`, label: t('build.noteChip', { label: noteGate.label.toLowerCase() }),
    tone: 'gate', removeHref: `/build/chips/unpin?ref=gate/${noteGate.id}`,
  }];
};

// The artifacts activity view: everything openable, in pipeline order.
function artifactIndex({ gates, stages }, t) {
  return [
    ...gates.map((g) => ({ ref: `gate/${g.id}`, label: g.label, kind: 'gate', state: g.state })),
    ...stages.map((s) => ({ ref: `stage/${s.id}`, label: s.label, kind: 'stage', state: s.state })),
    { ref: 'findings/coverage', label: t('build.artifact.findings'), kind: 'findings', state: 'red' },
    { ref: 'evidence/surfaces', label: t('build.artifact.evidence'), kind: 'evidence', state: 'pass' },
    { ref: 'chart/durations', label: t('build.artifact.chart'), kind: 'chart', state: null },
    { ref: 'log/full', label: t('build.artifact.log'), kind: 'log', state: null },
  ];
}

export const loopContext = (sessionData = {}, ref = null, prefs = {}, t = (k) => k, locale = 'en', fileArg, panelArg) => {
  const L = locale;
  const lv = jargon.level(prefs);
  // The open file (main panel): ?file=<path> opens, ?file=none closes; an
  // artifact open always clears it — the main panel shows one thing.
  if (fileArg === 'none') delete B(sessionData).currentFile;
  else if (fileArg) { B(sessionData).currentFile = fileArg; delete B(sessionData).currentArtifact; }
  const currentFile = B(sessionData).currentFile ?? null;
  // The panel bar (compact/medium): ?panel= picks the single visible content
  // panel and sticks; default main.
  if (['activity', 'main', 'composer'].includes(panelArg)) B(sessionData).panel = panelArg;
  const gates = gatesWithDecisions(sessionData, L, t);
  const stages = stagesWithDecisions(gates, lv, sessionData, L, t);
  const findings = findingsWithLevel(lv, L);
  const evidence = evidenceWithLevel(lv, L, t);
  const parts = { gates, stages, findings, evidence };
  const activeArtifact = currentFile ? null : (ref ?? B(sessionData).currentArtifact ?? null);
  const filter = THREAD_FILTERS.includes(B(sessionData).threadFilter) ? B(sessionData).threadFilter : 'all';
  const messages = messagesWithSession(sessionData, activeArtifact, lv, parts, filter, L, t);
  const artifact = resolveArtifact(activeArtifact, { ...parts, messages }, L);
  const openRef = artifact ? activeArtifact : null;
  const activityView = ACTIVITY_VIEW_IDS.includes(B(sessionData).activityView) ? B(sessionData).activityView : 'run';
  const noteGate = noteGateFor(sessionData, gates);
  return {
    run: runWithState(sessionData, gates, L, t),
    project: { name: repo.run(L).project },
    composerAction: '/build/messages',
    modelMenu: agent.modelMenuFor(sessionData, '/build', t),
    threading: messages.some((m) => m.from === 'user'),
    stages,
    gates,
    counts: repo.counts(L),
    messages,
    filter,
    timeline: timeline(parts),
    activeArtifact: openRef,
    artifact,
    fileView: currentFile ? fv.fileViewFor(currentFile, '/build?file=none') : null,
    panel: B(sessionData).panel ?? 'main',
    viewer: openRef === 'evidence/surfaces' ? viewerFor(sessionData, evidence) : null,
    chips: chipsFor(noteGate, L, t),
    noteGate,
    suggestions: noteGate
      ? [{ value: t('build.composer.rejectValue'), label: t('build.composer.rejectLabel') }]
      : [t('build.composer.sugCoverage'), t('build.composer.sugDurations'), t('build.composer.sugLog')],
    placeholder: noteGate ? t('composer.placeholder.buildNote') : t('composer.placeholder.build'),
    activityView,
    panelSize: panelSizeFor(sessionData, 'left'),
    panelSizeHref: '/build/panel/size/left/',
    activityViews: ACTIVITY_VIEWS.map((v) => ({ ...v, label: t('activityView.' + v.id), href: `/build/panel?view=${v.id}`, active: v.id === activityView })),
    artifacts: artifactIndex(parts, t),
    commits: repo.commits(L),
    files: repo.files(L).map((f) => ({ ...f, ...fv.fileLink(f.path, '/build') })),
    jargonLevel: lv,
  };
};

export const showArtifact = (sessionData, ref, prefs = {}, t = (k) => k, locale = 'en') => {
  B(sessionData).currentArtifact = ref;
  delete B(sessionData).currentFile;
  return loopContext(sessionData, ref, prefs, t, locale);
};

// A file row in the activity panel: open it in the main panel (the mode is
// the server's, from the extension).
export const openFile = (sessionData, path, prefs = {}, t = (k) => k, locale = 'en') =>
  loopContext(sessionData, null, prefs, t, locale, path ?? 'none');

// Composer chrome: pick the agent model (shared session state), then
// re-render the loop stage.
export const setModel = (sessionData, id, prefs = {}, t = (k) => k, locale = 'en') => {
  agent.setModel(sessionData, id);
  return loopContext(sessionData, null, prefs, t, locale);
};

// ---------- context chips (gate note pin / unpin) ----------

// "Reject with note" pins the gate as a context chip; the composer becomes
// the note input (single input path) and the next message is the rejection.
export const pinChip = (sessionData, ref, prefs = {}, t = (k) => k, locale = 'en') => {
  const [kind, id] = (ref || '').split('/');
  if (kind === 'gate') {
    const g = gatesWithDecisions(sessionData, locale, t).find((x) => x.id === id);
    if (g?.state === 'pending') B(sessionData).gateChip = id;
  }
  return loopContext(sessionData, null, prefs, t, locale);
};

export const unpinChip = (sessionData, ref, prefs = {}, t = (k) => k, locale = 'en') => {
  const [kind, id] = (ref || '').split('/');
  if (kind === 'gate' && B(sessionData).gateChip === id) delete B(sessionData).gateChip;
  return loopContext(sessionData, null, prefs, t, locale);
};

// Activity panel view switching: run / thread / artifacts / commits / files.
export const setActivityView = (sessionData, view, prefs = {}, t = (k) => k, locale = 'en') => {
  B(sessionData).activityView = ACTIVITY_VIEW_IDS.includes(view) ? view : 'run';
  return loopContext(sessionData, null, prefs, t, locale);
};

// Thread filter (thread view): all | stage | gate | findings | evidence | note.
export const setThreadFilter = (sessionData, filter, prefs = {}, t = (k) => k, locale = 'en') => {
  B(sessionData).threadFilter = THREAD_FILTERS.includes(filter) ? filter : 'all';
  return loopContext(sessionData, null, prefs, t, locale);
};

// Panel width grip: cycle persisted per side (the shell's own sizing state).
export const setPanelSize = (sessionData, side, size, prefs = {}, t = (k) => k, locale = 'en') => {
  if (['left', 'right'].includes(side) && PANEL_SIZES.includes(size)) {
    (B(sessionData).panelSize ??= {})[side] = size;
  }
  return loopContext(sessionData, null, prefs, t, locale);
};

// The composer round-trip: append the user's message, then a simulated
// agent reply; the reply may pull a new artifact onto the canvas.
// With a gate chip pinned, the message IS the reject note + decision.
export const sendMessage = (sessionData, text, prefs = {}, t = (k) => k, locale = 'en') => {
  const lv = jargon.level(prefs);

  if (B(sessionData).gateChip) {
    const gateId = B(sessionData).gateChip;
    delete B(sessionData).gateChip;
    const gate = gatesWithDecisions(sessionData, locale, t).find((g) => g.id === gateId);
    if (gate?.state === 'pending') {
      pushUser(sessionData, text);
      return decide(sessionData, gateId, 'rejected', text, prefs, t, locale);
    }
    // The gate was decided elsewhere — the stale chip drops, the message
    // falls through as an ordinary one.
  }

  pushUser(sessionData, text);
  const lower = text.toLowerCase();
  const ref = B(sessionData).currentArtifact ?? null;

  // Typed run-ops (pause / cancel / resume) scope to the open stage canvas —
  // the follow-up-with-context-chip replacement for the retired stage bar.
  if (ref) {
    const op = typedOp(sessionData, ref, lower, lv, t, locale);
    if (op) {
      narrate(sessionData, { textKey: op.replyKey, textVars: op.replyVars, artifact: ref, tone: null });
      const ctx = loopContext(sessionData, ref, prefs, t, locale);
      ctx.opFired = op.fired;
      return ctx;
    }
  }

  const reply = repo.replies(locale).find((r) => r.match.some((k) => lower.includes(k)))
    ?? (ref ? scopedReply(contextFor(sessionData, ref, lv, t, locale), locale, t) : repo.replyFallback(locale));
  narrate(sessionData, {
    text: reply.text, textBalanced: reply.textBalanced, textPlain: reply.textPlain,
    textKey: reply.textKey, textVars: reply.textVars,
    artifact: reply.artifact ?? null, tone: reply.artifact ? 'action' : null,
  });

  const nextRef = reply.artifact ?? ref;
  return nextRef ? showArtifact(sessionData, nextRef, prefs, t, locale) : loopContext(sessionData, null, prefs, t, locale);
};

// The scoped fallback: answer from the canvas's own envelope. Computed
// replies come back as translation keys + vars (rendered at read time);
// fixture fallbacks carry their per-locale strings directly.
function scopedReply(env, L, t) {
  const a = env.artifact;
  if (!a) return { ...repo.replyFallback(L) };
  if (a.summary !== undefined) return { textKey: 'build.reply.summary', textVars: { label: a.label, summary: a.summary, detail: a.detail ?? '' } };
  if (a.context) return { textKey: 'build.reply.context', textVars: { label: a.label, context: a.context } };
  if (a.list) return { textKey: 'build.reply.findings', textVars: { count: a.list.length, gate: a.gate } };
  if (Array.isArray(a)) {
    const watch = a.filter((e) => e.state === 'watch').length;
    return { textKey: 'build.reply.evidence', textVars: { count: a.length, pass: a.length - watch, watch } };
  }
  if (a.bars) return { textKey: 'build.reply.chart' };
  return { ...repo.replyFallback(L) };
}

// Shared stage-control overlay (button POST and typed op land here). The
// summary is a translation KEY — the reader's level/locale apply at render.
function applyStageControl(sessionData, stageId, action) {
  if (action === 'resume') delete (B(sessionData).stageStates ??= {})[stageId];
  else if (action === 'pause' || action === 'cancel') {
    (B(sessionData).stageStates ??= {})[stageId] = {
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
function typedOp(sessionData, ref, lower, lv, t, L) {
  const [kind, id] = ref.split('/');
  if (kind !== 'stage') return null;
  const wants = /\b(pause|hold)\b/.test(lower) ? 'pause'
    : /\b(cancel|stop|kill)\b/.test(lower) ? 'cancel'
    : /\b(resume|continue|unpause)\b/.test(lower) ? 'resume'
    : null;
  if (!wants) return null;
  const stages = stagesWithDecisions(gatesWithDecisions(sessionData, L, t), lv, sessionData, L, t);
  const s = stages.find((x) => x.id === id);
  if (!s) return null;
  const offered = wants === 'pause' ? ['active', 'queued'].includes(s.state)
    : wants === 'cancel' ? ['active', 'queued', 'held'].includes(s.state)
    : s.state === 'held';
  if (!offered) {
    return { fired: false, replyKey: 'build.op.notOffered', replyVars: { op: wants, label: s.label, state: t('status.name.' + s.state) } };
  }
  applyStageControl(sessionData, id, wants);
  const replyKey = wants === 'cancel' ? 'build.op.doneCancelled' : wants === 'pause' ? 'build.op.donePaused' : 'build.op.doneResumed';
  return { fired: true, replyKey, replyVars: { label: s.label } };
}

// Stage control from the run view: pause holds a stage, resume releases it,
// cancel takes it off the line. Narrated to the chat — the thread is the
// run's history.
export const stageControl = (sessionData, stageId, action, prefs = {}, t = (k) => k, locale = 'en') => {
  const stage = repo.stages(locale).find((s) => s.id === stageId);
  const label = stage ? stage.label : stageId;
  if (stage) applyStageControl(sessionData, stageId, action);
  narrate(sessionData, {
    textKey: opEvent[action],
    textVars: { label },
    text: `${label} ${action}.`,
    artifact: stage ? `stage/${stageId}` : null,
    tone: action === 'cancel' ? 'fail' : action === 'pause' ? 'warn' : 'action',
  });
  return showArtifact(sessionData, stage ? `stage/${stageId}` : (B(sessionData).currentArtifact ?? null), prefs, t, locale);
};

// Run control from the run view: pause holds the whole line.
export const runControl = (sessionData, action, prefs = {}, t = (k) => k, locale = 'en') => {
  if (action === 'pause') B(sessionData).runControl = { paused: true };
  else delete B(sessionData).runControl;
  narrate(sessionData, {
    textKey: action === 'pause' ? 'build.op.runPaused' : 'build.op.runResumed',
    artifact: null,
    tone: action === 'pause' ? 'warn' : 'action',
  });
  return loopContext(sessionData, null, prefs, t, locale);
};

// Gate decision: record it, mint provenance, narrate the consequence to the
// chat. The note arrives either as the form field (legacy) or — via the
// pinned gate chip — as the user's chat message itself.
export const decide = (sessionData, gateId, decision, note, prefs = {}, t = (k) => k, locale = 'en') => {
  const decisions = (B(sessionData).gateDecisions ??= {});
  decisions[gateId] = {
    decision,
    note: note || null,
    hash: decision === 'approved' ? 'c71b…e9d2' : '88d0…f4a6',
  };
  const gate = repo.humanGates(locale).find((g) => g.id === gateId);
  const label = gate ? gate.label.toLowerCase() : gateId;
  const hash = decisions[gateId].hash;
  narrate(sessionData, {
    textKey: decision === 'approved' ? 'build.decide.approved' : 'build.decide.rejected',
    textVars: { label, hash },
    artifact: `gate/${gateId}`,
    tone: decision === 'approved' ? 'action' : 'fail',
  });
  return showArtifact(sessionData, `gate/${gateId}`, prefs, t, locale);
};
