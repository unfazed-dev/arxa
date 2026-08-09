// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
export const surfaceId = 'app.dashboard';

import * as facade from '../../../../services/facades/app_facade.js';

const VIEW = 'ui/views/app_shell/dashboard/dashboard_view.html';

export const page = async (context, helpers) =>
  helpers.render(context, VIEW, { activeShell: 'app', ...(await facade.dashboardContext(helpers.session(context).data, helpers.locale(context))) });

// The app shell's dashboard IS the studio home, but the ENTRY is the real
// chain: root lands on /splash, which auto-advances splash → startup, and
// startup branches to /auth (signed out) or /dashboard (signed in).
export const root = (context, helpers) => context.redirect('/splash', 303);

// A project card picks the current project (writes ~/.appbox/current), 303
// back to the dashboard.
export const useProject = async (context, helpers) => {
  const form = await helpers.form(context);
  await facade.useProject(String(form.project || ''));
  return context.redirect('/dashboard', 303);
};

// Needs-you quick actions — seeded decision, 303 back to the dashboard.
export const decide = async (context, helpers) => {
  const form = await helpers.form(context);
  facade.decideGate(helpers.session(context).data, String(form.gate || ''), String(form.decision || ''), helpers.locale(context));
  return context.redirect('/dashboard', 303);
};

// GenUI new-project wizard — creates a REAL project in ~/.appbox, lands on intake.
export const createProject = async (context, helpers) => {
  const form = await helpers.form(context);
  await facade.createProject(helpers.session(context).data, String(form.name || ''), form.targets, helpers.translate(context));
  return context.redirect('/intake', 303);
};
