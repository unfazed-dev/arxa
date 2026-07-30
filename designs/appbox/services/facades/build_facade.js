// BuildFacade — composes the run fixture with session-scoped state (gate
// decisions, chat messages, stage/run controls, the open canvas artifact,
// context chips, the left rail's active view) into exactly what
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
// The run thread IS the chat: narrative cards render in the chat stage,
// evidence/charts/gates open as center artifacts (chat docks right), and
// gate notes are chat replies carrying a gate context chip — there is no
// second input path.
import * as repo from '../repositories/build_repository.js';
import * as jargon from './jargon.js';
import * as agent from './agent_menus.js';

// All build-tab session state lives behind one namespace so it never
// collides with the intake/design/app surfaces sharing the session — each
// shell manages its own data (design: sessionData.design, intake: .intake).
const B = (sd) => (sd.build ??= {});

// Rail filter vocabulary: 'all' shows everything; anything else matches the
// card type derived from the message's artifact ref ('note' = no artifact).
export const RAIL_FILTERS = ['all', 'stage', 'gate', 'findings', 'evidence', 'note'];

// Left multi-view rail registry: run controls, thread filter, artifact
// index, and the seeded commits/files views (real git wiring is a later
// stage — the views say so). Labels render via t('rail.<id>').
export const RAIL_VIEWS = [
  { id: 'run', icon: 'play', label: 'run' },
  { id: 'thread', icon: 'messages-square', label: 'thread' },
  { id: 'artifacts', icon: 'package', label: 'artifacts' },
  { id: 'commits', icon: 'git-branch', label: 'commits' },
  { id: 'files', icon: 'folder', label: 'files' },
];
const RAIL_VIEW_IDS = RAIL_VIEWS.map((v) => v.id);

// Rail width steps, per side — the build shell's own persisted rail sizing.
const RAIL_SIZES = ['s', 'm', 'l'];
const railSizeFor = (sd, side) => (RAIL_SIZES.includes(B(sd).railSize?.[side]) ? B(sd).railSize[side] : 's');

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

