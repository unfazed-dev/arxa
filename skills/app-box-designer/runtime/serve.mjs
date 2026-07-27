#!/usr/bin/env node
// app-box-designer Runtime — Serve CLI.
// Usage: node serve.mjs <artifact-dir> [--port N]   (default port 4319)
import { serve } from '@hono/node-server';
import path from 'node:path';
import { createArtifactApp } from './lib/router.mjs';

const args = process.argv.slice(2);
let dir;
let port = Number(process.env.PORT) || 4319;
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--port') port = Number(args[++i]);
  else if (args[i].startsWith('--port=')) port = Number(args[i].slice(7));
  else if (!args[i].startsWith('--')) dir = args[i];
}

if (!dir) {
  console.error('Usage: node serve.mjs <artifact-dir> [--port N]');
  process.exit(1);
}

const artifactDir = path.resolve(dir);
const app = await createArtifactApp(artifactDir);

serve({ fetch: app.fetch, port }, (info) => {
  console.log(`app-box-designer serving ${artifactDir}`);
  console.log(`→ http://localhost:${info.port}/`);
});
