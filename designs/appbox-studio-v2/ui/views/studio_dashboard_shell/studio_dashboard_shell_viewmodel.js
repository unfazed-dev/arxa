// Role: dashboard shell — the studio's working host. Owns its panels (header,
//   tabbar, rail, main, footer) and mounts hub-hosted widgets into them; the
//   dashboard surface itself lives under it. No hub-style furniture: a panel this shell
//   does not mount does not exist in it.
// Requirements: Q-v2-1 (shell fronts the pipeline), Q-v2-2 (studio_ prefix);
//   showcase law — panels are shell-owned, shared widgets are hub-hosted.
// Relationships: studio_dashboard/studio_dashboard_viewmodel.js spreads
//   shellProps() into its render context; consumed by
//   studio_dashboard_shell_view.tsx.
// History: created when studio_application_hub dissolved — its navigation
//   widgets moved to the hub roster (ui/widgets/studio_dashboard_widgets/), its
//   shell role landed here.

export const shellId = 'studio_dashboard_shell';

/** The id the hub destinations use for this shell's tab/rail highlight. */
export const destinationId = 'dashboard';

/** @param {(key: string) => string} t */
export const shellProps = (t) => ({
  activeShell: destinationId,
});