const labelForRef = (ref, L, t) => {
  const [kind, id] = (ref || '').split('/');
  if (kind === 'stage') return repo.stages(L).find((s) => s.id === id)?.label ?? id;
  if (kind === 'gate') return repo.humanGates(L).find((g) => g.id === id)?.label ?? id;
  if (kind === 'findings') return t('build.ref.findings', { id });
  if (kind === 'evidence') return t('build.ref.evidence');
  if (kind === 'chart') return t('build.ref.chart');
  if (kind === 'log') return t('build.ref.log');
  return ref;
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
// The evidence canvas embeds the designed screens in iframes; the toolbar
// offers only the viewports the design actually authored (seed truth).
// B(sessionData).viewer = { screen, vp, bg }.
export const VIEWPORT_WIDTHS = { mobile: 390, tablet: 744, desktop: 1280 };
export const VIEWER_BGS = ['canvas', 'warm', 'slate'];

function viewerFor(sessionData, evidence) {
  const v = B(sessionData).viewer ?? {};
  const screens = evidence.map((e) => ({
    id: e.surface, label: e.surface, state: e.state,
    chips: e.chips, viewports: e.viewports ?? ['mobile'],
  }));
  const screen = screens.find((s) => s.id === v.screen) ?? screens[0];
  const authored = screen?.viewports ?? ['mobile'];
  const vp = authored.includes(v.vp) ? v.vp : authored[0];
  const bg = VIEWER_BGS.includes(v.bg) ? v.bg : 'canvas';
  const os = ['ios', 'android'].includes(v.os) ? v.os : 'ios';
  const mode = ['single', 'rungs'].includes(v.mode) ? v.mode : 'single';
  return {
    screens, active: screen?.id, vp, bg, os, mode, strip: true,
    base: '/build/artifact/evidence/surfaces/viewer', stubBase: '/build/screens/',
  };
}

// The iframe document's context: an honest labelled stand-in for the designer
// artifact the daemon serves in the shipped app.
export const screenStub = (surface, vp, prefs = {}, locale = 'en') => {
  const e = repo.evidence(locale).find((x) => x.surface === surface);
  const authored = e?.viewports ?? ['mobile'];
  const v = authored.includes(vp) ? vp : authored[0];
  return {
    surface, vp: v, width: VIEWPORT_WIDTHS[v],
    kind: surface?.split('.')[1] ?? surface,
    theme: prefs.theme ?? 'light',
  };
};

// Viewer toolbar/filmstrip act: record the choice, re-render the viewer block.
export const setViewer = (sessionData, query, prefs = {}, t = (k) => k, locale = 'en') => {
  B(sessionData).viewer = { screen: query.screen, vp: query.vp, bg: query.bg, os: query.os, mode: query.mode };
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

// The canvas renders ONE artifact at a time; ref is "kind/id". No ref (or an
// unknown one) means nothing is open — the chat sits centered.
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

// Composer context chips for cs.wrap: the pinned gate (a reject note is the
// next chat message) and the open artifact (a follow-up is chat with the
// artifact in context). Both are removable.
const chipsFor = (activeArtifact, noteGate, L, t) => {
  const chips = [];
  if (noteGate) {
    chips.push({
      id: `gate/${noteGate.id}`, label: t('build.noteChip', { label: noteGate.label.toLowerCase() }),
      tone: 'gate', removeHref: `/build/chips/unpin?ref=gate/${noteGate.id}`,
    });
  }
  if (activeArtifact) {
    chips.push({ id: activeArtifact, label: labelForRef(activeArtifact, L, t), removeHref: '/build/close' });
  }
  return chips;
};

// The artifacts rail view: everything openable, in pipeline order.
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

export const loopContext = (sessionData = {}, ref = null, prefs = {}, t = (k) => k, locale = 'en') => {
  const L = locale;
  const lv = jargon.level(prefs);
  const gates = gatesWithDecisions(sessionData, L, t);
  const stages = stagesWithDecisions(gates, lv, sessionData, L, t);
  const findings = findingsWithLevel(lv, L);
  const evidence = evidenceWithLevel(lv, L, t);
  const parts = { gates, stages, findings, evidence };
  const activeArtifact = ref ?? B(sessionData).currentArtifact ?? null;
  const filter = RAIL_FILTERS.includes(B(sessionData).railFilter) ? B(sessionData).railFilter : 'all';
  const messages = messagesWithSession(sessionData, activeArtifact, lv, parts, filter, L, t);
  const artifact = resolveArtifact(activeArtifact, { ...parts, messages }, L);
  const openRef = artifact ? activeArtifact : null;
  const railView = RAIL_VIEW_IDS.includes(B(sessionData).railView) ? B(sessionData).railView : 'run';
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
    artifactOpen: Boolean(artifact),
    viewer: openRef === 'evidence/surfaces' ? viewerFor(sessionData, evidence) : null,
    chips: chipsFor(openRef, noteGate, L, t),
    noteGate,
    suggestions: noteGate
      ? [{ value: t('build.composer.rejectValue'), label: t('build.composer.rejectLabel') }]
      : [t('build.composer.sugCoverage'), t('build.composer.sugDurations'), t('build.composer.sugLog')],
    placeholder: noteGate ? t('composer.placeholder.buildNote') : t('composer.placeholder.build'),
    railView,
    railSize: railSizeFor(sessionData, 'left'),
    railSizeHref: '/build/rail/size/left/',
    railViews: RAIL_VIEWS.map((v) => ({ ...v, label: t('rail.' + v.id), href: `/build/rail?view=${v.id}`, active: v.id === railView })),
    artifacts: artifactIndex(parts, t),
    commits: repo.commits(L),
    files: repo.files(L),
    jargonLevel: lv,
  };
};

export const showArtifact = (sessionData, ref, prefs = {}, t = (k) => k, locale = 'en') => {
  B(sessionData).currentArtifact = ref;
  return loopContext(sessionData, ref, prefs, t, locale);
};

// Composer chrome: pick the agent model (shared session state), then
// re-render the loop stage.
export const setModel = (sessionData, id, prefs = {}, t = (k) => k, locale = 'en') => {
  agent.setModel(sessionData, id);
  return loopContext(sessionData, null, prefs, t, locale);
};

// Closing the artifact centers the chat again.
export const closeArtifact = (sessionData, prefs = {}, t = (k) => k, locale = 'en') => {
  delete B(sessionData).currentArtifact;
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

// Left rail view switching: run / thread / artifacts / commits / files.
export const setRailView = (sessionData, view, prefs = {}, t = (k) => k, locale = 'en') => {
  B(sessionData).railView = RAIL_VIEW_IDS.includes(view) ? view : 'run';
  return loopContext(sessionData, null, prefs, t, locale);
};

// Thread filter (thread view): all | stage | gate | findings | evidence | note.
export const setRailFilter = (sessionData, filter, prefs = {}, t = (k) => k, locale = 'en') => {
  B(sessionData).railFilter = RAIL_FILTERS.includes(filter) ? filter : 'all';
  return loopContext(sessionData, null, prefs, t, locale);
};

// Rail width grip: cycle persisted per side (the shell's own sizing state).
export const setRailSize = (sessionData, side, size, prefs = {}, t = (k) => k, locale = 'en') => {
  if (['left', 'right'].includes(side) && RAIL_SIZES.includes(size)) {
    (B(sessionData).railSize ??= {})[side] = size;
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

// Legacy stage-bar follow-up route — the FAB is retired. A follow-up is now
// an ordinary chat message with the artifact open as the context chip.
export const askArtifact = (sessionData, ref, text, prefs = {}, t = (k) => k, locale = 'en') => {
  B(sessionData).currentArtifact = ref;
  return sendMessage(sessionData, text, prefs, t, locale);
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
