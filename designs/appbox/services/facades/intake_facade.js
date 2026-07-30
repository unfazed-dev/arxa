// IntakeFacade — composes the intake fixture (story map, design brief,
// moodboard, question banks, live statuses) with session-scoped state (the
// interview, composer messages, the open artifact, the rail view) into
// exactly what the three intake viewmodels need. The intake shell root IS a
// chat: the interview runs in the chat stage, artifacts dock it right.
// Leveled fixture strings pass through jargon.pick; static leveled copy
// lives in l10n/app_*.arb and comes in as the runtime translator `t`
// (h.t(c) — level and locale already bound). The locale picks the
// per-locale fixture, en fallback.
import * as repo from '../repositories/intake_repository.js';
import * as jargon from './jargon.js';
import * as agent from './agent_menus.js';

export const SURFACES = ['mapping', 'brief', 'moodboard'];

// ---------- session ----------
const S = (sd) => (sd.intake ??= { extra: {}, current: {}, railView: {}, msgSeq: 0, interview: null });

// The interview: seeded from the fixture, then session-owned.
const interview = (sd, L) => (S(sd).interview ??= JSON.parse(JSON.stringify(repo.initialState(L))));
const isStale = (st) => st.approved && st.approvedVersion !== st.currentVersion;

const approvalFor = (sd, L) => {
  const st = interview(sd, L);
  return { approved: st.approved, stale: isStale(st), approvedVersion: st.approvedVersion, currentVersion: st.currentVersion };
};

// ---------- the interview → chat ----------
const DEPTH_ECHO = {
  simple: 'Simple — just the essentials.',
  normal: 'Normal — the usual depth.',
  advanced: 'Advanced — ask me everything.',
};

