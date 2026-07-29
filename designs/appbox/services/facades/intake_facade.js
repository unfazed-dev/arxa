// IntakeFacade — composes the intake fixture (story map, design brief,
// moodboard, question banks, live statuses) with session-scoped state (the
// interview, composer messages, the open artifact, the rail view) into
// exactly what the three intake viewmodels need. The intake tab root IS a
// chat: the interview runs in the chat stage, artifacts dock it right.
// Every leveled string passes through jargon.
import * as repo from '../repositories/intake_repository.js';
import * as jargon from './jargon.js';
import * as agent from './agent_menus.js';

export const SURFACES = ['mapping', 'brief', 'moodboard'];

// ---------- static leveled copy (the intake chapter of the jargon table) ----------
const COPY = {
  welcome: {
    technical: 'This is the intake interview — I ask, you answer, and the brief, story map and moodboard come out the other end. First: how deep should we go?',
    balanced: 'This is the intake interview — I ask, you answer, and the brief, story map and moodboard come out of it. First: how deep should we go?',
    plain: 'Let\u2019s talk about your app. I\u2019ll ask a few questions, then write the brief, the story map and the moodboard for you. First: how many questions?',
  },
  carouselIntro: {
    technical: 'Here they are — one card per question. Answer in the card, take a suggestion, or skip; swipe sideways to revisit any of them.',
    balanced: 'Here they are — one card per question. Answer in the card, take a suggestion, or skip; scroll sideways to revisit.',
    plain: 'Here are your questions — one per card. Type an answer, tap a suggestion, or skip. Scroll sideways to see them all.',
  },
  generated: {
    technical: 'That\u2019s every question. One pass, all at once: the story map is live below, the design brief is written — no per-screen refine loop here.',
    balanced: 'That\u2019s every question. I generated everything at once: the story map is live, the brief is written.',
    plain: 'All answered. I made two things for you in one go: the story map and the brief.',
  },
  moodboardNext: {
    technical: 'Suggested next step: the moodboard — per-epic reference gathering, real apps to steal from, every shot verified on disk.',
    balanced: 'Suggested next step: the moodboard — real apps to steal from, gathered per epic.',
    plain: 'Next, if you like: the moodboard — real apps worth copying.',
  },
  approved: {
    technical: 'Story map approved — this version is the contract the Design tab starts from. Design is unlocked.',
    balanced: 'Story map approved — design is unlocked and starts from this version.',
    plain: 'Approved. The design step is now open.',
  },
  stale: {
    technical: 'Heads up: answers changed after approval, so the map moved a version. Downstream artifacts carry a \u2018changed since approval\u2019 badge until you re-approve.',
    balanced: 'Heads up: answers changed after approval — the map needs a re-approval.',
    plain: 'You changed answers after approving, so the map needs a fresh approval.',
  },
  mapHeadline: {
    technical: 'Epic → Feature → Story — the whole product on one canvas, live',
    balanced: 'Epic → Feature → Story — the whole product on one canvas, live',
    plain: 'The whole product as one live map — big themes, features, stories',
  },
  mapLede: {
    technical: '66 stories across 9 epics and 22 features. Status dots stream from the pipeline: done, in progress, blocked, pending.',
    balanced: '66 stories across 9 epics. The dots show live pipeline status.',
    plain: '66 stories in 9 themes. Coloured dots show what\u2019s done, moving, or waiting.',
  },
  priHeadline: {
    technical: 'MoSCoW: 46 must · 18 should · 2 could',
    balanced: 'MoSCoW: 46 must · 18 should · 2 could',
    plain: '46 must-haves, 18 should-haves, 2 nice-to-haves',
  },
  priLede: {
    technical: 'Musts gate R1 Dogfood. The 2 coulds — EARS acceptance criteria, shared token edits — wait for R2/R3.',
    balanced: 'Musts gate R1 Dogfood; the 2 coulds wait for later releases.',
    plain: 'Only the must-haves block the first release. The 2 nice-to-haves can wait.',
  },
  relHeadline: {
    technical: 'Three swimlanes: R1 Dogfood · R2 Anywhere · R3 Delight',
    balanced: 'Three releases: R1 Dogfood · R2 Anywhere · R3 Delight',
    plain: 'Three releases, from "builds itself" to polish',
  },
  relLede: {
    technical: 'R1 carries 49 stories — app-box designs, builds and ships itself; Michelle\u2019s 20-minute evaluation.',
    balanced: 'R1 carries 49 stories — app-box builds itself, then Michelle evaluates it in 20 minutes.',
    plain: 'The first release has 49 stories: app-box builds itself, and Michelle can judge it in 20 minutes.',
  },
  storyTrace: {
    technical: 'Registry surfaces tracing to this feature',
    balanced: 'Surfaces tracing to this feature',
    plain: 'Screens that come from this feature',
  },
  briefHeadline: {
    technical: 'The generated design brief — the designer\u2019s contract',
    balanced: 'The design brief, generated from the mapping session',
    plain: 'The brief — written for you from the story map',
  },
  briefLede: {
    technical: 'MoSCoW priorities, release swimlanes, surface inventory. Every registry surface traces to a story — gates/intake, plan 10.7.',
    balanced: 'Priorities, releases and the surface inventory. Every surface traces to a story.',
    plain: 'What the app must do, sorted and slotted into releases. Every screen traces back to a story here.',
  },
  surfacesHeadline: {
    technical: 'Surface inventory — 22 surfaces, every one traced',
    balanced: '22 surfaces — every one traces to a story',
    plain: '22 screens — each one comes from a story',
  },
  surfacesLede: {
    technical: 'brief.md\u2019s surface table feeds the designer; the registry is seeded from it without rewriting.',
    balanced: 'This table feeds the designer; the registry is seeded from it without rewriting.',
    plain: 'The app\u2019s screen list is filled straight from this table — nothing retyped.',
  },
  galleryHeadline: {
    technical: 'The moodboard — real apps to steal from, curated per epic',
    balanced: 'The moodboard — real apps to steal from',
    plain: 'Apps worth copying, gathered for you',
  },
  galleryLede: {
    technical: '3 boards curated 2026-07-28 · 12 probe-runner captures, every shot verified on disk.',
    balanced: '3 boards curated 2026-07-28 · 12 captured screens, all verified on disk.',
    plain: '3 collections, 12 real screenshots — every one checked to exist.',
  },
  shotSteal: {
    technical: 'Steal these patterns',
    balanced: 'Steal these patterns',
    plain: 'What to copy',
  },
  shotWhy: {
    technical: 'Why it suits app-box',
    balanced: 'Why it suits app-box',
    plain: 'Why it matters for app-box',
  },
  chatIntroBrief: {
    technical: 'The brief is generated from the mapping session — ask how it feeds design, or open it on the stage.',
    balanced: 'The brief came out of the mapping session — ask about it, or open it on the stage.',
    plain: 'This is the brief we wrote from your answers — ask anything, or open it.',
  },
  chatIntroMoodboard: {
    technical: 'Three boards, twelve captures, all verified on disk — ask what to steal, or open the gallery on the stage.',
    balanced: 'Three boards, twelve captures — ask what to steal, or open the gallery.',
    plain: 'Real apps worth copying — ask about them, or open the gallery.',
  },
};

