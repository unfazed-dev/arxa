// arxa:provenance
// generator: arxa  licence: free  project: 662368770980
// Built with arxa (free tier) — https://arxa.dev
export const surfaceId = 'app.access';

import * as facade from '../../../../services/facades/app_facade.js';

const VIEW = 'ui/views/app_shell/auth/auth_view.html';

export const page = (context, helpers) =>
  helpers.render(context, VIEW, facade.authContext(helpers.locale(context), context.req.query('state')));

// Seeded auth: any input signs in. 303 to the dashboard (hx-boost follows it).
export const signIn = async (context, helpers) => {
  const form = await helpers.form(context);
  facade.signIn(helpers.session(context).data, String(form.email || '').trim(), String(form.provider || '').trim(), helpers.locale(context));
  return context.redirect('/dashboard', 303);
};
