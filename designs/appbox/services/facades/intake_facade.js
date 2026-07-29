// IntakeFacade — composes the intake fixture (story map, design brief,
// moodboard) with session-scoped state (rail filter, composer messages,
// per-canvas threads, the artifact on the canvas) into exactly what the
// three intake viewmodels need. Every leveled string passes through jargon.
import * as repo from '../repositories/intake_repository.js';
import * as jargon from './jargon.js';

export const SURFACES = ['mapping', 'brief', 'moodboard'];
const DEFAULT_ARTIFACT = { mapping: 'map/full', brief: 'doc/full', moodboard: 'gallery/all' };

// ---------- static leveled copy (the intake chapter of the jargon table) ----------
const COPY = {
  mapHeadline: {
    technical: 'Epic → Feature → Story — the whole product on one canvas',
    balanced: 'Epic → Feature → Story — the whole product on one canvas',
    plain: 'The whole product as one map — big themes, features, stories',
  },
  mapLede: {
    technical: '66 stories across 9 epics and 22 features. MoSCoW priorities, release swimlanes — tap any story for its trace.',
    balanced: '66 stories across 9 epics and 22 features. Priorities and releases shown — tap any story for its trace.',
    plain: '66 stories in 9 themes. Each is sorted must / should / could and slotted into a release — tap one to see more.',
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
  barHintMap: {
    technical: 'Scoped to the map — ask about MoSCoW, a release, or a story\u2019s trace.',
    balanced: 'Ask about the map, a release, or a story.',
    plain: 'Ask anything about the map or a story.',
  },
  barHintStory: {
    technical: 'Ask why this story carries its priority, or what surfaces trace to it.',
    balanced: 'Ask why this story is a must, or what traces to it.',
    plain: 'Ask why this story matters, or what screens come from it.',
  },
  barHintDoc: {
    technical: 'Ask how the brief feeds design, or how the registry was seeded.',
    balanced: 'Ask how the brief feeds design.',
    plain: 'Ask how this brief turns into screens.',
  },
  barHintGallery: {
    technical: 'Ask what to steal from a reference, or why one made the board.',
    balanced: 'Ask what to steal, or why a reference made the board.',
    plain: 'Ask what to copy, or why an app is here.',
  },
  barHintShot: {
    technical: 'Ask about this capture — the pattern, or how probe-runner took it.',
    balanced: 'Ask about this capture — the pattern, or how it was taken.',
    plain: 'Ask about this screenshot — what to copy from it.',
  },
};

const t = (lv) => Object.fromEntries(Object.entries(COPY).map(([k, v]) => [k, v[lv] ?? v.technical]));

// ---------- session ----------
const S = (sd) => (sd.intake ??= { threads: {}, barOpenFor: {}, current: {}, extra: {}, filters: {}, msgSeq: 0 });

const threadKey = (surface, ref) => `${surface}/${ref}`;
const threadFor = (sd, surface, ref) => (S(sd).threads)[threadKey(surface, ref)] ??= [];

const narrate = (sd, surface, m) => {
  const s = S(sd);
  const seq = (s.msgSeq += 1);
    (s.extra[surface] ??= []).push({ id: `a-${seq}`, at: 'now', from: 'agent', ...m });
};

// ---------- rail cards ----------
function cardFor(surface, ref, sd) {
  const threadCount = (S(sd).threads[threadKey(surface, ref)] ?? []).filter((e) => e.kind === 'user').length;
  if (!ref) return { type: 'note', threadCount: 0 };
  const [kind, id] = ref.split('/');
  const c = repo.counts();
  if (kind === 'map') return { type: 'map', detail: `story map · ${c.stories} stories · ${c.epics} epics`, ref, threadCount };
  if (kind === 'story') {
    const s = repo.story(id);
    return s ? { type: 'story', detail: `${s.epic} / ${s.feature} · ${s.priority} · ${s.release}`, ref, threadCount } : { type: 'story', ref, threadCount };
  }
  if (kind === 'doc' && id === 'surfaces') return { type: 'surfaces', detail: `${repo.brief().surfaces.length} surfaces · all traced`, ref, threadCount };
  if (kind === 'doc') return { type: 'doc', detail: 'the whole brief, generated', ref, threadCount };
  if (kind === 'gallery') {
    const mb = repo.moodboard();
    const b = mb.boards.find((x) => x.id === id);
    return { type: 'gallery', detail: b ? `${b.title} · ${b.references.length} shots` : `${mb.boards.length} boards · ${mb.counts.shots} shots`, ref, threadCount };
  }
  if (kind === 'shot') {
    const hit = repo.shot(id);
    return { type: 'shot', detail: hit ? `${hit.reference.name} · ${hit.board.title}` : 'capture', ref, threadCount };
  }
  return { type: 'note', ref, threadCount };
}

function messagesFor(sd, surface, activeArtifact, lv) {
  const all = [...repo.narrative(surface), ...(S(sd).extra[surface] ?? [])].map((m) => ({
    from: 'agent',
    tone: null,
    artifact: null,
    ...m,
    text: m.from === 'user' ? m.text : jargon.pick(m, 'text', lv),
    active: m.artifact === activeArtifact,
    card: m.from === 'user' ? { type: 'you', threadCount: 0 } : cardFor(surface, m.artifact, sd),
  }));
  return all;
}

// ---------- canvas artifacts ----------
// The mapping grid, projected into release swimlanes (and the rail-bar
// release filter). Stories keep their ids so cards deep-link to the trace.
function mapLanes(releaseFilter) {
  const lanes = [];
  for (const rel of repo.releases()) {
    if (releaseFilter !== 'all' && rel.name !== releaseFilter) continue;
    const epics = [];
    for (const e of repo.epics()) {
      const features = [];
      for (const f of e.features) {
        const stories = f.stories.filter((s) => s.release === rel.name);
        if (stories.length) features.push({ name: f.name, stories });
      }
      if (features.length) epics.push({ name: e.name, features });
    }
    lanes.push({ release: rel, epics });
  }
  return lanes;
}

function resolveArtifact(surface, ref, sd, lv, tt) {
  const c = repo.counts();
  const [kind, id] = (ref || DEFAULT_ARTIFACT[surface]).split('/');
  if (surface === 'mapping') {
    if (kind === 'story') {
      const s = repo.story(id);
      if (s) return { kind, story: s, ref, backRef: 'map/full' };
    }
    const filter = S(sd).filters.mapping ?? 'all';
    const head = id === 'priorities' ? [tt.priHeadline, tt.priLede] : id === 'releases' ? [tt.relHeadline, tt.relLede] : [tt.mapHeadline, tt.mapLede];
    return { kind: 'map', variant: id || 'full', headline: head[0], lede: head[1], lanes: mapLanes(filter), counts: c, ref: `map/${id || 'full'}` };
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

function barFor(surface, ref, tt) {
  const [kind] = (ref || '').split('/');
  const hint = kind === 'story' ? tt.barHintStory
    : kind === 'map' ? tt.barHintMap
    : kind === 'doc' || kind === 'surfaces' ? tt.barHintDoc
    : kind === 'shot' ? tt.barHintShot
    : tt.barHintGallery;
  return { kind, hint };
}

// Rail-bar facts per surface — the top-left state line.
function railFacts(surface) {
  const c = repo.counts();
  if (surface === 'mapping') return [`${c.epics} epics · ${c.features} features · ${c.stories} stories`, `${c.must} must · ${c.should} should · ${c.could} could`];
  if (surface === 'brief') return [`${repo.brief().surfaces.length} surfaces traced`, 'seeded into the registry'];
  const mb = repo.moodboard();
  return [`${mb.boards.length} boards · ${mb.counts.shots} shots`, `curated ${mb.curated}`];
}

// Rail-bar filter options (mapping: release; moodboard: board; brief: none).
function filterFor(surface, sd) {
  const s = S(sd);
  if (surface === 'mapping') {
    const active = s.filters.mapping ?? 'all';
    return { param: 'release', active, options: [{ id: 'all', label: 'all releases' }, ...repo.releases().map((r) => ({ id: r.name, label: r.name }))] };
  }
  if (surface === 'moodboard') {
    const active = s.filters.moodboard ?? 'all';
    return { param: 'board', active, options: [{ id: 'all', label: 'all boards' }, ...repo.moodboard().boards.map((b) => ({ id: b.id, label: b.title }))] };
  }
  return null;
}

export const context = (sd, surface, ref, prefs = {}) => {
  const lv = jargon.level(prefs);
  const tt = t(lv);
  const s = S(sd);
  const activeArtifact = ref ?? s.current[surface] ?? DEFAULT_ARTIFACT[surface];
  const thread = (s.threads[threadKey(surface, activeArtifact)] ?? [])
    .map((e) => ({ ...e, text: e.kind === 'agent' ? jargon.pick(e, 'text', lv) : e.text }));
  return {
    surface,
    base: { mapping: '/intake', brief: '/intake/brief', moodboard: '/intake/moodboard' }[surface],
    railTitle: { mapping: 'Story Mapping', brief: 'Design Brief', moodboard: 'Moodboard' }[surface],
    suggestions: {
      mapping: ["What's in R1?", 'Explain MoSCoW', 'Which surfaces trace?'],
      brief: ['How does the brief feed design?', 'Which surfaces trace?'],
      moodboard: ['What should we steal?', 'Which references made the board?'],
    }[surface],
    railFacts: railFacts(surface),
    filter: filterFor(surface, sd),
    messages: messagesFor(sd, surface, activeArtifact, lv),
    artifact: resolveArtifact(surface, activeArtifact, sd, lv, tt),
    activeArtifact,
    bar: barFor(surface, activeArtifact, tt),
    thread,
    barOpen: s.barOpenFor[surface] === activeArtifact,
    t: tt,
    jargonLevel: lv,
  };
};

export const showArtifact = (sd, surface, ref, prefs = {}) => {
  S(sd).current[surface] = ref;
  return context(sd, surface, ref, prefs);
};

export const setFilter = (sd, surface, param, value, prefs = {}) => {
  const s = S(sd);
  if (surface === 'mapping') s.filters.mapping = value || 'all';
  if (surface === 'moodboard') s.filters.moodboard = value || 'all';
  // The filter re-frames the canvas's primary artifact.
  const ref = surface === 'mapping' ? 'map/full' : `gallery/${s.filters.moodboard}`;
  return showArtifact(sd, surface, ref, prefs);
};

const replyFor = (text) => {
  const lower = text.toLowerCase();
  return repo.replies().find((r) => r.match.some((k) => lower.includes(k))) ?? repo.replyFallback();
};

// The composer round-trip: append the user's message, then a simulated agent
// reply; the reply may pull a new artifact onto the canvas.
export const sendMessage = (sd, surface, text, prefs = {}) => {
  const s = S(sd);
  const seq = (s.msgSeq += 1);
  (s.extra[surface] ??= []).push({ id: `u-${seq}`, at: 'now', from: 'user', text });
  const reply = replyFor(text);
  s.extra[surface].push({
    id: `a-${seq}`, at: 'now', from: 'agent',
    text: reply.text, textBalanced: reply.textBalanced, textPlain: reply.textPlain,
    artifact: reply.artifact, tone: reply.artifact ? 'action' : null,
  });
  const ref = reply.artifact ?? s.current[surface] ?? DEFAULT_ARTIFACT[surface];
  return showArtifact(sd, surface, ref, prefs);
};

// Stage-bar follow-up: artifact-scoped thread, bar stays open. The rail gets
// one digest line on first contact; the badge counts from then on.
export const askArtifact = (sd, surface, ref, text, prefs = {}) => {
  const s = S(sd);
  const thread = threadFor(sd, surface, ref);
  const first = thread.length === 0;
  thread.push({ id: `u-${thread.length}`, at: 'now', kind: 'user', text });
  s.barOpenFor[surface] = ref;
  if (first) narrate(sd, surface, { text: `Follow-ups started on this ${ref.split('/')[0]} — thread on the canvas.`, artifact: ref, tone: null });
  const reply = replyFor(text);
  thread.push({
    id: `a-${thread.length}`, at: 'now', kind: 'agent',
    text: reply.text, textBalanced: reply.textBalanced, textPlain: reply.textPlain,
    link: reply.artifact && reply.artifact !== ref ? reply.artifact : null,
  });
  return context(sd, surface, ref, prefs);
};

export const openBar = (sd, surface, ref) => { S(sd).barOpenFor[surface] = ref; };

export const barToggle = (sd, surface, ref, state, prefs = {}) => {
  S(sd).barOpenFor[surface] = state === 'fab' ? null : ref;
  return context(sd, surface, ref, prefs);
};
