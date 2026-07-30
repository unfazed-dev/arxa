export const surfaceId = 'app.access';

import * as facade from '../../../../services/facades/app_facade.js';

const VIEW = 'ui/views/app_shell/splash/splash_view.html';

export const page = (c, h) => h.render(c, VIEW, facade.splashContext(h.locale(c)));
