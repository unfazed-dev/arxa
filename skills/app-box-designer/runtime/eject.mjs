#!/usr/bin/env node
// Productionize (ADR-0008): eject an artifact into a self-contained Hono app.
// Usage: node runtime/eject.mjs <artifact-dir> <out-dir>
import { cpSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const [artifactArg, outArg] = process.argv.slice(2);
if (!artifactArg || !outArg) {
  console.error('Usage: node runtime/eject.mjs <artifact-dir> <out-dir>');
  process.exit(2);
}
const artifact = path.resolve(artifactArg);
const out = path.resolve(outArg);
const runtimeDir = path.dirname(fileURLToPath(import.meta.url));
const name =
  path
    .basename(artifact)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '') || 'artifact';

// 1. The artifact itself.
cpSync(artifact, out, { recursive: true });

// 2. The Runtime, inlined (source only — no node_modules, no dev fetch tooling).
for (const p of ['serve.mjs', 'lint.mjs', 'console-check.mjs', 'lib', 'vendor']) {
  cpSync(path.join(runtimeDir, p), path.join(out, 'runtime', p), { recursive: true });
}
rmSync(path.join(out, 'runtime', 'vendor', 'fetch.mjs'), { force: true });

// 3. package.json — deps inherited from the runtime's own manifest.
const runtimePkg = JSON.parse(readFileSync(path.join(runtimeDir, 'package.json'), 'utf8'));
const pkg = {
  name,
  version: '0.1.0',
  private: true,
  type: 'module',
  scripts: {
    start: 'node runtime/serve.mjs .',
    test: 'node --test',
    lint: 'node runtime/lint.mjs .',
  },
  dependencies: runtimePkg.dependencies,
};
writeFileSync(path.join(out, 'package.json'), JSON.stringify(pkg, null, 2) + '\n');

// 4. Baseline smoke test (extend per productionize.md §4).
mkdirSync(path.join(out, 'test'), { recursive: true });
writeFileSync(
  path.join(out, 'test', 'smoke.test.mjs'),
  `import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createArtifactApp } from '../runtime/lib/router.mjs';

const app = await createArtifactApp(process.cwd());

test('GET / renders a full page', async () => {
  const res = await app.request('/');
  assert.equal(res.status, 200);
  assert.match(await res.text(), /<html/i);
});

test('vendored htmx is served', async () => {
  const res = await app.request('/assets/vendor/htmx.min.js');
  assert.equal(res.status, 200);
});
`,
);

// 5. README with the hardening entry points.
writeFileSync(
  path.join(out, 'README.md'),
  `# ${name}

Ejected from a app-box-designer artifact — a self-contained Hono + htmx app
(server-rendered hypermedia, zero custom client-side JavaScript).

\`\`\`sh
npm install
npm start     # http://localhost:4319 (PORT env to change)
npm test      # request-level smoke tests (no listening server needed)
npm run lint  # zero-custom-client-JS contract
\`\`\`

## Layout

- \`app.routes.js\` — the URL inventory: [method, path, ViewModel handler]
- \`ui/views/<shell>_shell/<surface>/\` — view template + co-located ViewModel
- \`services/repositories|facades/\` — data access; **swap fixture Repositories
  for a real DB here** — ViewModels depend only on Facades, so nothing else changes
- \`runtime/\` — the vendored Runtime (serve, router, templates, state, timers)

## Hardening before production

Env config → Repository swap → session store swap (in-memory is single-process)
→ more tests → security headers → deploy (any Node ≥20 host; see
productionize.md in the originating skill for the full checklist).
`,
);

console.log(`ejected ${artifact} → ${out}`);
console.log(`next: cd ${out} && npm install && npm test && npm start`);
