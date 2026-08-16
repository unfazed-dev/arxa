/// This is the business logic for studio_intake_shell.
///
/// Role: intake shell — the pipeline's interview host. Owns its panels;
/// mounts hub-hosted widgets into them; the interview surface itself
/// lives under it. The registry lists interview_thread and
/// asset_upload_dropzone — no footer panel, so none mounts.
///
/// Requirements:
/// 1. [Shell fronts the pipeline] — Q-v2-1
/// 2. [studio_ prefix] — Q-v2-2
/// 3. [Panels are shell-owned, shared widgets are hub-hosted] — showcase law
///
/// Relationships: studio_intake/studio_intake_viewmodel.js spreads
/// shellProps() into its render context; consumed by
/// studio_intake_shell_view.tsx.
///
/// History: git log --follow -- ui/views/studio_intake_shell/studio_intake_shell_viewmodel.js

export const shellId = 'studio_intake_shell';

/** The id the hub destinations use for this shell's tab/rail highlight. */
export const destinationId = 'intake';

/** @param {(key: string) => string} translate */
export const shellProps = (translate) => ({
  activeShell: destinationId,
});
