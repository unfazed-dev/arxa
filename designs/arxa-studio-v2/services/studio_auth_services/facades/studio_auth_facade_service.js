// Role: the auth surface's one data door — turns the auth seed into the
//   render context the card consumes. The seed carries the v1 copy sets
//   (default/signup/expired) already locale-resolved, so nothing here
//   reaches for a raw key.
// Requirements: Q-v2-1 (manual trigger only), v1 auth contract (?state=
//   swaps headline/lede/note; form and providers stay identical).
// Relationships: studio_auth_repository_service.js -> this ->
//   studio_auth_viewmodel.js.
// History: created when the auth ceremony landed (all-shells pass,
//   2026-08-16).
import { authSeed } from '../repositories/studio_auth_repository_service.js';

/** The card's copy set for a ?state= value. Unknown states fall back to
 *  the default copy — a typo in the query never 500s a ceremony.
 *  @param {string} state
 *  @returns {{ mode?: string, headline?: string, lede?: string, note?: string, providers: Array<{ id: string, label: string }> }} */
export const authContext = (state) => {
  const seed = authSeed();
  const states = seed.states ?? {};
  const copy = states[state] ?? states.default ?? {};
  const providers = copy.providers ?? states.default?.providers ?? [];
  return {
    mode: state === 'default' ? undefined : state,
    headline: copy.headline,
    lede: copy.lede,
    note: copy.note,
    providers,
  };
};
