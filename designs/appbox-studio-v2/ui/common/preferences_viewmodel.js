/** @param {import('hono').Context} context @param {import('../../runtime/types').Helpers} helpers */
export const setAccent = async (context, helpers) => {
  const form = await helpers.form(context);
  helpers.setPrefs(context, { accent: String(form.accent ?? 'blueviolet') });
  // refresh-exempt: accent is CSS custom properties on the #app wrapper, which
  // is outside every swap target on the page — no fragment can repaint it.
  return helpers.refresh(context);
};

/** Mirrors setAccent for the theme toggle in the hub header drawer. The
 *  current theme rides in prefs.theme; the form posts the next mode. */
/** @param {import('hono').Context} context @param {import('../../runtime/types').Helpers} helpers */
export const setTheme = async (context, helpers) => {
  const form = await helpers.form(context);
  const next = String(form.theme ?? 'dark') === 'dark' ? 'dark' : 'light';
  helpers.setPrefs(context, { theme: next });
  // refresh-exempt for the same reason as accent: data-theme lives on the
  // #app wrapper, outside every swap target on the page.
  return helpers.refresh(context);
};
