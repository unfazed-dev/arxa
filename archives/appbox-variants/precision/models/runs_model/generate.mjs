// Fixture generator — seed → on-disk fixture the runs repository consumes.
// Run: node models/runs_model/generate.mjs   (never hand-edit run.fixture.json)
import { readFileSync, writeFileSync } from 'node:fs';

const here = (p) => new URL(p, import.meta.url);
const seed = JSON.parse(readFileSync(here('./seed/run.seed.json'), 'utf8'));

// Shape: one denormalized run record, gates merged into the stage timeline
// so the view renders a single ordered list, plus findings grouped by gate.
const run = seed.run;
const timeline = [];
for (const stage of run.stages) {
  timeline.push({ kind: 'stage', ...stage });
  for (const gate of run.gates.filter((g) => g.after === stage.id)) {
    timeline.push({ kind: 'gate', ...gate });
  }
}
const findingGroups = run.gates
  .map((g) => ({
    gate: g.id,
    label: g.label,
    findings: run.findings.filter((f) => f.gate === g.id),
  }))
  .filter((g) => g.findings.length > 0);

const fixture = { ...run, timeline, findingGroups };
writeFileSync(here('./run.fixture.json'), JSON.stringify(fixture, null, 2) + '\n');
console.log(`run.fixture.json — ${timeline.length} timeline rows, ${run.findings.length} findings`);
