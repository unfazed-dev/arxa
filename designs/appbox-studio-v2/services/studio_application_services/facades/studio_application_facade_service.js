// Role: the hub's one data door — turns the screens registry into the stage
//   roster a hub rung renders. Labels are resolved here, so no rung variant
//   ever reaches for a raw registry key.
// Requirements: Q-v2-1 (every stage names what it consumes and produces;
//   advancement is user-triggered, so `enabled` is data, never inferred).
// Relationships: studio_application_repository_service.js -> this ->
//   studio_stage_board_viewmodel.js.
// History: created for studio v2; consumer renamed when the hub's surface
//   became studio_stage_board (shell view + one board surface).
import { registry } from '../repositories/studio_application_repository_service.js';

/** @param {(key: string) => string} t */
export const stageRoster = (t) =>
  registry().stages.map((s) => ({
    id: s.id,
    name: t(s.labelKey),
    consumes: s.consumes,
    produces: s.produces,
    href: s.href,
    enabled: s.enabled,
  }));
