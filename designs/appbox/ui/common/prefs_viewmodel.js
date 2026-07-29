// Prefs — small scalar cookie prefs (theme, accent, jargon).
// Theme + accent render on #app; jargon is picked up server-side by facades.
const ALLOWED_ACCENT = ['cyan', 'violet', 'blue', 'ember'];
const ALLOWED_JARGON = ['plain', 'balanced', 'technical'];

export const setAccent = async (c, h) => {
  const form = await h.form(c);
  const accent = String(form.accent || '');
  if (ALLOWED_ACCENT.includes(accent)) h.setPrefs(c, { accent });
  return h.refresh(c);
};

export const setTheme = async (c, h) => {
  const current = h.prefs(c).theme || 'light';
  h.setPrefs(c, { theme: current === 'dark' ? 'light' : 'dark' });
  return h.refresh(c);
};

export const setJargon = async (c, h) => {
  const form = await h.form(c);
  const jargon = String(form.jargon || '');
  if (ALLOWED_JARGON.includes(jargon)) h.setPrefs(c, { jargon });
  return h.refresh(c);
};
