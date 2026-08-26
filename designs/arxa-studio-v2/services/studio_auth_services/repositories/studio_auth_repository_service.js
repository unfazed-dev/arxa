// Role: the only reader of the auth seed. Viewmodels never touch disk;
//   the productionize DB swap happens behind this file.
// Requirements: Q-v2-4 (recipe naming verbatim, extension mapped to .js).
// Relationships: fixture_reader.js -> this -> studio_auth_facade_service.js.
// History: created when the auth ceremony landed (all-shells pass,
//   2026-08-16).
import { readFixture } from '../../repositories/fixture_reader.js';

/** @returns {{ states: Record<string, Record<string, unknown>> }} */
export const authSeed = () =>
  /** @type {any} */ (readFixture('../../../models/studio_auth_model/auth_seed.json'));
