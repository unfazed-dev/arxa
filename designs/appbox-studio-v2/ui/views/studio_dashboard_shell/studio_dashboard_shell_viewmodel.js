/// This is the business logic for studio_dashboard_shell.
///
/// Role: dashboard shell — the studio's working host. Owns its panels
/// (header, tabbar, rail, main, footer) and mounts hub-hosted widgets
/// into them; the dashboard surface itself lives under it. No hub-style
/// furniture: a panel this shell does not mount does not exist in it.
///
/// Requirements:
/// 1. [Shell fronts the pipeline] — Q-v2-1
/// 2. [studio_ prefix] — Q-v2-2
/// 3. [Panels are shell-owned, shared widgets are hub-hosted] — showcase law
///
/// Relationships: studio_dashboard/studio_dashboard_viewmodel.js spreads
/// shellProps() into its render context; consumed by
/// studio_dashboard_shell_view.tsx.
///
/// History: git log --follow -- ui/views/studio_dashboard_shell/studio_dashboard_shell_viewmodel.js

export const shellId = 'studio_dashboard_shell';

/** The id the hub destinations use for this shell's tab/rail highlight. */
export const destinationId = 'dashboard';

/** @param {(key: string) => string} translate */
export const shellProps = (translate) => ({
  activeShell: destinationId,
});
