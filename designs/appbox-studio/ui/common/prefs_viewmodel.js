// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
// Prefs — small scalar cookie prefs (theme, accent, font, jargon).
// Theme, accent + font render on #app; jargon is picked up server-side by
// facades.
// accent allowlist = the swatch SSOT (models/theme.json) — one list to rule
// prefs, settings dots, config chips and the generated theme.css.
// font allowlist = the family SSOT (models/fonts.json), read the same way.
import { swatchNames } from '../../services/theme_tokens.js';
import { fontIds } from '../../services/font_tokens.js';
const ALLOWED_JARGON = ['plain', 'balanced', 'technical'];

export const setAccent = async (context, helpers) => {
  const form = await helpers.form(context);
  const accent = String(form.accent || '');
  if (swatchNames().includes(accent)) helpers.setPrefs(context, { accent });
  // refresh-exempt: accent renders as data-accent on #app (base.html) —
  // outside every swap unit; only a full reload restyles the shell chrome.
  return helpers.refresh(context);
};

export const setFont = async (context, helpers) => {
  const form = await helpers.form(context);
  const font = String(form.font || '');
  if (fontIds().includes(font)) helpers.setPrefs(context, { font });
  // refresh-exempt: for the same reason as accent: the family is switched by
  // data-font on #app (base.html), which is outside every swap unit — and the
  // four --font-* variables it re-keys are inherited by the whole document,
  // so a partial swap would leave un-swapped regions on the old family.
  return helpers.refresh(context);
};

export const setTheme = async (context, helpers) => {
  const current = helpers.prefs(context).theme || 'light';
  helpers.setPrefs(context, { theme: current === 'dark' ? 'light' : 'dark' });
  // refresh-exempt: theme renders as data-theme on #app (base.html) —
  // outside every swap unit; only a full reload restyles the shell chrome.
  return helpers.refresh(context);
};

export const setJargon = async (context, helpers) => {
  const form = await helpers.form(context);
  const jargon = String(form.jargon || '');
  if (ALLOWED_JARGON.includes(jargon)) helpers.setPrefs(context, { jargon });
  // refresh-exempt: jargon is applied server-side by every facade — the
  // next render of ANY surface reads it, so the whole page re-renders.
  return helpers.refresh(context);
};
