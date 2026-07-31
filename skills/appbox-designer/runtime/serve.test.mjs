// Exercises serve.mjs the way a UI would: spawn it, parse one line of stdout.
// Every path derives from this file's location, never the caller's CWD.
//
// Covers the ready-record contract, port collisions, name resolution, and the
// supervisor behaviors: hot reload, state continuity across a reload, and the
// SIGTERM-one / SIGINT-all kill semantics.
import { spawn, execSync } from 'node:child_process';
import { cpSync, existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const S = path.join(HERE, 'serve.mjs');
const HELLO = path.join(HERE, '..', 'examples', 'hello-hda');
const REGISTRY_DIR = path.join(os.tmpdir(), 'appbox-designer-serve');

// The repo root is the first ancestor holding designs/appbox — the skill's
// depth in a checkout is not fixed (.kimi-code/skills/… here, skills/… upstream).
let ROOT = HERE;
for (;;) {
  if (existsSync(path.join(ROOT, 'designs', 'appbox', 'app.routes.js'))) break;
  const parent = path.dirname(ROOT);
  if (parent === ROOT) {
    console.error('no repo root with designs/appbox above this file');
    process.exit(64);
  }
  ROOT = parent;
}

let bad = 0;
const chk = (n, c, x = '') => { if (!c) bad++; console.log((c ? '  ok   ' : '  FAIL ') + n + x); };

const waitFor = async (fn, ms = 8000) => {
  const t0 = Date.now();
  for (;;) {
    if (await fn()) return true;
    if (Date.now() - t0 > ms) return false;
    await new Promise((z) => setTimeout(z, 200));
  }
};

// Short-lived runs: resolves on a JSON line, a human ready line, process exit,
// or a deadline.
const start = (args) => new Promise((res) => {
  const p = spawn('node', [S, ...args], { cwd: ROOT });
  let out = '', err = '', done = false;
  const fin = (o) => { if (!done) { done = true; res({ proc: p, out, err, ...o }); } };
  const t = setTimeout(() => fin({ rec: null, code: null }), 6000);
  p.stdout.on('data', (d) => {
    out += d;
    const line = out.split('\n').find((x) => x.trim().startsWith('{'));
    if (line) { try { const rec = JSON.parse(line); clearTimeout(t); fin({ rec, code: null }); } catch {} }
    // Human mode prints several lines; settle before resolving or the last one
    // (the exposed-host warning) is read as absent.
    else if (out.includes('http://')) {
      clearTimeout(t);
      setTimeout(() => fin({ rec: null, code: null }), 400);
    }
  });
  p.stderr.on('data', (d) => { err += d; });
  p.on('exit', (code) => { clearTimeout(t); fin({ rec: null, code }); });
});

// Long-lived instances: live accumulators (reload notices land on stderr) and
// the parsed ready record once it arrives.
const startLive = (args) => {
  const p = spawn('node', [S, ...args], { cwd: ROOT });
  const live = { proc: p, out: '', err: '', rec: null };
  p.stdout.on('data', (d) => {
    live.out += d;
    const line = live.out.split('\n').find((x) => x.trim().startsWith('{'));
    if (line && !live.rec) { try { live.rec = JSON.parse(line); } catch {} }
  });
  p.stderr.on('data', (d) => { live.err += d; });
  return live;
};

const get = (u) => fetch(u).then((r) => r.status).catch(() => 0);
const body = (u) => fetch(u).then((r) => r.text()).catch(() => '');
const dead = (u) => get(u).then((s) => s === 0);

// --- resolution + ready-record contract --------------------------------------
const r = await start(['appbox', '--port', '0', '--json']);
chk('resolves a bare design NAME', !!r.rec && /designs\/appbox$/.test(r.rec.artifact || ''));
chk('--port 0 reports the port actually bound', !!r.rec && r.rec.port > 0 && r.rec.port !== 4319,
    r.rec ? `  (:${r.rec.port})` : `  (no record; stderr: ${r.err.trim().slice(0, 80)})`);
chk('record carries url/port/host/pid/artifact/workerPid',
    !!r.rec && ['url', 'port', 'host', 'pid', 'artifact', 'workerPid'].every((k) => k in r.rec));
chk('record pid is the supervisor, workerPid the server',
    !!r.rec && r.rec.pid === r.proc.pid && r.rec.workerPid !== r.rec.pid);
chk('the record URL answers 200', !!r.rec && (await get(r.rec.url)) === 200);

const ip = execSync('ipconfig getifaddr en0 || true').toString().trim();
if (ip && r.rec) {
  const lan = await fetch(`http://${ip}:${r.rec.port}/`).then((x) => x.status).catch(() => 'refused');
  chk('NOT reachable from the LAN by default', lan === 'refused', `  (${ip} -> ${lan})`);
}

// --- port collision ------------------------------------------------------------
const busy = await start(['appbox', '--port', String(r.rec.port), '--json']);
chk('collision exits non-zero', busy.code > 0, `  (exit ${busy.code})`);
chk('collision names the port, no stack trace',
    /already in use/.test(busy.err) && !/at Server|throw er/.test(busy.err));
chk('collision writes nothing to stdout', busy.out.trim() === '');

r.proc.kill('SIGTERM');
chk('SIGTERM releases the port', await waitFor(() => dead(`http://127.0.0.1:${r.rec.port}/`)));

const nope = await start(['no-such-design', '--json']);
chk('unknown design exits non-zero', nope.code > 0, `  (exit ${nope.code})`);
chk('unknown design lists the paths tried',
    /app\.routes\.js/.test(nope.err) && nope.err.split('\n').length > 3);

const legacy = await start(['designs/appbox', '--port', '4371']);
chk('legacy path + --port form still works', (await get('http://localhost:4371/')) === 200);
legacy.proc.kill('SIGTERM');
await waitFor(() => dead('http://localhost:4371/'));

const open = await start(['appbox', '--port', '4372', '--host', '0.0.0.0']);
chk('--host 0.0.0.0 opt-in warns it is exposed', /every interface/.test(open.out));
open.proc.kill('SIGTERM');
await waitFor(() => dead('http://localhost:4372/'));

// --- hot reload + state continuity (throwaway copy of hello-hda) ---------------
const ART = path.join(mkdtempSync(path.join(os.tmpdir(), 'appbox-serve-test-')), 'artifact');
cpSync(HELLO, ART, { recursive: true });

const live = startLive([ART, '--port', '0', '--json']);
await waitFor(() => live.rec);
const rec = live.rec;
chk('temp artifact boots', !!rec, rec ? `  (:${rec.port})` : `  (${live.err.trim().slice(0, 120)})`);

if (rec) {
  const baseHtml = path.join(ART, 'ui/common/base.html');
  const orig = readFileSync(baseHtml, 'utf8');
  writeFileSync(baseHtml, orig.replace('</body>', '<!-- serve-probe --></body>'));
  chk('hot reload serves a template edit on the same port',
      await waitFor(async () => (await body(rec.url)).includes('serve-probe')));
  writeFileSync(baseHtml, orig);
  // A failed fetch returns '' — require a real 200 body without the probe, so
  // this cannot pass mid-reload before the new worker is up.
  chk('hot reload picks the revert up too',
      await waitFor(async () => {
        const b = await body(rec.url);
        return b.length > 0 && !b.includes('serve-probe');
      }));

  // Server-side timers (ADR-0004) must ride out a reload: start the 30s timer,
  // force a reload, and the tick must still be counting — not reset, not done.
  await fetch(`${rec.url}timer`);
  const vm = path.join(ART, 'ui/views/main_shell/timer/timer_viewmodel.js');
  const mark = live.err.length; // earlier probes already logged 'reloaded'
  writeFileSync(vm, readFileSync(vm, 'utf8') + '\n// probe\n');
  const reloaded = await waitFor(() => live.err.slice(mark).includes('reloaded'));
  const tick = await body(`${rec.url}timer/tick`);
  chk('a reload preserves server-side timers', reloaded && />\d+s</.test(tick),
      `  (tick: ${tick.trim().slice(0, 80)})`);

  live.proc.kill('SIGTERM');
  await waitFor(() => dead(rec.url));
}

// --- kill semantics -------------------------------------------------------------
const k1 = startLive([ART, '--port', '0', '--json']);
const k2 = startLive([ART, '--port', '0', '--json']);
await waitFor(() => k1.rec && k2.rec);
k1.proc.kill('SIGTERM');
chk('SIGTERM stops only the signalled instance',
    (await waitFor(() => dead(k1.rec.url))) && (await get(k2.rec.url)) === 200);

const k3 = startLive([ART, '--port', '0', '--json']);
await waitFor(() => k3.rec);
k2.proc.kill('SIGINT');
chk('Ctrl+C stops every instance serving the same artifact',
    (await waitFor(() => dead(k2.rec.url))) && (await waitFor(() => dead(k3.rec.url))));

const left = (() => { try { return readdirSync(REGISTRY_DIR); } catch { return []; } })();
chk('pidfiles are swept after exit',
    ![k1, k2, k3].some((k) => left.includes(`${k.proc.pid}.json`)));

rmSync(ART, { recursive: true, force: true });

console.log(bad ? `\n  FAILURES: ${bad}` : '\n  all green');
process.exit(bad ? 1 : 0);
