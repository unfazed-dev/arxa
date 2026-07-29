// Fixture generator — seed.json → run.json. The fixture is the denormalized
// projection a template wants: durations in seconds, the duration-bar chart,
// summary counts. Never hand-edit run.json; edit the seed and re-run:
//   node models/build_model/generate.mjs
import { readFileSync, writeFileSync } from 'node:fs';

const seed = JSON.parse(readFileSync(new URL('./seed.json', import.meta.url), 'utf8'));

const toSecs = (d) => {
  const m = /^(?:(\d+)m\s*)?(?:(\d+)s)?$/.exec(d ?? '');
  return m ? (Number(m[1] ?? 0) * 60 + Number(m[2] ?? 0)) : 0;
};

// Duration chart — one bar per finished auto stage, longest bar carries the
// single warm hue (the datum that matters); red is reserved for failure.
const timed = seed.stages
  .filter((s) => s.kind === 'auto' && s.state !== 'queued')
  .map((s) => ({ id: s.id, label: s.label, duration: s.duration, secs: toSecs(s.duration) }));
const maxSecs = Math.max(...timed.map((b) => b.secs));
const chart = {
  bars: timed.map((b) => ({
    ...b,
    pct: Math.max(4, Math.round((b.secs / maxSecs) * 100)),
    hot: b.secs === maxSecs,
  })),
};
chart.title = `${timed.find((b) => b.secs === maxSecs).label} took the longest — ${timed.find((b) => b.secs === maxSecs).duration} of the run`;

const fixture = {
  ...seed,
  chart,
  counts: {
    findings: seed.findings.length,
    gatesPending: seed.humanGates.filter((g) => g.state === 'pending').length,
    stagesGreen: seed.stages.filter((s) => s.state === 'green').length,
  },
};

writeFileSync(new URL('./run.json', import.meta.url), JSON.stringify(fixture, null, 2) + '\n');
console.log(`run.json: ${seed.stages.length} stages, ${seed.findings.length} findings, ${chart.bars.length} chart bars`);
