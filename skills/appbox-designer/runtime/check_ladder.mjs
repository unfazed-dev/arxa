#!/usr/bin/env node
// Assert the ladder config and its doctrine agree, and that no rung sits on a
// window-size-class boundary.
//
// A doc that has drifted from the config is how a width nobody checks ends up
// being designed against. This is the drift check for the one config the whole
// design stage reads.
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const cfg = JSON.parse(readFileSync(join(HERE, 'ladder.json'), 'utf8'));
const doc = readFileSync(join(HERE, '..', 'references', 'viewport-ladder.md'), 'utf8');

const problems = [];

// Every rung in the config must appear in the doc's table with the same width.
for (const [name, r] of Object.entries(cfg.rungs)) {
  const row = doc.split('\n').find(
    (l) => l.includes(`\`${name}\``) && l.trimStart().startsWith('|'));
  if (!row) { problems.push(`doc has no table row for rung "${name}"`); continue; }
  if (!row.includes(String(r.width)))
    problems.push(`doc row for "${name}" does not carry width ${r.width}: ${row.trim()}`);
}

// Every rung named in the doc's table must exist in the config.
for (const l of doc.split('\n')) {
  const m = l.trimStart().startsWith('|') && l.match(/\|\s*`([a-z]+)`\s*\|\s*\*\*(\d+)\*\*/);
  if (m && !cfg.rungs[m[1]])
    problems.push(`doc names rung "${m[1]}" (${m[2]}px) that ladder.json does not define`);
}

// No rung may sit on a class boundary — the branch would be ambiguous.
for (const [name, r] of Object.entries(cfg.rungs))
  if (cfg.boundaries.includes(r.width))
    problems.push(`rung "${name}" sits ON boundary ${r.width} — renders are ambiguous there`);

if (problems.length) {
  for (const p of problems) console.error(`  ${p}`);
  process.exit(1);
}
console.log(`ladder ok: ${Object.entries(cfg.rungs).map(([n, r]) => `${n}=${r.width}`).join(' ')}`);