const t = (lv) => Object.fromEntries(Object.entries(COPY).map(([k, v]) => [k, v[lv] ?? v.technical]));

// ---------- session ----------
const S = (sd) => (sd.intake ??= { extra: {}, current: {}, railView: {}, msgSeq: 0, interview: null });

// The interview: seeded from the fixture, then session-owned.
const interview = (sd) => (S(sd).interview ??= JSON.parse(JSON.stringify(repo.initialState())));
const isStale = (st) => st.approved && st.approvedVersion !== st.currentVersion;

const approvalFor = (sd) => {
  const st = interview(sd);
  return { approved: st.approved, stale: isStale(st), approvedVersion: st.approvedVersion, currentVersion: st.currentVersion };
};

// ---------- the interview → chat ----------
const DEPTH_ECHO = {
  simple: 'Simple — just the essentials.',
  normal: 'Normal — the usual depth.',
  advanced: 'Advanced — ask me everything.',
};

function carouselFor(st) {
  const bank = repo.questionBanks()[st.depth] ?? [];
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

function mappingChat(sd, tt) {
  const st = interview(sd);
  const msgs = [];
  msgs.push({
    id: 'w', from: 'agent', text: tt.welcome,
    quickReplies: st.depth ? null : ['simple', 'normal', 'advanced'].map((d) => ({ label: d, action: '/intake/depth', name: 'depth', value: d })),
  });
  if (!st.depth) return msgs;
  msgs.push({ id: 'u-depth', from: 'user', text: DEPTH_ECHO[st.depth] ?? st.depth });
  msgs.push({ id: 'carousel', from: 'agent', text: tt.carouselIntro, carousel: carouselFor(st) });
  if (st.generated) {
    const stale = isStale(st);
    msgs.push({
      id: 'gen', from: 'agent', text: tt.generated,
      artifactRef: 'map/full', artifactLabel: 'open the live story map →',
      nextHref: '/intake/brief', nextLabel: 'read the brief →',
      quickReplies: !st.approved || stale
        ? [{ label: stale ? `re-approve the story map (v${st.currentVersion})` : 'approve the story map', action: '/intake/approve', name: 'go', value: 'approve' }]
        : null,
    });
    msgs.push({ id: 'next', from: 'agent', text: tt.moodboardNext, nextHref: '/intake/moodboard', nextLabel: 'curate the moodboard →' });
    if (st.approved && !stale) msgs.push({ id: 'ok', from: 'agent', text: tt.approved, nextHref: '/design', nextLabel: 'open the Design tab →' });
    if (stale) msgs.push({ id: 'stale', from: 'agent', text: tt.stale });
  }
  return msgs;
}

function extrasFor(sd, surface, lv) {
  return (S(sd).extra[surface] ?? []).map((m) => ({
    ...m,
    text: m.from === 'user' ? m.text : jargon.pick(m, 'text', lv),
  }));
}

function chatFor(sd, surface, lv, tt) {
  if (surface === 'mapping') return [...mappingChat(sd, tt), ...extrasFor(sd, surface, lv)];
  const intro = {
    mapping: null,
    brief: { id: 'intro', from: 'agent', text: tt.chatIntroBrief, artifactRef: 'doc/full', artifactLabel: 'open the brief on the stage →' },
    moodboard: { id: 'intro', from: 'agent', text: tt.chatIntroMoodboard, artifactRef: 'gallery/all', artifactLabel: 'open the gallery on the stage →' },
  }[surface];
  return [intro, ...extrasFor(sd, surface, lv)];
}

// ---------- canvas artifacts ----------
// The live map: release swimlanes × epic columns, stories carrying pipeline
// status dots, rollups per epic and per release. Display data only —
// docs/design/story-map.json's schema is untouched.
function mapLanes() {
  const statuses = repo.statuses();
  const withStatus = (s) => ({ ...s, status: statuses[s.id] ?? 'pending' });
  const rollup = (stories) => ({
    total: stories.length,
    done: stories.filter((s) => s.status === 'done').length,
    active: stories.filter((s) => s.status === 'in-progress').length,
    blocked: stories.filter((s) => s.status === 'blocked').length,
  });
  const lanes = [];
  for (const rel of repo.releases()) {
    const epics = [];
    const laneStories = [];
    for (const e of repo.epics()) {
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

function resolveArtifact(surface, ref, tt) {
  const c = repo.counts();
  const [kind, id] = ref.split('/');
  if (surface === 'mapping') {
    if (kind === 'story') {
      const s = repo.story(id);
      if (s) return { kind, story: { ...s, status: repo.statuses()[s.id] ?? 'pending' }, ref, backRef: 'map/full' };
    }
    const head = id === 'priorities' ? [tt.priHeadline, tt.priLede] : id === 'releases' ? [tt.relHeadline, tt.relLede] : [tt.mapHeadline, tt.mapLede];
    return { kind: 'map', variant: id || 'full', headline: head[0], lede: head[1], lanes: mapLanes(), counts: c, ref: `map/${id || 'full'}` };
  }
  if (surface === 'brief') {
    if (kind === 'doc' && id === 'surfaces') {
      return { kind: 'surfaces', headline: tt.surfacesHeadline, lede: tt.surfacesLede, surfaces: repo.brief().surfaces, ref };
    }
    return { kind: 'doc', headline: tt.briefHeadline, lede: tt.briefLede, brief: repo.brief(), releases: repo.releases(), epics: repo.epics(), ref: 'doc/full' };
  }
  // moodboard
  if (kind === 'shot') {
    const hit = repo.shot(id);
    if (hit) return { kind, ...hit, ref, backRef: `gallery/${hit.board.id}` };
  }
  const mb = repo.moodboard();
  const boards = id && id !== 'all' && id !== 'highlights' ? mb.boards.filter((b) => b.id === id) : mb.boards;
  return { kind: 'gallery', headline: tt.galleryHeadline, lede: tt.galleryLede, boards, curated: mb.curated, provenance: mb.provenance, ref: `gallery/${id || 'all'}` };
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
function timelineFor(sd, surface) {
  const st = interview(sd);
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
  { id: 'thread', glyph: '◫', label: 'Thread' },
  { id: 'artifacts', glyph: '▤', label: 'Artifacts' },
  { id: 'files', glyph: '⬚', label: 'Files' },
];

function railViewFor(sd, surface, base, lv) {
  const active = S(sd).railView[surface] ?? 'thread';
  const views = RAIL_VIEWS.map((v) => ({ ...v, href: `${base}/rail?view=${v.id}`, active: v.id === active }));
  let body;
  if (active === 'artifacts') {
    const c = repo.counts();
    const ap = approvalFor(sd);
    const mapBadges = [
      ap.approved && !ap.stale ? { tone: 'ok', label: `approved · v${ap.approvedVersion}` } : null,
      ap.stale ? { tone: 'warn', label: 'changed since approval' } : null,
    ].filter(Boolean);
    body = {
      artifacts: {
        mapping: [
          { ref: 'map/full', title: 'Live story map', detail: `${c.stories} stories · ${c.epics} epics · status dots live`, badges: mapBadges },
          { ref: 'map/priorities', title: 'MoSCoW priorities', detail: `${c.must} must · ${c.should} should · ${c.could} could`, badges: [] },
          { ref: 'map/releases', title: 'Release swimlanes', detail: repo.releases().map((r) => r.name).join(' · '), badges: [] },
        ],
        brief: [
          { ref: 'doc/full', title: 'Design brief', detail: `${repo.brief().surfaces.length} surfaces traced · generated`, badges: [] },
          { ref: 'doc/surfaces', title: 'Surface inventory', detail: 'the table the designer consumes', badges: [] },
        ],
        moodboard: [
          { ref: 'gallery/all', title: 'The moodboard', detail: `${repo.moodboard().boards.length} boards · ${repo.moodboard().counts.shots} shots`, badges: [] },
          ...repo.moodboard().boards.map((b) => ({ ref: `gallery/${b.id}`, title: b.title, detail: `${b.references.length} references · informs ${b.informs}`, badges: [] })),
        ],
      }[surface],
    };
  } else if (active === 'files') {
    body = { files: repo.files() };
  } else {
    body = {
      thread: repo.narrative(surface).map((m) => ({
        at: m.at,
        text: jargon.pick(m, 'text', lv),
        artifact: m.artifact ?? null,
        artifactLabel: m.artifact ? chipLabel(m.artifact) : null,
      })),
    };
  }
  return { views, active, label: RAIL_VIEWS.find((v) => v.id === active).label, body };
}

// ---------- context ----------
const BASE = { mapping: '/intake', brief: '/intake/brief', moodboard: '/intake/moodboard' };

export const context = (sd, surface, ref, prefs = {}) => {
  const lv = jargon.level(prefs);
  const tt = t(lv);
  const s = S(sd);
  const base = BASE[surface];
  const activeArtifact = ref ?? s.current[surface] ?? null;
  const docked = !!activeArtifact;
  const rail = railViewFor(sd, surface, base, lv);
  const chat = chatFor(sd, surface, lv, tt);
  return {
    surface,
    base,
    project: { name: repo.project() },
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
    artifact: docked ? resolveArtifact(surface, activeArtifact, tt) : null,
    activeArtifact,
    chips: docked ? [{ id: activeArtifact, label: chipLabel(activeArtifact), removeHref: `${base}/close` }] : [],
    collapseHref: docked ? `${base}/close` : null,
    railViews: rail.views,
    railView: rail.active,
    railLabel: rail.label,
    railBody: rail.body,
    timeline: timelineFor(sd, surface),
    approval: approvalFor(sd),
    t: tt,
    jargonLevel: lv,
  };
};

export const showArtifact = (sd, surface, ref, prefs = {}) => {
  S(sd).current[surface] = ref;
  return context(sd, surface, ref, prefs);
};

// Composer chrome: pick the agent model (shared session state), then
// re-render this surface.
export const setModel = (sd, surface, id, prefs = {}) => {
  agent.setModel(sd, id);
  return context(sd, surface, null, prefs);
};

export const closeArtifact = (sd, surface, prefs = {}) => {
  S(sd).current[surface] = null;
  return context(sd, surface, null, prefs);
};

export const setRailView = (sd, surface, view, prefs = {}) => {
  if (RAIL_VIEWS.some((v) => v.id === view)) S(sd).railView[surface] = view;
  return context(sd, surface, null, prefs);
};

// ---------- interview actions ----------
export const chooseDepth = (sd, depth, prefs = {}) => {
  const st = interview(sd);
  if (!st.depth && repo.questionBanks()[depth]) st.depth = depth;
  return context(sd, 'mapping', null, prefs);
};

const bankOf = (st) => repo.questionBanks()[st.depth] ?? [];
const allAnswered = (st) => bankOf(st).every((q) => st.answers[q.id]);

function record(sd, qid, entry) {
  const st = interview(sd);
  if (!st.depth || !bankOf(st).some((q) => q.id === qid)) return st;
  if (st.generated) st.currentVersion += 1; // post-approval edits move the version
  st.answers[qid] = entry;
  st.editing = null;
  if (allAnswered(st)) st.generated = true;
  return st;
}

export const answerQuestion = (sd, qid, text, prefs = {}) => {
  record(sd, qid, { text, skipped: false });
  return context(sd, 'mapping', null, prefs);
};

export const skipQuestion = (sd, qid, prefs = {}) => {
  record(sd, qid, { text: null, skipped: true });
  return context(sd, 'mapping', null, prefs);
};

export const editQuestion = (sd, qid, prefs = {}) => {
  const st = interview(sd);
  if (st.answers[qid]) st.editing = qid;
  return context(sd, 'mapping', null, prefs);
};

export const approveMap = (sd, prefs = {}) => {
  const st = interview(sd);
  if (st.generated) {
    st.approved = true;
    st.approvedVersion = st.currentVersion;
  }
  return context(sd, 'mapping', null, prefs);
};

// ---------- the composer round-trip ----------
const replyFor = (text) => {
  const lower = text.toLowerCase();
  return repo.replies().find((r) => r.match.some((k) => lower.includes(k))) ?? repo.replyFallback();
};

// Free-text chat: append the user's message and a simulated agent reply; the
// reply may pull an artifact onto the stage (chat docks right).
export const sendMessage = (sd, surface, text, prefs = {}) => {
  const s = S(sd);
  const seq = (s.msgSeq += 1);
  (s.extra[surface] ??= []).push({ id: `u-${seq}`, from: 'user', text });
  const reply = replyFor(text);
  s.extra[surface].push({
    id: `a-${seq}`, from: 'agent',
    text: reply.text, textBalanced: reply.textBalanced, textPlain: reply.textPlain,
    artifactRef: reply.artifact ?? null,
    artifactLabel: reply.artifact ? `open the ${chipLabel(reply.artifact)} →` : null,
  });
  if (reply.artifact) s.current[surface] = reply.artifact;
  return context(sd, surface, null, prefs);
};
