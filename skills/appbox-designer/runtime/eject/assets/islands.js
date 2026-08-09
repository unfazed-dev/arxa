// @ts-check
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

/** @typedef {(el: HTMLElement, ctx: any) => Record<string, any>|void} IslandInit */
/** @typedef {{ src?: string, integrity?: string }} IslandManifestEntry */

const initialized = new WeakSet();
const delegatedTypes = new Set();
const handlerCache = new Map();
/** @type {Map<string, IslandInit>} init fns registered via defineIsland() */
const defined = new Map();
/** @type {Map<Element, () => void>} per-island armer teardown, released on dispose */
const armDisposers = new Map();

// Sibling of this module in the ejected tree — never a hardcoded web-root path.
const kitUrl = new URL('island-kit.js', import.meta.url).href;

/**
 * Register an island implementation directly, without a chunk URL or
 * manifest entry. Public API for pages that inline their island code.
 * @param {string} name - the [hx-island="name"] key
 * @param {IslandInit} init - the island init function
 */
export function defineIsland(name, init) {
  defined.set(name, init);
}
// Reachable from plain (non-module) scripts too.
(/** @type {any} */ (window)).defineIsland = defineIsland;

// --- SRI verification for dynamic imports (fails closed) -------------------

/** @type {Record<string, IslandManifestEntry>} */
let manifest = {};
function readManifest() {
  const el = document.getElementById('island-manifest');
  if (el) { try { manifest = JSON.parse(el.textContent || ''); } catch { /* empty */ } }
}

/**
 * Import an island chunk only after verifying its sha384 SRI against the
 * manifest. Fails closed: with no integrity entry there is nothing to verify
 * against, so the chunk is refused rather than executed (review M11).
 * @param {string} url
 * @param {string|undefined} expectedSri
 */
