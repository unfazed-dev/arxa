export const surfaceId = 'main.home';

import { homeContext } from '../../../../services/facades/greeting_facade.js';
import { chrome } from '../main_shell_viewmodel.js';

export const page = (c, h) =>
  h.render(c, 'ui/views/main_shell/home/home_view.html', {
    ...chrome('home'),
    ...homeContext(),
  });
