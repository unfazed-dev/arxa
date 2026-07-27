#!/usr/bin/env node
// app-box-designer Runtime — Serve CLI.
//
//   node serve.mjs <artifact-dir|design-name> [--port N] [--host H] [--json]
//
// The target may be a path, or the bare name of a design — `app-box-app`
// resolves to `designs/app-box-app`. A UI offering "preview this prototype"
// has a name, not a path.
//
//   --port N   default 4319. `--port 0` asks the OS for a free one, which is
//              how a caller serves several prototypes without picking numbers.
//   --host H   default 127.0.0.1. See below.
//   --json     print one line of JSON once the socket is actually listening,
//              then keep serving. This is the machine-readable contract: a
//              parent process reads one line and knows the server is UP, not
//              merely spawned.
import { serve } from '@hono/node-server';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createArtifactApp } from './lib/router.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));

const args = process.argv.slice(2);
let target;
let port = process.env.PORT !== undefined ? Number(process.env.PORT) : 4319;
// Loopback by default. A prototype is unreleased client work, and the previous
// default bound every interface — it was reachable from any machine on the
// same wifi, which is not a thing anyone opted into. `--host 0.0.0.0` is still
// available for previewing on a phone, but it is now a decision.
let host = process.env.HOST || '127.0.0.1';
let asJson = false;

for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === '--port') port = Number(args[++i]);
  else if (a.startsWith('--port=')) port = Number(a.slice(7));
  else if (a === '--host') host = args[++i];
  else if (a.startsWith('--host=')) host = a.slice(7);
  else if (a === '--json') asJson = true;
  else if (a.startsWith('--')) fail(`unknown flag: ${a}`, 64);
  else target = a;
}

function fail(msg, code = 1) {
  // Errors go to stderr as plain text even under --json: a caller parsing
  // stdout must never mistake a failure for a ready record.
  console.error(msg);
  process.exit(code);
}

if (!target) fail('Usage: node serve.mjs <artifact-dir|design-name> [--port N] [--host H] [--json]', 64);
if (!Number.isInteger(port) || port < 0 || port > 65535) fail(`not a port: ${port}`, 64);

// --- resolve the target ----------------------------------------------------
// A path wins. Otherwise treat it as a design name and look under designs/ —
// first relative to where the caller is, then relative to the repo the skill
// lives in, so a UI can spawn this from anywhere.
const candidates = [
  path.resolve(target),
  path.resolve('designs', target),
  path.resolve(HERE, '../../..', 'designs', target),
];
const artifactDir = candidates.find((c) => existsSync(path.join(c, 'app.routes.js')));

if (!artifactDir) {
  // Name what was tried. "no such artifact" without the search path is the
  // kind of error that costs ten minutes to a wrong working directory.
  const tried = [...new Set(candidates)].map((c) => `  ${c}`).join('\n');
  fail(
    `no artifact at "${target}" — every candidate lacked app.routes.js:\n${tried}`,
    66,
  );
}

const app = await createArtifactApp(artifactDir);

const server = serve({ fetch: app.fetch, port, hostname: host }, (info) => {
  // info.port is the port the OS actually bound, which is the only truth when
  // --port 0 was asked for. Reporting the requested port would hand a caller a
  // URL that answers nothing.
  const shown = host === '0.0.0.0' || host === '::' ? 'localhost' : host;
  const url = `http://${shown}:${info.port}/`;
  if (asJson) {
    console.log(JSON.stringify({ url, port: info.port, host, pid: process.pid, artifact: artifactDir }));
  } else {
    console.log(`app-box-designer serving ${artifactDir}`);
    console.log(`→ ${url}`);
    if (host === '0.0.0.0' || host === '::') {
      console.log('  (bound to every interface — reachable from your network)');
    }
  }
});

// A port clash used to surface as an unhandled 'error' event: a raw stack
// trace on stderr and an exit code of 0. A caller could not tell that from
// success, so a UI would sit waiting for a server that never started.
server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    fail(`port ${port} is already in use on ${host} — pass --port 0 for any free port`, 69);
  }
  if (err.code === 'EACCES') fail(`not allowed to bind ${host}:${port}`, 77);
  fail(`${err.code || 'error'}: ${err.message}`, 70);
});

// Shut down on the signals a parent process actually sends, so a UI closing a
// preview leaves nothing holding the port.
for (const sig of ['SIGINT', 'SIGTERM']) {
  process.on(sig, () => server.close(() => process.exit(0)));
}
