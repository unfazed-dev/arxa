// Fixture generator — seed.json → run.json. The fixture is the denormalized
// projection a template wants: findings grouped by gate, summary counts,
// chart-ready numbers (stage durations as % of max, gate donut segments),
// pretty-printed artifact bodies for the side canvas.
// Never hand-edit run.json; edit the seed and re-run: node generate.mjs
import { readFileSync, writeFileSync } from 'node:fs';

const seed = JSON.parse(readFileSync(new URL('./seed.json', import.meta.url), 'utf8'));

const findingsByGate = {};
for (const f of seed.findings) {
  (findingsByGate[f.gate] ??= []).push(f);
}

const severities = [...new Set(seed.findings.map((f) => f.severity))];

// "3m 48s" → 228 · "12s" → 12 · "—" → null
const toSeconds = (d) => {
  if (!d || d === '—') return null;
  const m = d.match(/(?:(\d+)m)?\s*(?:(\d+)s)?/);
  return (Number(m[1] || 0) * 60) + Number(m[2] || 0);
};

const timed = seed.stages.filter((s) => toSeconds(s.duration) !== null);
const maxSec = Math.max(...timed.map((s) => toSeconds(s.duration)));
const pace = {
  // The chart title states the answer; the bars are the evidence.
  title: 'Design took the longest — 21m of the 34m elapsed',
  bars: timed.map((s) => ({
    id: s.id,
    label: s.label,
    duration: s.duration,
    pct: Math.max(2, Math.round((toSeconds(s.duration) / maxSec) * 100)),
    state: s.state,
  })),
};

const gateStates = ['approved', 'pending', 'queued'];
let acc = 0;
const gateChart = {
  total: seed.humanGates.length,
  segments: gateStates.map((state) => {
    const count = seed.humanGates.filter((g) => g.state === state).length;
    const seg = { state, count, from: Math.round(acc), to: Math.round(acc + (count / seed.humanGates.length) * 100) };
    acc += (count / seed.humanGates.length) * 100;
    return seg;
  }).filter((s) => s.count > 0),
};

const artifacts = Object.fromEntries(
  Object.entries(seed.artifacts).map(([k, a]) => [
    k,
    { ...a, pretty: a.body ? JSON.stringify(a.body, null, 2) : null },
  ]),
);

const fixture = {
  ...seed,
  findingsByGate,
  filters: { severities, gates: Object.keys(findingsByGate) },
  counts: {
    findings: seed.findings.length,
    gatesPending: seed.humanGates.filter((g) => g.state === 'pending').length,
    stagesGreen: seed.stages.filter((s) => s.state === 'green').length,
  },
  pace,
  gateChart,
  artifacts,
};

writeFileSync(new URL('./run.json', import.meta.url), JSON.stringify(fixture, null, 2) + '\n');
console.log(`run.json: ${seed.stages.length} stages, ${seed.findings.length} findings, ${seed.humanGates.length} human gates, ${pace.bars.length} pace bars`);
