/** @param {import('hono').Context} context @param {import('../../runtime/types').Helpers} helpers */
export const setAccent = async (context, helpers) => {
  const form = await helpers.form(context);
  helpers.setPrefs(context, { accent: String(form.accent ?? 'blueviolet') });
  // refresh-exempt: accent is CSS custom properties on the #app wrapper, which
  // is outside every swap target on the page — no fragment can repaint it.
  return helpers.refresh(context);
};
