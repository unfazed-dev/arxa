// Phase 0 spike — hello-hda served by REAL Hono on Node, artifact unchanged.
//
//   node server.js <artifact-dir> [--port N]
//
// The `lib/*.mjs` modules (ported from the archived pre-Dart runtime, which is
// the canonical source worker_shim.js was derived from) provide the `h`
// helpers on real Hono's `c` context. fixture_reader.js works unchanged
// (native node:fs). This file is just the entry point.
import { serve } from '@hono/node-server';
import { createArtifactApp } from './lib/router.mjs';

const args = process.argv.slice(2);
let artifactDir = null;
let port = 4319;
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--port') port = Number(args[++i]);
  else if (args[i].startsWith('--port=')) port = Number(args[i].slice(7));
  else artifactDir = args[i];
}
if (!artifactDir) {
  console.error('Usage: node server.js <artifact-dir> [--port N]');
  process.exit(64);
}

const app = await createArtifactApp(artifactDir);
serve({ fetch: app.fetch, port, hostname: '127.0.0.1' }, (info) => {
  console.log(`spike (real Hono) → http://127.0.0.1:${info.port}/`);
});
