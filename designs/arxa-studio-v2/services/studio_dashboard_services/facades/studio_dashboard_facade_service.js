// Role: the dashboard's one data door — turns the dashboard seed into the
//   render context the surface consumes. The seed carries v1's fixture data
//   (gates, stats, pairing, wizard) already locale-resolved, so nothing here
//   reaches for a raw key.
// Requirements: Q-v2-1 (every gate names its project and stage; advancement is
//   user-triggered — `current` on a project is data, never inferred).
// Relationships: studio_dashboard_repository_service.js -> this ->
//   studio_dashboard_viewmodel.js.
// History: created when the hub was dissolved into studio_dashboard_shell.
import { dashboardSeed } from '../repositories/studio_dashboard_repository_service.js';

/** @param {(key: string) => string} translate */
export const dashboardContext = (translate) => {
  const seed = dashboardSeed();
  const gates = seed.gates ?? [];
  return {
    account: seed.account ?? {},
    gates,
    gateCount: gates.length,
    projects: seed.projects ?? [],
    stats: seed.stats ?? {},
    pairingModal: seed.pairing ?? { qr: [] },
    wizard: seed.wizard ?? {},
  };
};
