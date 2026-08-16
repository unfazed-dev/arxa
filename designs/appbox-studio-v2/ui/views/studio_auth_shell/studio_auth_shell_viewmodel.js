/// This is the business logic for studio_auth_shell.
///
/// Role: auth shell — the credentials ceremony. Owns the shell
/// furnishings only (brand identity); the credential form itself
/// belongs to the surface.
///
/// Requirements:
/// 1. [Ceremony: consumes session, produces credentials] — Q-v2-1
/// 2. [Ceremony shells cut over first] — Q-v2-5 (amended: all shells
///    land enabled in one pass, owner ruling 2026-08-16)
///
/// Relationships: studio_auth/studio_auth_viewmodel.js spreads
/// shellProps() into its render context; consumed by
/// studio_auth_shell_view.tsx.
///
/// History: git log --follow -- ui/views/studio_auth_shell/studio_auth_shell_viewmodel.js

export const shellId = 'studio_auth_shell';

/** @param {(key: string) => string} translate */
export const shellProps = (translate) => ({
  brand: translate('appTitle'),
  tagline: translate('startupTagline'),
});
