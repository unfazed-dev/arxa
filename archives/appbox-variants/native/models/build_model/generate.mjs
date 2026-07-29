// Fixture generator — seed.json → run.json. The fixture is the denormalized
// projection a template wants: findings grouped by gate, summary counts.
// Never hand-edit run.json; edit the seed and re-run: node generate.mjs
import { readFileSync, writeFileSync } from 'node:fs';

const seed = JSON.parse(readFileSync(new URL('./seed.json', import.meta.url), 'utf8'));

const findingsByGate = {};
for (const f of seed.findings) {
  (findingsByGate[f.gate] ??= []).push(f);
}

const severities = [...new Set(seed.findings.map((f) => f.severity))];

const fixture = {
  ...seed,
  findingsByGate,
  filters: { severities, gates: Object.keys(findingsByGate) },
  counts: {
    findings: seed.findings.length,
    gatesPending: seed.humanGates.filter((g) => g.state === 'pending').length,
    stagesGreen: seed.stages.filter((s) => s.state === 'green').length,
  },
};

writeFileSync(new URL('./run.json', import.meta.url), JSON.stringify(fixture, null, 2) + '\n');
console.log(`run.json: ${seed.stages.length} stages, ${seed.findings.length} findings, ${seed.humanGates.length} human gates`);
