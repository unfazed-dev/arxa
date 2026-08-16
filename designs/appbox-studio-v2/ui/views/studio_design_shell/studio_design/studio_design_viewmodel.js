/// This is the business logic for studio_design.
///
/// Role: the design surface — the canvas studio. Renders the device
/// tiles (Portalo simulated content per the registry seed), the
/// inspector tabs, the composer sheet and the needs-you chips; the POST
/// is a design-medium simulation that acknowledges and stays.
///
/// Requirements:
/// 1. [Working shell: boot-guarded, flat route] — R2, R3
/// 2. [Designed-app content is Portalo] — registry seed note
/// 3. [v1 canvas/inspector layout restructured, not redesigned] — VISUAL PARITY LAW
///
/// Relationships: studio_design_facade_service.js -> this ->
/// studio_design_view.tsx; app.routes.js mounts view + compose.
///
/// History: git log --follow -- ui/views/studio_design_shell/studio_design/studio_design_viewmodel.js

export const surfaceId = 'studio_design';
export const viewId = 'studio_design_view';

import { shellProps } from '../studio_design_shell_viewmodel.js';
import { designContext } from '../../../../services/studio_design_services/facades/studio_design_facade_service.js';

const VIEW = 'ui/views/studio_design_shell/studio_design/studio_design_view.html';

/** @param {import('hono').Context} context @param {import('../../../../runtime/types').Helpers} helpers */
export const view = (context, helpers) => {
  const translate = helpers.translate(context);
  return helpers.render(context, VIEW, {
    ...shellProps(translate),
    translate,
    title: translate('designTitle'),
    canvasTitle: translate('designCanvas'),
    inspectorTitle: translate('designInspector'),
    composerTitle: translate('designComposer'),
    composerPlaceholder: translate('designComposerPlaceholder'),
    composerSend: translate('designComposerSend'),
    zoomLabel: translate('designZoom'),
    gridLabel: translate('designGrid'),
    needsYouLabel: translate('designNeedsYou'),
    activityTitle: translate('designActivity'),
    ...designContext(),
    locale: helpers.locale(context),
  });
};

/** Composer submit. Design medium: acknowledge and stay. */
/** @param {import('hono').Context} context @param {import('../../../../runtime/types').Helpers} helpers */
export const compose = (context, helpers) => context.redirect('/design', 303);
