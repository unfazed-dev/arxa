// DesignFacade — composes the design fixture with session-scoped state
// (the artboard on the canvas, per-screen threads, chat checkpoints, drift
// rechecks) into exactly what the design viewmodels need.
// Every string passes through the jargon facade at the reader's level;
// static view copy lives in the COPY table below (same rule as jargon.js).
import * as repo from '../repositories/design_repository.js';
import * as jargon from './jargon.js';

export const DEFAULT_SCREEN = 'build.loop';

// All design-tab ephemeral UI state lives behind one namespace so it never
// collides with the build/intake surfaces sharing the session.
export const design = (sessionData) => (sessionData.design ??= {});

// ---------- static view copy, leveled (jargon rule: 3 variants) ----------
const COPY = {
  protoFoot: {
    technical: 'Shots are the frozen goldens — structure carried, not pixels',
    balanced: 'These snapshots are the frozen goldens — structure, not pixels',
    plain: 'These snapshots are the approved reference — the layout matters, not decoration',
  },
  barHintScreen: {
    technical: 'Scoped to this artboard — rungs, kit coverage, freeze state.',
    balanced: 'Ask about this artboard — rungs, kit, or the freeze.',
    plain: 'Ask anything about this screen — sizes, parts, or the approval.',
  },
  chatHeadline: {
    technical: 'One surface in context — the rest dim',
    balanced: 'One screen in context — the rest dim',
    plain: 'Work on one screen at a time — the rest fade back',
  },
  chatLede: {
    technical: 'Hard tool-gating: edit-layout · restyle · adjust-states · regenerate — nothing outside this surfaceId is reachable.',
    balanced: 'Only this screen’s tools are live: edit-layout, restyle, adjust-states, regenerate.',
    plain: 'You can only change this screen here — layout, style, states, or regenerate. Nothing else is in scope.',
  },
  ctxChipNote: {
    technical: 'context: this surfaceId’s spec — never the whole app',
    balanced: 'context: this screen’s spec — never the whole app',
    plain: 'the chat only sees this screen — never the whole app',
  },
  staleNote: {
    technical: 'Frozen under frz_9c41e2 — edits land as checkpoints and flag this screen’s goldens stale until re-approval.',
    balanced: 'This screen is frozen — edits save as checkpoints and flag it as drift until you re-approve.',
    plain: 'This screen is part of the approved design — changes are saved and marked as drift until you approve them again.',
  },
  pickPrompt: {
    technical: 'Pick a surface — context scopes to its spec, tools gate to its surfaceId.',
    balanced: 'Pick a screen — the chat scopes to its spec only.',
    plain: 'Pick a screen on the left — the chat will only work on that one.',
  },
  freezeLede: {
    technical: 'Approval binds to the design hash — a post-approval change goes stale loudly, never silently.',
    balanced: 'The approval signs this exact design — any change after it is flagged loudly.',
    plain: 'You approved this exact design — if anything changes after that, it is clearly marked out-of-date.',
  },
  traceEyebrow: {
    technical: 'approvals & provenance · brief → approval → manifest',
    balanced: 'approvals & provenance · brief → approval → freeze',
    plain: 'what happened, in order · brief → your approval → locked',
  },
  traceabilityEyebrow: {
    technical: 'brief → surface → code traceability',
    balanced: 'story → screen → code traceability',
    plain: 'every screen traces to a story and its code',
  },
  driftLede: {
    technical: 'Goldens hashed at freeze; the drift check compares every shot against the manifest.',
    balanced: 'Every snapshot was fingerprinted at freeze; the drift check compares them against the manifest.',
    plain: 'Every approved snapshot was fingerprinted; this check proves nothing has moved since.',
  },
};

const t = (lv) =>
  Object.fromEntries(Object.entries(COPY).map(([k, v]) => [k, v[lv] ?? v.technical]));

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

// ---------- the design line (shell timeline) ----------
function timeline(currentId) {
  const items = repo.line().map((i) => ({ ...i, ref: i.id }));
  return { items, currentId };
}

// ---------- prototype surface ----------

const threadFor = (d, ref) => (d.threads ??= {})[ref] ??= [];

function screenCard(s, d) {
  const threadCount = (d.threads?.[`screen/${s.id}`] ?? []).filter((e) => e.kind === 'user').length;
  return {
    type: 'screen', state: s.state, threadCount,
    detail: `${s.rungs.length} rungs · kit ${s.kit}% · ${s.wire}`,
  };
}

// ---------- the shared design viewer (ui/common/design_viewer.html) ----------
// Artboards render in the same screen stage as the build evidence canvas;
// default mode is rungs — the 3-width triptych, now as live renders.
const RUNG_VP = { 390: 'mobile', 744: 'tablet', 1280: 'desktop' };

