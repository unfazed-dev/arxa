export const surfaceId = 'build.finding';

import { chrome } from '../../../../../services/facades/shell_facade.js';
import { findings } from '../../../../../services/facades/pipeline_facade.js';

// States named in the brief are server-driven in-page variants, not forks.
const STATES = ["finding"];

export const page = (c, h) => {
  const q = c.req.query('state');
  const state = STATES.includes(q) ? q : 'finding';
  return h.render(c, 'ui/views/stage_shell/build/finding/finding_view.html', {
    ...chrome('build'), state, states: STATES, base: '/build/finding',
    ...findings(),
  });
};
