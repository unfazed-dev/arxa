// Role: hub shell — the studio's navigation host. Owns chrome only (brand and
//   the locale switch); the stage board itself is a surface under it.
// Requirements: Q-v2-1 (hub fronts the shell roster), Q-v2-2 (studio_ prefix).
// Relationships: studio_stage_board_viewmodel.js spreads chrome() into its
//   render context; consumed by studio_application_hub_shell_view.tsx.
// History: created for studio v2.

export const shellId = 'studio_application_hub';

/** @param {(key: string) => string} t */
export const chrome = (t) => ({ brand: t('appTitle') });
