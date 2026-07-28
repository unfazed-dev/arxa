export const surfaceId = 'settings.devices';

import { chrome } from '../../../../../services/facades/shell_facade.js';
import { deviceList } from '../../../../../services/facades/catalog_facade.js';

// States named in the brief are server-driven in-page variants, not forks.
const STATES = ["paired", "revoke"];

export const page = (c, h) => {
  const q = c.req.query('state');
  const state = STATES.includes(q) ? q : 'paired';
  return h.render(c, 'ui/views/stage_shell/settings/devices/devices_view.html', {
    ...chrome('settings'), state, states: STATES, base: '/settings/devices',
    ...deviceList(),
  });
};
