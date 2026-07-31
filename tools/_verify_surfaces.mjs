// tools/_verify_surfaces.mjs -- plan 09 Done-when #1 proof harness (Node side).
//
// Renders every (route, state) surface of the reference design TWO ways:
//   A) the designer's Hono server (node serve.mjs) -- the Node baseline
//   B) the embedded harness (nunjucks + harness.js + artifact.bundle.js)
// then diffs the HTML byte-for-byte. NOT shipped; a verification tool.
import { readFileSync, existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';
import vm from 'node:vm';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..');
const DESIGN = path.join(ROOT, 'designs', 'appbox-app');
const RUNTIME = path.join(ROOT, 'skills', 'appbox-designer', 'runtime');

// route -> states (derived from the reference design's viewmodels; recompute
// by scanning app.routes.js + STATES if the design changes).
const ROUTES = {
  '/': ['list', 'empty', 'loading'],
  '/projects/new': ['form', 'validating', 'error'],
  '/design': ['three-up', 'approved'],
  '/design/surface': ['live', 'stale'],
  '/design/approve': ['pending', 'approved'],
  '/build': ['red', 'idle', 'running', 'green'],
  '/build/finding': ['finding'],
  '/build/approve': ['pending', 'approved'],
  '/ship': ['targets'],
  '/ship/confirm': ['pending', 'confirmed'],
  '/chat': ['idle', 'streaming', 'tool-call'],
  '/settings': ['credentials'],
  '/settings/devices': ['paired', 'revoke'],
  '/settings/kits': ['kits'],
};

function startNodeServer() {
  return new Promise((resolve, reject) => {
    const p = spawn('node', [path.join(RUNTIME, 'serve.mjs'), 'appbox-app', '--port', '0', '--json'], {
      cwd: ROOT,
    });
    let buf = '';
    p.stdout.on('data', (d) => {
      buf += d.toString();
      const nl = buf.indexOf('\n');
      if (nl !== -1) {
        const line = buf.slice(0, nl);
        try {
          const info = JSON.parse(line);
          resolve({ url: info.url, proc: p });
        } catch (e) { reject(new Error('no ready line: ' + line)); }
      }
    });
    p.stderr.on('data', (d) => process.stderr.write('[serve.mjs] ' + d));
    p.on('error', reject);
  });
}

async function fetchNode(url) {
  const res = await fetch(url);
  const text = await res.text();
  return text;
}

// Load the embedded harness stack into a vm context (true global scope, like
// the JS engine evaluates) and return __dispatch.
function loadEmbedded() {
  const sandbox = { console };
  vm.createContext(sandbox, { name: 'appbox-prototype' });
  // host bridges backed by the real filesystem.
  sandbox.__readTemplate = (name) => {
    const p = path.join(DESIGN, name);
    if (!existsSync(p)) throw new Error('template not found: ' + p);
    return readFileSync(p, 'utf8');
  };
  sandbox.__readFileSync = (p) => {
    let f = String(p).replace('file://__ARTIFACT__', DESIGN);
    if (f.startsWith('file://')) f = f.slice(7);
    return readFileSync(f, 'utf8');
  };
  const nj = readFileSync(path.join(RUNTIME, 'node_modules/nunjucks/browser/nunjucks.min.js'), 'utf8');
  const harness = readFileSync(path.join(ROOT, 'app/assets/prototype_runtime/harness.js'), 'utf8');
  const bundle = readFileSync(path.join(DESIGN, '_bundle/artifact.bundle.js'), 'utf8');
  vm.runInContext(nj + '\n;' + harness + '\n;' + bundle, sandbox, { filename: 'embedded-stack.js' });
  return sandbox;
}

async function main() {
  console.log('Starting Node baseline server (serve.mjs)...');
  const { url, proc } = await startNodeServer();
  console.log('  -> ' + url);

  const embedded = loadEmbedded();

  let identical = 0, differing = 0, errored = 0;
  const diffs = [];

  for (const [route, states] of Object.entries(ROUTES)) {
    for (const state of states) {
      const label = `${route}?state=${state}`;
      let nodeHtml, embHtml;
      try {
        nodeHtml = await fetchNode(url + route.replace(/^\//, '') + '?state=' + state);
      } catch (e) { console.error('NODE FETCH FAIL ' + label + ': ' + e.message); proc.kill(); process.exit(1); }
      try {
        const req = { method: 'GET', path: route, query: { state }, body: null, cookies: {} };
        const mode = embedded.__dispatch(req);
        // __dispatch stores the resolved response on __lastDispatchResponse;
        // for async handlers it lands there from the promise's .then.
        let res = embedded.__lastDispatchResponse;
        if (mode === '__async__' || !res) {
          await new Promise((r) => setImmediate(r));
          res = embedded.__lastDispatchResponse;
        }
        embHtml = res.body;
      } catch (e) {
        errored++;
        diffs.push({ label, kind: 'EMBEDDED ERROR', detail: e.message });
        continue;
      }
      if (nodeHtml === embHtml) {
        identical++;
      } else {
        differing++;
        diffs.push({ label, kind: 'DIFF', nodeLen: nodeHtml.length, embLen: embHtml.length,
          detail: firstDiff(nodeHtml, embHtml) });
      }
    }
  }

  proc.kill();

  console.log('\n=== SURFACE BYTE-COMPARISON (Node serve.mjs vs embedded harness) ===');
  const total = identical + differing + errored;
  console.log(`surfaces: ${total}  identical: ${identical}  differing: ${differing}  errored: ${errored}`);
  for (const d of diffs) {
    console.log(`  [${d.kind}] ${d.label}` + (d.detail ? ' :: ' + d.detail : ''));
  }
  process.exit(differing + errored > 0 ? 1 : 0);
}

function firstDiff(a, b) {
  const n = Math.min(a.length, b.length);
  for (let i = 0; i < n; i++) if (a[i] !== b[i]) {
    return `first byte diff @${i}: node=${JSON.stringify(a.slice(Math.max(0,i-20), i+20))} emb=${JSON.stringify(b.slice(Math.max(0,i-20), i+20))}`;
  }
  return `length mismatch: node=${a.length} emb=${b.length}`;
}

main().catch((e) => { console.error(e); process.exit(1); });
