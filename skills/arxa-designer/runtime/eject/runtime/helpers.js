// @ts-check
import { render as renderTsx } from './render.js';
import { raw } from 'hono/utils/html';
import { sessionOf, prefsOf, setPrefs } from './state.js';
import { localeOf } from './l10n.js';
import { timers } from './timers.js';
import { publishPatch, publishEvent } from './realtime.js';

// The `helpers` object every viewmodel handler receives: `handler(context, helpers) => Response`.
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
     * @param {import('./types').Context} context
     * @param {string} viewRef
     * @param {Record<string, unknown>} [ctx]
     * @param {number} [status]
     */
    render(context, viewRef, ctx = {}, status = 200) {
      const translateFn = l10n
        ? l10n.createTranslator({ locale: localeOf(context), level: prefsOf(context).jargon })
        : (/** @type {string} */ text) => text;
      const translate = (/** @type {string} */ key, /** @type {Record<string, unknown> | undefined} */ vars) =>
        raw(String(translateFn(key, vars)));
      // If ctx.partial is a string viewRef (e.g. 'ui/project/home.html'),
      // pre-render it through the TSX registry so the component receives
      // ready-made content instead of a raw path string — replaces the nunjucks
      // dynamic-include pattern (parity with the design-time shim).
      if (typeof ctx.partial === 'string' && ctx.partial) {
        const partialBag = { prefs: prefsOf(context), locale: localeOf(context), locales: l10n?.locales ?? [], translate, ...ctx };
        // @ts-ignore — circular self-reference (viewmodels expect props.context)
        partialBag.context = partialBag;
        try {
          ctx = { ...ctx, partial: raw(String(renderTsx(ctx.partial, partialBag))) };
        } catch { /* not in registry or render error — generic placeholder fallback */ }
      }
      const bag = { prefs: prefsOf(context), locale: localeOf(context), locales: l10n?.locales ?? [], translate, ...ctx };
      // @ts-ignore — circular self-reference (kept for parity; macro-free in TSX)
      bag.context = bag;
      context.status(/** @type {any} */ (status));
      // JSXNode → string via toString(), wrapped in raw() to prevent hono from
      // re-escaping the already-escaped HTML output.
      return /** @type {Response} */ (context.html(raw(String(renderTsx(viewRef, bag)))));
    },

    /** @param {import('./types').Context} context */
    form(context) {
      return context.req.parseBody();
    },

    session: sessionOf,
    prefs: prefsOf,

    // Request locale (resolved by the router middleware) and a translator
    // bound to it — viewmodels use helpers.translate(context) for strings the context carries
    // (nav labels, facade-level text). Returns raw() so hono/jsx renders the
    // pre-escaped catalog text without double-escaping.
    locale: localeOf,
    /**
     * @param {import('./types').Context} context
     */
    translate(context) {
      const fn = l10n
        ? l10n.createTranslator({ locale: localeOf(context), level: prefsOf(context).jargon })
        : (/** @type {string} */ text) => text;
      return (/** @type {string} */ key, /** @type {Record<string, unknown> | undefined} */ vars) =>
        raw(String(fn(key, vars)));
    },

    /**
     * @param {import('./types').Context} context
     * @param {Partial<import('./types').Prefs>} patch
     */
    setPrefs(context, patch) {
      setPrefs(context, { ...prefsOf(context), ...patch });
    },

    timers,

    // Server-push: publish onto the SSE bus (GET /__events?channel=<name>).
    sse: { publishPatch, publishEvent },

    /** @param {import('./types').Context} context */
    noContent(context) {
      context.status(204);
      return context.body(null);
    },

    // Cancels an `every Ns` / load-delay poll from the server side.
    /** @param {import('./types').Context} context */
    stopPolling(context) {
      context.status(/** @type {any} */ (286));
      return context.body(null);
    },

    // Full reload — the theme-change escape hatch (body attrs don't swap under boost).
    /** @param {import('./types').Context} context */
    refresh(context) {
      context.header('HX-Refresh', 'true');
      return context.body(null);
    },

    // Client-side navigation without a full reload (use instead of 3xx —
    // redirects swallow HX-* response headers).
    /**
     * @param {import('./types').Context} context
     * @param {string} url
     */
    location(context, url) {
      context.header('HX-Location', url);
      return context.body(null);
    },
  };
}
