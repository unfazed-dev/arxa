// Role: the hub — routes/navigation host for the studio (the showcase
//   `app.dart` analogue). It owns no pipeline state; it presents each shell as
//   the stage it fronts and hands the user a manual trigger into it.
// Requirements: Q-v2-1 (hub + shell roster; pipeline<->shell coherence; manual
//   per-shell "proceed" triggers, never implicit advancement).
// Relationships: app.routes.js -> this -> studio_application_hub_view.tsx,
//   reading the roster through studio_application_facade_service.js.
// History: created for studio v2 (fresh tree, Q-v2-5).

export const viewId = 'studio_application_hub_view';

import { stageRoster } from '../../../services/studio_application_services/facades/studio_application_facade_service.js';

/** @param {import('hono').Context} c @param {import('../../../runtime/types').Helpers} h */
export const view = (c, h) => {
  const t = h.t(c);
  return h.render(c, 'ui/views/studio_application_hub/studio_application_hub_view.html', {
    brand: t('appTitle'),
    stages: stageRoster(t),
    locale: h.locale(c),
  });
};
