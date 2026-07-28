export const surfaceId = 'design.surface';

import { chrome } from '../../../../../services/facades/shell_facade.js';

// States named in the brief are server-driven in-page variants, not forks.
const STATES = ["live", "stale"];
const VIEW = 'ui/views/stage_shell/design/surface/surface_view.html';

const stateOf = (c, h) => {
  const q = c.req.query('state');
  if (STATES.includes(q)) return q;
  return h.session(c).data.surfaceStale ? 'stale' : 'live';
};

export const page = (c, h) =>
  h.render(c, VIEW, {
    ...chrome('design'), state: stateOf(c, h), states: STATES, base: '/design/surface',
  });

// Re-render clears the staleness the panel was complaining about, then swaps
// the panel that was complaining. Write first, render from the write.
export const submit = (c, h) => {
  h.session(c).data.surfaceStale = false;
  return h.render(c, `${VIEW}#panel`, { ...chrome('design'), state: 'live' });
};
