// Prefs — small scalar cookie prefs (theme). Server-rendered on #app.
export const setTheme = async (c, h) => {
  const current = h.prefs(c).theme || 'light';
  h.setPrefs(c, { theme: current === 'dark' ? 'light' : 'dark' });
  return h.refresh(c);
};
