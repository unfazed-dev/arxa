// Role: startup shell — the boot ceremony. Owns the shell furnishings only (brand
//   and build identity); the boot checklist itself belongs to the surface.
// Requirements: Q-v2-1 (ceremony: boot/loading; splashscreen is a surface, not
//   a shell), Q-v2-5 (ceremony shells cut over first).
// Relationships: studio_startup/studio_startup_viewmodel.js spreads shellProps()
//   into its render context; consumed by studio_startup_shell_view.tsx.
// History: created for studio v2.

export const shellId = 'studio_startup_shell';

/** @param {(key: string) => string} t */
export const shellProps = (t) => ({
  brand: t('appTitle'),
  tagline: t('startupTagline'),
});
