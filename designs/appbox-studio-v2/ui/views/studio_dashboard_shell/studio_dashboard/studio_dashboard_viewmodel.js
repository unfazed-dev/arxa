// Role: the dashboard surface — the studio home. It presents the needs-you
//   gate strip, the project grid, the analytics trio and the new-project
//   wizard, and hands the user manual triggers onward. It owns no pipeline
//   state.
// Requirements: Q-v2-1 (manual per-gate/per-project triggers, never implicit
//   advancement). The POST handlers are design-medium simulations: they
//   acknowledge the trigger and return home — no state mutates in a fixture.
// Relationships: app.routes.js -> this -> studio_dashboard_view.tsx, reading
//   its context through studio_dashboard_facade_service.js.
// History: created when the hub was dissolved into studio_dashboard_shell.

export const surfaceId = 'studio_dashboard';
export const viewId = 'studio_dashboard_view';

import { shellProps } from '../studio_dashboard_shell_viewmodel.js';
import { dashboardContext } from '../../../../services/studio_dashboard_services/facades/studio_dashboard_facade_service.js';

const VIEW = 'ui/views/studio_dashboard_shell/studio_dashboard/studio_dashboard_view.html';

/** @param {import('hono').Context} context @param {import('../../../../runtime/types').Helpers} helpers */
export const view = (context, helpers) => {
  const translate = helpers.translate(context);
  return helpers.render(context, VIEW, {
    ...shellProps(translate),
    ...dashboardContext(translate),
    locale: helpers.locale(context),
  });
};

/** Gate decision trigger. Design medium: acknowledge and return home. */
/** @param {import('hono').Context} context @param {import('../../../../runtime/types').Helpers} helpers */
export const decideGate = (context, helpers) => context.redirect('/', 303);

/** "Use project" trigger. Design medium: acknowledge and return home. */
/** @param {import('hono').Context} context @param {import('../../../../runtime/types').Helpers} helpers */
export const useProject = (context, helpers) => context.redirect('/', 303);

/** New-project wizard submit. Design medium: acknowledge and return home. */
/** @param {import('hono').Context} context @param {import('../../../../runtime/types').Helpers} helpers */
export const createProject = (context, helpers) => context.redirect('/', 303);
