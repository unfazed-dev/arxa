export const surfaceId = 'settings.kits';

import { chrome } from '../../../../../services/facades/shell_facade.js';
import { kitList } from '../../../../../services/facades/catalog_facade.js';

// States named in the brief are server-driven in-page variants, not forks.
const STATES = ["kits"];

export const page = (c, h) => {
  const q = c.req.query('state');
  const state = STATES.includes(q) ? q : 'kits';
  return h.render(c, 'ui/views/stage_shell/settings/kits/kits_view.html', {
    ...chrome('settings'), state, states: STATES, base: '/settings/kits',
    ...kitList(),
  });
};
