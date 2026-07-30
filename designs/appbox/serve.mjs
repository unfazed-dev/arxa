#!/usr/bin/env node
// Serve this design: `node serve.mjs [--port N] [--host H] [--json]`
//
// Thin wrapper — the actual server is the app-box-designer runtime
// (one implementation for every artifact, ADR-0001). This file just finds
// it by walking up from the design folder, so a design can be served
// without remembering where the skill lives.
import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));

let dir = here;
let runtimeServe;
for (;;) {
  const candidate = path.join(dir, '.kimi-code/skills/app-box-designer/runtime/serve.mjs');
  if (existsSync(candidate)) {
    runtimeServe = candidate;
    break;
  }
  const parent = path.dirname(dir);
  if (parent === dir) {
    console.error(
      'app-box-designer runtime not found above this folder ' +
        '(expected .kimi-code/skills/app-box-designer/runtime/serve.mjs)',
    );
    process.exit(66);
  }
  dir = parent;
}

// Hand the runtime this directory as its target, then run it.
process.argv = [process.argv[0], runtimeServe, here, ...process.argv.slice(2)];
await import(runtimeServe);
