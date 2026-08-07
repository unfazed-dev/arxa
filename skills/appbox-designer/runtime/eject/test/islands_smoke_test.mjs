// @ts-check
// islands_smoke_test.mjs — browser-level smoke test for the ejected island
// machinery (assets/islands.js + assets/island-kit.js + a vendored
// micro-island). Would have caught review R1 (islands dead on arrival:
// bare effectScope() call, undefined `fn`) — Dart tests never execute the
// shipped JS.
//
// Zero dependencies: a node:http static server + headless Chrome driven over
// raw CDP (Node ≥22 built-in WebSocket). Chrome path via $CHROME_PATH or the
// usual macOS/Linux locations.
//
// Run: node skills/appbox-designer/runtime/eject/test/islands_smoke_test.mjs

import { spawn } from 'node:child_process';
import crypto from 'node:crypto';
import { existsSync } from 'node:fs';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import http from 'node:http';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const assetsDir = path.join(here, '..', 'assets');
const vendorDir = path.join(here, '..', '..', 'vendor');

const MIME = { '.js': 'text/javascript', '.html': 'text/html', '.json': 'application/json' };

/** sha384 SRI of a buffer, same format the eject pipeline stamps. */
function sri(buf) {
  return 'sha384-' + crypto.createHash('sha384').update(buf).digest('base64');
}

// --- Fixture ----------------------------------------------------------------
// One counter island (real vendored module, SRI-verified through the
// manifest), one defineIsland() inline island, one host for an htmx-driven
// swap (exercises the htmx 4 htmx_after_process extension hook).

async function buildFixture() {
  const counterSrc = await readFile(path.join(vendorDir, 'counter_island.js'));
  const formStateSrc = await readFile(path.join(vendorDir, 'form-state_island.js'));
  const manifest = {
    counter: { src: '/assets/islands/counter.js', integrity: sri(counterSrc) },
    'form-state': { src: '/assets/islands/form-state.js', integrity: sri(formStateSrc) },
  };
  const page = `<!doctype html>
<html><head><meta charset="utf-8"><title>islands smoke</title></head>
<body>
  <div hx-island="counter" hx-island-when="load" id="c1">
    <button data-on:click="dec">−</button>
    <span data-text="count">0</span>
    <button id="inc" data-on:click="inc">+</button>
    <script type="application/json" data-island-state="counter">{"count":41}</script>
  </div>

  <div hx-island="greeter" hx-island-when="load" id="g1">
    <span data-text="msg">?</span>
  </div>

  <div hx-island="form-state" hx-island-when="load" id="f1">
    <input data-field="email" type="email" value="">
    <p data-text="summary">0 characters</p>
    <button id="clear" data-on:click="clear">Clear</button>
    <script type="application/json" data-island-state="form-state">{"email":"ab"}</script>
  </div>

  <div id="swap-host"></div>

  <script type="application/json" id="island-manifest">${JSON.stringify(manifest)}</script>
  <script src="/assets/vendor/htmx4.min.js"></script>
  <script type="module" src="/assets/islands.js"></script>
  <script type="module">
    defineIsland('greeter', (el, { signal }) => {
      const msg = signal('hello');
      return { msg };
    });
  </script>
</body></html>`;
  return { page, counterSrc, formStateSrc };
}

// --- Static server ------------------------------------------------------------

function serve(routes) {
  const server = http.createServer((req, res) => {
    const route = routes[req.url || ''];
    if (!route) { res.writeHead(404); res.end('nope'); return; }
    Promise.resolve(route()).then(({ body, type }) => {
      res.writeHead(200, { 'content-type': type });
      res.end(body);
    });
  });
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server)));
}

// --- Minimal CDP client -------------------------------------------------------

const CHROME_CANDIDATES = [
  process.env.CHROME_PATH,
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/Applications/Chromium.app/Contents/MacOS/Chromium',
  '/usr/bin/google-chrome',
  '/usr/bin/chromium',
].filter(Boolean);

function findChrome() {
  const found = CHROME_CANDIDATES.find((p) => existsSync(/** @type {string} */ (p)));
  if (!found) throw new Error('no Chrome found — set $CHROME_PATH');
  return found;
}

