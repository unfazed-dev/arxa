/// This is the business logic for studio_application_hub.
///
/// Role: hub — the studio's navigation host. Owns the hub-hosted widgets
/// (brand and the locale switch); the stage board itself is a surface
/// under it.
///
/// Requirements:
/// 1. [Hub fronts the shell roster] — Q-v2-1
/// 2. [studio_ prefix] — Q-v2-2
///
/// Relationships: consumed by studio_application_hub_view.tsx; the
/// retired studio_stage_board surface no longer spreads hubBrand().
///
/// History: git log --follow -- ui/views/studio_application_hub/studio_application_hub_viewmodel.js

export const shellId = 'studio_application_hub';

/** @param {(key: string) => string} translate */
export const hubBrand = (translate) => ({ brand: translate('appTitle') });
