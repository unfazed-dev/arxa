// arxa:provenance
// generator: arxa  licence: free  project: 662368770980
// Built with arxa (free tier) — https://arxa.dev
// Fixture generator — build_seed.<locale>.json → run.<locale>.json (+ run.json
// as the en alias). The fixture is the denormalized projection a template
// wants: findings grouped by gate, stage durations as chart-ready
// percentages, summary counts.
// Never hand-edit run*.json fixtures; edit the seed and re-run: node generate.mjs
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';

const dir = new URL('.', import.meta.url);
const seeds = readdirSync(dir).filter((f) => /^build_seed\..+\.json$/.test(f));
if (!seeds.length) {
  console.error('no build_seed.<locale>.json found');
  process.exit(66);
}

for (const f of seeds.sort()) {
  const locale = f.match(/^build_seed\.(.+)\.json$/)[1];
  const seed = JSON.parse(readFileSync(new URL(f, import.meta.url), 'utf8'));

  const findingsByGate = {};
  for (const finding of seed.findings) {
    (findingsByGate[finding.gate] ??= []).push(finding);
  }

  // Chart projection: one bar per stage that consumed wall-clock time.
  const timed = seed.stages.filter((s) => s.durationSec > 0);
  const maxSec = Math.max(...timed.map((s) => s.durationSec));
  const chart = {
    maxDuration: timed.reduce((a, s) => (s.durationSec > a.durationSec ? s : a), timed[0]),
    bars: timed.map((s) => ({
      id: s.id,
      label: s.label,
      duration: s.duration,
      pct: Math.max(2, Math.round((s.durationSec / maxSec) * 100)),
      state: s.state,
    })),
  };

  const fixture = {
    ...seed,
    findingsByGate,
    chart,
    counts: {
      findings: seed.findings.length,
      gatesPending: seed.humanGates.filter((g) => g.state === 'pending').length,
      stagesGreen: seed.stages.filter((s) => s.state === 'green').length,
    },
  };

  writeFileSync(new URL(`run.${locale}.json`, import.meta.url), JSON.stringify(fixture, null, 2) + '\n');
  console.log(`run.${locale}.json ← ${f}: ${seed.stages.length} stages, ${seed.findings.length} findings, ${seed.humanGates.length} human gates, ${seed.narrative.length} narrative messages`);
}

// Un-suffixed alias = en, for anything that still reads run.json directly.
const en = JSON.parse(readFileSync(new URL('./run.en.json', import.meta.url), 'utf8'));
writeFileSync(new URL('./run.json', import.meta.url), JSON.stringify(en, null, 2) + '\n');
console.log('run.json ← run.en.json (alias)');
