// Fixture generator — seed.json → run.json. The fixture is the denormalized
// projection a template wants: findings grouped by gate, stage durations as
// chart-ready percentages, summary counts.
// Never hand-edit run.json; edit the seed and re-run: node generate.mjs
import { readFileSync, writeFileSync } from 'node:fs';

const seed = JSON.parse(readFileSync(new URL('./seed.json', import.meta.url), 'utf8'));

const findingsByGate = {};
for (const f of seed.findings) {
  (findingsByGate[f.gate] ??= []).push(f);
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

writeFileSync(new URL('./run.json', import.meta.url), JSON.stringify(fixture, null, 2) + '\n');
console.log(`run.json: ${seed.stages.length} stages, ${seed.findings.length} findings, ${seed.humanGates.length} human gates, ${seed.narrative.length} narrative messages`);
