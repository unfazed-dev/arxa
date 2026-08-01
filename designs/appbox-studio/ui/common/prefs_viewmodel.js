// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
// Prefs — small scalar cookie prefs (theme, accent, jargon).
// Theme + accent render on #app; jargon is picked up server-side by facades.
const ALLOWED_ACCENT = ['cyan', 'violet', 'blue', 'ember'];
const ALLOWED_JARGON = ['plain', 'balanced', 'technical'];

export const setAccent = async (c, h) => {
  const form = await h.form(c);
  const accent = String(form.accent || '');
  if (ALLOWED_ACCENT.includes(accent)) h.setPrefs(c, { accent });
  // refresh-exempt: accent renders as data-accent on #app (base.html) —
  // outside every swap unit; only a full reload restyles the shell chrome.
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
