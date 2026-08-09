/** @param {import('hono').Context} c @param {import('../../runtime/types').Helpers} h */
export const setAccent = async (c, h) => {
  const form = await h.form(c);
  h.setPrefs(c, { accent: String(form.accent ?? 'blueviolet') });
  // refresh-exempt: accent is CSS custom properties on the #app wrapper, which
  // is outside every swap target on the page — no fragment can repaint it.
  return h.refresh(c);
};
