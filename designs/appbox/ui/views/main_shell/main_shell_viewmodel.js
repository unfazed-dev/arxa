// appbox:provenance
// generator: app-box  licence: free  project: 662368770980
// Built with app-box (free tier) — https://appbox.dev
export const surfaceId = 'main.chrome';

import { shellIndexContext } from '../../../services/facades/screens_facade.js';

// The shell renders the chrome; surfaces fill its {% block surface %}.
// Until surfaces land, '/' doubles as the design index — the registry
// rendered as the build tracker. Labels follow the request locale.
export const page = (c, h) =>
  h.render(c, 'ui/views/main_shell/main_shell_view.html', { activeShell: 'index', ...shellIndexContext(h.t(c)) });
