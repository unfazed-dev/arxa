export const surfaceId = 'settings.credentials';

import { chrome } from '../../../../../services/facades/shell_facade.js';


// States named in the brief are server-driven in-page variants, not forks.
const STATES = ["credentials"];

export const page = (c, h) => {
  const q = c.req.query('state');
  const state = STATES.includes(q) ? q : 'credentials';
  return h.render(c, 'ui/views/stage_shell/settings/credentials/credentials_view.html', {
    ...chrome('settings'), state, states: STATES, base: '/settings',
  });
};