class Cdp {
  /** @param {WebSocket} ws */
  constructor(ws) {
    this.ws = ws;
    this.id = 0;
    /** @type {Map<number, {resolve: Function, reject: Function}>} */
    this.pending = new Map();
    /** @type {string[]} page errors + console.error from the tab */
    this.pageErrors = [];
    /** @type {string[]} all console output, for post-mortem debugging */
    this.pageLog = [];
    ws.addEventListener('message', (ev) => {
      const msg = JSON.parse(String(ev.data));
      if (msg.id && this.pending.has(msg.id)) {
        const { resolve, reject } = this.pending.get(msg.id);
        this.pending.delete(msg.id);
        msg.error ? reject(new Error(msg.error.message)) : resolve(msg.result);
      } else if (msg.method === 'Runtime.exceptionThrown') {
        this.pageErrors.push(msg.params.exceptionDetails?.exception?.description
          || msg.params.exceptionDetails?.text || 'exception');
      } else if (msg.method === 'Runtime.consoleAPICalled') {
        const line = msg.params.args?.map((a) => a.value ?? a.description).join(' ');
        this.pageLog.push(`${msg.params.type}: ${line}`);
        if (msg.params.type === 'error') this.pageErrors.push(line);
      }
    });
  }

  /** @param {string} method @param {object} [params] @param {string} [sessionId] */
  send(method, params = {}, sessionId) {
    const id = ++this.id;
    this.ws.send(JSON.stringify({ id, method, params, sessionId }));
    return new Promise((resolve, reject) => this.pending.set(id, { resolve, reject }));
  }

  /** Evaluate an expression in the page; returns the value. */
  async eval(expression, sessionId) {
    const r = await this.send('Runtime.evaluate',
      { expression, returnByValue: true, awaitPromise: true }, sessionId);
    if (r.exceptionDetails)
      throw new Error('page eval failed: ' + (r.exceptionDetails.exception?.description || r.exceptionDetails.text));
    return r.result.value;
  }
}

/** Launch headless Chrome with a random debug port; resolve with {proc, wsUrl}. */
function launchChrome() {
  const chrome = findChrome();
  return mkdtemp(path.join(tmpdir(), 'islands-smoke-')).then((profile) => {
    const proc = spawn(chrome, [
      '--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
      `--user-data-dir=${profile}`, '--remote-debugging-port=0', 'about:blank',
    ], { stdio: ['ignore', 'ignore', 'pipe'] });
    return new Promise((resolve, reject) => {
      let buf = '';
      proc.stderr.on('data', (d) => {
        buf += d;
        const m = buf.match(/DevTools listening on (ws:\/\/\S+)/);
        if (m) resolve({ proc, wsUrl: m[1], profile });
      });
      proc.on('exit', () => reject(new Error('chrome exited early: ' + buf.slice(-500))));
      setTimeout(() => reject(new Error('chrome devtools ws timeout')), 15000);
    });
  });
}

// --- Test ---------------------------------------------------------------------

