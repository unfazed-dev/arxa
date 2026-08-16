// Role: the only reader of the design seed. Viewmodels never touch disk;
//   the productionize DB swap happens behind this file.
// Requirements: Q-v2-4 (recipe naming verbatim, extension mapped to .js).
// Relationships: fixture_reader.js -> this -> studio_design_facade_service.js.
// History: created when the design shell landed (all-shells pass,
//   2026-08-16).
import { readFixture } from '../../repositories/fixture_reader.js';

/** @returns {{ tiles: Array<Record<string, unknown>>, inspectorTabs: Array<Record<string, unknown>>, chips: Array<Record<string, unknown>>, activity: Array<Record<string, unknown>> }} */
export const designSeed = () =>
  /** @type {any} */ (readFixture('../../../models/studio_design_model/design_seed.json'));
