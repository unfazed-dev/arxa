// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
// Theme tokens — models/theme.json is the SSOT for the accent swatches
// (5 swatches × 5 semantic roles). This module is its only reader and the
// only writer of assets/css/theme.css: every consumer of the accent list
// (prefs allowlist, settings dots, config chips, stub accent) imports from
// here, so adding/renaming a swatch is a theme.json edit plus one `node
// services/theme_tokens.js` run — nothing else to keep in step.
//
// Worker constraint: this module ALSO loads in the design server's
// headless-Chrome worker, whose import map shims ONLY `node:fs` (and that
// shim exports just readFileSync/existsSync — see
// appboxd/lib/design_server/worker_assets/). So: no `node:url`/`node:path`
// imports here, and writing stays inside the CLI branch behind a dynamic
// import that never runs in the worker.
import { readFileSync } from 'node:fs';

const JSON_URL = new URL('../models/theme.json', import.meta.url);

// Read per call, never at module load: the design server caches JS modules
// for the life of the process, so a load-time cache would pin the first
// render's theme across every later theme.json write-through edit.
export const theme = () => JSON.parse(readFileSync(JSON_URL, 'utf8'));
export const swatches = () => theme().swatches;
export const swatchNames = () => theme().swatches.map((s) => s.name);
export const defaultSwatch = () => theme().default;

const block = (sel, m) =>
  `${sel} { --accent: ${m.accent}; --accent-soft: ${m.soft}; --on-accent: ${m.on}; }`;

export const themeCss = (th = theme()) => {
  const light = th.swatches.map((s) => block(`#app[data-accent="${s.name}"]`, s.light));
  const dark = th.swatches.map((s) => block(`#app[data-theme="dark"][data-accent="${s.name}"]`, s.dark));
  const r = th.roles;
  return `/* GENERATED from models/theme.json by services/theme_tokens.js — do not edit
   by hand. Edit theme.json, run \`node services/theme_tokens.js\`, commit both.
   A swatch is 5 semantic roles, not 5 loose colors: accent (+ --on-accent),
   accent-soft, and three derived below with color-mix so they re-key
   automatically for every swatch and both themes (Radix natural-pairing:
   neutrals tinted toward the accent hue). Widgets bind to ROLES — switching
   data-accent re-themes everything coherently. */
${light.join('\n')}
${dark.join('\n')}

/* derived roles — one rule serves all swatches in both modes, because
   --accent/--bg/--tx vary by cascade above. */
#app {
  --accent-surface: color-mix(in oklab, var(--accent) ${r.surfaceMix}%, var(--bg));
  --accent-text: color-mix(in oklab, var(--accent) ${r.textMix}%, var(--tx));
  --accent-muted: color-mix(in oklab, var(--accent) ${r.mutedMix}%, var(--tx-2));
}
`;
};

// CLI entry (`node services/theme_tokens.js`) — regenerates theme.css. The
// process guard + dynamic import keep this inert in the worker, where
// `process` is undefined and the fs shim has no writeFileSync.
if (typeof process !== 'undefined' && process.argv?.[1]?.endsWith('theme_tokens.js')) {
  const { writeFileSync } = await import('node:fs');
  writeFileSync(new URL('../assets/css/theme.css', import.meta.url), themeCss());
  console.log('wrote assets/css/theme.css');
}
