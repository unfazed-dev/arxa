// Role: the design surface's one data door — turns the design seed into
//   the render context the studio consumes. The seed carries the Portalo
//   simulated content (registry seed.portalo: Portalo is NOT a studio
//   shell; its stills live under assets/portalo/) already
//   locale-resolved.
// Requirements: Q-v2-1 (needs-you decisions are manual triggers);
//   registry design_canvas note (tile set per rung is the caller's
//   business — this door serves every tile once).
// Relationships: studio_design_repository_service.js -> this ->
//   studio_design_viewmodel.js.
// History: created when the design shell landed (all-shells pass,
//   2026-08-16).
import { designSeed } from '../repositories/studio_design_repository_service.js';

/** @returns {{ tiles: Array<Record<string, unknown>>, inspectorTabs: Array<Record<string, unknown>>, chips: Array<Record<string, unknown>>, activity: Array<Record<string, unknown>> }} */
export const designContext = () => {
  const seed = designSeed();
  return {
    tiles: seed.tiles ?? [],
    inspectorTabs: seed.inspectorTabs ?? [],
    chips: seed.chips ?? [],
    activity: seed.activity ?? [],
  };
};
