// arxa:provenance
// generator: arxa  licence: free  project: 662368770980
// Built with arxa (free tier) — https://arxa.dev
// Font tokens — models/fonts.json is the SSOT for WHICH families exist (the
// four-entry font menu). This module is its only reader: the prefs allowlist
// and the settings menu both import from here, so adding or renaming a family
// is a fonts.json edit plus vendoring its woff2 — no second list to keep in
// step.
//
// Reader only, unlike services/theme_tokens.js. That module also WRITES
// assets/css/theme.css because theme.css is pure derivation from theme.json.
// fonts.css is not: its @font-face unicode-range strings and its design
// rationale do not live in fonts.json, so generating it would mean inventing
// SSOT data. fonts.css is maintained by hand as the documented CSS projection
// of this file — add a family here, vendor the woff2, add its faces and one
// [data-font] block there.
//
// Worker constraint (identical to theme_tokens.js): this module ALSO loads in
// the design server's headless-Chrome worker, whose import map shims ONLY
// `node:fs` (and that shim exports just readFileSync/existsSync — see
// arxa/lib/design_server/worker_assets/). So: no `node:url`/`node:path`
// imports here.
import { readFileSync } from 'node:fs';

const JSON_URL = new URL('../models/fonts.json', import.meta.url);

// Read per call, never at module load: the design server caches JS modules for
// the life of the process, so a load-time cache would pin the first render's
// font list across every later fonts.json edit.
export const fonts = () => JSON.parse(readFileSync(JSON_URL, 'utf8'));
export const families = () => fonts().families;
export const fontIds = () => fonts().families.map((fontFamily) => fontFamily.id);
export const defaultFont = () => fonts().default;

// The menu rows the settings UI renders, in SSOT order. `stack` rides along so
// each button can be set IN the family it selects — an honest preview, and the
// one place a literal font stack is allowed outside fonts.css, because the
// button must escape the --font-* variables the rest of the shell binds to.
export const fontMenu = () =>
  fonts().families.map(({ id, label, stack }) => ({ id, label, stack }));
