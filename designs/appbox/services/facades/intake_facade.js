// appbox:provenance
// generator: app-box  licence: free  project: 662368770980
// Built with app-box (free tier) — https://appbox.dev
// IntakeFacade — composes the intake fixture (story map, design brief,
// moodboard, question banks, live statuses) with session-scoped state (the
// interview, composer messages, the open artifact, the activity panel view)
// into exactly what the three intake viewmodels need. The intake shell root
// IS a chat: the interview runs in the composer panel, artifacts dock it
// right.
// Leveled fixture strings pass through jargon.pick; static leveled copy
// lives in l10n/app_*.arb and comes in as the runtime translator `t`
// (h.t(c) — level and locale already bound). The locale picks the
// per-locale fixture, en fallback.
import * as repo from '../repositories/intake_repository.js';
import * as jargon from './jargon.js';
import * as agent from './agent_menus.js';
import * as fv from './file_views.js';

export const SURFACES = ['mapping', 'brief', 'moodboard'];

// ---------- session ----------
const S = (sd) => (sd.intake ??= { extra: {}, current: {}, activityView: {}, msgSeq: 0, interview: null });

// The interview: seeded from the fixture, then session-owned.
const interview = (sd, L) => (S(sd).interview ??= JSON.parse(JSON.stringify(repo.initialState(L))));
const isStale = (st) => st.approved && st.approvedVersion !== st.currentVersion;

const approvalFor = (sd, L) => {
  const st = interview(sd, L);
  return { approved: st.approved, stale: isStale(st), approvedVersion: st.approvedVersion, currentVersion: st.currentVersion };
};

// ---------- the interview → chat ----------
function carouselFor(st, t, L) {
  const bank = repo.questionBanks(L)[st.depth] ?? [];
  const firstOpen = bank.find((q) => !st.answers[q.id]);
  return {
    bank: st.depth,
    bankLabel: t('intake.bank.' + st.depth),
    questions: bank.map((q) => {
      const a = st.answers[q.id];
      const state = st.editing === q.id ? 'editing'
        : a ? (a.skipped ? 'skipped' : 'answered')
        : !st.editing && firstOpen && firstOpen.id === q.id ? 'current'
        : 'upcoming';
      return { id: q.id, text: q.text, suggestions: q.suggestions, state, answer: a?.text ?? null };
    }),
  };
}

function mappingChat(sd, t, L) {
  const st = interview(sd, L);
  const msgs = [];
  msgs.push({
    id: 'w', from: 'agent', text: t('welcome'),
    quickReplies: st.depth ? null : ['simple', 'normal', 'advanced'].map((d) => ({ label: t('intake.bank.' + d), action: '/intake/depth', name: 'depth', value: d })),
  });
  if (!st.depth) return msgs;
  msgs.push({ id: 'u-depth', from: 'user', text: t('intake.depthEcho.' + st.depth) });
  msgs.push({ id: 'carousel', from: 'agent', text: t('carouselIntro'), carousel: carouselFor(st, t, L) });
  if (st.generated) {
    const stale = isStale(st);
    msgs.push({
      id: 'gen', from: 'agent', text: t('generated'),
      artifactRef: 'map/full', artifactLabel: t('intake.cta.openStoryMap'),
      nextHref: '/intake/brief', nextLabel: t('intake.cta.readBrief'),
      quickReplies: !st.approved || stale
        ? [{ label: stale ? t('intake.cta.reapproveMap', { version: st.currentVersion }) : t('intake.cta.approveMap'), action: '/intake/approve', name: 'go', value: 'approve' }]
        : null,
    });
    msgs.push({ id: 'next', from: 'agent', text: t('moodboardNext'), nextHref: '/intake/moodboard', nextLabel: t('intake.cta.curateMoodboard') });
    if (st.approved && !stale) msgs.push({ id: 'ok', from: 'agent', text: t('approved'), nextHref: '/design', nextLabel: t('intake.cta.openDesignShell') });
    if (stale) msgs.push({ id: 'stale', from: 'agent', text: t('stale') });
  }
  return msgs;
}

function extrasFor(sd, surface, lv) {
  return (S(sd).extra[surface] ?? []).map((m) => ({
    ...m,
    text: m.from === 'user' ? m.text : jargon.pick(m, 'text', lv),
  }));
}

