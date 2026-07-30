// appbox:provenance
// generator: app-box  licence: free  project: 662368770980
// Built with app-box (free tier) — https://appbox.dev
export const surfaceId = 'app.splash';

import * as facade from '../../../../services/facades/app_facade.js';

const VIEW = 'ui/views/app_shell/splash/splash_view.html';

export const page = (c, h) => h.render(c, VIEW, facade.splashContext(h.locale(c)));
