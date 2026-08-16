/// This is the business logic for studio_intake.
///
/// Role: the intake surface — the interview thread. Renders the turn
/// list, the current question's composer and the upload dropzone; the
/// POSTs are design-medium simulations that acknowledge and return
/// (Q-v2-1: advancement is a manual trigger, and no answer state
/// mutates in a fixture — the thread's shape is the reviewable thing).
///
/// Requirements:
/// 1. [Working shell: boot-guarded, flat route] — R2, R3
/// 2. [Manual advancement — every answer is a user trigger] — Q-v2-1
/// 3. [Produces intake/registry.json] — registry stage contract
///
/// Relationships: studio_intake_facade_service.js -> this ->
/// studio_intake_view.tsx; app.routes.js mounts view + answer + upload.
///
/// History: git log --follow -- ui/views/studio_intake_shell/studio_intake/studio_intake_viewmodel.js

export const surfaceId = 'studio_intake';
export const viewId = 'studio_intake_view';

import { shellProps } from '../studio_intake_shell_viewmodel.js';
import { intakeContext } from '../../../../services/studio_intake_services/facades/studio_intake_facade_service.js';

const VIEW = 'ui/views/studio_intake_shell/studio_intake/studio_intake_view.html';

/** @param {import('hono').Context} context @param {import('../../../../runtime/types').Helpers} helpers */
export const view = (context, helpers) => {
  const translate = helpers.translate(context);
  return helpers.render(context, VIEW, {
    ...shellProps(translate),
    translate,
    title: translate('intakeTitle'),
    subtitle: translate('intakeSubtitle'),
    answerLabel: translate('intakeAnswer'),
    answerPlaceholder: translate('intakeAnswerPlaceholder'),
    skipLabel: translate('intakeSkip'),
    assetTitle: translate('intakeAssets'),
    assetHint: translate('intakeAssetsHint'),
    assetButton: translate('intakeAssetsButton'),
    ...intakeContext(),
    locale: helpers.locale(context),
  });
};

/** Answer submit. Design medium: acknowledge and stay — the thread is a
 *  fixture; the productionize swap lands behind the facade. */
/** @param {import('hono').Context} context @param {import('../../../../runtime/types').Helpers} helpers */
export const answer = (context, helpers) => context.redirect('/intake', 303);

/** Asset upload. Design medium: acknowledge and stay. */
/** @param {import('hono').Context} context @param {import('../../../../runtime/types').Helpers} helpers */
export const upload = (context, helpers) => context.redirect('/intake', 303);
