// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
// Shared fixture reader — the only file that touches models/ JSON on disk.
// Repositories build on this; the productionize DB swap happens behind them.
//
// Two roots:
//   readFixture        — the ARTIFACT (the studio's own design, in the repo)
//   readProjectFixture — the CURRENT PROJECT (~/.appbox/projects/<name>),
//                        overlaid by the design server at /project/<rel>
//                        (see _scanArtifact in appboxd/lib/design_server/worker.dart)
import { existsSync, readFileSync } from 'node:fs';

const cache = new Map();

export function readFixture(relFromThisFile) {
  if (!cache.has(relFromThisFile)) {
    cache.set(relFromThisFile, JSON.parse(readFileSync(new URL(relFromThisFile, import.meta.url), 'utf8')));
  }
  return cache.get(relFromThisFile);
}

// A fixture inside the live-read project: rel is project-relative
// ('design/models/design_model/run.en.json', 'intake/flows.json').
export function readProjectFixture(rel) {
  return readFixture(`../../project/${rel}`);
}

// A project fixture that MAY LEGITIMATELY NOT EXIST — absent → null, present
// but unparseable → still throws.
//
// That split is the whole point of the function. A project whose story-mapper
// or moodboarder has never run has no intake/map.json AT ALL — the state every
// project made before Slice B is in — and the surface must say so plainly.
// A map.json that exists but does not parse is a FAULT; folding it into the
// same reassuring "nothing here yet" sentence would hide a real break behind
// an explanation of a different problem.
//
// existsSync rather than try/catch on the read because the two environments
// throw differently: real node throws ENOENT with a `.code`, the worker's
// fs_shim throws a bare Error (worker_assets/fs_shim.js:9). Both implement
// existsSync over the same key, so probing is the only test that agrees.
export function readOptionalProjectFixture(rel) {
  const key = `../../project/${rel}`;
  if (cache.has(key)) return cache.get(key);
  if (!existsSync(new URL(key, import.meta.url))) return null;
  return readFixture(key);
}

// Write one project fixture through the design server's confined channel
// (POST /__project_write) — the studio EDITS the current project: flow
// confirms, tile reorders, membership. Async (viewmodels are); updates the
// worker's prefetched map + busts the read cache so the re-render that
// follows sees the new bytes immediately (the project watcher also reloads,
// ~200ms later, for every OTHER client).
export async function writeProjectFixture(rel, value, { project } = {}) {
  const body = typeof value === 'string' ? value : `${JSON.stringify(value, null, 2)}\n`;
  const origin = new URL('../../', import.meta.url).href.replace(/\/$/, '');
  const res = await fetch(`${origin}/__project_write`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ path: rel, body, ...(project ? { project } : {}) }),
  });
  if (!res.ok) throw new Error(`project write failed (${res.status}): ${await res.text()}`);
  if (!project) {
    globalThis.__fixtures[`${origin}/project/${rel}`] = body;
    cache.delete(`../../project/${rel}`);
  }
}