function chatFor(sd, surface, lv, t, L) {
  if (surface === 'mapping') return [...mappingChat(sd, t, L), ...extrasFor(sd, surface, lv)];
  const intro = {
    mapping: null,
    brief: { id: 'intro', from: 'agent', text: t('chatIntroBrief'), artifactRef: 'doc/full', artifactLabel: t('intake.cta.openBriefStage') },
    moodboard: { id: 'intro', from: 'agent', text: t('chatIntroMoodboard'), artifactRef: 'gallery/all', artifactLabel: t('intake.cta.openGalleryStage') },
  }[surface];
  return [intro, ...extrasFor(sd, surface, lv)];
}

// ---------- canvas artifacts ----------
// The live map: release swimlanes × epic columns, stories carrying pipeline
// status dots, rollups per epic and per release. Display data only —
// docs/design/story-map.json's schema is untouched.
function mapLanes(L) {
  const statuses = repo.statuses(L);
  const withStatus = (s) => ({ ...s, status: statuses[s.id] ?? 'pending' });
  const rollup = (stories) => ({
    total: stories.length,
    done: stories.filter((s) => s.status === 'done').length,
    active: stories.filter((s) => s.status === 'in-progress').length,
    blocked: stories.filter((s) => s.status === 'blocked').length,
  });
  const lanes = [];
  for (const rel of repo.releases(L)) {
    const epics = [];
    const laneStories = [];
    for (const e of repo.epics(L)) {
      const features = [];
      const epicStories = [];
      for (const f of e.features) {
        const stories = f.stories.filter((s) => s.release === rel.name).map(withStatus);
        if (stories.length) { features.push({ name: f.name, stories }); epicStories.push(...stories); }
      }
      if (features.length) epics.push({ name: e.name, features, rollup: rollup(epicStories) });
      laneStories.push(...epicStories);
    }
    lanes.push({ release: { ...rel, rollup: rollup(laneStories) }, epics });
  }
  return lanes;
}

function resolveArtifact(surface, ref, t, L) {
  const c = repo.counts(L);
  const [kind, id] = ref.split('/');
  if (surface === 'mapping') {
    if (kind === 'story') {
      const s = repo.story(id, L);
      if (s) return { kind, story: { ...s, status: repo.statuses(L)[s.id] ?? 'pending' }, ref, backRef: 'map/full' };
    }
    const head = id === 'priorities' ? [t('priHeadline'), t('priLede')] : id === 'releases' ? [t('relHeadline'), t('relLede')] : [t('mapHeadline'), t('mapLede')];
    return { kind: 'map', variant: id || 'full', headline: head[0], lede: head[1], lanes: mapLanes(L), counts: c, ref: `map/${id || 'full'}` };
  }
  if (surface === 'brief') {
    if (kind === 'doc' && id === 'surfaces') {
      return { kind: 'surfaces', headline: t('surfacesHeadline'), lede: t('surfacesLede'), surfaces: repo.brief(L).surfaces, ref };
    }
    return { kind: 'doc', headline: t('briefHeadline'), lede: t('briefLede'), brief: repo.brief(L), releases: repo.releases(L), epics: repo.epics(L), ref: 'doc/full' };
  }
  // moodboard
  if (kind === 'shot') {
    const hit = repo.shot(id, L);
    if (hit) return { kind, ...hit, ref, backRef: `gallery/${hit.board.id}` };
  }
  const mb = repo.moodboard(L);
  const boards = id && id !== 'all' && id !== 'highlights' ? mb.boards.filter((b) => b.id === id) : mb.boards;
  return { kind: 'gallery', headline: t('galleryHeadline'), lede: t('galleryLede'), boards, curated: mb.curated, provenance: mb.provenance, ref: `gallery/${id || 'all'}` };
}

// Short chip label per artifact ref — the chat-head context chip.
function chipLabel(ref, t) {
  const [kind, id] = (ref ?? '').split('/');
  return {
    map: id === 'priorities' ? t('intake.chip.priorities') : id === 'releases' ? t('intake.chip.releases') : t('intake.chip.storyMap'),
    story: t('intake.chip.story', { id }), doc: id === 'surfaces' ? t('intake.chip.surfaceInventory') : t('intake.chip.designBrief'),
    gallery: t('intake.chip.moodboard'), shot: t('intake.chip.capture'),
  }[kind] ?? ref;
}

