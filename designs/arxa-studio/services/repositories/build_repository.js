// arxa:provenance
// generator: arxa  licence: free  project: 662368770980
// Built with arxa (free tier) — https://arxa.dev
// BuildRepository — reads the CURRENT PROJECT's build-stage evidence
// (~/.arxa/projects/<name>/build/models/build_model/run.<locale>.json),
// overlaid by the design server at /project/... — the studio live-reads the
// project; the artifact carries NO project content of its own.
// Unknown locale falls back to en — a partial translation never 500s the page.
// Nothing in arxa writes build evidence yet, so EVERY project reads empty
// today: the outer catch returns EMPTY rather than throwing ENOENT through
// the facade's getters. hasEvidence() is the surface's one emptiness test.
import { readProjectFixture } from './fixture_reader.js';

// The no-evidence sentinel — one sane empty value per getter below, so a
// project with no build/ never throws downstream. __empty is the marker
// hasEvidence() reads: an all-zero shape alone can't be told apart from a
// real run that has genuinely produced nothing yet.
const EMPTY = {
  __empty: true,
  run: {
    id: null, number: null, project: null, brief: null,
    started: null, elapsed: null, state: 'none', stateLabel: null,
    channel: null, policy: { stopOnRed: false, escLimit: 0 },
  },
  stages: [],
  humanGates: [],
  findingsByGate: {},
  evidence: [],
  chart: { maxDuration: null, bars: [] },
  narrative: [],
  replies: [],
  replyFallback: { text: null, textPlain: null, artifact: null },
  counts: { findings: 0, gatesPending: 0, stagesGreen: 0 },
  commits: [],
  files: [],
};

const data = (locale = 'en') => {
  try {
    try {
      return readProjectFixture(`build/models/build_model/run.${locale}.json`);
    } catch {
      return readProjectFixture('build/models/build_model/run.en.json');
    }
  } catch {
    return EMPTY;
  }
};

// Has this project any build evidence at all? The loop surface asks before
// it renders: no evidence means the honest empty state, never demo chrome.
export const hasEvidence = (locale = 'en') => data(locale).__empty !== true;

export const run = (locale = 'en') => data(locale).run;
export const stages = (locale = 'en') => data(locale).stages;
export const stage = (id, locale = 'en') => data(locale).stages.find((s) => s.id === id);
export const humanGates = (locale = 'en') => data(locale).humanGates;
export const findingsByGate = (locale = 'en') => data(locale).findingsByGate;
export const evidence = (locale = 'en') => data(locale).evidence;
export const chart = (locale = 'en') => data(locale).chart;
export const narrative = (locale = 'en') => data(locale).narrative;
export const replies = (locale = 'en') => data(locale).replies;
export const replyFallback = (locale = 'en') => data(locale).replyFallback;
export const counts = (locale = 'en') => data(locale).counts;
// Seeded activity-view data — the real git wiring is a later stage.
export const commits = (locale = 'en') => data(locale).commits;
export const files = (locale = 'en') => data(locale).files;