function viewerFor(d, activeId) {
  const v = d.viewer ?? {};
  const screens = repo.screens().map((s) => ({
    id: s.id, label: s.label, state: s.state,
    viewports: s.rungs.map((r) => ({ vp: RUNG_VP[r.width] ?? 'mobile', width: r.width, rung: r.rung, note: r.note, shot: r.shot })),
  }));
  const screen = screens.find((s) => s.id === activeId) ?? screens[0];
  const authored = screen ? screen.viewports.map((x) => x.vp) : ['mobile'];
  const vp = authored.includes(v.vp) ? v.vp : authored[0];
  const bg = ['canvas', 'warm', 'slate'].includes(v.bg) ? v.bg : 'canvas';
  const os = ['ios', 'android'].includes(v.os) ? v.os : 'ios';
  const mode = ['single', 'rungs'].includes(v.mode) ? v.mode : 'rungs';
  return {
    screens, active: screen?.id, vp, bg, os, mode, strip: true,
    base: '/design/viewer', stubBase: '/build/screens/',
  };
}

// Viewer toolbar/strip act: record the choice, keep the artboard in sync.
export const setViewer = (sessionData, query, prefs = {}) => {
  const d = design(sessionData);
  d.viewer = { screen: query.screen, vp: query.vp, bg: query.bg, os: query.os, mode: query.mode };
  if (query.screen && repo.screen(query.screen)) d.currentScreen = query.screen;
  return protoContext(sessionData, query.screen ?? null, prefs);
};

export const protoContext = (sessionData = {}, screenId = null, prefs = {}) => {
  const lv = jargon.level(prefs);
  const d = design(sessionData);
  const active = repo.screen(screenId) ? screenId : (d.currentScreen ?? DEFAULT_SCREEN);
  const filter = d.railFilter ?? 'all';
  const screens = repo.screens()
    .filter((s) => filter === 'all' || s.epic === filter)
    .map((s) => ({
      ...s,
      summary: jargon.pick(s, 'summary', lv),
      active: s.id === active,
      card: screenCard(s, d),
    }));
  const screen = repo.screen(active);
  const thread = (d.threads?.[`screen/${active}`] ?? [])
    .map((e) => ({ ...e, text: e.kind === 'agent' ? jargon.pick(e, 'text', lv) : e.text }));
  return {
    // rungsLabel precomputed: fragment imports re-execute page blocks with an
    // empty context, and a join filter on undefined throws — plain access is safe.
    run: { ...repo.run(), rungsLabel: repo.run().policy.rungs.join('/') },
    counts: repo.counts(),
    epics: repo.epics(),
    filter,
    screens,
    screen: { ...screen, summary: jargon.pick(screen, 'summary', lv) },
    viewer: viewerFor(d, active),
    thread,
    barOpen: d.barOpenFor === active,
    timeline: timeline('prototype'),
    t: t(lv),
    jargonLevel: lv,
  };
};

export const showScreen = (sessionData, screenId, prefs = {}) => {
  if (repo.screen(screenId)) design(sessionData).currentScreen = screenId;
  return protoContext(sessionData, screenId, prefs);
};

export const setRailFilter = (sessionData, filter, prefs = {}) => {
  design(sessionData).railFilter = filter;
  return protoContext(sessionData, null, prefs);
};

// Stage-bar follow-up on an artboard: lives in the screen's own thread.
export const askScreen = (sessionData, screenId, text, prefs = {}) => {
  const d = design(sessionData);
  const ref = `screen/${screenId}`;
  const thread = threadFor(d, ref);
  thread.push({ id: `u-${thread.length}`, at: 'now', kind: 'user', text });
  d.barOpenFor = screenId;

  const screen = repo.screen(screenId);
  const lower = text.toLowerCase();
  const found = repo.protoReplies().find((r) => r.match.some((k) => lower.includes(k)));
  const reply = fillReply(found ?? repo.protoFallback(), { ...screen, summary: jargon.pick(screen, 'summary', jargon.level(prefs)) });
  thread.push({ id: `a-${thread.length}`, at: 'now', kind: 'agent', ...reply });
  return protoContext(sessionData, screenId, prefs);
};

// ---------- screen chat surface ----------

