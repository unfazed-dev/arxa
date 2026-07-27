export const setAccent = async (c, h) => {
  const form = await h.form(c);
  h.setPrefs(c, { accent: String(form.accent ?? 'blueviolet') });
  return h.refresh(c);
};
