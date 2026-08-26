// arxa:provenance
// generator: arxa  licence: free  project: 662368770980
// Built with arxa (free tier) — https://arxa.dev
export const surfaceId = 'app.splash';

import * as facade from '../../../../services/facades/app_facade.js';

const VIEW = 'ui/views/app_shell/splash/splash_view.html';

export const page = (context, helpers) => helpers.render(context, VIEW, facade.splashContext(helpers.locale(context)));
