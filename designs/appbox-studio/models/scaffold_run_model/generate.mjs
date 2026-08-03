// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
//
// Fixture generator — run_seed.<locale>.json → scaffold_run.<locale>.json.
//
// Counts are DERIVED here rather than hand-listed in the seed, for the same
// reason scaffold_model derives its dependency closure: a hand-written count
// is a second source of truth that drifts silently the moment a write row is
// added. The template must never compute a total either — a receipt that does
// arithmetic in the view can disagree with the list printed beside it.
//
// Never hand-edit scaffold_run*.json fixtures; edit the seed and re-run:
//   node models/scaffold_run_model/generate.mjs
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';

const dir = new URL('./', import.meta.url);
const seeds = readdirSync(dir).filter((f) => /^run_seed\..+\.json$/.test(f));
if (!seeds.length) {
  console.error('no run_seed.<locale>.json found');
  process.exit(1);
}

for (const f of seeds.sort()) {
  const locale = f.match(/^run_seed\.(.+)\.json$/)[1];
  const seed = JSON.parse(readFileSync(new URL(f, import.meta.url), 'utf8'));

  const byKit = Object.fromEntries(seed.kits.map((k) => [k.id, k]));

  // Each write row carries its kit's readiness forward so the warning state
  // can point at the exact file that came from an unconfigured kit.
  const writes = seed.writes.map((w) => ({
    ...w,
    ready: w.kitId ? Boolean(byKit[w.kitId] && byKit[w.kitId].ready) : true,
  }));

  const counts = {
    created: writes.filter((w) => w.kind === 'created').length,
    updated: writes.filter((w) => w.kind === 'updated').length,
    skipped: writes.filter((w) => w.kind === 'skipped').length,
    total: writes.length,
    kits: seed.kits.length,
    warnings: seed.warnings.length,
    // The failed state stops partway: the receipt shows what actually landed
    // before the stop, not the full list, so the two never contradict.
    wroteBeforeFailure: seed.states.failed.wrote,
  };

  const unready = seed.kits.filter((k) => !k.ready).map((k) => k.id);

  const out = {
    _generated: 'DO NOT EDIT — run: node models/scaffold_run_model/generate.mjs',
    locale,
    structure: seed.structure,
    manifest: seed.manifest,
    kits: seed.kits,
    writes,
    deltas: seed.deltas,
    warnings: seed.warnings,
    states: seed.states,
    counts,
    unready,
  };

  const name = `scaffold_run.${locale}.json`;
  writeFileSync(new URL(name, import.meta.url), `${JSON.stringify(out, null, 2)}\n`);
  console.log(`${name}: ${counts.total} writes, ${counts.kits} kits, ${counts.warnings} warnings`);
}
