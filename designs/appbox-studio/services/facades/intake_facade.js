// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
// IntakeFacade — composes the intake fixture (interview banks, personas,
// surface inventory, flows, direction, story map, design brief, moodboard)
// with session-scoped state into exactly what the intake viewmodels need.
//
// The intake shell is a TYPEFORM JOURNEY: eight steps, each a surfaced
// screen whose main panel walks one item at a time (question, persona,
// surface group, flow, direction group) — prefilled from the fixture with a
// provenance chip, confirmed or corrected, never blank. The composer panel
// on the right is the chat rail, always in the current step's context.
//
// Modes (the interview's depth choice): simple auto-accepts prefills and
// collapses the journey to interview → brief; normal (default) shows every
// step prefilled for confirmation; advanced (expert) shows every step with
// no auto-accept.
//
// Leveled fixture strings pass through jargon.pick; static leveled copy
// lives in l10n/app_*.arb and comes in as the runtime translator `translate`
// (helpers.translate(context) — level and locale already bound). The locale picks the
// per-locale fixture, en fallback.
import * as repo from '../repositories/intake_repository.js';
import * as screens from '../repositories/screens_repository.js';
import * as proj from '../repositories/project_repository.js';
import * as jargon from './jargon.js';
import * as agent from './agent_menus.js';
import * as fv from './file_views.js';

export const SURFACES = ['interview', 'personas', 'surfaces', 'flows', 'mapping', 'direction', 'brief', 'moodboard'];

const BASE = {
  interview: '/intake',
  personas: '/intake/personas',
  surfaces: '/intake/surfaces',
  flows: '/intake/flows',
  mapping: '/intake/map',
  direction: '/intake/direction',
  brief: '/intake/brief',
  moodboard: '/intake/moodboard',
};

// The journey, in order. Moodboard keeps its historic slot after the brief.
// Simple mode collapses to the fast path; the approval gate follows brief.
const JOURNEY = ['interview', 'personas', 'surfaces', 'flows', 'mapping', 'direction', 'brief', 'moodboard'];
const SIMPLE_JOURNEY = ['interview', 'brief'];
const STEPS = ['personas', 'surfaces', 'flows', 'direction']; // item-engine steps
const ARTIFACT_SURFACES = ['mapping', 'brief', 'moodboard'];

// ---------- session ----------
const S = (sd) => (sd.intake ??= { extra: {}, current: {}, activityView: {}, msgSeq: 0, interview: null, steps: {} });

// The interview: seeded from the fixture, then session-owned.
const interview = (sd, L) => (S(sd).interview ??= JSON.parse(JSON.stringify(repo.initialState(L))));
const isStale = (st) => st.approved && st.approvedVersion !== st.currentVersion;

const approvalFor = (sd, L) => {
  const st = interview(sd, L);
  return { approved: st.approved, stale: isStale(st), approvedVersion: st.approvedVersion, currentVersion: st.currentVersion };
};

