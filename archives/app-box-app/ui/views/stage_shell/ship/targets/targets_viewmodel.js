export const surfaceId = 'ship.targets';

import { chrome } from '../../../../../services/facades/shell_facade.js';
import { targetList } from '../../../../../services/facades/catalog_facade.js';

// States named in the brief are server-driven in-page variants, not forks.
const STATES = ["targets"];

export const page = (c, h) => {
  const q = c.req.query('state');
  const state = STATES.includes(q) ? q : 'targets';
  return h.render(c, 'ui/views/stage_shell/ship/targets/targets_view.html', {
    ...chrome('ship'), state, states: STATES, base: '/ship',
    ...targetList(),
  });
};
