// DesignFacade — composes the design fixture with session-scoped state
// (draft-all acceptance, pinned context chips, the design thread with
// per-screen checkpoints, manifest approval, drift rechecks) into exactly
// what the design viewmodels need.
// Leveled fixture strings pass through jargon.pick; static leveled copy
// lives in l10n/app_*.arb and is rendered by the runtime t() in the
// templates. The locale comes from the request and picks the per-locale
// fixture, en fallback.
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

// ---------- the design line (shell timeline, bottom bar) ----------
function timeline(currentId, L) {
  const items = repo.line(L).map((i) => ({ ...i, ref: i.id }));
  return { items, currentId };
}

// ---------- pinned context ----------

const contextIds = (d, L) => (d.context ?? []).filter((id) => repo.screen(id, L));
const pin = (d, id, L) => {
  if (repo.screen(id, L) && !contextIds(d, L).includes(id)) (d.context ??= []).push(id);
  d.chatCentered = false; // pinning re-docks a chat the user closed to center
  d.trayOpen = true;      // …and auto-expands the composer's context tray
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

// ---------- the shared design viewer (ui/common/design_viewer.html) ----------
// Board mode (the default once drafted): every screen as an artboard with its
// rungs side by side at real device sizes; the filmstrip is the context
// picker. Single/rungs stay for one-screen deep looks.
const RUNG_VP = { 390: 'mobile', 744: 'tablet', 1280: 'desktop' };

function viewerFor(d, L, t) {
  const v = d.viewer ?? {};
  const ids = contextIds(d, L);
  const screens = repo.screens(L).map((s) => ({
    id: s.id, label: s.label, state: s.state,
    inContext: ids.includes(s.id),
    dim: ids.length > 0 && !ids.includes(s.id),
    tone: toneFor(s.id, L),
    chips: [{ text: `${s.kit}%`, title: t('design.kitChipTitle', { kit: s.kit, id: s.id }) }],
    viewports: s.rungs.map((r) => ({ vp: RUNG_VP[r.width] ?? 'mobile', width: r.width, rung: r.rung, note: r.note, shot: r.shot })),
  }));
  const active = repo.screen(v.screen, L) ? v.screen : (ids[0] ?? d.currentScreen ?? DEFAULT_SCREEN);
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
export const setViewer = (sessionData, query, prefs = {}, t = (k) => k, locale = 'en') => {
  const d = design(sessionData);
  d.viewer = { screen: query.screen, vp: query.vp, bg: query.bg, os: query.os, mode: query.mode };
  if (query.screen && repo.screen(query.screen, locale)) d.currentScreen = query.screen;
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

  const drafted = d.drafted === true;
  const ids = contextIds(d, L);
  const filter = d.railFilter ?? 'all';
  const railView = ['screens', 'artifacts', 'files'].includes(d.railView) ? d.railView : 'screens';
  const thread = threadFor(d, lv, L);
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
    railView,
    railLabel: t('rail.' + railView),
    railViews: [
      { id: 'screens', icon: 'layout-grid' },
      { id: 'artifacts', icon: 'package' },
      { id: 'files', icon: 'folder' },
    ].map((v) => ({ ...v, label: t('rail.' + v.id), href: `/design/rail/${v.id}`, active: v.id === railView })),
    screens,
    artifacts: repo.artifacts(L),
    files: repo.files(L),
    drafted,
    docked: drafted && d.chatCentered !== true,
    threading: thread.some((m) => m.from === 'user'),
    stageEyebrow: t('design.chat.eyebrow'),
    composerAction: '/design/chat/messages',
    modelMenu: agent.modelMenuFor(sessionData, base, t),
    tray: { open: d.trayOpen !== false, toggleHref: `${base}/tray?state=toggle` },
    strip: stripFor(d, base, L),
    collapseHref: `${base}/close`,
    viewer: viewerFor(d, L, t),
    thread,
    draft: { offer: jargon.pick(repo.draft(L), 'offer', lv), chip: repo.draft(L).chip },
    suggestions: drafted ? refineSuggestions(t) : [{ value: 'draft-all', label: repo.draft(L).chip }],
    placeholder: drafted ? t('composer.placeholder.refine', { label: ctxLabel(d, L, t) }) : t('composer.placeholder.design'),
    timeline: timeline(opts.line ?? 'prototype', L),
    jargonLevel: lv,
  };
};

// Context pin toggle from the filmstrip / artboard chrome / rail card.
// state: 'toggle' | 'on' | 'off'.
export const toggleContext = (sessionData, screenId, state = 'toggle', prefs = {}, t = (k) => k, locale = 'en') => {
  const d = design(sessionData);
  const on = state === 'toggle' ? !contextIds(d, locale).includes(screenId) : state === 'on';
  if (on) pin(d, screenId, locale); else unpin(d, screenId, locale);
  if (repo.screen(screenId, locale)) d.currentScreen = screenId;
  return stageContext(sessionData, {}, prefs, t, locale);
};

// Composer chrome: pick the agent model, or collapse/expand the context
// tray. Both mutate session state; callers re-render their own surface
// context (freeze ignores the returned stage context, same as closeChat).
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

// The close act on the docked chat: unpin every screen and recenter the
// chat (d.chatCentered — any later pin re-docks it). Freeze ignores the
// returned stage context and re-renders from freezeContext instead.
export const closeChat = (sessionData, opts = {}, prefs = {}, t = (k) => k, locale = 'en') => {
  const d = design(sessionData);
  d.context = [];
  d.chatCentered = true;
  return stageContext(sessionData, opts, prefs, t, locale);
};

export const setRailFilter = (sessionData, filter, prefs = {}, t = (k) => k, locale = 'en') => {
  design(sessionData).railFilter = filter;
  return stageContext(sessionData, {}, prefs, t, locale);
};

export const setRailView = (sessionData, view, prefs = {}, t = (k) => k, locale = 'en') => {
  design(sessionData).railView = view;
  return stageContext(sessionData, {}, prefs, t, locale);
};

// The single composer path (chat-Centric Layout: no inputs outside the chat).
// 'draft-all' accepts the one-pass draft; 'approve' signs the manifest; any
// other text refines the pinned screens and may mint one checkpoint per
// pinned screen.
export const sendChat = (sessionData, text, prefs = {}, pinId = null, t = (k) => k, locale = 'en') => {
  const L = locale;
  const d = design(sessionData);
  if (pinId) pin(d, pinId, L);
  const thread = (d.designThread ??= []);

  if (text === 'draft-all') {
    thread.push({ at: 'now', from: 'user', text: repo.draft(L).chip });
    d.drafted = true;
    thread.push({ at: 'now', from: 'agent', text: repo.draft(L).done, textPlain: repo.draft(L).donePlain });
    return stageContext(sessionData, {}, prefs, t, L);
  }
  if (text === 'approve') return approveManifest(sessionData, prefs, t, L);

  thread.push({ at: 'now', from: 'user', text });
  const ids = contextIds(d, L);
  if (!ids.length) {
    thread.push({ at: 'now', from: 'agent', text: repo.noContext(L).text, textPlain: repo.noContext(L).textPlain });
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

export const freezeContext = (sessionData = {}, prefs = {}, t = (k) => k, locale = 'en') => {
  const L = locale;
  const stage = stageContext(sessionData, { line: 'freeze', base: '/design/freeze' }, prefs, t, L);
  const lv = stage.jargonLevel;
  const d = design(sessionData);
  const ap = repo.approval(L);
  const approved = d.approved ?? ap.state === 'approved';
  const manifest = { ...repo.manifest(L), structure: jargon.pick(repo.manifest(L), 'structure', lv) };
  const rechecks = d.driftRechecks ?? 0;
  return {
    ...stage,
    docked: d.chatCentered !== true,
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