// ---------- the bottom-bar timeline (read-only) ----------
function timelineFor(sd, surface, t, L) {
  const st = interview(sd, L);
  const stale = isStale(st);
  const unlocked = st.approved && !stale;
  const items = [
    { id: 'interview', kind: 'stage', label: t('screen.label.intake.interview'), state: st.depth ? 'green' : 'active' },
    { id: 'mapping', kind: 'stage', label: t('intake.timeline.storyMap'), state: st.generated ? 'green' : st.depth ? 'active' : 'pending' },
    { id: 'brief', kind: 'stage', label: t('screen.label.intake.brief'), state: st.generated ? 'green' : 'pending' },
    { id: 'moodboard', kind: 'stage', label: t('screen.label.intake.moodboard'), state: st.generated ? 'active' : 'pending' },
    { id: 'intake.approval', kind: 'gate', label: t('intake.timeline.approval'), state: st.approved ? (stale ? 'held' : 'approved') : st.generated ? 'active' : 'pending' },
    { id: 'design', kind: 'stage', label: unlocked ? t('tab.design') : t('intake.timeline.lockedSuffix', { label: t('tab.design') }), state: unlocked ? 'pending' : 'cancelled' },
  ];
  // current = the step actively in progress (first 'active'), never a
  // surface being browsed — the line must read as pipeline truth; the shared
  // timeline macro matches currentId against `ref`, so mirror id → ref
  const withRefs = items.map((i) => ({ ...i, ref: i.id }));
  return { items: withRefs, currentId: (items.find((i) => i.state === 'active') || {}).id ?? null };
}

// ---------- the activity panel views: thread / artifacts / files ----------
const ACTIVITY_VIEWS = [
  { id: 'thread', icon: 'messages-square', label: 'Thread' },
  { id: 'artifacts', icon: 'package', label: 'Artifacts' },
  { id: 'files', icon: 'folder', label: 'Files' },
];

// Panel width steps, per side — one sizing state for the whole intake shell
// (unlike activityView, which is per surface).
const PANEL_SIZES = ['s', 'm', 'l'];
const panelSizeFor = (sd, side) => (PANEL_SIZES.includes(S(sd).panelSize?.[side]) ? S(sd).panelSize[side] : 's');

function activityViewFor(sd, surface, base, lv, t, L) {
  const active = S(sd).activityView[surface] ?? 'thread';
  const views = ACTIVITY_VIEWS.map((v) => ({ ...v, label: t('activityView.' + v.id), href: `${base}/panel?view=${v.id}`, active: v.id === active }));
  let body;
  if (active === 'artifacts') {
    const c = repo.counts(L);
    const ap = approvalFor(sd, L);
    const mapBadges = [
      ap.approved && !ap.stale ? { tone: 'ok', label: t('map.approvedBadge', { version: ap.approvedVersion }) } : null,
      ap.stale ? { tone: 'warn', label: t('badge.stale') } : null,
    ].filter(Boolean);
    body = {
      artifacts: {
        mapping: [
          { ref: 'map/full', title: t('intake.activity.liveStoryMap.title'), detail: t('intake.activity.liveStoryMap.detail', { stories: c.stories, epics: c.epics }), badges: mapBadges },
          { ref: 'map/priorities', title: t('intake.activity.moscow.title'), detail: t('intake.activity.moscow.detail', { must: c.must, should: c.should, could: c.could }), badges: [] },
          { ref: 'map/releases', title: t('intake.activity.releases.title'), detail: repo.releases(L).map((r) => r.name).join(' · '), badges: [] },
        ],
        brief: [
          { ref: 'doc/full', title: t('intake.activity.designBrief.title'), detail: t('intake.activity.designBrief.detail', { count: repo.brief(L).surfaces.length }), badges: [] },
          { ref: 'doc/surfaces', title: t('intake.activity.surfaceInventory.title'), detail: t('intake.activity.surfaceInventory.detail'), badges: [] },
        ],
        moodboard: [
          { ref: 'gallery/all', title: t('intake.activity.moodboard.title'), detail: t('intake.activity.moodboard.detail', { boards: repo.moodboard(L).boards.length, shots: repo.moodboard(L).counts.shots }), badges: [] },
          ...repo.moodboard(L).boards.map((b) => ({ ref: `gallery/${b.id}`, title: b.title, detail: t('intake.activity.board.detail', { count: b.references.length, informs: b.informs }), badges: [] })),
        ],
      }[surface],
    };
  } else if (active === 'files') {
    body = { files: repo.files(L).map((f) => ({ ...f, ...fv.fileLink(f.path, base) })) };
  } else {
    // Seeded narrative + this session's own messages — the activity thread
    // is live, it reacts to what the chat is fed, not a frozen copy.
    body = {
      thread: [
        ...repo.narrative(surface, L).map((m) => ({
          at: m.at,
          text: jargon.pick(m, 'text', lv),
          artifact: m.artifact ?? null,
          artifactLabel: m.artifact ? chipLabel(m.artifact, t) : null,
        })),
        ...extrasFor(sd, surface, lv).map((m) => ({
          at: t('time.now'),
          text: m.text,
          artifact: m.artifactRef ?? null,
          artifactLabel: m.artifactRef ? m.artifactLabel ?? chipLabel(m.artifactRef, t) : null,
        })),
      ],
    };
  }
  return { views, active, label: views.find((v) => v.id === active).label, body };
}

