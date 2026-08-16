// Role: the intake surface's one data door — turns the intake seed into
//   the render context the thread consumes. The seed carries the v1
//   fixture data (mode cards, interview turns, uploaded assets) already
//   locale-resolved, so nothing here reaches for a raw key.
// Requirements: Q-v2-1 (manual advancement; the thread's shape is
//   reviewable, no state mutates in a fixture).
// Relationships: studio_intake_repository_service.js -> this ->
//   studio_intake_viewmodel.js.
// History: created when the intake shell landed (all-shells pass,
//   2026-08-16).
import { intakeSeed } from '../repositories/studio_intake_repository_service.js';

/** @returns {{ modes: Array<Record<string, unknown>>, turns: Array<Record<string, unknown>>, currentQuestion: string, assets: Array<Record<string, unknown>> }} */
export const intakeContext = () => {
  const seed = intakeSeed();
  return {
    modes: seed.modes ?? [],
    turns: seed.turns ?? [],
    currentQuestion: seed.currentQuestion ?? '',
    assets: seed.assets ?? [],
  };
};
