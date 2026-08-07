// @ts-check
import { render as renderTsx } from './render.js';
import { raw } from 'hono/utils/html';
import { sessionOf, prefsOf, setPrefs } from './state.js';
import { localeOf } from './l10n.js';
import { timers } from './timers.js';
import { publishPatch, publishEvent } from './realtime.js';

// The `h` object every viewmodel handler receives: `handler(c, h) => Response`.
/**
 * @param {string} artifactDir
 * @param {import('./types').L10n} l10n
 * @returns {import('./types').Helpers}
 */
export function createHelpers(artifactDir, l10n) {
  return {
    // Renders a page or a `#fragment`; merges cookie prefs and the request
    // locale into the context. TSX components see the context bag as props.
    // `t` is wrapped in raw() so hono/jsx renders pre-escaped catalog text
    // without double-escaping (the interpolate() inside t() already escapes).
    /**
     * @param {import('./types').Context} c
     * @param {string} viewRef
     * @param {Record<string, unknown>} [ctx]
     * @param {number} [status]
     */
    render(c, viewRef, ctx = {}, status = 200) {
      const tFn = l10n
        ? l10n.createT({ locale: localeOf(c), level: prefsOf(c).jargon })
        : (/** @type {string} */ s) => s;
      const t = (/** @type {string} */ key, /** @type {Record<string, unknown> | undefined} */ vars) =>
        raw(String(tFn(key, vars)));
      // If ctx.partial is a string viewRef (e.g. 'ui/project/home.html'),
      // pre-render it through the TSX registry so the component receives
      // ready-made content instead of a raw path string — replaces the nunjucks
      // dynamic-include pattern (parity with the design-time shim).
      if (typeof ctx.partial === 'string' && ctx.partial) {
        const partialBag = { prefs: prefsOf(c), locale: localeOf(c), locales: l10n?.locales ?? [], t, ...ctx };
        // @ts-ignore — circular self-reference (viewmodels expect props.c)
        partialBag.c = partialBag;
        try {
          ctx = { ...ctx, partial: raw(String(renderTsx(ctx.partial, partialBag))) };
        } catch { /* not in registry or render error — generic placeholder fallback */ }
      }
      const bag = { prefs: prefsOf(c), locale: localeOf(c), locales: l10n?.locales ?? [], t, ...ctx };
      // @ts-ignore — circular self-reference (kept for parity; macro-free in TSX)
      bag.c = bag;
      c.status(/** @type {any} */ (status));
      // JSXNode → string via toString(), wrapped in raw() to prevent hono from
      // re-escaping the already-escaped HTML output.
      return /** @type {Response} */ (c.html(raw(String(renderTsx(viewRef, bag)))));
    },

    /** @param {import('./types').Context} c */
    form(c) {
      return c.req.parseBody();
    },

    session: sessionOf,
    prefs: prefsOf,

    // Request locale (resolved by the router middleware) and a translator
    // bound to it — viewmodels use h.t(c) for strings the context carries
    // (nav labels, facade-level text). Returns raw() so hono/jsx renders the
    // pre-escaped catalog text without double-escaping.
    locale: localeOf,
    /**
     * @param {import('./types').Context} c
     */
    t(c) {
      const fn = l10n
        ? l10n.createT({ locale: localeOf(c), level: prefsOf(c).jargon })
        : (/** @type {string} */ s) => s;
      return (/** @type {string} */ key, /** @type {Record<string, unknown> | undefined} */ vars) =>
        raw(String(fn(key, vars)));
    },

    /**
     * @param {import('./types').Context} c
     * @param {Partial<import('./types').Prefs>} patch
     */
    setPrefs(c, patch) {
      setPrefs(c, { ...prefsOf(c), ...patch });
    },

    timers,

    // Server-push: publish onto the SSE bus (GET /__events?channel=<name>).
    sse: { publishPatch, publishEvent },

    /** @param {import('./types').Context} c */
    noContent(c) {
      c.status(204);
      return c.body(null);
    },

    // Cancels an `every Ns` / load-delay poll from the server side.
    /** @param {import('./types').Context} c */
    stopPolling(c) {
      c.status(/** @type {any} */ (286));
      return c.body(null);
    },

    // Full reload — the theme-change escape hatch (body attrs don't swap under boost).
    /** @param {import('./types').Context} c */
    refresh(c) {
      c.header('HX-Refresh', 'true');
      return c.body(null);
    },

    // Client-side navigation without a full reload (use instead of 3xx —
    // redirects swallow HX-* response headers).
    /**
     * @param {import('./types').Context} c
     * @param {string} url
     */
    location(c, url) {
      c.header('HX-Location', url);
      return c.body(null);
    },
  };
}
