// Role: the only reader of the dashboard seed. Viewmodels never touch disk;
//   the productionize DB swap happens behind this file.
// Requirements: Q-v2-4 (recipe naming verbatim, extension mapped to .js).
// Relationships: fixture_reader.js -> this -> studio_dashboard_facade_service.js.
// History: created when the hub was dissolved into studio_dashboard_shell —
//   the dashboard is the landing surface and needs its own data door.
import { readFixture } from '../../repositories/fixture_reader.js';

/** @returns {{ account: Record<string, unknown>, gates: Array<Record<string, unknown>>, projects: Array<Record<string, unknown>>, stats: Record<string, unknown>, pairing: Record<string, unknown>, wizard: Record<string, unknown> }} */
export const dashboardSeed = () =>
  /** @type {any} */ (readFixture('../../../models/studio_dashboard_model/dashboard_seed.json'));
