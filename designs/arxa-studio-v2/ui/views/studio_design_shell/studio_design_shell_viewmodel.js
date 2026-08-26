/// This is the business logic for studio_design_shell.
///
/// Role: design shell — the pipeline's canvas host. Owns its panels;
/// mounts hub-hosted widgets into them; the design surface itself lives
/// under it. The registry lists design_canvas, inspector_panel,
/// composer_slider_panel, needs_you_strip and activity — all
/// surface-owned; no footer panel, so none mounts.
///
/// Requirements:
/// 1. [Shell fronts the pipeline] — Q-v2-1
/// 2. [studio_ prefix] — Q-v2-2
/// 3. [Panels are shell-owned, shared widgets are hub-hosted] — showcase law
///
/// Relationships: studio_design/studio_design_viewmodel.js spreads
/// shellProps() into its render context; consumed by
/// studio_design_shell_view.tsx.
///
/// History: git log --follow -- ui/views/studio_design_shell/studio_design_shell_viewmodel.js

export const shellId = 'studio_design_shell';

/** The id the hub destinations use for this shell's tab/rail highlight. */
export const destinationId = 'design';

/** @param {(key: string) => string} translate */
export const shellProps = (translate) => ({
  activeShell: destinationId,
});
