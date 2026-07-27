export const surfaceId = 'projects.new';

import { chrome } from '../../../../../services/facades/shell_facade.js';


// States named in the brief are server-driven in-page variants, not forks.
const STATES = ["form", "validating", "error"];

export const page = (c, h) => {
  const q = c.req.query('state');
  const state = STATES.includes(q) ? q : 'form';
  return h.render(c, 'ui/views/stage_shell/projects/new/new_view.html', {
    ...chrome('projects'), state, states: STATES, base: '/projects/new',
  });
};

// The prototype re-renders; it does not persist. Approval and build state
// belong to pipeline state, not to a design artifact pretending to hold them.
export const submit = (c, h) => h.refresh(c);
