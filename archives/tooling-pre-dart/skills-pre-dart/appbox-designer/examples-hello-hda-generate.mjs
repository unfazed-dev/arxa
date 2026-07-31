#!/usr/bin/env node
// greeting_model generator — seed is the SSOT; fixtures are never hand-edited.
// One fixture per locale seed:
//   greeting_seed.<locale>.json  →  greeting_fixtures.<locale>.json
// (pseudolocalize.mjs drops a greeting_seed.qps-ploc.json here; it flows
// through the same path). Run: node models/greeting_model/generate.mjs
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';

const dir = new URL('.', import.meta.url);
const seeds = readdirSync(dir).filter((f) => /^greeting_seed\..+\.json$/.test(f));
if (!seeds.length) {
  console.error('no greeting_seed.<locale>.json found');
  process.exit(66);
}
for (const f of seeds.sort()) {
  const locale = f.match(/^greeting_seed\.(.+)\.json$/)[1];
  const seed = JSON.parse(readFileSync(new URL(f, import.meta.url), 'utf8'));
  const out = { _generated_from: f, greetings: seed.greetings };
  writeFileSync(
    new URL(`greeting_fixtures.${locale}.json`, import.meta.url),
    JSON.stringify(out, null, 2) + '\n',
  );
  console.log(`greeting_fixtures.${locale}.json ← ${f}`);
}
