export const surfaceId = 'projects.home';

import { chrome } from '../../../../../services/facades/shell_facade.js';
import { list } from '../../../../../services/facades/project_facade.js';

// States named in the brief are server-driven in-page variants, not forks.
const STATES = ["list", "empty", "loading"];

export const page = (c, h) => {
  const q = c.req.query('state');
  const state = STATES.includes(q) ? q : 'list';
  return h.render(c, 'ui/views/stage_shell/projects/home/home_view.html', {
    ...chrome('projects'), state, states: STATES, base: '/',
    ...list(),
  });
};
