// Prefs — small scalar cookie prefs (theme, accent). Server-rendered on #app.
export const setAccent = async (c, h) => {
  const form = await h.form(c);
  h.setPrefs(c, { accent: form.accent });
  return h.refresh(c);
};

export const setTheme = async (c, h) => {
  const current = h.prefs(c).theme || 'light';
  h.setPrefs(c, { theme: current === 'dark' ? 'light' : 'dark' });
  return h.refresh(c);
};
