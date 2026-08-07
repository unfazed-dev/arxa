// counter_island.js — first-party micro-island: increment/decrement counter.
//
// HTML contract:
//   <div hx-island="counter" hx-island-when="interaction">
//     <button data-on:click="dec">−</button>
//     <span data-text="count">0</span>
//     <button data-on:click="inc">+</button>
//     <script type="application/json" data-island-state="counter">{"count":0}</script>
//   </div>

export default function counter(el, { state, signal, effect }) {
  const count = signal(state?.count ?? 0);
  // Declarative bindings (data-text, data-on:*) are handled by island-kit.js
  // from the returned API — the effect runs once writing the server value.
  return {
    count,
    inc: () => { count.value++; },
    dec: () => { count.value--; },
  };
}
