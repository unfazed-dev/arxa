export const surfaceId = 'main.shell';

import { routes } from '../../../runtime/routes.js';

// The shell renders the chrome; surfaces fill its {% block surface %}.
/** @param {import('hono').Context} c @param {import('../../../runtime/types').Helpers} h */
export const page = (c, h) =>
  h.render(c, 'ui/views/main_shell/main_shell_view.html');

// One `rail` context feeds both nav widgets — the rail (medium+) and the
// bottom nav (compact) are the same destinations at different rungs of the
// ladder. Every surface merges chrome(<its id>, h.t(c)) so `current` follows
// the route and the labels follow the request locale.
//
// hrefs come from the generated route manifest (runtime/routes.js), not
// string literals: renaming a route in app.routes.js then fails
// `npm run typecheck` here instead of silently 404ing a nav item.
/**
 * @param {string} current
 * @param {(key: string, vars?: Record<string, unknown>) => string} [t]
 */
export const chrome = (current, t = (s) => s) => ({
  rail: {
    brand: 'hello-hda',
    items: [
      { id: 'home', label: t('nav.home'), icon: 'house', href: routes.index(), current: current === 'home' },
      { id: 'timer', label: t('nav.timer'), icon: 'timer', href: routes.timer.index(), current: current === 'timer' },
    ],
  },
});
