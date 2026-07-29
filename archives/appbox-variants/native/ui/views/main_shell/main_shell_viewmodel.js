export const surfaceId = 'main.shell';

import { shellIndexContext } from '../../../services/facades/screens_facade.js';

// The shell renders the chrome; surfaces fill its {% block surface %}.
// Until surfaces land, '/' doubles as the design index — the registry
// rendered as the build tracker.
export const page = (c, h) =>
  h.render(c, 'ui/views/main_shell/main_shell_view.html', { activeTab: 'index', ...shellIndexContext() });
