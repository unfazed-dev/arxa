export const surfaceId = 'main.home';

import { homeContext } from '../../../../services/facades/greeting_facade.js';
import { chrome } from '../main_shell_viewmodel.js';

export const page = (c, h) => {
  const ctx = homeContext(h.locale(c));
  // ?n= overrides the count for the itemCount plural demo (one/few/many).
  const n = Number(c.req.query('n'));
  return h.render(c, 'ui/views/main_shell/home/home_view.html', {
    ...chrome('home', h.t(c)),
    ...ctx,
    demoCount: Number.isInteger(n) && n >= 0 ? n : ctx.count,
  });
};
