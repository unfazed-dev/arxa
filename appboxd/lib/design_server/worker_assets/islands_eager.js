// islands_eager.js — the design-time eager island loader.
//
// The eject twin (runtime/eject/assets/islands.js) loads islands lazily —
// zero JS until hx-island-when fires — from esbuild-bundled, SRI-pinned chunks
// at /assets/islands/<name>.js. Design time has no bundling step and wants the
// opposite trade: every [hx-island] initializes on boot from the vendored
// source at /assets/vendor/<name>_island.js, conditions ignored, so a lens
// check sees the real island, not the inert pre-condition markup (M10).
//
// The init mechanics mirror island-kit's withIsland (an effectScope around
// init, the { signal, computed, effect, state } ctx, the declarative data-*
// bindings) — inlined, because the design server does not serve the eject
// tree and this file must stand alone. Keep the two in sync when island-kit's
// ctx or binding set grows.
//
// The design server injects this module into every full HTML page it serves
// (design_server.dart, _dispatch) — the ejected app never sees it.

import { signal, computed, effect, effectScope } from '/assets/vendor/alien-signals.min.js';

const initialized = new WeakSet();

function readState(el) {
  const s = el.querySelector('script[data-island-state]');
  if (!s) return null;
  try { return JSON.parse(s.textContent); } catch { return null; }
}

// Declarative bindings, same contract as island-kit's bindDeclarative:
// data-text, data-show, data-attr:<name>, data-on:<event> resolve against the
// init's return value (signals or methods).
function bindDeclarative(root, api) {
  for (const el of root.querySelectorAll('*')) {
    for (const attr of el.attributes) {
      const val = attr.value;
      if (attr.name === 'data-text') {
        const sig = api[val];
        if (sig) effect(() => { el.textContent = sig.value; });
      } else if (attr.name === 'data-show') {
        const sig = api[val];
        if (sig) effect(() => { el.hidden = !sig.value; });
      } else if (attr.name.startsWith('data-attr:')) {
        const attrName = attr.name.slice('data-attr:'.length);
        const sig = api[val];
        if (sig) effect(() => { el.setAttribute(attrName, sig.value); });
      } else if (attr.name.startsWith('data-on:')) {
        const eventType = attr.name.slice('data-on:'.length);
        if (typeof api[val] === 'function')
          el.addEventListener(eventType, api[val]);
      }
    }
  }
}

async function boot(el) {
  if (initialized.has(el)) return;
  initialized.add(el);
  const name = el.getAttribute('hx-island');
  try {
    // Design-time module = the vendored island source; the eject-time SRI
    // manifest does not exist here (no bundling step to produce it).
    const mod = await import(`/assets/vendor/${name}_island.js`);
    const init = mod.default;
    if (typeof init !== 'function') return;
    const dispose = effectScope(() => {
      const api = init(el, { signal, computed, effect, state: readState(el) });
      if (api && typeof api === 'object') bindDeclarative(el, api);
    });
    // Same disposal channel as islands.js dispatches.
    el.addEventListener('island:dispose', () => dispose(), { once: true });
  } catch (e) {
    console.error(`island "${name}" failed:`, e);
  }
}

function scan(root) {
  if (!root || !root.querySelectorAll) return;
  if (root.hasAttribute?.('hx-island')) boot(root);
  for (const el of root.querySelectorAll('[hx-island]')) boot(el);
}

scan(document.documentElement);
// htmx swaps and fragment inserts bring new islands after boot.
new MutationObserver((records) => {
  for (const r of records) for (const n of r.addedNodes) scan(n);
}).observe(document.documentElement, { childList: true, subtree: true });
