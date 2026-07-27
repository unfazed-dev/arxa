// Exercises serve.mjs the way a UI would: spawn it, parse one line of stdout.
import { spawn, execSync } from 'node:child_process';

const S = 'skills/app-box-designer/runtime/serve.mjs';
let bad = 0;
const chk = (n, c, x = '') => { if (!c) bad++; console.log((c ? '  ok   ' : '  FAIL ') + n + x); };

// Resolves on a JSON line, a human ready line, process exit, or a deadline.
const start = (args) => new Promise((res) => {
  const p = spawn('node', [S, ...args]);
  let out = '', err = '', done = false;
  const fin = (o) => { if (!done) { done = true; res({ proc: p, out, err, ...o }); } };
  const t = setTimeout(() => fin({ rec: null, code: null }), 6000);
  p.stdout.on('data', (d) => {
    out += d;
    const line = out.split('\n').find((x) => x.trim().startsWith('{'));
    if (line) { try { const rec = JSON.parse(line); clearTimeout(t); fin({ rec, code: null }); } catch {} }
    // Human mode prints up to three lines; settle before resolving or the
    // last one (the exposed-host warning) is read as absent.
    else if (out.includes('http://')) {
      clearTimeout(t);
      setTimeout(() => fin({ rec: null, code: null }), 400);
    }
  });
  p.stderr.on('data', (d) => { err += d; });
  p.on('exit', (code) => { clearTimeout(t); fin({ rec: null, code }); });
});

const get = (u) => fetch(u).then((r) => r.status).catch(() => 0);

const r = await start(['app-box-app', '--port', '0', '--json']);
chk('resolves a bare design NAME', !!r.rec && /designs\/app-box-app$/.test(r.rec.artifact || ''));
chk('--port 0 reports the port actually bound', !!r.rec && r.rec.port > 0 && r.rec.port !== 4319,
    r.rec ? `  (:${r.rec.port})` : `  (no record; stderr: ${r.err.trim().slice(0, 80)})`);
chk('record carries url/port/host/pid/artifact',
    !!r.rec && ['url', 'port', 'host', 'pid', 'artifact'].every((k) => k in r.rec));
chk('the record URL answers 200', !!r.rec && (await get(r.rec.url)) === 200);

const ip = execSync('ipconfig getifaddr en0 || true').toString().trim();
if (ip && r.rec) {
  const lan = await fetch(`http://${ip}:${r.rec.port}/`).then((x) => x.status).catch(() => 'refused');
  chk('NOT reachable from the LAN by default', lan === 'refused', `  (${ip} -> ${lan})`);
}

const busy = await start(['app-box-app', '--port', String(r.rec.port), '--json']);
chk('collision exits non-zero', busy.code > 0, `  (exit ${busy.code})`);
chk('collision names the port, no stack trace',
    /already in use/.test(busy.err) && !/at Server|throw er/.test(busy.err));
chk('collision writes nothing to stdout', busy.out.trim() === '');

r.proc.kill('SIGTERM');
await new Promise((z) => setTimeout(z, 900));
chk('SIGTERM releases the port', (await get(`http://127.0.0.1:${r.rec.port}/`)) === 0);

const nope = await start(['no-such-design', '--json']);
chk('unknown design exits non-zero', nope.code > 0, `  (exit ${nope.code})`);
chk('unknown design lists the paths tried',
    /app\.routes\.js/.test(nope.err) && nope.err.split('\n').length > 3);

const legacy = await start(['designs/app-box-app', '--port', '4371']);
chk('legacy path + --port form still works', (await get('http://localhost:4371/')) === 200);
legacy.proc.kill('SIGTERM');

const open = await start(['app-box-app', '--port', '4372', '--host', '0.0.0.0']);
chk('--host 0.0.0.0 opt-in warns it is exposed', /every interface/.test(open.out));
open.proc.kill('SIGTERM');

console.log(bad ? `\n  FAILURES: ${bad}` : '\n  all green');
process.exit(bad ? 1 : 0);
