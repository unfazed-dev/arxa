export const surfaceId = 'main.home';

import { homeContext } from '../../../../services/facades/greeting_facade.js';
import { chrome } from '../main_shell_viewmodel.js';

/** @param {import('hono').Context} c @param {import('../../../../runtime/types').Helpers} h */
export const page = (context, helpers) => {
  const ctx = homeContext(helpers.locale(context));
  // ?n= overrides the count for the itemCount plural demo (one/few/many).
  const demoCount = Number(context.req.query('n'));
  return helpers.render(context, 'ui/views/main_shell/home/home_view.html', {
    ...chrome('home', helpers.translate(context)),
    ...ctx,
    demoCount: Number.isInteger(demoCount) && demoCount >= 0 ? demoCount : ctx.count,
  });
};
