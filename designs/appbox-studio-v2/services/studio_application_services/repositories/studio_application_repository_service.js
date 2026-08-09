// Role: the only reader of the screens registry. Viewmodels never touch disk;
//   the productionize DB swap happens behind this file.
// Requirements: Q-v2-4 (recipe naming verbatim, extension mapped to .js).
// Relationships: fixture_reader.js -> this -> studio_application_facade_service.js.
// History: created for studio v2.
import { readFixture } from '../../repositories/fixture_reader.js';

/** @returns {{ stages: Array<Record<string, unknown>>, shells: Array<Record<string, unknown>> }} */
export const registry = () =>
  /** @type {any} */ (readFixture('../../../models/screens_model/registry.json'));
