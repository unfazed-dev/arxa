#!/usr/bin/env node
// Fixture generator — seed.json → fixture.json. The fixture is the on-disk
// shape the BuildRepository consumes: seed rows plus derived rollups
// (finding counts per gate/severity, stage index) so templates stay dumb.
// Nothing under models/ is hand-edited; edit the seed and re-run this.
import { readFileSync, writeFileSync } from 'node:fs';

const seed = JSON.parse(readFileSync(new URL('./seed.json', import.meta.url), 'utf8'));

const findingsByGate = {};
for (const f of seed.findings) {
  findingsByGate[f.gate] = findingsByGate[f.gate] || { error: 0, warning: 0, total: 0 };
  findingsByGate[f.gate][f.severity] += 1;
  findingsByGate[f.gate].total += 1;
}

const fixture = {
  ...seed,
  rollup: {
    findingsByGate,
    errors: seed.findings.filter((f) => f.severity === 'error').length,
    warnings: seed.findings.filter((f) => f.severity === 'warning').length,
    stagesPassed: seed.stages.filter((s) => s.status === 'pass').length,
    stageCount: seed.stages.length,
  },
};

writeFileSync(new URL('./fixture.json', import.meta.url), JSON.stringify(fixture, null, 2) + '\n');
console.log(`fixture.json written — ${fixture.rollup.errors} errors, ${fixture.rollup.warnings} warnings`);
