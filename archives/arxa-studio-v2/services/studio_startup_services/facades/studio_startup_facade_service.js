// Role: the startup surface's one data door. Reports boot steps and whether
//   the session may advance. Advancement is never inferred from "all steps
//   done" — Q-v2-1 makes every stage hand-off a user trigger, so `ready` only
//   means the trigger is allowed to be pressed.
// Requirements: Q-v2-1 (manual per-shell proceed trigger).
// Relationships: fixture_reader.js -> this -> studio_startup_viewmodel.js.
// History: created for studio v2.
import { readFixture } from '../../repositories/fixture_reader.js';

/** @param {(key: string) => string} translate @param {number} elapsed ticks observed so far */
export const bootProgress = (translate, elapsed) => {
  const steps = /** @type {any} */ (readFixture('../../../models/startup_model/boot_seed.json')).steps;
  const done = Math.min(elapsed, steps.length);
  return {
    steps: steps.map((step, index) => ({
      id: step.id,
      label: translate(step.labelKey),
      state: index < done ? 'done' : index === done ? 'running' : 'waiting',
    })),
    ready: done >= steps.length,
  };
};
