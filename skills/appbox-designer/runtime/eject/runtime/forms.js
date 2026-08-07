// runtime/forms.js — zod-validated POST form actions.
//
// Convention: parse with zod, on failure return 422 + re-rendered form partial
// with errors and prior values. On success, the handler does its thing
// (redirect, fragment swap, etc.). Benchmark UX against Unpoly's form-
// validation conventions: [HTTP 422] with the form partial re-rendered is
// the Carson-endorsed reference — the client swaps the form in-place, errors
// and values preserved, no full reload.
//
// Client story (htmx 4): the stack's base layout blacklists 4xx/5xx via its
// meta htmx-config `noSwap` (v4's default noSwap is only [204,304]). The
// escape hatch is v4-native: an `hx-status:422` attribute on any ancestor of
// the form (the artifact's base layout puts `hx-status:422="{}"` on <body>)
// merges that JSON config into the swap for 422 responses, so the re-rendered
// form partial swaps in place of the submitting form — no extensions, no
// custom JS. Two hard dependencies, both in the base layout's meta config:
// the `noSwap:["4xx",…]` blacklist (without it every 4xx swaps anyway and the
// escape is moot) and `"implicitInheritance":true` (without it the body-level
// attribute is invisible to the lookup — verified against 4.0.0-beta6 in
// test/islands_smoke_test.mjs). The form also wants `hx-swap="outerHTML"`:
// the default innerHTML swap would nest the re-rendered <form> inside the
// submitting one.
//
// Field-error convention in the re-rendered partial (the artifact's
// FormField widget implements it — mirror it in hand-rolled forms):
//   - `aria-invalid="true"` on the invalid input, and an error element right
//     next to the field (`<p class="field__error" id="field-error-<name>">`),
//     wired with `aria-describedby`.
//   - `autofocus` on the FIRST invalid field — htmx 4 focuses the first
//     `[autofocus]` in swapped content natively, which restores focus after
//     the swap instead of stranding the user on a detached node.
//
// Usage in a ViewModel handler:
//
//   import { parseForm } from '../../runtime/forms.js';
//   import { z } from 'zod';
//
//   const schema = z.object({ email: z.string().email(), name: z.string().min(1) });
//
//   export async function submit(c, h) {
//     const result = await parseForm(c, schema);
//     if (!result.ok) {
//       return h.render(c, 'ui/views/.../form_view.html#form', {
//         errors: result.errors,
//         values: result.values,
//       }, 422);
//     }
//     // success — result.data is typed
//     return h.refresh(c);
//   }

/**
 * @typedef {Object} FormOk
 * @property {true} ok
 * @property {Record<string, unknown>} data - validated, typed form data
 *
 * @typedef {Object} FormErr
 * @property {false} ok
 * @property {Record<string, string>} errors - field name → error message
 * @property {Record<string, string>} values - prior values for re-render
 *
 * @typedef {FormOk | FormErr} FormResult
 */

/**
 * Parse and validate a POST body against a zod schema.
 *
 * @param {import('hono').Context} c - Hono context
 * @param {import('zod').ZodSchema} schema - zod schema for the form fields
 * @returns {Promise<FormResult>} — ok: validated data, or errors+values for 422 re-render
 */
export async function parseForm(c, schema) {
  const raw = await c.req.parseBody();
  // parseBody returns { field: value | File | string[] } — coerce to string map.
  /** @type {Record<string, string>} */
  const values = {};
  for (const [k, v] of Object.entries(raw)) {
    values[k] = typeof v === 'string' ? v : Array.isArray(v) ? v.join(', ') : '';
  }
  const result = schema.safeParse(values);
  if (result.success) {
    return { ok: true, data: result.data };
  }
  // Flatten zod issues into { field: message } for the template.
  /** @type {Record<string, string>} */
  const errors = {};
  for (const issue of result.error.issues) {
    const field = issue.path[0] ?? '_form';
    if (!errors[field]) errors[field] = issue.message;
  }
  return { ok: false, errors, values };
}
