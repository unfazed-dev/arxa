/// This is the business logic for studio_startup_shell.
///
/// Role: startup shell — the boot ceremony. Owns the shell furnishings
/// only (brand and build identity); the boot checklist itself belongs to
/// the surface.
///
/// Requirements:
/// 1. [Ceremony: boot/loading; splashscreen is a surface, not a shell] — Q-v2-1
/// 2. [Ceremony shells cut over first] — Q-v2-5
///
/// Relationships: studio_startup/studio_startup_viewmodel.js spreads
/// shellProps() into its render context; consumed by
/// studio_startup_shell_view.tsx.
///
/// History: git log --follow -- ui/views/studio_startup_shell/studio_startup_shell_viewmodel.js

export const shellId = 'studio_startup_shell';

/** @param {(key: string) => string} translate */
export const shellProps = (translate) => ({
  brand: translate('appTitle'),
  tagline: translate('startupTagline'),
});
