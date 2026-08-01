// appbox:provenance
// generator: appbox  licence: free  project: 662368770980
// Built with appbox (free tier) — https://appbox.dev
export const surfaceId = 'app.dashboard';

import * as facade from '../../../../services/facades/app_facade.js';

const VIEW = 'ui/views/app_shell/dashboard/dashboard_view.html';

export const page = (c, h) =>
  h.render(c, VIEW, {
    activeShell: 'app',
    tab: 'dashboard',
    ...facade.embedContext(c),
    ...facade.dashboardContext(h.session(c).data, h.locale(c)),
  });

// Needs-you quick actions — seeded decision, 303 back to the dashboard.
export const decide = async (c, h) => {
  const form = await h.form(c);
  facade.decideGate(h.session(c).data, String(form.gate || ''), String(form.decision || ''), h.locale(c));
  return c.redirect('/dashboard', 303);
};

// GenUI new-project wizard — creates a seeded project row, lands on intake.
export const createProject = async (c, h) => {
  const form = await h.form(c);
  facade.createProject(h.session(c).data, String(form.name || ''), form.targets, h.t(c));
  return c.redirect('/intake', 303);
};
