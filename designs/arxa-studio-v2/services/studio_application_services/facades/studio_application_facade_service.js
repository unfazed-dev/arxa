// Role: the hub's one data door — turns the screens registry into the stage
//   roster a hub rung renders. Labels are resolved here, so no rung variant
//   ever reaches for a raw registry key.
// Requirements: Q-v2-1 (every stage names what it consumes and produces;
//   advancement is user-triggered, so `enabled` is data, never inferred).
// Relationships: studio_application_repository_service.js -> this.
// History: created for studio v2; former consumer studio_stage_board was
//   retired when studio_dashboard_shell took over the stage roster —
//   currently consumer-less, pending hub-shell disposition.
import { registry } from '../repositories/studio_application_repository_service.js';

/** @param {(key: string) => string} translate */
export const stageRoster = (translate) =>
  registry().stages.map((stage) => ({
    id: stage.id,
    name: translate(stage.labelKey),
    consumes: stage.consumes,
    produces: stage.produces,
    href: stage.href,
    enabled: stage.enabled,
  }));
