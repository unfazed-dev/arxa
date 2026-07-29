// BuildFacade — composes the run fixture with session-scoped state
// (gate decisions, composer messages, stage controls, per-canvas threads,
// the artifact on the canvas) into exactly what loop_viewmodel needs.
// Every string passes through the jargon facade at the reader's level.
import * as repo from '../repositories/build_repository.js';
import * as jargon from './jargon.js';

export const DEFAULT_ARTIFACT = 'gate/build.acceptance';

// Rail filter vocabulary: 'all' shows everything; anything else matches the
// card type derived from the message's artifact ref ('note' = no artifact).
export const RAIL_FILTERS = ['all', 'stage', 'gate', 'findings', 'evidence', 'note'];

// Where each human gate sits on the timeline: it docks after this stage.
const GATE_AFTER = { 'design.approval': 'design', 'build.acceptance': 'review', 'ship.confirm': 'deploy' };

const narrate = (sessionData, m) => {
  const extra = (sessionData.extraMessages ??= []);
  const seq = (sessionData.msgSeq = (sessionData.msgSeq ?? 0) + 1);
  extra.push({ id: `a-${seq}`, at: 'now', from: 'agent', ...m });
};

// ---------- per-canvas threads ----------
// sessionData.threads = { [artifactRef]: [entry] }; entry kinds:
//   user  — a follow-up asked from the stage bar
//   agent — the reply (may carry textPlain/textBalanced, link, action chip)
//   event — a provenance/control act on that canvas (approve, pause, …)
// The thread is the artifact's conversation AND its history.
const threadFor = (sessionData, ref) => (sessionData.threads ??= {})[ref] ??= [];

const logThreadEvent = (sessionData, ref, text) => {
  const thread = threadFor(sessionData, ref);
  thread.push({ id: `e-${thread.length}`, at: 'now', kind: 'event', text });
};

const labelForRef = (ref) => {
  const [kind, id] = (ref || '').split('/');
  if (kind === 'stage') return repo.stages().find((s) => s.id === id)?.label ?? id;
  if (kind === 'gate') return repo.humanGates().find((g) => g.id === id)?.label ?? id;
  if (kind === 'findings') return `the ${id} findings`;
  if (kind === 'evidence') return 'surface evidence';
  if (kind === 'chart') return 'the duration chart';
  if (kind === 'log') return 'the full log';
  return ref;
};

// Human-gate decisions are the human's act; a POST lands them in the session
// and the facade overlays them onto the fixture's lifecycle.
function gatesWithDecisions(sessionData) {
  const decisions = sessionData.gateDecisions ?? {};
  return repo.humanGates().map((g) => {
    const d = decisions[g.id];
    if (!d) return g;
    return {
      ...g,
      state: d.decision,
      provenance: {
        by: 'Evan',
        shell: 'macOS shell',
        device: 'studio-mac (node m4-mini)',
        method: 'Touch ID',
        at: 'just now',
        hash: d.hash,
      },
      note: d.decision === 'rejected' ? d.note : null,
    };
  });
}

function stagesWithDecisions(gates, lv, sessionData) {
  const acceptance = gates.find((g) => g.id === 'build.acceptance');
  return repo.stages().map((s) => {
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
        summary: lv === 'plain'
          ? 'Unlocked by your build approval · a second approval confirms release'
          : 'Unlocked by build acceptance · ship.confirm gates release',
      };
    }
    if (s.id === 'deploy' && acceptance.state === 'rejected') {
      out = {
        ...out,
        state: 'held',
        summary: lv === 'plain'
          ? 'Held — you rejected the build; back to the checks with your note'
          : 'Held — build rejected, back to coverage with your note',
      };
    }
    // Human stage controls (pause/cancel from the stage bar) win last.
    const control = sessionData.stageStates?.[s.id];
    if (control) out = { ...out, state: control.state, summary: control.summary };
    return out;
  });
}

