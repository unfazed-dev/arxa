// tabs_island.js — first-party micro-island: tab switching.
//
// HTML contract:
//   <div hx-island="tabs" hx-island-when="interaction">
//     <button data-tab="a">Tab A</button>
//     <button data-tab="b">Tab B</button>
//     <div data-panel="a">…</div>
//     <div data-panel="b" hidden>…</div>
//     <script type="application/json" data-island-state="tabs">{"active":"a"}</script>
//   </div>

export default function tabs(el, { state, signal, effect }) {
  const active = signal(state?.active ?? null);
  const tabBtns = el.querySelectorAll('[data-tab]');
  const panels = el.querySelectorAll('[data-panel]');

  effect(() => {
    tabBtns.forEach((btn) => {
      const on = btn.dataset.tab === active.value;
      btn.setAttribute('aria-selected', String(on));
      btn.classList.toggle('active', on);
    });
    panels.forEach((p) => { p.hidden = p.dataset.panel !== active.value; });
  });

  tabBtns.forEach((btn) =>
    btn.addEventListener('click', () => { active.value = btn.dataset.tab; }),
  );
  return { active };
}
