export const surfaceId = 'design.directions';

import { chrome } from '../../../../../services/facades/shell_facade.js';


// States named in the brief are server-driven in-page variants, not forks.
const STATES = ["three-up", "approved"];

export const page = (c, h) => {
  const q = c.req.query('state');
  const state = STATES.includes(q) ? q : 'three-up';
  return h.render(c, 'ui/views/stage_shell/design/directions/directions_view.html', {
    ...chrome('design'), state, states: STATES, base: '/design',
  });
};
