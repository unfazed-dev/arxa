// assets/islands.js — first-party island loader (replaces is-land).
//
// Eject-only: the design-time server loads islands eagerly. This module ships
// in the ejected tree at assets/islands.js and is the single place htmx
// extension hooks are used — if htmx 4 changes a hook name, this is the one
// call site to fix (plan risk #2).
//
// Two mechanisms:
// 1. Island discovery: [hx-island="name"] elements load their island module
//    when the hx-island-when condition fires (visible|idle|interaction|load).
// 2. Delegated lazy handlers (Qwikloader design): [data-on:event="./chunk.js#sym"]
//    attributes are served by one capture-phase listener per event type on
//    document — the handler import()s on demand. Capture-phase at the root
//    cannot miss events, so no replay queue is needed.

const initialized = new WeakSet();
const delegatedTypes = new Set();
const handlerCache = new Map();

// --- SRI verification for dynamic imports (fails closed on mismatch) ------

let manifest = {};
function readManifest() {
  const el = document.getElementById('island-manifest');
  if (el) { try { manifest = JSON.parse(el.textContent); } catch { /* empty */ } }
}

async function importVerified(url, expectedSri) {
  if (!expectedSri) return import(url);
  const resp = await fetch(url);
  if (!resp.ok) throw new Error(`island chunk ${url} → HTTP ${resp.status}`);
  const buf = new Uint8Array(await resp.arrayBuffer());
  const hash = await crypto.subtle.digest('SHA-384', buf);
  const sri = 'sha384-' + btoa(String.fromCharCode(...new Uint8Array(hash)));
  if (sri !== expectedSri)
    throw new Error(`SRI mismatch for ${url}: expected ${expectedSri}, got ${sri}`);
  const blob = new Blob([buf], { type: 'text/javascript' });
  return import(URL.createObjectURL(blob));
}

// --- Island discovery + condition-based loading --------------------------

function discover(root) {
  if (!root || !root.querySelectorAll) return;
  if (root.hasAttribute?.('hx-island')) armIsland(root);
  for (const el of root.querySelectorAll('[hx-island]')) armIsland(el);
  // Scan for delegated handler types we haven't armed yet.
  for (const el of root.querySelectorAll('*')) {
    for (const attr of el.attributes) {
      if (attr.name.startsWith('data-on:') && isChunkRef(attr.value))
        armDelegated(attr.name.slice('data-on:'.length));
    }
  }
}

function armIsland(el) {
  if (initialized.has(el)) return;
  const name = el.getAttribute('hx-island');
  const when = el.getAttribute('hx-island-when') || 'load';
  const fire = () => { initialized.add(el); loadIsland(name, el); };
  switch (when) {
    case 'load':      fire(); break;
    case 'idle':
      if ('requestIdleCallback' in window) requestIdleCallback(fire, { timeout: 3000 });
      else setTimeout(fire, 200);
      break;
    case 'visible': {
      const obs = new IntersectionObserver((entries) => {
        if (entries.some((e) => e.isIntersecting)) { obs.disconnect(); fire(); }
      });
      obs.observe(el);
      break;
    }
    case 'interaction': {
      const arm = () => {
        document.removeEventListener('pointerdown', arm, true);
        document.removeEventListener('keydown', arm, true);
        fire();
      };
      document.addEventListener('pointerdown', arm, true);
      document.addEventListener('keydown', arm, true);
      break;
    }
    default: fire();
  }
}

async function loadIsland(name, el) {
  const entry = manifest[name];
  const url = entry?.src || `/assets/islands/${name}.js`;
  try {
    const mod = await importVerified(url, entry?.integrity);
    const init = mod.default;
    if (typeof init !== 'function') return;
    const { withIsland } = await import('/assets/island-kit.js');
    withIsland(el, init, readState(el));
  } catch (e) {
    console.error(`island "${name}" failed:`, e);
  }
}

function readState(el) {
  const s = el.querySelector?.('script[data-island-state]');
  if (!s) return null;
  try { return JSON.parse(s.textContent); } catch { return null; }
}

// --- Delegated lazy handlers (Qwikloader pattern) ------------------------

function isChunkRef(val) {
  return val.startsWith('.') || val.startsWith('/');
}

function armDelegated(eventType) {
  if (delegatedTypes.has(eventType)) return;
  delegatedTypes.add(eventType);
  document.addEventListener(eventType, (e) => {
    for (let node = e.target; node; node = node.parentElement) {
      const spec = node.getAttribute?.(`data-on:${eventType}`);
      if (!spec || !isChunkRef(spec)) continue;
      invokeDelegated(node, spec, e, eventType);
    }
  }, true);
}

async function invokeDelegated(el, spec, event, eventType) {
  const hashIdx = spec.indexOf('#');
  const url = hashIdx >= 0 ? spec.slice(0, hashIdx) : spec;
  const symbol = hashIdx >= 0 ? spec.slice(hashIdx + 1) : 'default';
  let mod = handlerCache.get(url);
  if (!mod) { mod = await import(url); handlerCache.set(url, mod); }
  const fn = mod[symbol] || mod.default;
  if (typeof fn === 'function') fn(el, event);
}

// --- Teardown ------------------------------------------------------------

function dispose(el) {
  if (!el || !el.querySelectorAll) return;
  // island-kit.js owns the scopes WeakMap; signal it via a custom event.
  el.dispatchEvent(new CustomEvent('island:dispose'));
  for (const child of el.querySelectorAll('[hx-island]'))
    child.dispatchEvent(new CustomEvent('island:dispose'));
}

// --- Bootstrap -----------------------------------------------------------

function boot() {
  readManifest();
  const htmx = window.htmx;
  if (htmx) {
    // Feature-detect: htmx 4 uses registerExtension, 2.x uses defineExtension.
    const register = htmx.registerExtension || htmx.defineExtension;
    if (register) register.call(htmx, 'islands', {
      onEvent(name, evt) {
        const target = name === 'htmx:afterProcessNode' || name === 'htmx:afterProcess'
          ? (evt.detail?.target || evt.target) : null;
        if (target) discover(target);
      },
    });
    if (htmx.onLoad) htmx.onLoad(discover);
    document.addEventListener('htmx:beforeCleanupElement', (e) => {
      const elt = e.detail?.target || e.target;
      if (elt) dispose(elt);
    });
  }
  // Teardown for non-htmx removals (direct DOM manipulation).
  const mo = new MutationObserver((muts) => {
    for (const m of muts) for (const node of m.removedNodes) dispose(node);
  });
  mo.observe(document.body, { childList: true, subtree: true });
  if (document.readyState === 'loading')
    document.addEventListener('DOMContentLoaded', () => discover(document));
  else discover(document);
}

boot();
