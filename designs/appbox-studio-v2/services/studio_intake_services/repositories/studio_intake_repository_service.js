// Role: the only reader of the intake seed. Viewmodels never touch disk;
//   the productionize DB swap happens behind this file.
// Requirements: Q-v2-4 (recipe naming verbatim, extension mapped to .js).
// Relationships: fixture_reader.js -> this -> studio_intake_facade_service.js.
// History: created when the intake shell landed (all-shells pass,
//   2026-08-16).
import { readFixture } from '../../repositories/fixture_reader.js';

/** @returns {{ modes: Array<Record<string, unknown>>, turns: Array<Record<string, unknown>>, currentQuestion: string, assets: Array<Record<string, unknown>> }} */
export const intakeSeed = () =>
  /** @type {any} */ (readFixture('../../../models/studio_intake_model/intake_seed.json'));