function carouselFor(st, L) {
  const bank = repo.questionBanks(L)[st.depth] ?? [];
  const firstOpen = bank.find((q) => !st.answers[q.id]);
  return {
    bank: st.depth,
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
    quickReplies: st.depth ? null : ['simple', 'normal', 'advanced'].map((d) => ({ label: d, action: '/intake/depth', name: 'depth', value: d })),
  });
  if (!st.depth) return msgs;
  msgs.push({ id: 'u-depth', from: 'user', text: DEPTH_ECHO[st.depth] ?? st.depth });
  msgs.push({ id: 'carousel', from: 'agent', text: t('carouselIntro'), carousel: carouselFor(st, L) });
  if (st.generated) {
    const stale = isStale(st);
    msgs.push({
      id: 'gen', from: 'agent', text: t('generated'),
      artifactRef: 'map/full', artifactLabel: 'open the live story map',
      nextHref: '/intake/brief', nextLabel: 'read the brief',
      quickReplies: !st.approved || stale
        ? [{ label: stale ? `re-approve the story map (v${st.currentVersion})` : 'approve the story map', action: '/intake/approve', name: 'go', value: 'approve' }]
        : null,
    });
    msgs.push({ id: 'next', from: 'agent', text: t('moodboardNext'), nextHref: '/intake/moodboard', nextLabel: 'curate the moodboard' });
    if (st.approved && !stale) msgs.push({ id: 'ok', from: 'agent', text: t('approved'), nextHref: '/design', nextLabel: 'open the Design shell' });
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
    brief: { id: 'intro', from: 'agent', text: t('chatIntroBrief'), artifactRef: 'doc/full', artifactLabel: 'open the brief on the stage' },
    moodboard: { id: 'intro', from: 'agent', text: t('chatIntroMoodboard'), artifactRef: 'gallery/all', artifactLabel: 'open the gallery on the stage' },
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
function chipLabel(ref) {
  const [kind, id] = (ref ?? '').split('/');
  return {
    map: id === 'priorities' ? 'priorities' : id === 'releases' ? 'releases' : 'story map',
    story: `story ${id}`, doc: id === 'surfaces' ? 'surface inventory' : 'design brief',
    gallery: 'moodboard', shot: 'capture',
  }[kind] ?? ref;
}

// ---------- the bottom-bar timeline (read-only) ----------
function timelineFor(sd, surface, L) {
  const st = interview(sd, L);
  const stale = isStale(st);
  const unlocked = st.approved && !stale;
  const items = [
    { id: 'interview', kind: 'stage', label: 'Interview', state: st.depth ? 'green' : 'active' },
    { id: 'mapping', kind: 'stage', label: 'Story map', state: st.generated ? 'green' : st.depth ? 'active' : 'pending' },
    { id: 'brief', kind: 'stage', label: 'Brief', state: st.generated ? 'green' : 'pending' },
    { id: 'moodboard', kind: 'stage', label: 'Moodboard', state: st.generated ? 'active' : 'pending' },
    { id: 'intake.approval', kind: 'gate', label: 'Approval', state: st.approved ? (stale ? 'held' : 'approved') : st.generated ? 'active' : 'pending' },
    { id: 'design', kind: 'stage', label: unlocked ? 'Design' : 'Design · locked', state: unlocked ? 'pending' : 'cancelled' },
  ];
  // current = the step actively in progress (first 'active'), never a
  // surface being browsed — the line must read as pipeline truth; the shared
  // timeline macro matches currentId against `ref`, so mirror id → ref
  const withRefs = items.map((i) => ({ ...i, ref: i.id }));
  return { items: withRefs, currentId: (items.find((i) => i.state === 'active') || {}).id ?? null };
}

// ---------- the left multi-view rail: thread / artifacts / files ----------
const RAIL_VIEWS = [
  { id: 'thread', icon: 'messages-square', label: 'Thread' },
  { id: 'artifacts', icon: 'package', label: 'Artifacts' },
  { id: 'files', icon: 'folder', label: 'Files' },
];

function railViewFor(sd, surface, base, lv, t, L) {
  const active = S(sd).railView[surface] ?? 'thread';
  const views = RAIL_VIEWS.map((v) => ({ ...v, label: t('rail.' + v.id), href: `${base}/rail?view=${v.id}`, active: v.id === active }));
  let body;
  if (active === 'artifacts') {
    const c = repo.counts(L);
    const ap = approvalFor(sd, L);
    const mapBadges = [
      ap.approved && !ap.stale ? { tone: 'ok', label: `approved · v${ap.approvedVersion}` } : null,
      ap.stale ? { tone: 'warn', label: 'changed since approval' } : null,
    ].filter(Boolean);
    body = {
      artifacts: {
        mapping: [
          { ref: 'map/full', title: 'Live story map', detail: `${c.stories} stories · ${c.epics} epics · status dots live`, badges: mapBadges },
          { ref: 'map/priorities', title: 'MoSCoW priorities', detail: `${c.must} must · ${c.should} should · ${c.could} could`, badges: [] },
          { ref: 'map/releases', title: 'Release swimlanes', detail: repo.releases(L).map((r) => r.name).join(' · '), badges: [] },
        ],
        brief: [
          { ref: 'doc/full', title: 'Design brief', detail: `${repo.brief(L).surfaces.length} surfaces traced · generated`, badges: [] },
          { ref: 'doc/surfaces', title: 'Surface inventory', detail: 'the table the designer consumes', badges: [] },
        ],
        moodboard: [
          { ref: 'gallery/all', title: 'The moodboard', detail: `${repo.moodboard(L).boards.length} boards · ${repo.moodboard(L).counts.shots} shots`, badges: [] },
          ...repo.moodboard(L).boards.map((b) => ({ ref: `gallery/${b.id}`, title: b.title, detail: `${b.references.length} references · informs ${b.informs}`, badges: [] })),
        ],
      }[surface],
    };
  } else if (active === 'files') {
    body = { files: repo.files(L) };
  } else {
    body = {
      thread: repo.narrative(surface, L).map((m) => ({
        at: m.at,
        text: jargon.pick(m, 'text', lv),
        artifact: m.artifact ?? null,
        artifactLabel: m.artifact ? chipLabel(m.artifact) : null,
      })),
    };
  }
  return { views, active, label: views.find((v) => v.id === active).label, body };
}

// ---------- context ----------
const BASE = { mapping: '/intake', brief: '/intake/brief', moodboard: '/intake/moodboard' };

export const context = (sd, surface, ref, prefs = {}, t = (k) => k, locale = 'en') => {
  const L = locale;
  const lv = jargon.level(prefs);
  const s = S(sd);
  const base = BASE[surface];
  const activeArtifact = ref ?? s.current[surface] ?? null;
  const docked = !!activeArtifact;
  const rail = railViewFor(sd, surface, base, lv, t, L);
  const chat = chatFor(sd, surface, lv, t, L);
  return {
    surface,
    base,
    project: { name: repo.project(L) },
    eyebrow: { mapping: 'intake · interview', brief: 'intake · brief', moodboard: 'intake · moodboard' }[surface],
    composerAction: `${base}/messages`,
    placeholder: 'Message the intake agent…',
    modelMenu: agent.modelMenuFor(sd, base),
    threading: chat.some((m) => m.from === 'user'),
    suggestions: {
      mapping: ["What's in R1?", 'Explain MoSCoW', 'Which surfaces trace?'],
      brief: ['How does the brief feed design?', 'Which surfaces trace?'],
      moodboard: ['What should we steal?', 'Which references made the board?'],
    }[surface],
    chat,
    docked,
    artifact: docked ? resolveArtifact(surface, activeArtifact, t, L) : null,
    activeArtifact,
    chips: docked ? [{ id: activeArtifact, label: chipLabel(activeArtifact), removeHref: `${base}/close` }] : [],
    collapseHref: docked ? `${base}/close` : null,
    railViews: rail.views,
    railView: rail.active,
    railLabel: rail.label,
    railBody: rail.body,
    timeline: timelineFor(sd, surface, L),
    approval: approvalFor(sd, L),
    jargonLevel: lv,
  };
};

export const showArtifact = (sd, surface, ref, prefs = {}, t = (k) => k, locale = 'en') => {
  S(sd).current[surface] = ref;
  return context(sd, surface, ref, prefs, t, locale);
};

// Composer chrome: pick the agent model (shared session state), then
// re-render this surface.
export const setModel = (sd, surface, id, prefs = {}, t = (k) => k, locale = 'en') => {
  agent.setModel(sd, id);
  return context(sd, surface, null, prefs, t, locale);
};

export const closeArtifact = (sd, surface, prefs = {}, t = (k) => k, locale = 'en') => {
  S(sd).current[surface] = null;
  return context(sd, surface, null, prefs, t, locale);
};

export const setRailView = (sd, surface, view, prefs = {}, t = (k) => k, locale = 'en') => {
  if (RAIL_VIEWS.some((v) => v.id === view)) S(sd).railView[surface] = view;
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
    artifactLabel: reply.artifact ? `open the ${chipLabel(reply.artifact)}` : null,
  });
  if (reply.artifact) s.current[surface] = reply.artifact;
  return context(sd, surface, null, prefs, t, locale);
};