async function importVerified(url, expectedSri) {
  if (!expectedSri)
    throw new Error(`island chunk ${url} has no SRI entry — refusing to import (fail closed)`);
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

// --- Island discovery + condition-based loading -----------------------------

/**
 * Scan a subtree for islands to arm and delegated handler types to arm.
 * @param {ParentNode} root - element or document to scan
 */
function discover(root) {
  if (!root || !root.querySelectorAll) return;
  if (root instanceof Element && root.hasAttribute('hx-island')) armIsland(root);
  for (const el of root.querySelectorAll('[hx-island]')) armIsland(el);
  // Scan for delegated handler types we haven't armed yet.
  for (const el of root.querySelectorAll('*')) {
    for (const attr of el.attributes) {
      if (attr.name.startsWith('data-on:') && isChunkRef(attr.value))
        armDelegated(attr.name.slice('data-on:'.length));
    }
  }
}

/**
 * Arm one island element: load it now or when its hx-island-when condition
 * fires. Armer teardown is recorded so a dispose before the condition fires
 * releases the observer/listener/timer instead of leaking it.
 * @param {Element} el
 */
function armIsland(el) {
  // Idempotent: initialized islands are done, armed-but-unfired ones are in
  // armDisposers — re-discovery (htmx swaps, the DOMContentLoaded scan)
  // must not double-arm listeners/observers.
  if (initialized.has(el) || armDisposers.has(el)) return;
  const name = el.getAttribute('hx-island');
  const when = el.getAttribute('hx-island-when') || 'load';
  const fire = () => {
    armDisposers.delete(el);
    initialized.add(el);
    loadIsland(name, el);
  };
  switch (when) {
    case 'load': fire(); break;
    case 'idle':
      if ('requestIdleCallback' in window) {
        const id = requestIdleCallback(fire, { timeout: 3000 });
        armDisposers.set(el, () => cancelIdleCallback(id));
      } else {
        const id = setTimeout(fire, 200);
        armDisposers.set(el, () => clearTimeout(id));
      }
      break;
    case 'visible': {
      const obs = new IntersectionObserver((entries) => {
        if (entries.some((entry) => entry.isIntersecting)) { obs.disconnect(); fire(); }
      });
      obs.observe(el);
      armDisposers.set(el, () => obs.disconnect());
      break;
    }
    case 'interaction': {
      const release = () => {
        document.removeEventListener('pointerdown', arm, true);
        document.removeEventListener('keydown', arm, true);
      };
      const arm = () => { release(); fire(); };
      document.addEventListener('pointerdown', arm, true);
      document.addEventListener('keydown', arm, true);
      armDisposers.set(el, release);
      break;
    }
    default: fire();
  }
}

/**
 * Load and mount an island: a defineIsland() registration wins, otherwise
 * the manifest entry (or the conventional chunk path) is imported under SRI.
 * @param {string|null} name
 * @param {Element} el
 */
async function loadIsland(name, el) {
  try {
    let init = name ? defined.get(name) : undefined;
    if (!init) {
      const entry = name ? manifest[name] : undefined;
      const url = entry?.src || `/assets/islands/${name}.js`;
      const mod = await importVerified(url, entry?.integrity);
      init = mod.default;
    }
    if (typeof init !== 'function')
      throw new Error(`island "${name}" has no default export`);
    const { withIsland } = await import(kitUrl);
    withIsland(/** @type {HTMLElement} */ (el), init, readState(el));
  } catch (e) {
    console.error(`island "${name}" failed:`, e);
  }
}

/**
 * Read the server-serialized state script inside the island root.
 * @param {Element} el
 * @returns {any} parsed state, or null
 */
function readState(el) {
  const stateScript = el.querySelector?.('script[data-island-state]');
  if (!stateScript) return null;
  try { return JSON.parse(stateScript.textContent || ''); } catch { return null; }
}

// --- Delegated lazy handlers (Qwikloader pattern) ---------------------------

/**
 * @param {string} val
 * @returns {boolean} true if the data-on:* value is a chunk ref, not a method name
 */
function isChunkRef(val) {
  return val.startsWith('.') || val.startsWith('/');
}

/**
 * Arm one capture-phase document listener for an event type (idempotent).
 * @param {string} eventType
 */
function armDelegated(eventType) {
  if (delegatedTypes.has(eventType)) return;
  delegatedTypes.add(eventType);
  document.addEventListener(eventType, (e) => {
    for (let node = /** @type {HTMLElement|null} */ (e.target); node; node = node.parentElement) {
      const spec = node.getAttribute?.(`data-on:${eventType}`);
      if (!spec || !isChunkRef(spec)) continue;
      invokeDelegated(node, spec, e, eventType);
    }
  }, true);
}

/**
 * Import the handler chunk on demand (cached) and invoke the symbol.
 * @param {HTMLElement} el
 * @param {string} spec - "./chunk.js#symbol" or "./chunk.js" (default export)
 * @param {Event} event
 * @param {string} eventType
 */
async function invokeDelegated(el, spec, event, eventType) {
  try {
    const hashIdx = spec.indexOf('#');
    const url = hashIdx >= 0 ? spec.slice(0, hashIdx) : spec;
    const symbol = hashIdx >= 0 ? spec.slice(hashIdx + 1) : 'default';
    let mod = handlerCache.get(url);
    if (!mod) { mod = await import(url); handlerCache.set(url, mod); }
    const fn = mod[symbol] || mod.default;
    if (typeof fn === 'function') fn(el, event);
  } catch (e) {
    console.error(`delegated ${eventType} handler ${spec} failed:`, e);
  }
}

// --- Teardown ---------------------------------------------------------------

/**
 * Dispose an island subtree: release any pending condition armer and signal
 * island-kit to stop the island's effectScope.
 * @param {any} el - removed root (may be a non-element node)
 */
function dispose(el) {
  if (!el || !el.querySelectorAll) return;
  releaseArmer(el);
  // island-kit.js owns the scope stop functions; signal it via a custom event.
  el.dispatchEvent(new CustomEvent('island:dispose'));
  for (const child of el.querySelectorAll('[hx-island]')) {
    releaseArmer(child);
    child.dispatchEvent(new CustomEvent('island:dispose'));
  }
}

/**
 * Release a pending condition armer (observer/listener/timer) for an island
 * that was disposed before its condition fired.
 * @param {Element} el
 */
function releaseArmer(el) {
  const release = armDisposers.get(el);
  if (release) { armDisposers.delete(el); release(); }
}

/**
 * @param {any} node
 * @returns {boolean} true if the node is or contains island roots
 */
function hasIslands(node) {
  return node instanceof Element &&
    (node.hasAttribute('hx-island') || node.querySelector('[hx-island]') !== null);
}

// --- Bootstrap ---------------------------------------------------------------

function boot() {
  readManifest();
  const htmx = (/** @type {any} */ (window)).htmx;
  if (htmx) {
    // htmx 4 extension API: an object of top-level hook keys (`:` → `_`),
    // each called with (element, detail) — the pattern the bundled hx-sse
    // extension uses. htmx:after:process fires per processed root.
    htmx.registerExtension('islands', {
      htmx_after_process(/** @type {ParentNode} */ root) { discover(root); },
    });
    // v4 teardown event (bubbles, composed); MutationObserver below is the
    // backstop for non-htmx removals.
    document.addEventListener('htmx:before:cleanup', (e) => {
      if (e.target) dispose(e.target);
    });
    if (htmx.onLoad) htmx.onLoad(discover);
  }
  // Teardown backstop for non-htmx removals (direct DOM manipulation),
  // scoped to subtrees that actually contain island roots.
  const mo = new MutationObserver((muts) => {
    for (const m of muts) for (const node of m.removedNodes)
      if (hasIslands(node)) dispose(node);
  });
  mo.observe(document.body, { childList: true, subtree: true });
  // First discovery at DOMContentLoaded: module scripts execute before it,
  // so inline <script type="module"> defineIsland() registrations are in
  // place by the first scan. (htmx's own initial processing may discover
  // even earlier via the extension hook — armIsland is idempotent.)
  if (document.readyState === 'complete') discover(document);
  else document.addEventListener('DOMContentLoaded', () => discover(document));
}

boot();