export const chatContext = (sessionData = {}, screenId = null, prefs = {}) => {
  const lv = jargon.level(prefs);
  const d = design(sessionData);
  if (screenId === 'none') delete d.chatScreen;
  else if (repo.screen(screenId)) d.chatScreen = screenId;
  const active = repo.screen(d.chatScreen) ? d.chatScreen : null;

  const screens = repo.screens().map((s) => ({
    ...s,
    summary: jargon.pick(s, 'summary', lv),
    active: s.id === active,
  }));

  let thread = [];
  let checkpoints = [];
  let screen = null;
  if (active) {
    screen = { ...repo.screen(active), summary: jargon.pick(repo.screen(active), 'summary', lv) };
    const cps = [
      ...(repo.checkpoints()[active] ?? []),
      ...(d.chatCheckpoints?.[active] ?? []),
    ].map((cp) => ({
      ...cp,
      summary: jargon.pick(cp, 'summary', lv),
      reverted: (d.reverted ?? []).includes(cp.id),
    }));
    checkpoints = cps;
    const cpById = Object.fromEntries(cps.map((cp) => [cp.id, cp]));
    thread = [
      ...(repo.chatThreads()[active] ?? []),
      ...(d.chatThreads?.[active] ?? []),
    ].map((m) => ({
      ...m,
      text: m.from === 'user' ? m.text : jargon.pick(m, 'text', lv),
      checkpoint: m.cp ? cpById[m.cp] ?? null : null,
    }));
  }

  return {
    run: repo.run(),
    screens,
    screen,
    thread,
    checkpoints,
    timeline: timeline('refine'),
    t: t(lv),
    jargonLevel: lv,
  };
};

export const selectScreen = (sessionData, screenId, prefs = {}) =>
  chatContext(sessionData, screenId, prefs);

// Send: append the user's message, then a simulated reply scoped to this
// screen; a reply carrying a checkpoint mints one (cp-N continues the
// screen's numbering) and attaches it to the message.
export const sendChat = (sessionData, screenId, text, prefs = {}) => {
  const lv = jargon.level(prefs);
  const d = design(sessionData);
  d.chatScreen = screenId;
  const threads = (d.chatThreads ??= {});
  const thread = threads[screenId] ??= [];
  thread.push({ at: 'now', from: 'user', text });

  const screen = repo.screen(screenId);
  const lower = text.toLowerCase();
  const found = repo.chatReplies().find((r) => r.match.some((k) => lower.includes(k)));
  const reply = fillReply(found ?? repo.chatFallback(), screen);

  let cpId = null;
  if (reply.checkpoint) {
    const cps = (d.chatCheckpoints ??= {});
    const list = cps[screenId] ??= [];
    const n = (repo.checkpoints()[screenId] ?? []).length + list.length + 1;
    cpId = `cp-${n}`;
    list.push({
      id: cpId, n, at: 'now',
      summary: reply.checkpoint,
      summaryPlain: reply.checkpointPlain ?? reply.checkpoint,
      before: reply.before, after: reply.after,
    });
  }
  thread.push({ at: 'now', from: 'agent', text: reply.text, textBalanced: reply.textBalanced, textPlain: reply.textPlain, cp: cpId });
  return chatContext(sessionData, screenId, prefs);
};

// One-tap revert: the checkpoint stays rendered as history, flagged reverted,
// and the act is logged into the thread — the thread is the screen's history.
export const revertCheckpoint = (sessionData, screenId, cpId, prefs = {}) => {
  const d = design(sessionData);
  const all = [...(repo.checkpoints()[screenId] ?? []), ...(d.chatCheckpoints?.[screenId] ?? [])];
  const cp = all.find((x) => x.id === cpId);
  if (cp && !(d.reverted ??= []).includes(cpId)) {
    d.reverted.push(cpId);
    const threads = (d.chatThreads ??= {});
    const thread = threads[screenId] ??= [];
    thread.push({ at: 'now', from: 'agent', kind: 'event', text: `You reverted to ${cpId} — ${cp.summary}. Later checkpoints stay on record.` });
  }
  return chatContext(sessionData, screenId, prefs);
};

// ---------- freeze & trace surface ----------

export const freezeContext = (sessionData = {}, prefs = {}) => {
  const lv = jargon.level(prefs);
  const d = design(sessionData);
  const manifest = { ...repo.manifest(), structure: jargon.pick(repo.manifest(), 'structure', lv) };
  const rechecks = d.driftRechecks ?? 0;
  return {
    run: repo.run(),
    manifest,
    trace: repo.trace().map((e) => ({ ...e, text: jargon.pick(e, 'text', lv) })),
    traceability: repo.traceability(),
    drift: {
      ...repo.drift(),
      history: repo.drift().history.map((e) => ({ ...e, text: jargon.pick(e, 'text', lv) })),
    },
    rechecks,
    toast: rechecks ? `Drift check #${rechecks + 1} — ${repo.drift().matched} goldens match · clean` : null,
    timeline: timeline('freeze'),
    t: t(lv),
    jargonLevel: lv,
  };
};

export const recheckDrift = (sessionData, prefs = {}) => {
  const d = design(sessionData);
  d.driftRechecks = (d.driftRechecks ?? 0) + 1;
  return freezeContext(sessionData, prefs);
};
