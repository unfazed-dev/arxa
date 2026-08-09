// Role: the stage board surface — the studio's front door. It owns no pipeline
//   state; it presents each shell as the stage it fronts and hands the user a
//   manual trigger into it.
// Requirements: Q-v2-1 (hub + shell roster; pipeline<->shell coherence; manual
//   per-shell triggers, never implicit advancement).
// Relationships: app.routes.js -> this -> studio_stage_board_view.tsx, reading
//   the roster through studio_application_facade_service.js.
// History: created for studio v2.

export const surfaceId = 'studio_stage_board';
export const viewId = 'studio_stage_board_view';

import { chrome } from '../studio_application_hub_shell_viewmodel.js';
import { stageRoster } from '../../../../services/studio_application_services/facades/studio_application_facade_service.js';

/** @param {import('hono').Context} c @param {import('../../../../runtime/types').Helpers} h */
export const view = (c, h) => {
  const t = h.t(c);
  return h.render(c, 'ui/views/studio_application_hub/studio_stage_board/studio_stage_board_view.html', {
    ...chrome(t),
    title: t('hubTitle'),
    subtitle: t('hubSubtitle'),
    consumesLabel: t('stageConsumes'),
    producesLabel: t('stageProduces'),
    stages: stageRoster(t),
    locale: h.locale(c),
  });
};
