// @ts-check
// runtime/router.js — creates the Hono app for an appbox-designer artifact.
//
// Target-agnostic: session/locale middleware, /prefs/lang, route dispatch, and
// error handling live here. Static-file serving is injected by the entry point
// (server.js for node, worker.js for Cloudflare) via `staticSetup`, because
// the mechanism differs per platform (serveStatic on node, [assets] binding on
// Workers). fixture_reader.js works unchanged on node (native node:fs); on
// Workers a generated runtime/fixtures.js replaces it.

/**
 * @typedef {{ locale: string, kdh_session: { id: string, data: Record<string, unknown> } | null }} AppVars
 * @typedef {(app: import('hono').Hono) => void} StaticSetup
 * @typedef {{ staticSetup?: StaticSetup | null, preload?: Record<string, unknown> | null, routes?: unknown[] | null }} AppOptions
 */

import { Hono } from 'hono';
import { pathToFileURL } from 'node:url';
import path from 'node:path';
import { sessionMiddleware } from './state.js';
import { createHelpers } from './helpers.js';
import { attachSse } from './realtime.js';
import { createL10n, resolveLocale } from './l10n.js';
import { runForSession } from './timers.js';

/**
 * @param {string} artifactDir
 * @param {AppOptions} [opts]
 * @returns {Promise<import('hono').Hono>}
 */
export async function createArtifactApp(artifactDir, { staticSetup = null, preload = null, routes: preloadedRoutes = null } = {}) {
  /** @type {import('hono').Hono<{ Variables: AppVars }>} */
  const app = new Hono();
  const source = preload ?? artifactDir;
  const l10n = createL10n(/** @type {any} */ (source));
  const helpers = createHelpers(/** @type {string} */ (source), l10n);

  app.use('*', sessionMiddleware);
  app.use('*', async (context, next) => {
    context.set('locale', resolveLocale(context, l10n));
    await next();
    context.header('Vary', 'HX-Request', { append: true });
    if ((context.res.headers.get('content-type') ?? '').includes('text/html')) {
      context.header('Vary', 'Accept-Language', { append: true });
    }
  });

  // Built-in locale switch (ADR-0004 prefs recipe).
  app.on(['GET', 'POST'], '/prefs/lang', async (context) => {
    const lang =
      context.req.method === 'POST' ? String((await helpers.form(context)).lang ?? '') : context.req.query('lang');
    if (l10n.locales.includes(lang ?? '')) helpers.setPrefs(context, { lang });
    if (context.req.header('HX-Request')) return helpers.refresh(context);
    let back = '/';
    try {
      const ref = context.req.header('Referer');
      if (ref) { const refUrl = new URL(ref); back = refUrl.pathname + refUrl.search; }
    } catch { /* unparseable Referer */ }
    return context.redirect(back, 302);
  });

  // Target-specific static serving (vendor + assets). null on Workers where
  // the [assets] binding handles it before the Worker runs.
  if (staticSetup) staticSetup(app);

  // SSE bus: GET /__events?channel=<name> (replay buffer + Last-Event-ID).
  attachSse(app);

  const routes = preloadedRoutes
    ?? (await import(/** @type {string} */ (pathToFileURL(path.join(artifactDir, 'app.routes.js')).href))).default;
  for (const [method, routePath, handler] of routes) {
    app.on(method, routePath, /** @param {import('./types').Context} context */ (context) =>
      /** @type {Response} */ (runForSession(context.get('kdh_session')?.id, () => handler(context, helpers))),
    );
  }

  app.notFound(/** @param {import('./types').Context} context */ (context) => context.text(`404 — no route for ${context.req.method} ${context.req.path}`, 404));
  app.onError((err, context) => {
    console.error(err);
    return context.text(`500 — handler threw: ${err?.message ?? err}`, 500);
  });

  return app;
}