// ---------- context ----------
const BASE = { mapping: '/intake', brief: '/intake/brief', moodboard: '/intake/moodboard' };

export const context = (sd, surface, ref, prefs = {}, t = (k) => k, locale = 'en', fileArg, panelArg) => {
  const L = locale;
  const lv = jargon.level(prefs);
  const s = S(sd);
  const base = BASE[surface];
  // The open file (main panel): ?file=<path> opens, ?file=none closes; an
  // artifact open always clears it — the main panel shows one thing.
  if (fileArg === 'none') (s.currentFile ??= {})[surface] = null;
  else if (fileArg) { (s.currentFile ??= {})[surface] = fileArg; s.current[surface] = null; }
  const currentFile = s.currentFile?.[surface] ?? null;
  // The panel bar (compact/medium): ?panel= picks the single visible content
  // panel and sticks; default main.
  if (['activity', 'main', 'composer'].includes(panelArg)) s.panel = panelArg;
  const panel = s.panel ?? 'main';
  const activeArtifact = currentFile ? null : (ref ?? s.current[surface] ?? null);
  const activity = activityViewFor(sd, surface, base, lv, t, L);
  const chat = chatFor(sd, surface, lv, t, L);
  return {
    surface,
    base,
    project: { name: repo.project(L) },
    eyebrow: t('intake.eyebrow.' + surface),
    composerAction: `${base}/messages`,
    placeholder: t('composer.placeholder.intake'),
    modelMenu: agent.modelMenuFor(sd, base, t),
    threading: chat.some((m) => m.from === 'user'),
    suggestions: {
      mapping: [t('intake.sug.whatsInR1'), t('intake.sug.explainMoscow'), t('intake.sug.whichSurfaces')],
      brief: [t('intake.sug.briefFeedsDesign'), t('intake.sug.whichSurfaces')],
      moodboard: [t('intake.sug.whatToSteal'), t('intake.sug.whichReferences')],
    }[surface],
    chat,
    artifact: activeArtifact ? resolveArtifact(surface, activeArtifact, t, L) : null,
    activeArtifact,
    fileView: currentFile ? fv.fileViewFor(currentFile, `${base}?file=none`) : null,
    panel,
    activityViews: activity.views,
    activityView: activity.active,
    activityLabel: activity.label,
    panelSize: panelSizeFor(sd, 'left'),
    panelSizeHref: `${base}/panel/size/left/`,
    activityBody: activity.body,
    timeline: timelineFor(sd, surface, t, L),
    approval: approvalFor(sd, L),
    jargonLevel: lv,
  };
};

export const showArtifact = (sd, surface, ref, prefs = {}, t = (k) => k, locale = 'en') => {
  S(sd).current[surface] = ref;
  (S(sd).currentFile ??= {})[surface] = null;
  return context(sd, surface, ref, prefs, t, locale);
};

