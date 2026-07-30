#!/usr/bin/env node
// app-box-designer Runtime — Serve CLI.
//
//   node serve.mjs <artifact-dir|design-name> [--port N] [--host H] [--json] [--no-watch]
//
// The target may be a path, or the bare name of a design — `app-box-app`
// resolves to `designs/app-box-app`. A UI offering "preview this prototype"
// has a name, not a path.
//
//   --port N    default 4319. `--port 0` asks the OS for a free one, which is
//               how a caller serves several prototypes without picking numbers.
//   --host H    default 127.0.0.1. See below.
//   --json      print one line of JSON once the socket is actually listening,
//               then keep serving. This is the machine-readable contract: a
//               parent process reads one line and knows the server is UP, not
//               merely spawned.
//   --no-watch  serve in-process with no file watching and no registry — the
//               ejected (productionized) app's start script uses this.
//
// Default mode is a dev server with hot reload + hot restart: a thin
// supervisor spawns the actual server as a child (`--worker`, internal) and
// watches the artifact AND the runtime's own code — any change restarts the
// child, so template, l10n, fixture, route and lib/*.mjs edits go live
// without a manual relaunch, always on the port that was reported. Sessions
// and timers ride out a reload: the child snapshots them to a per-artifact
// state file on shutdown and the next child restores them on boot. A child
// that crashes is respawned — unless it crashes 3 times in 10 seconds, in
// which case the supervisor stays down (but keeps watching) until the next
// file change.
//
// Ctrl+C (SIGINT) stops not just this instance but EVERY instance serving
// the same artifact — the stale-server-from-last-session problem. Instances
// are tracked as pidfiles under os.tmpdir()/app-box-designer-serve/ (one
// file per instance — no shared registry, no lock); a sibling pid is
// signalled only after `ps` confirms it is still a serve.mjs process — pids
// get reused. SIGTERM stops only the signalled instance: that is how a UI
// closing one preview leaves the others running.
import { serve } from '@hono/node-server';
import {
  existsSync, mkdirSync, readFileSync, writeFileSync, unlinkSync, readdirSync, watch,
} from 'node:fs';
import { spawn, execSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createArtifactApp } from './lib/router.mjs';
import { snapshotSessions, restoreSessions } from './lib/state.mjs';
import { snapshotTimers, restoreTimers } from './lib/timers.mjs';

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
let noWatch = false;
let worker = false; // internal: the supervisor spawns us with this

for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === '--port') port = Number(args[++i]);
  else if (a.startsWith('--port=')) port = Number(a.slice(7));
  else if (a === '--host') host = args[++i];
  else if (a.startsWith('--host=')) host = a.slice(7);
  else if (a === '--json') asJson = true;
  else if (a === '--no-watch') noWatch = true;
  else if (a === '--worker') worker = true;
  else if (a.startsWith('--')) fail(`unknown flag: ${a}`, 64);
  else target = a;
}

function fail(msg, code = 1) {
  // Errors go to stderr as plain text even under --json: a caller parsing
  // stdout must never mistake a failure for a ready record.
  console.error(msg);
  process.exit(code);
}

if (!target) fail('Usage: node serve.mjs <artifact-dir|design-name> [--port N] [--host H] [--json] [--no-watch]', 64);
if (!Number.isInteger(port) || port < 0 || port > 65535) fail(`not a port: ${port}`, 64);

// --- resolve the target ----------------------------------------------------
// A path wins. Otherwise treat it as a design name and look under designs/ —
// first relative to where the caller is, then walking up from the skill's own
// location (its depth in a checkout is not fixed: skills/… upstream,
// .kimi-code/skills/… here), so a UI can spawn this from anywhere.
const candidates = [
  path.resolve(target),
  path.resolve('designs', target),
];
for (let dir = HERE; ; dir = path.dirname(dir)) {
  candidates.push(path.join(dir, 'designs', target));
  if (path.dirname(dir) === dir) break;
}
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

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const shownHost = () => (host === '0.0.0.0' || host === '::' ? 'localhost' : host);

