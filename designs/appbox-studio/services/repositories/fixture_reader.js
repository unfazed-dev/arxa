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
import { readFileSync } from 'node:fs';

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

// Write one project fixture through the design server's confined channel
// (POST /__project_write) — the studio EDITS the current project: flow
// confirms, tile reorders, membership. Async (viewmodels are); updates the
// worker's prefetched map + busts the read cache so the re-render that
// follows sees the new bytes immediately (the project watcher also reloads,
// ~200ms later, for every OTHER client).
export async function writeProjectFixture(rel, value) {
  const body = typeof value === 'string' ? value : `${JSON.stringify(value, null, 2)}\n`;
  const origin = new URL('../../', import.meta.url).href.replace(/\/$/, '');
  const res = await fetch(`${origin}/__project_write`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ path: rel, body }),
  });
  if (!res.ok) throw new Error(`project write failed (${res.status}): ${await res.text()}`);
  globalThis.__fixtures[`${origin}/project/${rel}`] = body;
  cache.delete(`../../project/${rel}`);
}
