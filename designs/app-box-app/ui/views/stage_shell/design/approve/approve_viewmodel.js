export const surfaceId = 'design.approve';

import { chrome } from '../../../../../services/facades/shell_facade.js';


// States named in the brief are server-driven in-page variants, not forks.
const STATES = ["pending", "approved"];

export const page = (c, h) => {
  const q = c.req.query('state');
  const state = STATES.includes(q) ? q : 'pending';
  return h.render(c, 'ui/views/stage_shell/design/approve/approve_view.html', {
    ...chrome('design'), state, states: STATES, base: '/design/approve',
  });
};

export const approve = (c, h) => h.refresh(c);
