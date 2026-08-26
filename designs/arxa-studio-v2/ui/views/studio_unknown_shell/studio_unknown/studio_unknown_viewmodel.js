/// This is the business logic for studio_unknown.
///
/// Role: the unknown surface — the 404 notice. Stateless by ruling: three
/// strings and a home link, no models, no facade. Everything renders from
/// l10n; there is nothing to fetch on a route that does not exist.
///
/// Requirements:
/// 1. [Ceremony shells cut over first, behind user validation] — Q-v2-5
/// 2. [No models/facade for unknown — empty-state and chrome only] — grill
///    ruling D9 (data-spine scope)
///
/// Relationships: this -> studio_unknown_view.tsx; return-home edge is
/// intake/flows.json `studio_unknown_shell.unknown ->
/// studio_dashboard_shell.studio_dashboard`.
///
/// History: git log --follow -- ui/views/studio_unknown_shell/studio_unknown/studio_unknown_viewmodel.js

export const surfaceId = 'studio_unknown';
export const viewId = 'studio_unknown_view';

import { shellProps } from '../studio_unknown_shell_viewmodel.js';

const VIEW = 'ui/views/studio_unknown_shell/studio_unknown/studio_unknown_view.html';

/** @param {import('hono').Context} context @param {import('../../../../runtime/types').Helpers} helpers */
export const view = (context, helpers) => {
  const translate = helpers.translate(context);
  return helpers.render(context, VIEW, {
    ...shellProps(translate),
    code: translate('unknownCode'),
    msg: translate('unknownMsg'),
    hint: translate('unknownHint'),
    homeHref: '/',
    homeLabel: translate('unknownHome'),
    locale: helpers.locale(context),
  });
};
