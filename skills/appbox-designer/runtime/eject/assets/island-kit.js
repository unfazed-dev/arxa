// assets/island-kit.js — signals-based declarative island bindings.
//
// Sits between islands.js (the loader) and island init functions. Provides:
//   - withIsland(el, init, state): wraps an init function in an effectScope,
//     runs it with signal/effect from alien-signals, then binds data-*
//     declarative attributes inside the island.
//
// Declarative bindings (data-text, data-show, data-attr:*, data-on:*):
//   The init function may return an object whose keys are signals or methods.
//   data-text="key"   → effect sets el.textContent = signals.key.value
//   data-show="key"   → effect sets el.hidden = !signals.key.value
//   data-attr:X="key" → effect sets el.setAttribute(X, signals.key.value)
//   data-on:ev="key"  → el.addEventListener(ev, methods.key)
//
// Teardown: one MutationObserver + the island:dispose event from islands.js.
// Signals never auto-dispose; we stop the effectScope when the island root
// leaves the DOM. Idiomorph preserves element identity, so effects survive
// morphs and die only on true removal.

import { signal, computed, effect, effectScope } from '/assets/vendor/alien-signals.min.js';

/** @typedef {{ signal: typeof signal, computed: typeof computed, effect: typeof effect, state: any }} IslandContext */

/**
 * Called by islands.js when an island's condition fires. Creates a scope,
 * runs the init function, binds declarative attributes, arms teardown.
 * @param {HTMLElement} el - the [hx-island] root element
 * @param {(el: HTMLElement, ctx: IslandContext) => Object|void} init
 * @param {any} state - parsed server-serialized state (or null)
 */
export function withIsland(el, init, state) {
  const scope = effectScope();

  scope.run(() => {
    /** @type {IslandContext} */
    const ctx = { state, signal, computed, effect };
    const api = fn(el, ctx);
    if (api && typeof api === 'object') bindDeclarative(el, api);
  });

  // Teardown: islands.js dispatches island:dispose when the subtree is removed.
  el.addEventListener('island:dispose', () => {
    scope.stop();
  }, { once: true });
}

/**
 * Process data-* declarative bindings inside the island root.
 * @param {HTMLElement} root
 * @param {Record<string, any>} api
 */
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
        // Only bind simple method refs here — chunk URLs (./path#sym) are
        // handled by islands.js's capture-phase delegated listeners.
        const eventType = attr.name.slice('data-on:'.length);
        if (typeof api[val] === 'function')
          el.addEventListener(eventType, api[val]);
      }
    }
  }
}
