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
