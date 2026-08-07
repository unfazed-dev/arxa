// form-state_island.js — first-party micro-island: reactive form field tracking.
//
// HTML contract:
//   <div hx-island="form-state" hx-island-when="interaction">
//     <input data-field="email" type="email" value="">
//     <p data-text="summary">0 characters</p>
//     <button data-on:click="clear">Clear</button>
//     <script type="application/json" data-island-state="form-state">{"email":""}</script>
//   </div>
//
// Tracks each [data-field] in a signal, derives a summary, and exposes a
// clear() method. Demonstrates the signal → derived → DOM binding pattern.

export default function formState(el, { state, signal, effect }) {
  const fields = {};
  for (const input of el.querySelectorAll('[data-field]')) {
    const key = input.dataset.field;
    fields[key] = signal(state?.[key] ?? input.value ?? '');
    input.addEventListener('input', () => { fields[key].value = input.value; });
    // Keep the input in sync if the signal changes programmatically (e.g. clear).
    effect(() => { if (input.value !== fields[key].value) input.value = fields[key].value; });
  }
  const summary = computed(() => {
    const total = Object.values(fields).reduce((n, s) => n + String(s.value).length, 0);
    return `${total} character${total === 1 ? '' : 's'}`;
  });
  return {
    ...fields,
    summary,
    clear: () => { Object.values(fields).forEach((s) => { s.value = ''; }); },
  };
}
