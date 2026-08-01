// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
export const surfaceId = 'app.dashboard';

import * as facade from '../../../../services/facades/app_facade.js';

const VIEW = 'ui/views/app_shell/dashboard/dashboard_view.html';

export const page = async (c, h) =>
  h.render(c, VIEW, { activeShell: 'app', ...(await facade.dashboardContext(h.session(c).data, h.locale(c))) });

// The Surfaces catalog shell is retired — the app shell's dashboard IS the
// studio home, so the root lands there.
export const root = (c, h) => c.redirect('/dashboard', 303);

// A project card picks the current project (writes ~/.appbox/current), 303
// back to the dashboard.
export const useProject = async (c, h) => {
  const form = await h.form(c);
  await facade.useProject(String(form.project || ''));
  return c.redirect('/dashboard', 303);
};

// Needs-you quick actions — seeded decision, 303 back to the dashboard.
export const decide = async (c, h) => {
  const form = await h.form(c);
  facade.decideGate(h.session(c).data, String(form.gate || ''), String(form.decision || ''), h.locale(c));
  return c.redirect('/dashboard', 303);
};

// GenUI new-project wizard — creates a REAL project in ~/.appbox, lands on intake.
export const createProject = async (c, h) => {
  const form = await h.form(c);
  await facade.createProject(h.session(c).data, String(form.name || ''), form.targets, h.t(c));
  return c.redirect('/intake', 303);
};
