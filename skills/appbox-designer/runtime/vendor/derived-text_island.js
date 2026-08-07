// derived-text_island.js — first-party micro-island: computed text from inputs.
//
// HTML contract:
//   <div hx-island="derived-text" hx-island-when="idle">
//     <input data-source="first" placeholder="First">
//     <input data-source="last" placeholder="Last">
//     <p data-text="greeting">Hello, !</p>
//     <script type="application/json" data-island-state="derived-text">
//       {"first":"","last":""}
//     </script>
//   </div>
//
// Demonstrates computed signals: greeting derives from first + last,
// never re-renders — the data-text effect writes in-place.

export default function derivedText(el, { state, signal, computed, effect }) {
  const first = signal(state?.first ?? '');
  const last = signal(state?.last ?? '');

  for (const input of el.querySelectorAll('[data-source="first"]'))
    input.addEventListener('input', () => { first.value = input.value; });
  for (const input of el.querySelectorAll('[data-source="last"]'))
    input.addEventListener('input', () => { last.value = input.value; });

  const greeting = computed(() => `Hello, ${first.value} ${last.value}!`);
  return { greeting };
}
