// @ts-check
// runtime/forms.js — zod-validated POST form actions.
//
// Convention: parse with zod, on failure return 422 + re-rendered form partial
// with errors and prior values. On success, the handler does its thing
// (redirect, fragment swap, etc.). Benchmark UX against Unpoly's form-
// validation conventions: [HTTP 422] with the form partial re-rendered is
// the Carson-endorsed reference — the client swaps the form in-place, errors
// and values preserved, no full reload.
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
