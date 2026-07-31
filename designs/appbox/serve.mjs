#!/usr/bin/env node
// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
// Serve this design: `node serve.mjs [--port N] [--host H] [--json] [--no-watch]`
//
// Thin wrapper — the actual server is the appbox-designer runtime
// (one implementation for every artifact, ADR-0001). This file just finds
// it by walking up from the design folder, so a design can be served
// without remembering where the skill lives.
//
// The runtime watches this design's files and reloads on change (hot reload);
// edits to the runtime's own code restart the server child (hot restart).
// Ctrl+C stops every instance serving this design, not just this one.
// `--no-watch` turns all of that off (ejected/production apps).
import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));

let dir = here;
let runtimeServe;
for (;;) {
  const candidate = path.join(dir, '.kimi-code/skills/appbox-designer/runtime/serve.mjs');
  if (existsSync(candidate)) {
    runtimeServe = candidate;
    break;
  }
  const parent = path.dirname(dir);
  if (parent === dir) {
    console.error(
      'appbox-designer runtime not found above this folder ' +
        '(expected .kimi-code/skills/appbox-designer/runtime/serve.mjs)',
    );
    process.exit(66);
  }
  dir = parent;
}

// Hand the runtime this directory as its target, then run it.
process.argv = [process.argv[0], runtimeServe, here, ...process.argv.slice(2)];
await import(runtimeServe);
