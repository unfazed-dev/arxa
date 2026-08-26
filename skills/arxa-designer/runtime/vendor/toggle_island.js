// toggle_island.js — first-party micro-island: expand/collapse.
//
// HTML contract:
//   <div hx-island="toggle" hx-island-when="interaction">
//     <button data-island-btn aria-expanded="false">Show</button>
//     <div data-island-panel hidden>…content…</div>
//     <script type="application/json" data-island-state="toggle">{"open":false}</script>
//   </div>
//
// Returns { open } so data-text="open" / data-show="open" also work inside the island.

export default function toggle(el, { state, signal, effect }) {
  const open = signal(state?.open ?? false);
  const btn = el.querySelector('[data-island-btn]');
  const panel = el.querySelector('[data-island-panel]');
  if (btn && panel) {
    effect(() => {
      panel.hidden = !open();
      btn.setAttribute('aria-expanded', String(open()));
    });
    btn.addEventListener('click', () => { open(!open()); });
  }
  return { open };
}