if (worker || noWatch) {
  // --- the actual server -----------------------------------------------------

  // Reload continuity: sessions/timers ride out a hot reload — the outgoing
  // child snapshots them on shutdown, the incoming child restores them here.
  // Keyed by artifact, so two designs never see each other's state.
  const stateFile = path.join(
    os.tmpdir(),
    `app-box-serve-state-${createHash('sha1').update(artifactDir).digest('hex').slice(0, 12)}.json`,
  );
  try {
    const s = JSON.parse(readFileSync(stateFile, 'utf8'));
    restoreSessions(s.sessions);
    restoreTimers(s.timers);
  } catch { /* no prior state — fresh boot */ }

  const app = await createArtifactApp(artifactDir);

  const server = serve({ fetch: app.fetch, port, hostname: host }, (info) => {
    // info.port is the port the OS actually bound, which is the only truth when
    // --port 0 was asked for. Reporting the requested port would hand a caller a
    // URL that answers nothing.
    const url = `http://${shownHost()}:${info.port}/`;
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
  // preview leaves nothing holding the port. Snapshot first — the supervisor's
  // next child restores exactly this.
  for (const sig of ['SIGINT', 'SIGTERM']) {
    process.on(sig, () => {
      try {
        writeFileSync(stateFile, JSON.stringify({
          sessions: snapshotSessions(),
          timers: snapshotTimers(),
        }));
      } catch { /* state is a nicety, never a reason to hang shutdown */ }
      server.close(() => process.exit(0));
    });
  }
} else {
  // --- supervisor: hot reload + hot restart + instance pidfiles ---------------
  const SELF = path.join(HERE, 'serve.mjs');

  let child = null;
  let childExit = Promise.resolve(0); // resolves with the current child's exit code
  let boundPort = null;
  let restarting = false;
  let shuttingDown = false;
  let everReady = false; // crash-respawn only after the first successful boot
  let crashes = []; // timestamps of unexpected child exits, for the respawn guard

  // Instance registry as a pidfile directory: one file per instance, owned and
  // written only by that instance — no shared mutable file, so no lock.
  const registryDir = path.join(os.tmpdir(), 'app-box-designer-serve');
  const selfFile = path.join(registryDir, `${process.pid}.json`);
  const register = () => {
    mkdirSync(registryDir, { recursive: true });
    writeFileSync(selfFile, JSON.stringify({ artifactDir }));
  };
  const deregister = () => {
    try { unlinkSync(selfFile); } catch { /* already gone */ }
  };

  // Spawn the worker; resolve with its ready record (it always runs --json so
  // "up" is a fact, not a hope), reject if it exits before reporting ready.
  function spawnChild(portToUse) {
    child = spawn(
      process.execPath,
      [SELF, artifactDir, '--worker', '--port', String(portToUse), '--host', host, '--json'],
      { stdio: ['ignore', 'pipe', 'inherit'] }, // worker stderr → our stderr
    );
    childExit = new Promise((res) => child.on('exit', res));
    childExit.then((code) => {
      if (restarting || shuttingDown || !everReady) return;
      const now = Date.now();
      crashes = crashes.filter((t) => now - t < 10_000);
      crashes.push(now);
      if (crashes.length >= 3) {
        // A crash-looping server that looks alive is worse than a stopped one.
        // Stay down; the watcher is still up, so the next file change retries.
        console.error('[serve] worker crashed 3 times in 10s — staying down; it restarts on the next file change');
        return;
      }
      console.error(`[serve] worker exited (${code}) — respawning`);
      respawn();
    });
    let buf = '';
    return new Promise((resolve, reject) => {
      child.stdout.on('data', (d) => {
        buf += d;
        const line = buf.split('\n').find((x) => x.trim().startsWith('{'));
        if (line) {
          try {
            resolve(JSON.parse(line));
          } catch { /* partial line — keep buffering */ }
        }
      });
      child.on('exit', (code) => reject(new Error(`worker exited (${code}) before ready`)));
    });
  }

  async function respawn() {
    try {
      const rec = await spawnChild(boundPort);
      boundPort = rec.port;
      crashes = [];
      console.error(`[serve] worker back → http://${shownHost()}:${rec.port}/`);
    } catch { /* that exit was already counted by the childExit handler */ }
  }

  async function stopChild() {
    child.kill('SIGTERM');
    const done = await Promise.race([childExit.then(() => true), sleep(2000).then(() => false)]);
    if (!done) {
      try { child.kill('SIGKILL'); } catch { /* already gone */ }
      await childExit;
    }
  }

  const IGNORE = /(^|[/\\])(node_modules|\.git|build|\.dart_tool)([/\\]|$)|\.DS_Store$/;
  let debounce = null;
  const changed = (file) => {
    if (IGNORE.test(file)) return;
    clearTimeout(debounce);
    debounce = setTimeout(() => {
      if (!shuttingDown && !restarting) reload(file);
    }, 200);
  };

  // fs.watch(recursive) exists on darwin/win32 only; elsewhere watch each
  // subdirectory instead, and re-walk after every reload so directories
  // created after startup get watched too.
  let recursiveWatch = true;
  const watchedDirs = new Set();
  function* subdirs(dir) {
    for (const d of readdirSync(dir, { withFileTypes: true })) {
      if (!d.isDirectory()) continue;
      const p = path.join(dir, d.name);
      if (IGNORE.test(p)) continue;
      yield p;
      yield* subdirs(p);
    }
  }
  function watchOne(dir) {
    if (watchedDirs.has(dir)) return;
    watchedDirs.add(dir);
    watch(dir, (_e, f) => f && changed(String(f)));
  }
  function watchTree(dir) {
    try {
      watch(dir, { recursive: true }, (_e, f) => f && changed(String(f)));
    } catch {
      recursiveWatch = false;
      watchOne(dir);
      for (const d of subdirs(dir)) watchOne(d);
    }
  }

  async function reload(reason) {
    restarting = true;
    console.error(`[serve] ${reason} changed — reloading`);
    await stopChild();
    try {
      const rec = await spawnChild(boundPort);
      boundPort = rec.port;
      crashes = [];
      console.error(`[serve] reloaded → http://${shownHost()}:${rec.port}/`);
    } catch {
      console.error('[serve] reload failed — the worker error is above; fix it and save again');
    }
    if (!recursiveWatch) watchTree(artifactDir); // pick up dirs created since boot
    restarting = false;
  }

  function killSiblings() {
    let files = [];
    try {
      files = readdirSync(registryDir);
    } catch {
      return;
    }
    for (const f of files) {
      const pid = Number(f.match(/^(\d+)\.json$/)?.[1]);
      if (!pid || pid === process.pid) continue;
      const file = path.join(registryDir, f);
      let entry;
      try {
        entry = JSON.parse(readFileSync(file, 'utf8'));
      } catch {
        continue;
      }
      if (entry.artifactDir !== artifactDir) continue;
      // "instances of itself only": a pid may have been reused by an unrelated
      // process since the pidfile was written — verify before signalling, and
      // sweep the file away when the pid is dead or no longer one of ours.
      try {
        const cmd = execSync(`ps -p ${pid} -o command=`, {
          encoding: 'utf8',
          stdio: ['ignore', 'pipe', 'ignore'],
        });
        if (cmd.includes('serve.mjs')) process.kill(pid, 'SIGTERM');
        else unlinkSync(file);
      } catch {
        try { unlinkSync(file); } catch { /* someone else swept it */ }
      }
    }
  }

  async function shutdown(code) {
    if (shuttingDown) return;
    shuttingDown = true;
    deregister();
    await stopChild();
    process.exit(code);
  }

  register();
  process.on('exit', deregister);
  process.on('SIGINT', () => {
    killSiblings();
    shutdown(0);
  });
  process.on('SIGTERM', () => shutdown(0));

  let rec;
  try {
    rec = await spawnChild(port);
  } catch (e) {
    // Startup failure (a port clash exits 69): the worker already said why on
    // stderr — propagate its code so a caller can tell clash from crash.
    process.exit(Number(e.message.match(/\((\d+)\)/)?.[1]) || 1);
  }
  boundPort = rec.port;
  everReady = true;

  if (asJson) {
    // pid is the supervisor — the process a caller manages and kills (its
    // SIGTERM takes the worker down with it). workerPid is the actual server.
    console.log(JSON.stringify({ ...rec, pid: process.pid, workerPid: rec.pid }));
  } else {
    console.log(`app-box-designer serving ${artifactDir}`);
    console.log(`→ http://${shownHost()}:${rec.port}/`);
    if (host === '0.0.0.0' || host === '::') {
      console.log('  (bound to every interface — reachable from your network)');
    }
    console.log('  watching for changes — Ctrl+C stops every instance of this design');
  }

  watchTree(artifactDir);
  watch(SELF, () => changed('serve.mjs'));
  watch(path.join(HERE, 'lib'), (_e, f) => f && changed(`lib/${f}`));
}
