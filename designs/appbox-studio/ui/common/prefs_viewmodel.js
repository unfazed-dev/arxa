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

export const setAccent = async (c, h) => {
  const form = await h.form(c);
  const accent = String(form.accent || '');
  if (swatchNames().includes(accent)) h.setPrefs(c, { accent });
  // refresh-exempt: accent renders as data-accent on #app (base.html) —
  // outside every swap unit; only a full reload restyles the shell chrome.
  return h.refresh(c);
};

export const setFont = async (c, h) => {
  const form = await h.form(c);
  const font = String(form.font || '');
  if (fontIds().includes(font)) h.setPrefs(c, { font });
  // refresh-exempt: for the same reason as accent: the family is switched by
  // data-font on #app (base.html), which is outside every swap unit — and the
  // four --font-* variables it re-keys are inherited by the whole document,
  // so a partial swap would leave un-swapped regions on the old family.
  return h.refresh(c);
};

export const setTheme = async (c, h) => {
  const current = h.prefs(c).theme || 'light';
  h.setPrefs(c, { theme: current === 'dark' ? 'light' : 'dark' });
  // refresh-exempt: theme renders as data-theme on #app (base.html) —
  // outside every swap unit; only a full reload restyles the shell chrome.
  return h.refresh(c);
};

export const setJargon = async (c, h) => {
  const form = await h.form(c);
  const jargon = String(form.jargon || '');
  if (ALLOWED_JARGON.includes(jargon)) h.setPrefs(c, { jargon });
  // refresh-exempt: jargon is applied server-side by every facade — the
  // next render of ANY surface reads it, so the whole page re-renders.
  return h.refresh(c);
};
