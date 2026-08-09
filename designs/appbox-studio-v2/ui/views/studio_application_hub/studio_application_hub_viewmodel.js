// Role: hub — the studio's navigation host. Owns the hub-hosted widgets
//   (brand and the locale switch); the stage board itself is a surface under it.
// Requirements: Q-v2-1 (hub fronts the shell roster), Q-v2-2 (studio_ prefix).
// Relationships: consumed by studio_application_hub_view.tsx; the
//   retired studio_stage_board surface no longer spreads hubBrand().
// History: created for studio v2.

export const shellId = 'studio_application_hub';

/** @param {(key: string) => string} t */
export const hubBrand = (t) => ({ brand: t('appTitle') });
