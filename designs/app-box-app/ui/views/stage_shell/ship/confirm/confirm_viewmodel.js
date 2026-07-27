export const surfaceId = 'ship.confirm';

import { chrome } from '../../../../../services/facades/shell_facade.js';
import { release } from '../../../../../services/facades/pipeline_facade.js';

// States named in the brief are server-driven in-page variants, not forks.
const STATES = ["pending", "confirmed"];

export const page = (c, h) => {
  const q = c.req.query('state');
  const state = STATES.includes(q) ? q : 'pending';
  return h.render(c, 'ui/views/stage_shell/ship/confirm/confirm_view.html', {
    ...chrome('ship'), state, states: STATES, base: '/ship/confirm',
    ...release(),
  });
};

export const approve = (c, h) => h.refresh(c);
