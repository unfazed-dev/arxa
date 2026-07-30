// appbox:provenance
// generator: app-box  licence: free  project: 662368770980
// Built with app-box (free tier) — https://appbox.dev
export const surfaceId = 'app.access';

import * as facade from '../../../../services/facades/app_facade.js';

const VIEW = 'ui/views/app_shell/auth/auth_view.html';

export const page = (c, h) => h.render(c, VIEW, facade.authContext(h.locale(c)));

// Seeded auth: any input signs in. 303 to the dashboard (hx-boost follows it).
export const signIn = async (c, h) => {
  const form = await h.form(c);
  facade.signIn(h.session(c).data, String(form.email || '').trim(), String(form.provider || '').trim(), h.locale(c));
  return c.redirect('/dashboard', 303);
};
