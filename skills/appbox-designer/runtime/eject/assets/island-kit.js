// @ts-check
// assets/island-kit.js — signals-based declarative island bindings.
//
// Sits between islands.js (the loader) and island init functions. Provides:
//   - withIsland(el, init, state): runs an init function inside one
//     effectScope, runs it with signal/computed/effect from alien-signals,
//     then binds data-* declarative attributes inside the island.
//
// Declarative bindings (data-text, data-show, data-attr:*, data-on:*):
//   The init function may return an object whose keys are signals or methods.
//   Signals are alien-signals 3.x accessors: read with sig(), write sig(v).
//   data-text="key"   → effect sets el.textContent = signals.key()
//   data-show="key"   → effect sets el.hidden = !signals.key()
//   data-attr:X="key" → effect sets el.setAttribute(X, signals.key())
//   data-on:ev="key"  → el.addEventListener(ev, methods.key)
//
// Teardown: the island:dispose event from islands.js. Signals never
// auto-dispose; one effectScope per island means one stop() tears down every
// effect the island created. Idiomorph preserves element identity, so
// effects survive morphs and die only on true removal.

// @ts-ignore — resolved from the ejected web root at runtime; there is no
// module on disk at this specifier for tsc to analyze.
import { signal, computed, effect, effectScope } from '/assets/vendor/alien-signals.min.js';

/** @typedef {{ signal: typeof signal, computed: typeof computed, effect: typeof effect, state: any }} IslandContext */

/**
 * Called by islands.js when an island's condition fires. Creates a scope,
 * runs the init function inside it, binds declarative attributes, arms
 * teardown.
 * @param {HTMLElement} el - the [hx-island] root element
 * @param {(el: HTMLElement, ctx: IslandContext) => Record<string, any>|void} init
 * @param {any} state - parsed server-serialized state (or null)
 */
export function withIsland(el, init, state) {
  // alien-signals 3.x: effectScope(fn) runs fn inside the scope and returns
  // a stop function; stop() disposes every effect created within. One scope
  // per island → one stop() disposes the whole island.
  const stop = effectScope(() => {
    /** @type {IslandContext} */
    const ctx = { state, signal, computed, effect };
    const api = init(el, ctx);
    if (api && typeof api === 'object') bindDeclarative(el, api);
  });

  // Teardown: islands.js dispatches island:dispose when the subtree is removed.
  el.addEventListener('island:dispose', () => {
    stop();
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
        if (sig) effect(() => { el.textContent = sig(); });
      } else if (attr.name === 'data-show') {
        const sig = api[val];
        if (sig) effect(() => { (/** @type {HTMLElement} */ (el)).hidden = !sig(); });
      } else if (attr.name.startsWith('data-attr:')) {
        const attrName = attr.name.slice('data-attr:'.length);
        const sig = api[val];
        if (sig) effect(() => { el.setAttribute(attrName, String(sig())); });
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
