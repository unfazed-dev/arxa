// DesignFacade — composes the design fixture with session-scoped state
// (draft-all acceptance, pinned context chips, the design thread with
// per-screen checkpoints, manifest approval, drift rechecks) into exactly
// what the design viewmodels need.
// Every string passes through the jargon facade at the reader's level;
// static view copy lives in the COPY table below (same rule as jargon.js).
import * as repo from '../repositories/design_repository.js';
import * as jargon from './jargon.js';
import * as agent from './agent_menus.js';

export const DEFAULT_SCREEN = 'build.loop';

// All design-tab ephemeral UI state lives behind one namespace so it never
// collides with the build/intake surfaces sharing the session.
export const design = (sessionData) => (sessionData.design ??= {});

// Context chip tones — stable per screen (fixture order), so a chip's colour
// always matches its canvas outline regardless of pin order. The first four
// names are chat.css's palette (chips get --ctx AND --ctx-soft there); blue
// and ember extend it in viewer.css for 11 screens with fewer collisions.
const TONES = ['cyan', 'violet', 'olive', 'amber', 'blue', 'ember'];
const toneFor = (id) => {
  const i = repo.screens().findIndex((s) => s.id === id);
  return TONES[(i < 0 ? 0 : i) % TONES.length];
};

// ---------- static view copy, leveled (jargon rule: 3 variants) ----------
const COPY = {
  protoFoot: {
    technical: 'Shots are the frozen goldens — structure carried, not pixels',
    balanced: 'These snapshots are the frozen goldens — structure, not pixels',
    plain: 'These snapshots are the approved reference — the layout matters, not decoration',
  },
  ctxNote: {
    technical: 'context: the pinned surfaceIds’ specs — never the whole app',
    balanced: 'context: the pinned screens’ specs — never the whole app',
    plain: 'the chat only sees the pinned screens — never the whole app',
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

// ---------- the design line (shell timeline, bottom bar) ----------
function timeline(currentId) {
  const items = repo.line().map((i) => ({ ...i, ref: i.id }));
  return { items, currentId };
}

// ---------- pinned context ----------

const contextIds = (d) => (d.context ?? []).filter((id) => repo.screen(id));
const pin = (d, id) => {
  if (repo.screen(id) && !contextIds(d).includes(id)) (d.context ??= []).push(id);
  d.chatCentered = false; // pinning re-docks a chat the user closed to center
  d.trayOpen = true;      // …and auto-expands the composer's context tray
};
const unpin = (d, id) => {
  d.context = contextIds(d).filter((x) => x !== id);
};

// The context filmstrip over the composer: one live thumb per pinned screen.
// base scopes the remove route to the surface being rendered (/design/chat or
// /design/freeze) so the × swaps THAT surface's stage, never another's.
const stripFor = (d, base) =>
  contextIds(d).map((id) => ({
    id,
    label: repo.screen(id).label,
    tone: toneFor(id),
    src: `/build/screens/${id}?vp=mobile`,
    removeHref: `${base}/context/${id}?state=off`,
  }));

const ctxLabel = (d) => contextIds(d).map((id) => repo.screen(id).label).join(' + ') || 'the draft';

// ---------- the shared design viewer (ui/common/design_viewer.html) ----------
// Board mode (the default once drafted): every screen as an artboard with its
// rungs side by side at real device sizes; the filmstrip is the context
// picker. Single/rungs stay for one-screen deep looks.
const RUNG_VP = { 390: 'mobile', 744: 'tablet', 1280: 'desktop' };

function viewerFor(d) {
  const v = d.viewer ?? {};
  const ids = contextIds(d);
  const screens = repo.screens().map((s) => ({
    id: s.id, label: s.label, state: s.state,
    inContext: ids.includes(s.id),
    dim: ids.length > 0 && !ids.includes(s.id),
    tone: toneFor(s.id),
    chips: [{ text: `${s.kit}%`, title: `kit coverage ${s.kit}% — the adaptive primitive layer carries this much of ${s.id}` }],
    viewports: s.rungs.map((r) => ({ vp: RUNG_VP[r.width] ?? 'mobile', width: r.width, rung: r.rung, note: r.note, shot: r.shot })),
  }));
  const active = repo.screen(v.screen) ? v.screen : (ids[0] ?? d.currentScreen ?? DEFAULT_SCREEN);
  const authored = screens.find((s) => s.id === active)?.viewports.map((x) => x.vp) ?? ['mobile'];
  const vp = authored.includes(v.vp) ? v.vp : authored[0];
  const bg = ['canvas', 'warm', 'slate'].includes(v.bg) ? v.bg : 'canvas';
  const os = ['ios', 'android'].includes(v.os) ? v.os : 'ios';
  const mode = ['single', 'rungs', 'board'].includes(v.mode) ? v.mode : 'board';
  return {
    screens, active, vp, bg, os, mode, strip: true,
    base: '/design/viewer', stubBase: '/build/screens/',
    contextBase: '/design/chat/context/',
  };
}

// Viewer toolbar act: record the choice, keep the artboard in sync.
export const setViewer = (sessionData, query, prefs = {}) => {
  const d = design(sessionData);
  d.viewer = { screen: query.screen, vp: query.vp, bg: query.bg, os: query.os, mode: query.mode };
  if (query.screen && repo.screen(query.screen)) d.currentScreen = query.screen;
  return stageContext(sessionData, {}, prefs);
};

// ---------- the design thread (seeded history + session messages) ----------

const allCheckpoints = (d, screenId) =>
  [...(repo.checkpoints()[screenId] ?? []), ...(d.chatCheckpoints?.[screenId] ?? [])]
    .map((cp) => ({ ...cp, reverted: (d.reverted ?? []).includes(cp.id) }));

function threadFor(d, lv) {
  return [...repo.designThread(), ...(d.designThread ?? [])].map((m) => ({
    ...m,
    text: m.from === 'user' ? m.text : jargon.pick(m, 'text', lv),
    link: m.link ?? null,
    cps: (m.cps ?? [])
      .map(({ screen, cp }) => {
        const found = allCheckpoints(d, screen).find((x) => x.id === cp);
        return found ? { screen, ...found, summary: jargon.pick(found, 'summary', lv) } : null;
      })
      .filter(Boolean),
  }));
}

// ---------- the stage context (prototype / chat share it) ----------

const REFINE_SUGGESTIONS = [
  { value: 'edit-layout: stack the rail under the canvas on compact', label: 'edit-layout' },
  { value: 'restyle: make the pending state calmer', label: 'restyle' },
  { value: 'adjust-states: accent token on the pinned screens', label: 'adjust-states' },
  { value: 'regenerate the compact 390 shot', label: 'regenerate' },
];

function screenCard(s, d) {
  const checkpoints = (repo.checkpoints()[s.id] ?? []).length + (d.chatCheckpoints?.[s.id] ?? []).length;
  return {
    type: 'screen', state: s.state, threadCount: checkpoints,
    detail: `${s.rungs.length} rungs · kit ${s.kit}% · ${s.wire}`,
  };
}

// opts: { line (timeline current id), pin (screenId | 'none'), base (route
// prefix for the strip × and the close act — the surface being rendered) }
export const stageContext = (sessionData = {}, opts = {}, prefs = {}) => {
  const lv = jargon.level(prefs);
  const d = design(sessionData);
  if (opts.pin === 'none') d.context = [];
  else if (opts.pin) pin(d, opts.pin);
  const base = opts.base ?? '/design/chat';

  const drafted = d.drafted === true;
  const ids = contextIds(d);
  const filter = d.railFilter ?? 'all';
  const railView = ['screens', 'artifacts', 'files'].includes(d.railView) ? d.railView : 'screens';
  const thread = threadFor(d, lv);
  const screens = repo.screens()
    .filter((s) => filter === 'all' || s.epic === filter)
    .map((s) => ({
      ...s,
      summary: jargon.pick(s, 'summary', lv),
      inContext: ids.includes(s.id),
      tone: toneFor(s.id),
      card: screenCard(s, d),
    }));
  return {
    // rungsLabel precomputed: fragment imports re-execute page blocks with an
    // empty context, and a join filter on undefined throws — plain access is safe.
    run: { ...repo.run(), rungsLabel: repo.run().policy.rungs.join('/') },
    project: { name: repo.run().project },
    counts: repo.counts(),
    epics: repo.epics(),
    filter,
    railView,
    screens,
    artifacts: repo.artifacts(),
    files: repo.files(),
    drafted,
    docked: drafted && d.chatCentered !== true,
    threading: thread.some((m) => m.from === 'user'),
    stageEyebrow: 'design chat',
    composerAction: '/design/chat/messages',
    modelMenu: agent.modelMenuFor(sessionData, base),
    tray: { open: d.trayOpen !== false, toggleHref: `${base}/tray?state=toggle` },
    strip: stripFor(d, base),
    collapseHref: `${base}/close`,
    viewer: viewerFor(d),
    thread,
    draft: { offer: jargon.pick(repo.draft(), 'offer', lv), chip: repo.draft().chip },
    suggestions: drafted ? REFINE_SUGGESTIONS : [{ value: 'draft-all', label: repo.draft().chip }],
    placeholder: drafted ? `Refine ${ctxLabel(d)}…` : 'Message the design agent…',
    timeline: timeline(opts.line ?? 'prototype'),
    t: t(lv),
    jargonLevel: lv,
  };
};

// Context pin toggle from the filmstrip / artboard chrome / rail card.
// state: 'toggle' | 'on' | 'off'.
export const toggleContext = (sessionData, screenId, state = 'toggle', prefs = {}) => {
  const d = design(sessionData);
  const on = state === 'toggle' ? !contextIds(d).includes(screenId) : state === 'on';
  if (on) pin(d, screenId); else unpin(d, screenId);
  if (repo.screen(screenId)) d.currentScreen = screenId;
  return stageContext(sessionData, {}, prefs);
};

// Composer chrome: pick the agent model, or collapse/expand the context
// tray. Both mutate session state; callers re-render their own surface
// context (freeze ignores the returned stage context, same as closeChat).
export const setModel = (sessionData, id, opts = {}, prefs = {}) => {
  agent.setModel(sessionData, id);
  return stageContext(sessionData, opts, prefs);
};

export const setTray = (sessionData, state, opts = {}, prefs = {}) => {
  const d = design(sessionData);
  // the checkbox already flipped locally — mirror it (toggling, never an
  // absolute state: a stale absolute href would desync on double-click)
  d.trayOpen = state === 'toggle' ? !(d.trayOpen !== false) : state !== 'off';
  return stageContext(sessionData, opts, prefs);
};

// The close act on the docked chat: unpin every screen and recenter the
// chat (d.chatCentered — any later pin re-docks it). Freeze ignores the
// returned stage context and re-renders from freezeContext instead.
export const closeChat = (sessionData, opts = {}, prefs = {}) => {
  const d = design(sessionData);
  d.context = [];
  d.chatCentered = true;
  return stageContext(sessionData, opts, prefs);
};

export const setRailFilter = (sessionData, filter, prefs = {}) => {
  design(sessionData).railFilter = filter;
  return stageContext(sessionData, {}, prefs);
};

export const setRailView = (sessionData, view, prefs = {}) => {
  design(sessionData).railView = view;
  return stageContext(sessionData, {}, prefs);
};

// The single composer path (chat-Centric Layout: no inputs outside the chat).
// 'draft-all' accepts the one-pass draft; 'approve' signs the manifest; any
// other text refines the pinned screens and may mint one checkpoint per
// pinned screen.
export const sendChat = (sessionData, text, prefs = {}, pinId = null) => {
  const d = design(sessionData);
  if (pinId) pin(d, pinId);
  const thread = (d.designThread ??= []);

  if (text === 'draft-all') {
    thread.push({ at: 'now', from: 'user', text: repo.draft().chip });
    d.drafted = true;
    thread.push({ at: 'now', from: 'agent', text: repo.draft().done, textPlain: repo.draft().donePlain });
    return stageContext(sessionData, {}, prefs);
  }
  if (text === 'approve') return approveManifest(sessionData, prefs);

  thread.push({ at: 'now', from: 'user', text });
  const ids = contextIds(d);
  if (!ids.length) {
    thread.push({ at: 'now', from: 'agent', text: repo.noContext().text, textPlain: repo.noContext().textPlain });
    return stageContext(sessionData, {}, prefs);
  }

  const first = repo.screen(ids[0]);
  const scope = { label: ctxLabel(d), kit: first.kit, id: ids[0], summary: '' };
  const lower = text.toLowerCase();
  const found = repo.chatReplies().find((r) => r.match.some((k) => lower.includes(k)));
  const reply = fillReply(found ?? repo.chatFallback(), scope);

  // Each message checkpoints the in-context screens only (story map → Chat).
  let cps = [];
  if (reply.checkpoint) {
    cps = ids.map((screenId) => {
      const list = (d.chatCheckpoints ??= {})[screenId] ??= [];
      const n = (repo.checkpoints()[screenId] ?? []).length + list.length + 1;
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
  return stageContext(sessionData, {}, prefs);
};

// One-tap revert: the checkpoint stays rendered as history, flagged reverted,
// and the act is logged into the thread — the thread is the design's history.
export const revertCheckpoint = (sessionData, screenId, cpId, prefs = {}) => {
  const d = design(sessionData);
  const cp = allCheckpoints(d, screenId).find((x) => x.id === cpId);
  if (cp && !(d.reverted ??= []).includes(cpId)) {
    d.reverted.push(cpId);
    (d.designThread ??= []).push({ at: 'now', from: 'agent', kind: 'event', text: `You reverted ${screenId} to ${cpId} — ${cp.summary}. Later checkpoints stay on record.` });
  }
  return stageContext(sessionData, {}, prefs);
};

// ---------- freeze & trace surface ----------

export const freezeContext = (sessionData = {}, prefs = {}) => {
  const stage = stageContext(sessionData, { line: 'freeze', base: '/design/freeze' }, prefs);
  const lv = stage.jargonLevel;
  const d = design(sessionData);
  const ap = repo.approval();
  const approved = d.approved ?? ap.state === 'approved';
  const manifest = { ...repo.manifest(), structure: jargon.pick(repo.manifest(), 'structure', lv) };
  const rechecks = d.driftRechecks ?? 0;
  return {
    ...stage,
    docked: d.chatCentered !== true,
    stageEyebrow: 'freeze & trace',
    composerAction: '/design/freeze/messages',
    suggestions: [{ value: 'approve', label: ap.chip }, ...REFINE_SUGGESTIONS],
    placeholder: approved ? 'Ask about the freeze…' : 'Approve or ask about the freeze…',
    manifest,
    approval: {
      approved,
      lede: jargon.pick(ap, 'lede', lv),
      note: jargon.pick(ap, approved ? 'approvedNote' : 'pendingNote', lv),
    },
    trace: repo.trace().map((e) => ({ ...e, text: jargon.pick(e, 'text', lv) })),
    traceability: repo.traceability(),
    drift: {
      ...repo.drift(),
      history: repo.drift().history.map((e) => ({ ...e, text: jargon.pick(e, 'text', lv) })),
    },
    rechecks,
    toast: rechecks ? `Drift check #${rechecks + 1} — ${repo.drift().matched} goldens match · clean` : null,
  };
};

// The human gate: approving the frozen manifest unlocks the Build stage.
// Idempotent — the act and the confirmation both land in the design thread.
export const approveManifest = (sessionData, prefs = {}) => {
  const d = design(sessionData);
  const thread = (d.designThread ??= []);
  thread.push({ at: 'now', from: 'user', text: repo.approval().chip });
  d.approved = true;
  thread.push({ at: 'now', from: 'agent', text: repo.approval().confirm, textPlain: repo.approval().confirmPlain });
  return freezeContext(sessionData, prefs);
};

export const recheckDrift = (sessionData, prefs = {}) => {
  const d = design(sessionData);
  d.driftRechecks = (d.driftRechecks ?? 0) + 1;
  return freezeContext(sessionData, prefs);
};