function runWithState(sessionData, gates) {
  const run = { ...repo.run() };
  const acceptance = gates.find((g) => g.id === 'build.acceptance');
  run.pausedByYou = Boolean(sessionData.runControl?.paused);
  if (run.pausedByYou) {
    run.state = 'paused';
    run.stateLabel = 'Paused by you — the line holds';
  } else if (acceptance.state === 'approved') {
    run.state = 'running';
    run.stateLabel = 'Running — deploy stage unlocked';
  } else if (acceptance.state === 'rejected') {
    run.state = 'held';
    run.stateLabel = 'Held — you rejected the build';
  }
  return run;
}

// The rail card: type (color-coded in the view), lifecycle state, one detail
// line, and the canvas thread's exchange count — all resolved from the
// artifact the message points at.
function cardFor(ref, parts, sessionData) {
  const threadCount = (sessionData.threads?.[ref] ?? []).filter((e) => e.kind === 'user').length;
  if (!ref) return { type: 'note', threadCount: 0 };
  const [kind, id] = ref.split('/');
  switch (kind) {
    case 'stage': {
      const s = parts.stages.find((x) => x.id === id);
      if (!s) return { type: 'stage', ref, threadCount };
      const when = s.duration && s.duration !== '—' ? s.duration : 'queued';
      return { type: 'stage', state: s.state, detail: `stage ${s.n} of ${parts.stages.length} · ${when} · automated`, ref, threadCount };
    }
    case 'gate': {
      const g = parts.gates.find((x) => x.id === id);
      if (!g) return { type: 'gate', ref, threadCount };
      const detail = g.state === 'approved' ? `signed ${g.provenance?.at ?? ''}`
        : g.state === 'rejected' ? 'rejected — with your note'
        : g.state === 'pending' ? 'awaiting your decision'
        : 'not yet reachable';
      return { type: 'gate', state: g.state, detail: `human gate · ${detail}`, ref, threadCount };
    }
    case 'findings': {
      const list = parts.findings[id] ?? [];
      return { type: 'findings', state: 'red', detail: `${list.length} findings · attempt 1 → fixed in attempt 2`, ref, threadCount };
    }
    case 'evidence': {
      const pass = parts.evidence.filter((e) => e.state === 'pass').length;
      const watch = parts.evidence.length - pass;
      return { type: 'evidence', state: 'pass', detail: `${parts.evidence.length} screens · ${pass} pass${watch ? ` · ${watch} on watch` : ''}`, ref, threadCount };
    }
    case 'chart':
      return { type: 'chart', detail: 'every stage, side by side', ref, threadCount };
    case 'log':
      return { type: 'log', detail: 'the whole line, in order', ref, threadCount };
    default:
      return { type: 'note', ref, threadCount };
  }
}

function messagesWithSession(sessionData, activeArtifact, lv, parts, filter) {
  const extra = sessionData.extraMessages ?? [];
  const all = [...repo.narrative(), ...extra].map((m) => ({
    from: 'agent',
    tone: null,
    artifact: null,
    ...m,
    text: m.from === 'user' ? m.text : jargon.pick(m, 'text', lv),
    active: m.artifact === activeArtifact,
    card: m.from === 'user' ? { type: 'you', threadCount: 0 } : cardFor(m.artifact, parts, sessionData),
  }));
  if (filter === 'all') return all;
  return all.filter((m) => m.card.type === filter);
}

