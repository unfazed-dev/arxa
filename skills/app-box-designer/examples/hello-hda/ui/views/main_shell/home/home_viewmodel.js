export const surfaceId = 'main.home';

import { homeContext } from '../../../../services/facades/greeting_facade.js';

export const page = (c, h) =>
  h.render(c, 'ui/views/main_shell/home/home_view.html', homeContext());
