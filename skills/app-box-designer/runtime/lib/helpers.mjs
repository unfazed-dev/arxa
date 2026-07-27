import { createTemplates } from './templates.mjs';
import { sessionOf, prefsOf, setPrefs } from './state.mjs';
import { timers } from './timers.mjs';

// The `h` object every viewmodel handler receives: `handler(c, h) => Response`.
export function createHelpers(artifactDir) {
  const templates = createTemplates(artifactDir);

  return {
    // Renders a page or a `#fragment`; merges cookie prefs into the context.
    // Templates see the context bag as top-level keys AND as `c` (for macro calls).
    render(c, viewRef, ctx = {}, status = 200) {
      const bag = { prefs: prefsOf(c), ...ctx };
      bag.c = bag;
      c.status(status);
      return c.html(templates.render(viewRef, bag));
    },

    form(c) {
      return c.req.parseBody();
    },

    session: sessionOf,
    prefs: prefsOf,

    setPrefs(c, patch) {
      setPrefs(c, { ...prefsOf(c), ...patch });
    },

    timers,

    noContent(c) {
      c.status(204);
      return c.body(null);
    },

    // Cancels an `every Ns` / load-delay poll from the server side.
    stopPolling(c) {
      c.status(286);
      return c.body(null);
    },

    // Full reload — the theme-change escape hatch (body attrs don't swap under boost).
    refresh(c) {
      c.header('HX-Refresh', 'true');
      return c.body(null);
    },

    // Client-side navigation without a full reload (use instead of 3xx —
    // redirects swallow HX-* response headers).
    location(c, url) {
      c.header('HX-Location', url);
      return c.body(null);
    },
  };
}
