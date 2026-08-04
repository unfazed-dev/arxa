// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
// The per-screen PLAN SIDECAR — the edit composer's durable output (plan
// decision 13: plan storage is a per-screen file in the PROJECT, versioned
// with it, and the edit composer reads it back as context).
//
// Path: design/plans/<screenId>.json inside the live-read project. The plan
// record's decision 13 shows a `.md` example; the shipped format is `.json`
// because the entries are MACHINE-READABLE (the composer appends them, the
// plan editor round-trips them, a later LLM pass consumes them) — prose
// markdown cannot carry `scope`/`status` without a second parser.
//
// No prefetch change was needed to read these back after a restart:
// worker.dart `_scanArtifact` already maps EVERY project `**.json` to the
// fixture key `$origin/project/<rel>` (worker.dart:202-204, over the
// recursive `_walk` at :222-226) — which is exactly the key
// readOptionalProjectFixture builds (fixture_reader.js:44). The surfaces
// branch needed its own `/project-src/` key only because it prefetches raw
// .html SOURCE, and its index.json exists only for discovery; we read by
// exact screen id, so we need neither.
import { readOptionalProjectFixture, writeProjectFixture } from './fixture_reader.js';

export const planRel = (screenId) => `design/plans/${screenId}.json`;

const bad = (msg) => {
  const err = new Error(msg);
  err.status = 400;
  throw err;
};

// A screen with no sidecar is a NORMAL EMPTY STATE, not an error — every
// project made before this increment is in it. readOptionalProjectFixture
// draws exactly that line: absent → null, present-but-unparseable → throws
// (a corrupt plan is a fault worth surfacing, not an empty list).
export const readPlan = (screenId) => {
  const doc = readOptionalProjectFixture(planRel(screenId));
  const entries = Array.isArray(doc?.entries) ? doc.entries : [];
  return { screen: screenId, entries };
};

// One writer, so the on-disk shape is stated once. `screen` is redundant with
// the filename on purpose: a plan file that gets copied or hand-moved still
// says which screen it belongs to.
const write = async (screenId, entries) => {
  await writeProjectFixture(planRel(screenId), { screen: screenId, entries });
  return { screen: screenId, entries };
};

// The composer's append. Shape per the increment spec:
//   { ts, scope: { screen, widget? }, text, status: 'pending' }
export const appendIntent = async (screenId, text, scope = {}) => {
  const body = String(text ?? '').trim();
  if (!body) bad('empty intent');
  const { entries } = readPlan(screenId);
  const entry = {
    ts: new Date().toISOString(),
    scope: { screen: screenId, ...(scope.widget ? { widget: scope.widget } : {}) },
    text: body,
    status: 'pending',
  };
  return write(screenId, [...entries, entry]);
};

export const removeIntent = async (screenId, index) => {
  const { entries } = readPlan(screenId);
  const i = Number(index);
  if (!Number.isInteger(i) || i < 0 || i >= entries.length) bad('no such plan entry');
  return write(screenId, entries.filter((_, n) => n !== i));
};

// The plan editor's raw round-trip. Rejecting bad JSON with a 400 (rather
// than salvaging it) keeps the sidecar's shape a contract: a plan the server
// cannot read is a plan the next stage cannot execute, and silently rewriting
// the user's text would lose the edit they were mid-way through.
export const replacePlan = async (screenId, raw) => {
  let doc;
  try {
    doc = JSON.parse(String(raw ?? ''));
  } catch {
    bad('plan is not valid JSON');
  }
  const list = Array.isArray(doc) ? doc : doc?.entries;
  if (!Array.isArray(list)) bad('plan needs an entries array');
  const entries = list.map((e) => {
    const text = String(e?.text ?? '').trim();
    if (!text) bad('every entry needs text');
    return {
      ...(e.ts ? { ts: String(e.ts) } : {}),
      scope: { screen: screenId, ...(e?.scope?.widget ? { widget: String(e.scope.widget) } : {}) },
      text,
      status: e?.status === 'done' ? 'done' : 'pending',
    };
  });
  return write(screenId, entries);
};