let failures = 0;
/** @param {string} name @param {boolean} ok @param {any} [detail] */
function check(name, ok, detail) {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${ok ? '' : ' — ' + JSON.stringify(detail)}`);
  if (!ok) failures++;
}

/** Poll an expression until truthy or timeout. */
async function waitFor(cdp, sessionId, expr, timeoutMs = 5000) {
  const deadline = Date.now() + timeoutMs;
  for (;;) {
    const v = await cdp.eval(expr, sessionId).catch(() => false);
    if (v) return v;
    if (Date.now() > deadline) return false;
    await new Promise((r) => setTimeout(r, 100));
  }
}

async function main() {
  const { page, counterSrc, formStateSrc } = await buildFixture();
  const routes = {
    '/': async () => ({ body: page, type: MIME['.html'] }),
    '/assets/islands.js': async () => ({ body: await readFile(path.join(assetsDir, 'islands.js')), type: MIME['.js'] }),
    '/assets/island-kit.js': async () => ({ body: await readFile(path.join(assetsDir, 'island-kit.js')), type: MIME['.js'] }),
    '/assets/islands/counter.js': async () => ({ body: counterSrc, type: MIME['.js'] }),
    '/assets/islands/form-state.js': async () => ({ body: formStateSrc, type: MIME['.js'] }),
    '/assets/vendor/alien-signals.min.js': async () => ({ body: await readFile(path.join(vendorDir, 'alien-signals.min.js')), type: MIME['.js'] }),
    '/assets/vendor/htmx4.min.js': async () => ({ body: await readFile(path.join(vendorDir, 'htmx4.min.js')), type: MIME['.js'] }),
  };
  const server = await serve(routes);
  const port = /** @type {any} */ (server.address()).port;

  const { proc, wsUrl, profile } = await launchChrome();
  const ws = new WebSocket(wsUrl);
  await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
  const cdp = new Cdp(ws);

  try {
    const { targetId } = await cdp.send('Target.createTarget', { url: 'about:blank' });
    const { sessionId } = await cdp.send('Target.attachToTarget', { targetId, flatten: true });
    await cdp.send('Runtime.enable', {}, sessionId);
    await cdp.send('Page.enable', {}, sessionId);
    await cdp.send('Page.navigate', { url: `http://127.0.0.1:${port}/` }, sessionId);

    // 1. R1 regression: the SRI-verified counter island initializes and
    //    writes its server-serialized state through the declarative binding.
    const text = `#c1 [data-text="count"]`;
    check('counter island initializes (effectScope + init run)',
      await waitFor(cdp, sessionId, `document.querySelector('${text}')?.textContent === '41'`));

    // 2. Interaction: click +, the signal-driven binding reacts.
    await cdp.eval(`document.getElementById('inc').click()`, sessionId);
    check('counter reacts to click (41 → 42)',
      await waitFor(cdp, sessionId, `document.querySelector('${text}')?.textContent === '42'`));

    // 3. defineIsland() public API: inline-registered island mounts.
    check('defineIsland() inline island mounts',
      await waitFor(cdp, sessionId,
        `document.querySelector('#g1 [data-text="msg"]')?.textContent === 'hello'`));

    // 3b. form-state island (the missing `computed` destructure): derived
    //     summary tracks input, clear() resets it.
    const summary = `#f1 [data-text="summary"]`;
    check('form-state derived summary reflects server state ("2 characters")',
      await waitFor(cdp, sessionId,
        `document.querySelector('${summary}')?.textContent === '2 characters'`));
    await cdp.eval(`(() => {
      const input = document.querySelector('#f1 [data-field="email"]');
      input.value = 'abcd';
      input.dispatchEvent(new Event('input'));
    })()`, sessionId);
    check('form-state summary tracks input (→ "4 characters")',
      await waitFor(cdp, sessionId,
        `document.querySelector('${summary}')?.textContent === '4 characters'`));
    await cdp.eval(`document.getElementById('clear').click()`, sessionId);
    check('form-state clear() resets (→ "0 characters")',
      await waitFor(cdp, sessionId,
        `document.querySelector('${summary}')?.textContent === '0 characters'`));

    // 4. R5 regression: htmx 4 discovery via the htmx_after_process
    //    extension hook — a swapped-in island initializes.
    await cdp.eval(`(() => {
      const host = document.getElementById('swap-host');
      host.innerHTML = \`<div hx-island="counter" hx-island-when="load" id="c2">
        <span data-text="count">0</span>
        <button id="inc2" data-on:click="inc">+</button>
        <script type="application/json" data-island-state="counter">{"count":7}<\/script>
      </div>\`;
      htmx.process(host);
    })()`, sessionId);
    check('htmx 4 htmx_after_process hook discovers swapped island',
      await waitFor(cdp, sessionId,
        `document.querySelector('#c2 [data-text="count"]')?.textContent === '7'`));

    // 5. Teardown: removing an island dispatches island:dispose without error.
    await cdp.eval(`document.getElementById('c2').remove()`, sessionId);
    await new Promise((r) => setTimeout(r, 200));

    check('no page errors or console.error', cdp.pageErrors.length === 0, cdp.pageErrors);

    if (failures) {
      console.log('--- page console ---');
      for (const l of cdp.pageLog) console.log('  ' + l);
      console.log('--- #c1 outerHTML ---');
      console.log(await cdp.eval(`document.getElementById('c1')?.outerHTML`, sessionId));
      console.log('--- htmx? ---', await cdp.eval(`typeof window.htmx`, sessionId));
    }
  } finally {
    proc.kill('SIGKILL');
    ws.close();
    server.close();
    await rm(profile, { recursive: true, force: true }).catch(() => {});
  }

  console.log(failures ? `\n${failures} failure(s)` : '\nall green');
  process.exit(failures ? 1 : 0);
}

main().catch((e) => { console.error('smoke test harness error:', e); process.exit(1); });