function findingsWithLevel(lv) {
  const byGate = repo.findingsByGate();
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

function evidenceWithLevel(lv) {
  return repo.evidence().map((e) => ({
    ...e,
    chips: jargon.probeChips(e.probe, lv),
    band: jargon.band(jargon.scoreDeltaE(e.probe.deltaE)),
  }));
}

// ---------- design viewer (evidence canvas) ----------
// The evidence canvas embeds the designed screens in iframes; the toolbar
// offers only the viewports the design actually authored (seed truth).
// sessionData.viewer = { screen, vp, bg }.
export const VIEWPORT_WIDTHS = { mobile: 390, tablet: 744, desktop: 1280 };
export const VIEWER_BGS = ['canvas', 'warm', 'slate'];

function viewerFor(sessionData, evidence) {
  const v = sessionData.viewer ?? {};
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
export const screenStub = (surface, vp, prefs = {}) => {
  const e = repo.evidence().find((x) => x.surface === surface);
  const authored = e?.viewports ?? ['mobile'];
  const v = authored.includes(vp) ? vp : authored[0];
  return {
    surface, vp: v, width: VIEWPORT_WIDTHS[v],
    kind: surface?.split('.')[1] ?? surface,
    theme: prefs.theme ?? 'light',
  };
};

// Viewer toolbar/filmstrip act: record the choice, re-render the viewer block.
export const setViewer = (sessionData, query, prefs = {}) => {
  sessionData.viewer = { screen: query.screen, vp: query.vp, bg: query.bg, os: query.os, mode: query.mode };
  return loopContext(sessionData, 'evidence/surfaces', prefs);
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
export const contextFor = (sessionData, ref, lv = 'balanced') => {
  const gates = gatesWithDecisions(sessionData);
  const stages = stagesWithDecisions(gates, lv, sessionData);
  const run = repo.run();
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
    if (id === 'coverage') linked.push({ findings: findingsWithLevel(lv).coverage ?? [] });
    if (id === 'deploy') linked.push({ gates: gates.filter((g) => g.id !== 'design.approval') });
    if (id === 'design') linked.push({ gate: gates.find((g) => g.id === 'design.approval') });
  } else if (kind === 'gate') {
    artifact = gates.find((g) => g.id === id) ?? null;
    if (id === 'build.acceptance') linked.push({ evidence: evidenceWithLevel(lv) }, { stage: stages.find((s) => s.id === 'deploy') });
    if (id === 'design.approval') linked.push({ stages: stages.filter((s) => ['design', 'freeze'].includes(s.id)) });
    if (id === 'ship.confirm') linked.push({ stage: stages.find((s) => s.id === 'deploy') });
  } else if (kind === 'findings') {
    artifact = { gate: id, list: findingsWithLevel(lv)[id] ?? [] };
    linked.push({ stage: stages.find((s) => s.id === id) });
  } else if (kind === 'chart') {
    artifact = repo.chart();
    linked.push({ stages: stages.map((s) => ({ id: s.id, duration: s.duration, state: s.state })) });
  } else if (kind === 'evidence') {
    artifact = evidenceWithLevel(lv);
    linked.push({ stage: stages.find((s) => s.id === 'freeze') });
  } else if (kind === 'log') {
    artifact = { note: 'the whole line, in order' };
  }
  return { artifact, linked, brief };
};

// The stage bar (FAB → floating toolbar) context for the active artifact.
function barFor(ref, parts, t) {
  const [kind, id] = (ref || '').split('/');
  const bar = { kind, hint: t.barHintLog };
  if (kind === 'stage') {
    const s = parts.stages.find((x) => x.id === id);
    bar.stageId = id;
    bar.pauseable = Boolean(s && ['active', 'queued'].includes(s.state));
    bar.resumable = Boolean(s && s.state === 'held');
    bar.cancelable = Boolean(s && ['active', 'queued', 'held'].includes(s.state));
    bar.hint = t.barHintStage;
  } else if (kind === 'gate') bar.hint = t.barHintGate;
  else if (kind === 'findings') bar.hint = t.barHintFindings;
  else if (kind === 'evidence') bar.hint = t.barHintEvidence;
  else if (kind === 'chart') bar.hint = t.barHintChart;
  return bar;
}

// The canvas renders ONE artifact at a time; ref is "kind/id".
function resolveArtifact(ref, { gates, stages, messages, findings, evidence }) {
  const [kind, id] = (ref || DEFAULT_ARTIFACT).split('/');
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
      return { kind, chart: repo.chart(), ref };
    case 'log':
      return { kind, messages, ref };
    case 'evidence':
      return { kind, evidence, ref };
  }
  if (ref !== DEFAULT_ARTIFACT) return resolveArtifact(DEFAULT_ARTIFACT, { gates, stages, messages, findings, evidence });
  return { kind: 'log', messages, ref: DEFAULT_ARTIFACT };
}

export const loopContext = (sessionData = {}, ref = null, prefs = {}) => {
  const lv = jargon.level(prefs);
  const gates = gatesWithDecisions(sessionData);
  const stages = stagesWithDecisions(gates, lv, sessionData);
  const findings = findingsWithLevel(lv);
  const evidence = evidenceWithLevel(lv);
  const parts = { gates, stages, findings, evidence };
  const t = jargon.t(lv);
  const activeArtifact = ref ?? sessionData.currentArtifact ?? DEFAULT_ARTIFACT;
  const filter = RAIL_FILTERS.includes(sessionData.railFilter) ? sessionData.railFilter : 'all';
  const messages = messagesWithSession(sessionData, activeArtifact, lv, parts, filter);
  const thread = (sessionData.threads?.[activeArtifact] ?? [])
    .map((e) => {
      const out = { ...e, text: e.kind === 'agent' ? jargon.pick(e, 'text', lv) : e.text };
      // a chip stays live only while its gate is still decidable; after the
      // act it renders as a historical record, not a button
      if (out.action) {
        const g = gates.find((x) => x.id === out.action.gate);
        out.action = { ...out.action, open: g?.state === 'pending' };
      }
      return out;
    });
  return {
    run: runWithState(sessionData, gates),
    stages,
    gates,
    counts: repo.counts(),
    messages,
    filter,
    timeline: timeline(parts),
    bar: barFor(activeArtifact, parts, t),
    thread,
    activeArtifact,
    artifact: resolveArtifact(activeArtifact, { ...parts, messages }),
    viewer: activeArtifact === 'evidence/surfaces' ? viewerFor(sessionData, evidence) : null,
    barMode: sessionData.barMode ?? null,
    t,
    jargonLevel: lv,
    barOpen: sessionData.barOpenFor === activeArtifact,
  };
};

export const showArtifact = (sessionData, ref, prefs = {}) => {
  sessionData.currentArtifact = ref;
  return loopContext(sessionData, ref, prefs);
};

// The composer round-trip: append the user's message, then a simulated
// agent reply; the reply may pull a new artifact onto the canvas.
export const sendMessage = (sessionData, text, prefs = {}) => {
  const extra = (sessionData.extraMessages ??= []);
  const seq = (sessionData.msgSeq = (sessionData.msgSeq ?? 0) + 1);
  extra.push({ id: `u-${seq}`, at: 'now', from: 'user', text });

  const lower = text.toLowerCase();
  const reply = repo.replies().find((r) => r.match.some((k) => lower.includes(k)))
    ?? repo.replyFallback();
  extra.push({
    id: `a-${seq}`, at: 'now', from: 'agent',
    text: reply.text, textBalanced: reply.textBalanced, textPlain: reply.textPlain,
    artifact: reply.artifact, tone: reply.artifact ? 'action' : null,
  });

  const ref = reply.artifact ?? sessionData.currentArtifact ?? DEFAULT_ARTIFACT;
  return showArtifact(sessionData, ref, prefs);
};

// ---------- stage bar: scoped threads, typed ops, action chips ----------

// A follow-up asked from the stage bar. Lives in the artifact's OWN thread —
// never in the run rail (the rail gets one digest line per thread instead).
// Typed commands fire only reversible ops (pause/cancel/resume) and only on
// this canvas's stage. Approval intents render as action chips: the thread
// proposes, the human taps, provenance mints.
export const askArtifact = (sessionData, ref, text, prefs = {}) => {
  const lv = jargon.level(prefs);
  const thread = threadFor(sessionData, ref);
  const first = thread.length === 0;
  thread.push({ id: `u-${thread.length}`, at: 'now', kind: 'user', text });
  sessionData.barOpenFor = ref;

  // Rail sync = digest on first contact; the card badge counts from then on.
  if (first) narrate(sessionData, { text: `Follow-ups started on ${labelForRef(ref)} — thread on the canvas.`, artifact: ref, tone: null });

  const lower = text.toLowerCase();

  // Typed ops — reversible only, scoped to this canvas's stage.
  const op = typedOp(sessionData, ref, lower, lv);
  if (op) {
    if (op.eventText) logThreadEvent(sessionData, ref, op.eventText);
    thread.push({ id: `a-${thread.length}`, at: 'now', kind: 'agent', text: op.replyText });
    const ctx = loopContext(sessionData, ref, prefs);
    ctx.opFired = op.fired;
    return ctx;
  }

  // Approval/rejection intent on a pending gate → render the chip.
  const [kind, id] = ref.split('/');
  if (kind === 'gate' && /approv|accept|ship|reject|decline/.test(lower)) {
    const gates = gatesWithDecisions(sessionData);
    const gate = gates.find((g) => g.id === id);
    const decision = /reject|decline/.test(lower) ? 'rejected' : 'approved';
    if (gate?.state === 'pending') {
      thread.push({
        id: `a-${thread.length}`, at: 'now', kind: 'agent',
        text: `The word is yours, not mine — the chip below signs ${decision === 'approved' ? 'approval' : 'rejection'} with Touch ID on studio-mac, exactly like the button above.`,
        textPlain: 'I can bring the decision to you, never take it — tap the chip to sign it with Touch ID, same as the button above.',
        action: { gate: id, decision, label: `${decision === 'approved' ? 'Approve' : 'Reject'} ${gate.label.toLowerCase()}` },
      });
    } else {
      thread.push({ id: `a-${thread.length}`, at: 'now', kind: 'agent', text: `${gate?.label ?? 'This gate'} is ${gate?.state ?? 'not reachable'} — nothing to decide here.` });
    }
    return loopContext(sessionData, ref, prefs);
  }

  // Ordinary follow-up: global keyword replies first, then the envelope.
  const reply = repo.replies().find((r) => r.match.some((k) => lower.includes(k)))
    ?? scopedReply(contextFor(sessionData, ref, lv));
  thread.push({
    id: `a-${thread.length}`, at: 'now', kind: 'agent',
    text: reply.text, textBalanced: reply.textBalanced, textPlain: reply.textPlain,
    link: reply.artifact && reply.artifact !== ref ? reply.artifact : null,
  });
  return loopContext(sessionData, ref, prefs);
};

// The scoped fallback: answer from the canvas's own envelope.
function scopedReply(env) {
  const a = env.artifact;
  if (!a) return { ...repo.replyFallback() };
  if (a.summary !== undefined) return { text: `${a.label} — ${a.summary}. ${a.detail ?? ''}`.trim() };
  if (a.context) return { text: `${a.label} — ${a.context}` };
  if (a.list) return { text: `${a.list.length} findings on the ${a.gate} gate — all fixed in attempt 2. Ask about one by name.` };
  if (Array.isArray(a)) {
    const watch = a.filter((e) => e.state === 'watch').length;
    return { text: `${a.length} screens probed against their goldens — ${a.length - watch} pass${watch ? `, ${watch} on watch` : ''}.` };
  }
  if (a.bars) return { text: `Design took two-thirds of the line — every other stage came in under seven minutes.` };
  return { ...repo.replyFallback() };
}

// Shared stage-control overlay (button POST and typed op land here).
function applyStageControl(sessionData, stageId, action) {
  if (action === 'resume') delete (sessionData.stageStates ??= {})[stageId];
  else if (action === 'pause' || action === 'cancel') {
    (sessionData.stageStates ??= {})[stageId] = {
      state: action === 'pause' ? 'held' : 'cancelled',
      summary: action === 'pause' ? 'Paused by you — resume when ready' : 'Cancelled by you',
    };
  }
}

const opEvent = {
  pause: (label) => `You paused ${label} — nothing moves until you resume.`,
  cancel: (label) => `You cancelled ${label} — the stage is off the line.`,
  resume: (label) => `You resumed ${label} — back on the line.`,
};

// Typed ops from the thread: pause/hold, cancel/stop/kill, resume/continue —
// only when the stage's current state actually offers the action.
function typedOp(sessionData, ref, lower, lv) {
  const [kind, id] = ref.split('/');
  if (kind !== 'stage') return null;
  const wants = /\b(pause|hold)\b/.test(lower) ? 'pause'
    : /\b(cancel|stop|kill)\b/.test(lower) ? 'cancel'
    : /\b(resume|continue|unpause)\b/.test(lower) ? 'resume'
    : null;
  if (!wants) return null;
  const stages = stagesWithDecisions(gatesWithDecisions(sessionData), lv, sessionData);
  const s = stages.find((x) => x.id === id);
  if (!s) return null;
  const offered = wants === 'pause' ? ['active', 'queued'].includes(s.state)
    : wants === 'cancel' ? ['active', 'queued', 'held'].includes(s.state)
    : s.state === 'held';
  if (!offered) {
    return { fired: false, eventText: null, replyText: `Nothing to ${wants} — ${s.label} is ${s.state} right now.` };
  }
  applyStageControl(sessionData, id, wants);
  // The act is audit — the rail keeps it even when the thread asked for it.
  narrate(sessionData, {
    text: opEvent[wants](s.label),
    artifact: ref, tone: wants === 'cancel' ? 'fail' : wants === 'pause' ? 'warn' : 'action',
  });
  return { fired: true, eventText: opEvent[wants](s.label), replyText: `Done — ${s.label} ${wants === 'cancel' ? 'is off the line' : wants === 'pause' ? 'holds until you resume' : 'is back on the line'}.` };
}

// Stage control from the stage bar: pause holds a stage, resume releases it,
// cancel takes it off the line. Narrated to the rail AND logged to the
// stage's thread — the thread is the canvas's history.
export const stageControl = (sessionData, stageId, action, prefs = {}) => {
  const stage = repo.stages().find((s) => s.id === stageId);
  const label = stage ? stage.label : stageId;
  if (stage) {
    applyStageControl(sessionData, stageId, action);
    logThreadEvent(sessionData, `stage/${stageId}`, opEvent[action]?.(label) ?? `${label} ${action}.`);
  }
  narrate(sessionData, {
    text: opEvent[action]?.(label) ?? `${label} ${action}.`,
    textPlain: action === 'pause' ? `You paused ${label} — it waits until you resume it.`
      : action === 'cancel' ? `You cancelled ${label} — it won't run in this build.`
      : `You resumed ${label} — it continues.`,
    artifact: stage ? `stage/${stageId}` : null,
    tone: action === 'cancel' ? 'fail' : action === 'pause' ? 'warn' : 'action',
  });
  return showArtifact(sessionData, stage ? `stage/${stageId}` : (sessionData.currentArtifact ?? DEFAULT_ARTIFACT), prefs);
};

// Run control from the rail top bar: pause holds the whole line.
export const runControl = (sessionData, action, prefs = {}) => {
  if (action === 'pause') sessionData.runControl = { paused: true };
  else delete sessionData.runControl;
  narrate(sessionData, {
    text: action === 'pause'
      ? 'Run paused by you — the line holds; anything already waiting on you stays with you.'
      : 'Run resumed — the line picks up where it held.',
    textPlain: action === 'pause'
      ? 'You paused the run — everything holds; decisions waiting on you stay with you.'
      : 'You resumed the run — it continues from where it stopped.',
    artifact: null,
    tone: action === 'pause' ? 'warn' : 'action',
  });
  return loopContext(sessionData, null, prefs);
};

// Gate decision: record it, mint provenance, narrate the consequence — and
// log the act into the gate's own thread (two-way sync: the thread is the
// canvas's history, whether the act came from the button or the chip).
export const decide = (sessionData, gateId, decision, note, prefs = {}) => {
  const decisions = (sessionData.gateDecisions ??= {});
  decisions[gateId] = {
    decision,
    note: note || null,
    hash: decision === 'approved' ? 'c71b…e9d2' : '88d0…f4a6',
  };
  const gate = repo.humanGates().find((g) => g.id === gateId);
  const label = gate ? gate.label.toLowerCase() : gateId;
  const hash = decisions[gateId].hash;
  logThreadEvent(sessionData, `gate/${gateId}`,
    decision === 'approved'
      ? `You approved ${label} — Touch ID · studio-mac · ${hash}`
      : `You rejected ${label}${note ? ` — "${note}"` : ''} · ${hash}`);
  narrate(sessionData, {
    text: decision === 'approved'
      ? `You approved ${label} — provenance ${hash} minted via Touch ID on studio-mac. Deploy stage unlocked.`
      : `You rejected ${label} — run held, back to coverage with your note.`,
    textPlain: decision === 'approved'
      ? `You approved the ${label} — signed with Touch ID on studio-mac and stamped onto this exact content. Shipping is unlocked.`
      : `You rejected the ${label} — the run is held; back to the checks with your note.`,
    artifact: `gate/${gateId}`,
    tone: decision === 'approved' ? 'action' : 'fail',
  });
  return showArtifact(sessionData, `gate/${gateId}`, prefs);
};