// A file row in the activity panel: open it in the main panel (the mode is
// the server's, from the extension).
export const openFile = (sd, surface, path, prefs = {}, t = (k) => k, locale = 'en') =>
  context(sd, surface, null, prefs, t, locale, path ?? 'none');

// Composer chrome: pick the agent model (shared session state), then
// re-render this surface.
export const setModel = (sd, surface, id, prefs = {}, t = (k) => k, locale = 'en') => {
  agent.setModel(sd, id);
  return context(sd, surface, null, prefs, t, locale);
};

export const setActivityView = (sd, surface, view, prefs = {}, t = (k) => k, locale = 'en') => {
  if (ACTIVITY_VIEWS.some((v) => v.id === view)) S(sd).activityView[surface] = view;
  return context(sd, surface, null, prefs, t, locale);
};

// Panel width grip: one persisted size per side for the whole intake shell.
export const setPanelSize = (sd, surface, side, size, prefs = {}, t = (k) => k, locale = 'en') => {
  if (['left', 'right'].includes(side) && PANEL_SIZES.includes(size)) {
    (S(sd).panelSize ??= {})[side] = size;
  }
  return context(sd, surface, null, prefs, t, locale);
};

// ---------- interview actions ----------
export const chooseDepth = (sd, depth, prefs = {}, t = (k) => k, locale = 'en') => {
  const st = interview(sd, locale);
  if (!st.depth && repo.questionBanks(locale)[depth]) st.depth = depth;
  return context(sd, 'mapping', null, prefs, t, locale);
};

const bankOf = (st, L) => repo.questionBanks(L)[st.depth] ?? [];
const allAnswered = (st, L) => bankOf(st, L).every((q) => st.answers[q.id]);

function record(sd, qid, entry, L) {
  const st = interview(sd, L);
  if (!st.depth || !bankOf(st, L).some((q) => q.id === qid)) return st;
  if (st.generated) st.currentVersion += 1; // post-approval edits move the version
  st.answers[qid] = entry;
  st.editing = null;
  if (allAnswered(st, L)) st.generated = true;
  return st;
}

export const answerQuestion = (sd, qid, text, prefs = {}, t = (k) => k, locale = 'en') => {
  record(sd, qid, { text, skipped: false }, locale);
  return context(sd, 'mapping', null, prefs, t, locale);
};

export const skipQuestion = (sd, qid, prefs = {}, t = (k) => k, locale = 'en') => {
  record(sd, qid, { text: null, skipped: true }, locale);
  return context(sd, 'mapping', null, prefs, t, locale);
};

export const editQuestion = (sd, qid, prefs = {}, t = (k) => k, locale = 'en') => {
  const st = interview(sd, locale);
  if (st.answers[qid]) st.editing = qid;
  return context(sd, 'mapping', null, prefs, t, locale);
};

export const approveMap = (sd, prefs = {}, t = (k) => k, locale = 'en') => {
  const st = interview(sd, locale);
  if (st.generated) {
    st.approved = true;
    st.approvedVersion = st.currentVersion;
  }
  return context(sd, 'mapping', null, prefs, t, locale);
};

// ---------- the composer round-trip ----------
const replyFor = (text, L) => {
  const lower = text.toLowerCase();
  return repo.replies(L).find((r) => r.match.some((k) => lower.includes(k))) ?? repo.replyFallback(L);
};

// Free-text chat: append the user's message and a simulated agent reply; the
// reply may pull an artifact onto the stage (chat docks right).
export const sendMessage = (sd, surface, text, prefs = {}, t = (k) => k, locale = 'en') => {
  const s = S(sd);
  const seq = (s.msgSeq += 1);
  (s.extra[surface] ??= []).push({ id: `u-${seq}`, from: 'user', text });
  const reply = replyFor(text, locale);
  s.extra[surface].push({
    id: `a-${seq}`, from: 'agent',
    text: reply.text, textBalanced: reply.textBalanced, textPlain: reply.textPlain,
    artifactRef: reply.artifact ?? null,
    artifactLabel: reply.artifact ? t('intake.cta.openArtifact', { label: chipLabel(reply.artifact, t) }) : null,
  });
  if (reply.artifact) { s.current[surface] = reply.artifact; (s.currentFile ??= {})[surface] = null; }
  return context(sd, surface, null, prefs, t, locale);
};
