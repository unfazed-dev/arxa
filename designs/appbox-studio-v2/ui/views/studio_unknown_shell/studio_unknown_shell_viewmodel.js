/// This is the business logic for studio_unknown_shell.
///
/// Role: unknown shell — the dead-route ceremony. Chromeless on purpose
/// (v1 parity): the shell furnishes only the document title; there is no
/// brand rail, no build identity, nothing to navigate but the notice.
///
/// Requirements:
/// 1. [Ceremony shells cut over first] — Q-v2-5
/// 2. [No models, no facade — a 404 has no content, only strings] — grill
///    ruling D9 (data-spine scope)
///
/// Relationships: studio_unknown/studio_unknown_viewmodel.js spreads
/// shellProps() into its render context; consumed by
/// studio_unknown_shell_view.tsx.
///
/// History: git log --follow -- ui/views/studio_unknown_shell/studio_unknown_shell_viewmodel.js

export const shellId = 'studio_unknown_shell';

/** @param {(key: string) => string} translate */
export const shellProps = (translate) => ({
  pageTitle: translate('unknownPageTitle'),
});
