export const surfaceId = 'design.surface';

import { chrome } from '../../../../../services/facades/shell_facade.js';


// States named in the brief are server-driven in-page variants, not forks.
const STATES = ["live", "stale"];

export const page = (c, h) => {
  const q = c.req.query('state');
  const state = STATES.includes(q) ? q : 'live';
  return h.render(c, 'ui/views/stage_shell/design/surface/surface_view.html', {
    ...chrome('design'), state, states: STATES, base: '/design/surface',
  });
};

// The prototype re-renders; it does not persist. Approval and build state
// belong to pipeline state, not to a design artifact pretending to hold them.
export const submit = (c, h) => h.refresh(c);