// ---------- the interview → question carousel (main-panel typeform) ----------
function carouselFor(st, translate, L) {
  const bank = repo.questionBanks(L)[st.depth] ?? [];
  const firstOpen = bank.find((q) => !st.answers[q.id]);
  return {
    bank: st.depth,
    bankLabel: translate('intake.bank.' + st.depth),
    editing: st.editing ?? null,
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

// ---------- the item engine (personas / surfaces / flows / direction) ----------
// Every step walks the same protocol: items prefilled from the fixture,
// session records confirm/correct/skip per item, current = first open item.
const stepState = (sd, step) => (S(sd).steps[step] ??= { answers: {}, editing: null, auto: false });

// Registry id → label, for flow node chips and surface group headers.
let LABELS = null;
const labelOf = (id) => (LABELS ??= Object.fromEntries(screens.all().map((e) => [e.id, e.label])))[id] ?? id;

function stepItems(step, L) {
  if (step === 'personas') {
    // The CURRENT PROJECT's elicited user types (intake/personas.json), the
    // same rule the mapping/brief/moodboard panels now follow: appbox's own
    // personas are appbox's, and walking a client through them as if they were
    // the client's own is the §22 fiction. Absent → [], never the studio's set;
    // emitPersonas writes [] for every project that has not answered the
    // personas question, so the step simply has nothing to confirm yet.
    //
    // With NO project overlaid the studio is showing itself and its own
    // fixture IS its content, so the seed still stands there.
    if (proj.currentName()) return proj.personas() ?? [];
    return repo.personas(L);
  }
  if (step === 'surfaces') {
    // The CURRENT PROJECT's screen registry, grouped by shell — the studio's
    // own brief.surfaces is its design brief, never this project's inventory.
    // Registry entries carry no MoSCoW (priority/release): those live on the
    // brief, not on the scaffolder's registry, so those chips render empty.
    try {
      const groups = {};
      for (const s of proj.registry()) {
        const shell = s.shell ?? s.id.split('.')[0];
        (groups[shell] ??= { id: shell, label: labelOf(shell + '.shell') === shell + '.shell' ? shell : labelOf(shell + '.shell'), surfaces: [] }).surfaces.push(s);
      }
      return Object.values(groups);
    } catch {
      return []; // no project overlaid — nothing to confirm
    }
  }
  if (step === 'flows') {
    // The CURRENT PROJECT's flows (live-read from its intake/flows.json),
    // labelled from its registry. The studio's own journey flows are pipeline
    // metadata (screens_model) — never shown here. Project flows carry no
    // persona (flows.json v2) — the chip hides on null.
    try {
      const labels = Object.fromEntries(proj.registry().map((e) => [e.id, e.label]));
      return proj.flows().map((f) => ({
        ...f,
        personaName: null,
        edges: f.edges.map((e) => ({ ...e, fromLabel: labels[e.from] ?? e.from, toLabel: labels[e.to] ?? e.to })),
      }));
    } catch {
      return []; // no project overlaid — nothing to confirm
    }
  }
  // direction: the CURRENT PROJECT's design direction, one group per axis.
  //
  // PREFERRED SOURCE is intake/direction.json, because emitDirection already
  // promotes the field's single provenance onto each item — exactly the
  // {value, provenance} shape the chips want. Reading it means this file does
  // no stamping at all: the derivation belongs to the emitter, and doing it
  // twice is how the emitted file and the rendered chip start disagreeing.
  //
  // A group only exists when the project supplies it, so a project with no
  // moodboard pulls has no `references` group rather than an empty card.
  const emitted = proj.direction();
  if (emitted) {
    const groups = [];
    for (const id of ['adjectives', 'avoids', 'references']) {
      const values = emitted[id] ?? [];
      if (values.length) groups.push({ id, values });
    }
    return groups;
  }
  // FALLBACK for a project emitted before Slice B, which has answers.json but
  // no direction.json. Here the stamping is unavoidable — the answer holds
  // bare strings under one field-level provenance and nothing else has
  // promoted it — and it disappears the moment that project is re-emitted.
  try {
    const d = proj.answers().direction;
    const prov = d.provenance ?? 'inferred';
    const groups = [];
    for (const id of ['adjectives', 'avoids']) {
      const values = (d.value?.[id] ?? []).map((value) => ({ value, provenance: prov }));
      if (values.length) groups.push({ id, values });
    }
    const refs = d.value?.references ?? [];
    if (refs.length) groups.push({ id: 'references', values: refs });
    return groups;
  } catch {
    return []; // no project overlaid, or no direction answered — nothing to confirm
  }
}

function withStates(items, st) {
  const firstOpen = items.find((i) => !st.answers[i.id]);
  return items.map((i) => {
    const a = st.answers[i.id];
    const state = st.editing === i.id ? 'editing'
      : a ? (a.skipped ? 'skipped' : 'confirmed')
      : !st.editing && firstOpen && firstOpen.id === i.id ? 'current'
      : 'upcoming';
    // Corrections ride the item: saved fields override the prefill verbatim.
    // `edited` flags a corrected item so views can mark it after confirm.
    return { ...i, ...(a?.edited ?? {}), state, edited: a?.edited ? true : null };
  });
}

function stepContext(sd, step, L) {
  const st = stepState(sd, step);
  const mode = interview(sd, L).depth;
  const source = stepItems(step, L);
  // simple mode auto-accepts every prefill once; expert never does.
  if (mode === 'simple' && !st.auto) {
    for (const i of source) st.answers[i.id] ??= { confirmed: true };
    st.auto = true;
  }
  const items = withStates(source, st);
  const done = items.filter((i) => i.state === 'confirmed' || i.state === 'skipped').length;
  const idx = JOURNEY.indexOf(step);
  const journey = mode === 'simple' ? SIMPLE_JOURNEY : JOURNEY;
  const next = journey[journey.indexOf(step) + 1];
  return {
    id: step,
    mode,
    items,
    total: items.length,
    done,
    complete: items.length > 0 && done === items.length,
    nextHref: next ? BASE[next] : null,
    nextLabel: next ? 'screen.label.intake.' + next : null, // view feeds it through translate()
    position: idx + 1,
  };
}

// ---------- chat (the rail, always in step context) ----------
function interviewChat(sd, translate, L) {
  const st = interview(sd, L);
  const msgs = [];
  msgs.push({
    id: 'w', from: 'agent', text: translate('welcome'),
    quickReplies: st.depth ? null : ['simple', 'normal', 'advanced'].map((d) => ({ label: translate('intake.bank.' + d), action: '/intake/depth', name: 'depth', value: d })),
  });
  if (!st.depth) return msgs;
  msgs.push({ id: 'u-depth', from: 'user', text: translate('intake.depthEcho.' + st.depth) });
  msgs.push({ id: 'guide', from: 'agent', text: translate('intake.chat.guideInterview') });
  if (st.generated) {
    msgs.push({ id: 'gen', from: 'agent', text: translate('intake.chat.interviewDone'), nextHref: BASE.personas, nextLabel: translate('intake.cta.nextPersonas') });
  }
  return msgs;
}

function stepChat(sd, surface, translate, L) {
  const sc = stepContext(sd, surface, L);
  const msgs = [{ id: 'intro', from: 'agent', text: translate('intake.chat.intro.' + surface) }];
  if (sc.complete) {
    msgs.push({
      id: 'done', from: 'agent', text: translate('intake.chat.stepDone', { done: sc.done, total: sc.total }),
      nextHref: sc.nextHref, nextLabel: sc.nextLabel ? translate(sc.nextLabel) : null,
    });
  } else {
    msgs.push({ id: 'progress', from: 'agent', text: translate('intake.chat.stepProgress', { done: sc.done, total: sc.total }) });
  }
  return msgs;
}

function mappingChat(sd, translate, L) {
  const st = interview(sd, L);
  const msgs = [{ id: 'intro', from: 'agent', text: translate('intake.chat.intro.mapping') }];
  if (st.generated) {
    const stale = isStale(st);
    msgs.push({
      id: 'gen', from: 'agent', text: translate('generated'),
      artifactRef: 'map/full', artifactLabel: translate('intake.cta.openStoryMap'),
      nextHref: BASE.direction, nextLabel: translate('intake.cta.nextDirection'),
      quickReplies: !st.approved || stale
        ? [{ label: stale ? translate('intake.cta.reapproveMap', { version: st.currentVersion }) : translate('intake.cta.approveMap'), action: '/intake/map/approve', name: 'go', value: 'approve' }]
        : null,
    });
    if (st.approved && !stale) msgs.push({ id: 'ok', from: 'agent', text: translate('approved'), nextHref: BASE.direction, nextLabel: translate('intake.cta.nextDirection') });
    if (stale) msgs.push({ id: 'stale', from: 'agent', text: translate('stale') });
  }
  return msgs;
}

function extrasFor(sd, surface, lv) {
  return (S(sd).extra[surface] ?? []).map((m) => ({
    ...m,
    text: m.from === 'user' ? m.text : jargon.pick(m, 'text', lv),
  }));
}

function chatFor(sd, surface, lv, translate, L) {
  const base = {
    interview: () => interviewChat(sd, translate, L),
    mapping: () => mappingChat(sd, translate, L),
    brief: () => [{
      id: 'intro', from: 'agent', text: translate('chatIntroBrief'),
      artifactRef: 'doc/full', artifactLabel: translate('intake.cta.openBriefStage'),
      ...approvalChatBits(sd, translate, L),
    }],
    moodboard: () => [{ id: 'intro', from: 'agent', text: translate('chatIntroMoodboard'), artifactRef: 'gallery/all', artifactLabel: translate('intake.cta.openGalleryStage') }],
  }[surface];
  const msgs = base ? base() : stepChat(sd, surface, translate, L);
  return [...msgs, ...extrasFor(sd, surface, lv)];
}

// The brief carries the approval gate: the approve quick-reply rides its intro.
function approvalChatBits(sd, translate, L) {
  const st = interview(sd, L);
  if (!st.generated) return {};
  const stale = isStale(st);
  if (st.approved && !stale) return { nextHref: '/design', nextLabel: translate('intake.cta.openDesignShell') };
  return {
    quickReplies: [{ label: stale ? translate('intake.cta.reapproveMap', { version: st.currentVersion }) : translate('intake.cta.approveMap'), action: '/intake/brief/approve', name: 'go', value: 'approve' }],
  };
}

// ---------- canvas artifacts ----------
// mapping / brief / moodboard read the CURRENT PROJECT — intake/map.json,
// intake/moodboard.json and intake/registry.json, live-read through the server
// overlay (Slice B3). They used to read the studio's own intake fixture: the
// appbox product plan and appbox's own reference captures, rendered under the
// client's project name with nothing on screen to tell them apart. That is the
// confident fiction §22 forbids, and it is why every branch below ends in
// `artifactMissing` rather than in a fallback to something that renders.
//
// Nothing here recomputes what the emitter baked in. Story/epic/feature ids,
// `counts` (MoSCoW buckets and byRelease included) and each shot's `id` and
// served `src` all arrive precomputed from intake_artifacts.dart and are read
// as-is. The one thing this file does compute is the swimlane grouping, which
// is presentation: a lane is not a stored fact and map.json has no lane list.

// Where each artifact would live, named in the empty state so the message is
// actionable rather than merely apologetic.
const ARTIFACT_FILE = {
  map: 'intake/map.json',
  brief: 'intake/registry.json',
  moodboard: 'intake/moodboard.json',
};

// The honest empty state: what is missing, the file it would live in, and the
// steps that produce it. Never a placeholder, never the studio's copy of the
// same document — a reader must be able to tell "this project has no moodboard"
// from "here is a moodboard", and a fallback makes those two look identical.
function artifactMissing(what, translate, ref) {
  const project = proj.currentName();
  const file = ARTIFACT_FILE[what];
  const base = { kind: 'missing', what, ref, file, tone: 'empty', badge: translate('intake.missing.badge'), howLabel: translate('intake.missing.howLabel') };
  // No project overlaid at all (artifact-only serving) is a different fact
  // from "this project has not run the story-mapper", and saying the second
  // when the first is true would send the reader after the wrong command.
  if (!project) {
    return { ...base, headline: translate('intake.missing.noProject.headline'), lede: translate('intake.missing.noProject.lede'), steps: [translate('intake.missing.step.open')] };
  }
  const artifact = translate('intake.missing.name.' + what);
  return {
    ...base,
    headline: translate('intake.missing.headline', { artifact, project }),
    lede: translate('intake.missing.lede', { artifact, file }),
    steps: [translate('intake.missing.step.' + what), translate('intake.missing.stepEmit', { project })],
  };
}

// The live map: release swimlanes × epic columns, stories carrying pipeline
// status dots, rollups per epic and per release.
//
// `statuses` come off map.json itself — the studio writes them there (a
// reviewer marking a story done) and `mergeStoryMap` carries them across each
// re-emit, so the map and its progress are one document, never two that can
// drift apart.
function mapLanes(map, translate) {
  const statuses = map.statuses ?? {};
  const withStatus = (s) => ({ ...s, status: statuses[s.id] ?? 'pending' });
  const rollup = (stories) => ({
    total: stories.length,
    done: stories.filter((s) => s.status === 'done').length,
    active: stories.filter((s) => s.status === 'in-progress').length,
    blocked: stories.filter((s) => s.status === 'blocked').length,
  });
  const laneFor = (release, keep) => {
    const epics = [];
    const laneStories = [];
    for (const e of map.epics ?? []) {
      const features = [];
      const epicStories = [];
      for (const f of e.features ?? []) {
        const stories = (f.stories ?? []).filter(keep).map(withStatus);
        if (stories.length) { features.push({ name: f.name, stories }); epicStories.push(...stories); }
      }
      if (features.length) epics.push({ name: e.name, features, rollup: rollup(epicStories) });
      laneStories.push(...epicStories);
    }
    return { release: { ...release, rollup: rollup(laneStories) }, epics };
  };
  const releases = map.releases ?? [];
  const lanes = releases.map((rel) => laneFor(rel, (s) => s.release === rel.name));
  // A story with `release: null` — which emitStoryMap writes whenever the
  // story-mapper did not slot it — or one naming a release the map never
  // declared is STILL A STORY. Filtering it into nothing would leave the
  // canvas disagreeing with `counts.stories`, which is a stored fact, and a
  // project with epics but no declared releases would render as a blank map
  // that reads like a rendering failure. So it gets a lane of its own.
  const declared = new Set(releases.map((r) => r.name));
  const rest = laneFor({ name: translate('map.unassignedLane'), description: translate('map.unassignedLaneDesc') }, (s) => !declared.has(s.release));
  if (rest.epics.length) lanes.push(rest);
  return lanes;
}

// One story by id, plus the epic and feature it sits under. Those two are the
// story's POSITION in the document, not fields on it: emitStoryMap does not
// write `epic`/`feature` onto a story, so reading them off the walk is the
// only non-inventing way to render the breadcrumb.
function storyAt(map, id) {
  for (const e of map.epics ?? []) {
    for (const f of e.features ?? []) {
      for (const s of f.stories ?? []) {
        if (s.id === id) return { story: s, epic: e.name, feature: f.name };
      }
    }
  }
  return null;
}

function shotAt(mb, id) {
  for (const b of mb.boards ?? []) {
    for (const r of b.references ?? []) {
      if (r.shot?.id === id) return { board: b, reference: r, shot: r.shot };
    }
  }
  return null;
}

function resolveArtifact(surface, ref, translate, L) {
  const [kind, id] = ref.split('/');
  if (surface === 'mapping') {
    const map = proj.storyMap();
    // No file, or a file with no epics, is the same fact to a reader: this
    // project has no story map. One branch, one message.
    if (!map?.epics?.length) return artifactMissing('map', translate, ref);
    if (kind === 'story') {
      const hit = storyAt(map, id);
      if (hit) {
        return {
          kind,
          story: { ...hit.story, status: (map.statuses ?? {})[hit.story.id] ?? 'pending' },
          epic: hit.epic, feature: hit.feature,
          ref, backRef: 'map/full',
        };
      }
    }
    // The map/priorities/releases headlines used to be FIXED SENTENCES about
    // the studio's own plan — "66 stories across 9 epics", "Three releases: R1
    // Dogfood · R2 Anywhere · R3 Delight" — printed verbatim above a client
    // project's map. Reading right and being false is the worst failure mode
    // this surface has, so the catalog strings now take the project's own
    // counts. The numbers are READ from `map.counts`, which the emitter
    // totalled; nothing is re-counted here.
    const context = map.counts ?? {};
    const releases = map.releases ?? [];
    const relVars = { count: String(releases.length), names: releases.map((r) => r.name).join(' · ') };
    const mapVars = { stories: String(context.stories ?? 0), epics: String(context.epics ?? 0), features: String(context.features ?? 0) };
    const priVars = { must: String(context.must ?? 0), should: String(context.should ?? 0), could: String(context.could ?? 0) };
    const head = id === 'priorities' ? [translate('priHeadline', priVars), translate('priLede', priVars)]
      : id === 'releases' ? [translate('relHeadline', relVars), translate('relLede', relVars)]
      : [translate('mapHeadline'), translate('mapLede', mapVars)];
    return { kind: 'map', variant: id || 'full', headline: head[0], lede: head[1], lanes: mapLanes(map, translate), counts: context, ref: `map/${id || 'full'}` };
  }
  if (surface === 'brief') {
    // The project's surface inventory IS its screen registry — the same list
    // the scaffolder builds from. `priority`/`release` are additive columns
    // the story-mapper fills in; a project without them shows blank cells,
    // which is true, rather than a MoSCoW chip nobody assigned.
    const surfaces = projectSurfaces();
    if (kind === 'doc' && id === 'surfaces') {
      if (!surfaces.length) return artifactMissing('brief', translate, ref);
      return { kind: 'surfaces', headline: translate('surfaces.headlineN', { count: surfaces.length }), lede: translate('surfacesLede'), surfaces, ref };
    }
    const map = proj.storyMap();
    if (!surfaces.length && !map?.epics?.length) return artifactMissing('brief', translate, ref);
    // There is no project-side brief OBJECT — intake writes intake/brief.md,
    // prose this reader cannot parse into sections. So the document is
    // assembled from what the project does state: its name, its registry, its
    // story map. The studio brief's `provenance` line ("Elicited via
    // appbox-story-mapper · …") is deliberately NOT reproduced: it is a
    // specific claim about how a document was made, and no project-side source
    // states it. Inventing one would be exactly the fiction this slice removes.
    const name = proj.currentName();
    return {
      kind: 'doc',
      headline: translate('briefHeadline'),
      lede: translate('briefLede'),
      brief: {
        title: name ? translate('brief.projectTitle', { name }) : translate('brief.untitledTitle'),
        surfaceNote: translate('brief.surfaceNoteProject'),
        surfaces,
      },
      releases: map?.releases ?? [],
      epics: map?.epics ?? [],
      // The brief has TWO project sources and they arrive independently: the
      // registry (present as soon as the interview names surfaces) and the
      // story map (only once the story-mapper has run). With surfaces but no
      // map, the releases and must-do sections would render as bare headings
      // over nothing — which reads as a broken page, not as a missing input.
      // This carries the same explanation the standalone empty state gives.
      mapMissing: map?.epics?.length ? null : artifactMissing('map', translate, ref),
      ref: 'doc/full',
    };
  }
  // moodboard
  const mb = proj.moodboard();
  if (!mb?.boards?.length) return artifactMissing('moodboard', translate, ref);
  if (kind === 'shot') {
    const hit = shotAt(mb, id);
    if (hit) return { kind, ...hit, ref, backRef: `gallery/${hit.board.id}` };
  }
  const boards = id && id !== 'all' && id !== 'highlights' ? mb.boards.filter((b) => b.id === id) : mb.boards;
  // `method` not `provenance`: the emitter renamed it because the seed's value
  // is free-text methodology, not the client|founder|inferred enum, and a
  // reader that called it provenance would invite parsing prose as an enum.
  // `curated` is gone entirely — it was a date, and emitted artifacts must be
  // byte-identical for identical input (project.dart:13).
  // Counts READ off `mb.counts` (the emitter totalled them), never re-counted
  // here — and the lede no longer hard-codes "3 boards curated 2026-07-28 · 12
  // captured screens", which was the studio's own tally printed above whatever
  // the project actually had.
  const mc = mb.counts ?? {};
  const galleryVars = { boards: String(mc.boards ?? 0), references: String(mc.references ?? 0), shots: String(mc.shots ?? 0) };
  return { kind: 'gallery', headline: translate('galleryHeadline'), lede: translate('galleryLede', galleryVars), boards, method: mb.method ?? null, ref: `gallery/${id || 'all'}` };
}

// The CURRENT PROJECT's screen registry, or [] when nothing is overlaid.
const projectSurfaces = () => {
  try {
    return proj.registry();
  } catch {
    return [];
  }
};

// ADR-0003: an artifact read that can fail needs a visible failure state, not
// a 500 and not a silently blank panel. These reads are synchronous (the
// server prefetches every project .json before the render), so there is no
// busy state to show — but a project file that EXISTS and does not parse is a
// real, reachable failure, and readOptionalProjectFixture deliberately lets it
// through rather than disguising it as "not produced yet".
function artifactFor(surface, ref, translate, L) {
  try {
    return resolveArtifact(surface, ref, translate, L);
  } catch (e) {
    return {
      kind: 'missing', tone: 'error', ref, what: null, file: null,
      badge: translate('intake.missing.broken.badge'),
      headline: translate('intake.missing.broken.headline'),
      lede: translate('intake.missing.broken.lede', { error: String(e?.message ?? e) }),
      howLabel: null, steps: [],
    };
  }
}

// Short chip label per artifact ref — the chat-head context chip.
function chipLabel(ref, translate) {
  const [kind, id] = (ref ?? '').split('/');
  return {
    map: id === 'priorities' ? translate('intake.chip.priorities') : id === 'releases' ? translate('intake.chip.releases') : translate('intake.chip.storyMap'),
    story: translate('intake.chip.story', { id }), doc: id === 'surfaces' ? translate('intake.chip.surfaceInventory') : translate('intake.chip.designBrief'),
    gallery: translate('intake.chip.moodboard'), shot: translate('intake.chip.capture'),
  }[kind] ?? ref;
}

// ---------- the footer-panel journey timeline (read-only) ----------
function stepDone(sd, step, st, L) {
  if (step === 'interview') return Boolean(st.depth && st.generated);
  if (step === 'mapping' || step === 'brief') return st.generated;
  if (step === 'moodboard') return false; // stays browsable; never blocks the gate
  return stepContext(sd, step, L).complete;
}

function timelineFor(sd, surface, translate, L) {
  const st = interview(sd, L);
  const stale = isStale(st);
  const unlocked = st.approved && !stale;
  const journey = st.depth === 'simple' ? SIMPLE_JOURNEY : JOURNEY;
  const items = journey.map((step) => ({
    id: step, kind: 'stage', label: translate('screen.label.intake.' + step),
    state: stepDone(sd, step, st, L) ? 'green' : 'pending', ref: step,
  }));
  items.push({ id: 'intake.approval', kind: 'gate', label: translate('intake.timeline.approval'), state: st.approved ? (stale ? 'held' : 'approved') : st.generated ? 'active' : 'pending', ref: 'intake.approval' });
  items.push({ id: 'design', kind: 'stage', label: unlocked ? translate('tab.design') : translate('intake.timeline.lockedSuffix', { label: translate('tab.design') }), state: unlocked ? 'pending' : 'cancelled', ref: 'design' });
  // current = the first unfinished stage — the line reads as pipeline truth,
  // never as the surface being browsed.
  const firstOpen = items.find((i) => i.state === 'pending' || i.state === 'active');
  if (firstOpen && firstOpen.state === 'pending') firstOpen.state = 'active';
  return { items, currentId: firstOpen?.id ?? null };
}

// ---------- the activity panel views: thread / artifacts / files ----------
const ACTIVITY_VIEWS = [
  { id: 'thread', icon: 'messages-square', label: 'Thread' },
  { id: 'artifacts', icon: 'package', label: 'Artifacts' },
  { id: 'files', icon: 'folder', label: 'Files' },
];

// Panel width steps, per panel — one sizing state for the whole intake shell
// (unlike activityView, which is per surface).
const PANEL_SIZES = ['s', 'm', 'l'];
// Panels whose width is server state. Only the activity panel persists one:
// the composer's width is client-only and rides morph (see drag.js data-persist).
const PERSISTABLE_PANELS = ['activity'];
const panelSizeFor = (sd, panel) => (PANEL_SIZES.includes(S(sd).panelSize?.[panel]) ? S(sd).panelSize[panel] : 's');

function activityViewFor(sd, surface, base, lv, translate, L) {
  const views = ARTIFACT_SURFACES.includes(surface) ? ACTIVITY_VIEWS : ACTIVITY_VIEWS.filter((v) => v.id !== 'artifacts');
  let active = S(sd).activityView[surface] ?? 'thread';
  if (!views.some((v) => v.id === active)) active = 'thread';
  const viewLinks = views.map((v) => ({ ...v, label: translate('activityView.' + v.id), href: `${base}/panel?view=${v.id}`, active: v.id === active }));
  let body;
  if (active === 'artifacts') {
    // Every count on this list comes off the PROJECT's artifacts, and each
    // list is empty-safe on its own: this panel is reachable on a project with
    // no map and no moodboard, and reading `.boards.length` unconditionally is
    // how that page used to 500 before the main panel ever got a chance to
    // explain itself.
    const ap = approvalFor(sd, L);
    const mapBadges = [
      ap.approved && !ap.stale ? { tone: 'ok', label: translate('map.approvedBadge', { version: ap.approvedVersion }) } : null,
      ap.stale ? { tone: 'warn', label: translate('badge.stale') } : null,
    ].filter(Boolean);
    const notYet = [{ tone: 'warn', label: translate('intake.missing.badge') }];
    const map = proj.storyMap();
    const mb = proj.moodboard();
    const surfaces = projectSurfaces();
    const context = map?.counts ?? {};
    body = {
      artifacts: {
        mapping: map?.epics?.length
          ? [
            { ref: 'map/full', title: translate('intake.activity.liveStoryMap.title'), detail: translate('intake.activity.liveStoryMap.detail', { stories: context.stories ?? 0, epics: context.epics ?? 0 }), badges: mapBadges },
            { ref: 'map/priorities', title: translate('intake.activity.moscow.title'), detail: translate('intake.activity.moscow.detail', { must: context.must ?? 0, should: context.should ?? 0, could: context.could ?? 0 }), badges: [] },
            { ref: 'map/releases', title: translate('intake.activity.releases.title'), detail: (map.releases ?? []).map((r) => r.name).join(' · '), badges: [] },
          ]
          // One row, not zero: an empty artifacts list looks like a panel that
          // failed to load. The row opens the same explanation the main panel
          // shows, so the missing artifact stays reachable from here.
          : [{ ref: 'map/full', title: translate('intake.activity.liveStoryMap.title'), detail: translate('intake.missing.activityDetail', { file: ARTIFACT_FILE.map }), badges: notYet }],
        brief: surfaces.length
          ? [
            { ref: 'doc/full', title: translate('intake.activity.designBrief.title'), detail: translate('intake.activity.designBrief.detail', { count: surfaces.length }), badges: [] },
            { ref: 'doc/surfaces', title: translate('intake.activity.surfaceInventory.title'), detail: translate('intake.activity.surfaceInventory.detail'), badges: [] },
          ]
          : [{ ref: 'doc/full', title: translate('intake.activity.designBrief.title'), detail: translate('intake.missing.activityDetail', { file: ARTIFACT_FILE.brief }), badges: notYet }],
        moodboard: mb?.boards?.length
          ? [
            { ref: 'gallery/all', title: translate('intake.activity.moodboard.title'), detail: translate('intake.activity.moodboard.detail', { boards: mb.counts?.boards ?? mb.boards.length, shots: mb.counts?.shots ?? 0 }), badges: [] },
            ...mb.boards.map((b) => ({ ref: `gallery/${b.id}`, title: b.title, detail: translate('intake.activity.board.detail', { count: (b.references ?? []).length, informs: b.informs }), badges: [] })),
          ]
          : [{ ref: 'gallery/all', title: translate('intake.activity.moodboard.title'), detail: translate('intake.missing.activityDetail', { file: ARTIFACT_FILE.moodboard }), badges: notYet }],
      }[surface] ?? [],
    };
  } else if (active === 'files') {
    body = { files: repo.files(L).map((f) => ({ ...f, ...fv.fileLink(f.path, base) })) };
  } else {
    // Seeded narrative + this session's own messages — the activity thread
    // is live, it reacts to what the chat is fed, not a frozen copy.
    //
    // The SEEDED half is the studio's own: its messages assert facts ("R1
    // Dogfood carries 49 stories", "Dreamflow is the structural sibling") about
    // appbox's story map and appbox's moodboard. Rendered beside a client
    // project's real map they read as statements about THAT project, which is
    // the same confident fiction the main panel now refuses — so on the three
    // artifact surfaces the seed is dropped whenever a project is overlaid, and
    // the thread carries only what this session actually produced.
    //
    // With no project overlaid the studio is showing itself, the seed IS its
    // own content, and it stays. Scoped to these three surfaces on purpose: the
    // item-engine steps are a separate migration and not this slice's to make.
    const seeded = ARTIFACT_SURFACES.includes(surface) && proj.currentName()
      ? []
      : repo.narrative(surface, L);
    body = {
      thread: [
        ...seeded.map((m) => ({
          at: m.at,
          text: jargon.pick(m, 'text', lv),
          artifact: m.artifact ?? null,
          artifactLabel: m.artifact ? chipLabel(m.artifact, translate) : null,
        })),
        ...extrasFor(sd, surface, lv).map((m) => ({
          at: translate('time.now'),
          text: m.text,
          artifact: m.artifactRef ?? null,
          artifactLabel: m.artifactRef ? m.artifactLabel ?? chipLabel(m.artifactRef, translate) : null,
        })),
      ],
    };
  }
  return { views: viewLinks, active, label: viewLinks.find((v) => v.id === active).label, body };
}

// ---------- context ----------
export const context = (sd, surface, ref, prefs = {}, translate = (k) => k, locale = 'en', fileArg, panelArg) => {
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
  let activeArtifact = currentFile ? null : (ref ?? s.current[surface] ?? null);
  // The story map opens by default once generated — the mapping step's main
  // panel is the map, not an empty stage.
  if (surface === 'mapping' && !activeArtifact && !currentFile && interview(sd, L).generated) activeArtifact = 'map/full';
  const activity = activityViewFor(sd, surface, base, lv, translate, L);
  const chat = chatFor(sd, surface, lv, translate, L);
  const st = interview(sd, L);
  return {
    surface,
    base,
    // The CURRENT PROJECT's name, null when serving the artifact alone —
    // the studio's own fixture name is not this project's.
    project: { name: proj.currentName() },
    eyebrow: translate('intake.eyebrow.' + surface),
    composerAction: `${base}/messages`,
    placeholder: translate('composer.placeholder.intake'),
    modelMenu: agent.modelMenuFor(sd, base, translate),
    threading: chat.some((m) => m.from === 'user'),
    suggestions: {
      interview: [translate('intake.sug.whyTheseQuestions'), translate('intake.sug.whichMode')],
      personas: [translate('intake.sug.whoIsMissing'), translate('intake.sug.whyThesePersonas')],
      surfaces: [translate('intake.sug.whichSurfaces'), translate('intake.sug.whyTheseStates')],
      flows: [translate('intake.sug.whichFlows'), translate('intake.sug.whichSurfaces')],
      mapping: [translate('intake.sug.whatsInR1'), translate('intake.sug.explainMoscow'), translate('intake.sug.whichSurfaces')],
      direction: [translate('intake.sug.whatToSteal'), translate('intake.sug.whyThisDirection')],
      brief: [translate('intake.sug.briefFeedsDesign'), translate('intake.sug.whichSurfaces')],
      moodboard: [translate('intake.sug.whatToSteal'), translate('intake.sug.whichReferences')],
    }[surface],
    chat,
    artifact: activeArtifact ? artifactFor(surface, activeArtifact, translate, L) : null,
    activeArtifact,
    fileView: currentFile ? fv.fileViewFor(currentFile, `${base}?file=none`) : null,
    panel,
    activityViews: activity.views,
    activityView: activity.active,
    activityLabel: activity.label,
    panelSize: panelSizeFor(sd, 'activity'),
    panelSizeHref: `${base}/panel/size/activity/`,
    activityBody: activity.body,
    timeline: timelineFor(sd, surface, translate, L),
    approval: approvalFor(sd, L),
    jargonLevel: lv,
    // The step payload: interview carries the question carousel; the four
    // item steps carry the item engine's state.
    carousel: surface === 'interview' && st.depth ? carouselFor(st, translate, L) : null,
    step: STEPS.includes(surface) ? stepContext(sd, surface, L)
      : surface === 'interview'
        ? { id: 'interview', mode: st.depth, complete: st.generated, done: Object.keys(st.answers).length, total: (repo.questionBanks(L)[st.depth] ?? []).length, nextHref: BASE.personas, nextLabel: 'screen.label.intake.personas' }
        : null,
  };
};

export const showArtifact = (sd, surface, ref, prefs = {}, translate = (k) => k, locale = 'en') => {
  S(sd).current[surface] = ref;
  (S(sd).currentFile ??= {})[surface] = null;
  return context(sd, surface, ref, prefs, translate, locale);
};

// A file row in the activity panel: open it in the main panel (the mode is
// the server's, from the extension).
export const openFile = (sd, surface, path, prefs = {}, translate = (k) => k, locale = 'en') =>
  context(sd, surface, null, prefs, translate, locale, path ?? 'none');

// Composer chrome: pick the agent model (shared session state), then
// re-render this surface.
export const setModel = (sd, surface, id, prefs = {}, translate = (k) => k, locale = 'en') => {
  agent.setModel(sd, id);
  return context(sd, surface, null, prefs, translate, locale);
};

export const setActivityView = (sd, surface, view, prefs = {}, translate = (k) => k, locale = 'en') => {
  if (ACTIVITY_VIEWS.some((v) => v.id === view)) S(sd).activityView[surface] = view;
  return context(sd, surface, null, prefs, translate, locale);
};

// Panel width grip: one persisted size per panel for the whole intake shell.
export const setPanelSize = (sd, surface, panel, size, prefs = {}, translate = (k) => k, locale = 'en') => {
  if (PERSISTABLE_PANELS.includes(panel) && PANEL_SIZES.includes(size)) {
    (S(sd).panelSize ??= {})[panel] = size;
  }
  return context(sd, surface, null, prefs, translate, locale);
};

// ---------- interview actions ----------
export const chooseDepth = (sd, depth, prefs = {}, translate = (k) => k, locale = 'en') => {
  const st = interview(sd, locale);
  if (!st.depth && repo.questionBanks(locale)[depth]) st.depth = depth;
  // simple mode: the fast path answers every question with its first
  // suggestion and auto-approves nothing — confirmation still gates design.
  if (st.depth === 'simple') {
    for (const q of repo.questionBanks(locale).simple) st.answers[q.id] ??= { text: q.suggestions?.[0] ?? null, skipped: !q.suggestions?.length };
    st.generated = true;
  }
  return context(sd, 'interview', null, prefs, translate, locale);
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

export const answerQuestion = (sd, qid, text, prefs = {}, translate = (k) => k, locale = 'en') => {
  record(sd, qid, { text, skipped: false }, locale);
  return context(sd, 'interview', null, prefs, translate, locale);
};

export const skipQuestion = (sd, qid, prefs = {}, translate = (k) => k, locale = 'en') => {
  record(sd, qid, { text: null, skipped: true }, locale);
  return context(sd, 'interview', null, prefs, translate, locale);
};

export const editQuestion = (sd, qid, prefs = {}, translate = (k) => k, locale = 'en') => {
  const st = interview(sd, locale);
  if (st.answers[qid]) st.editing = qid;
  return context(sd, 'interview', null, prefs, translate, locale);
};

// The approval gate: approving locks the intake output at its version and
// unlocks the design shell. Reachable from mapping and from the brief.
export const approveMap = (sd, surface = 'mapping', prefs = {}, translate = (k) => k, locale = 'en') => {
  const st = interview(sd, locale);
  if (st.generated) {
    st.approved = true;
    st.approvedVersion = st.currentVersion;
  }
  return context(sd, surface, null, prefs, translate, locale);
};

// ---------- item-engine actions (personas / surfaces / flows / direction) ----------
const recordItem = (sd, step, id, entry, L) => {
  const st = stepState(sd, step);
  if (!stepItems(step, L).some((i) => i.id === id)) return;
  st.answers[id] = entry;
  st.editing = null;
};

export const confirmItem = (sd, surface, id, prefs = {}, translate = (k) => k, locale = 'en') => {
  recordItem(sd, surface, id, { confirmed: true }, locale);
  return context(sd, surface, null, prefs, translate, locale);
};

// Confirming a flow flips its provenance to founder in the PROJECT's
// flows.json (derive + confirm) — the studio edits the project through the
// server's confined write channel. Session state is the item engine's; the
// file write is the real confirm. No project overlaid → the session confirm
// still stands, the file stays as derived.
export const confirmFlowProvenance = async (flowId) => {
  try {
    const flows = proj.flows();
    const f = flows.find((x) => x.id === flowId);
    if (f && f.provenance !== 'founder') {
      f.provenance = 'founder';
      // `['provenance']` — the ONLY field this confirm touched. Syncing `edges`
      // as well would quietly adopt whatever edge drift the flow already had,
      // which is a data change the user never asked for (see writeFlowsDual).
      await proj.writeFlowsDual(flows, [flowId], ['provenance']);
    }
  } catch {
    // no project overlaid — nothing to write
  }
};

export const confirmAllFlows = async () => {
  try {
    const flows = proj.flows();
    if (flows.some((f) => f.provenance === 'inferred')) {
      const confirmed = flows.filter((f) => f.provenance === 'inferred').map((f) => f.id);
      for (const f of flows) if (f.provenance === 'inferred') f.provenance = 'founder';
      // Only the ids this pass actually flipped, and only their `provenance` —
      // a flow already marked founder is untouched in answers too.
      await proj.writeFlowsDual(flows, confirmed, ['provenance']);
    }
  } catch {
    // no project overlaid — nothing to write
  }
};

// A correction: the form's fields ride the entry and override the prefill.
export const saveItem = (sd, surface, id, fields, prefs = {}, translate = (k) => k, locale = 'en') => {
  recordItem(sd, surface, id, { confirmed: true, edited: fields }, locale);
  return context(sd, surface, null, prefs, translate, locale);
};

export const skipItem = (sd, surface, id, prefs = {}, translate = (k) => k, locale = 'en') => {
  recordItem(sd, surface, id, { skipped: true }, locale);
  return context(sd, surface, null, prefs, translate, locale);
};

export const editItem = (sd, surface, id, prefs = {}, translate = (k) => k, locale = 'en') => {
  const st = stepState(sd, surface);
  if (st.answers[id]) st.editing = id;
  return context(sd, surface, null, prefs, translate, locale);
};

// Normal mode's convenience: accept every remaining prefill in one move.
export const acceptAll = (sd, surface, prefs = {}, translate = (k) => k, locale = 'en') => {
  const st = stepState(sd, surface);
  for (const i of stepItems(surface, locale)) st.answers[i.id] ??= { confirmed: true };
  return context(sd, surface, null, prefs, translate, locale);
};

// ---------- the composer round-trip ----------
const replyFor = (text, L) => {
  const lower = text.toLowerCase();
  return repo.replies(L).find((r) => r.match.some((k) => lower.includes(k))) ?? repo.replyFallback(L);
};

// Free-text chat: append the user's message and a simulated agent reply; the
// reply may pull an artifact onto the stage (chat docks right).
export const sendMessage = (sd, surface, text, prefs = {}, translate = (k) => k, locale = 'en') => {
  const s = S(sd);
  const seq = (s.msgSeq += 1);
  (s.extra[surface] ??= []).push({ id: `u-${seq}`, from: 'user', text });
  const reply = replyFor(text, locale);
  s.extra[surface].push({
    id: `a-${seq}`, from: 'agent',
    text: reply.text, textBalanced: reply.textBalanced, textPlain: reply.textPlain,
    artifactRef: reply.artifact ?? null,
    artifactLabel: reply.artifact ? translate('intake.cta.openArtifact', { label: chipLabel(reply.artifact, translate) }) : null,
  });
  if (reply.artifact && ARTIFACT_SURFACES.includes(surface)) { s.current[surface] = reply.artifact; (s.currentFile ??= {})[surface] = null; }
  return context(sd, surface, null, prefs, translate, locale);
};
