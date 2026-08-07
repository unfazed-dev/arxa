import { Hono } from 'hono';
import { serveStatic } from '@hono/node-server/serve-static';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { sessionMiddleware } from './state.mjs';
import { createHelpers } from './helpers.mjs';
import { createL10n, resolveLocale } from './l10n.mjs';
import { runForSession } from './timers.mjs';

const runtimeDir = path.dirname(path.dirname(fileURLToPath(import.meta.url)));

export async function createArtifactApp(artifactDir) {
  const app = new Hono();
  const l10n = createL10n(artifactDir);
  const helpers = createHelpers(artifactDir, l10n);

  app.use('*', sessionMiddleware);
  app.use('*', async (c, next) => {
    // Locale resolution (?lang= → prefs cookie → Accept-Language → 'en');
    // helpers.render merges it into every render context.
    c.set('locale', resolveLocale(c, l10n));
    await next();
    c.header('Vary', 'HX-Request', { append: true });
    if ((c.res.headers.get('content-type') ?? '').includes('text/html')) {
      c.header('Vary', 'Accept-Language', { append: true });
    }
  });

  // Language switching, built-in (ADR-0004 prefs recipe): every artifact gets
  // it — locale is runtime state, not surface content. htmx-boosted →
  // HX-Refresh (chrome strings are everywhere; no fragment can repaint them
  // all); plain navigation → 302 back to the Referer.
  app.on(['GET', 'POST'], '/prefs/lang', async (c) => {
    const lang =
      c.req.method === 'POST' ? String((await helpers.form(c)).lang ?? '') : c.req.query('lang');
    if (l10n.locales.includes(lang)) helpers.setPrefs(c, { lang });
    if (c.req.header('HX-Request')) return helpers.refresh(c);
    let back = '/';
    try {
      const ref = c.req.header('Referer');
      if (ref) {
        const u = new URL(ref);
        back = u.pathname + u.search;
      }
    } catch {
      // unparseable Referer — fall back to '/'
    }
    return c.redirect(back, 302);
  });

  // Allowlisted client libraries, vendored in the runtime (ADR-0002).
  app.use(
    '/assets/vendor/*',
    serveStatic({
      root: path.join(runtimeDir, 'vendor'),
      rewriteRequestPath: (p) => p.replace(/^\/assets\/vendor/, ''),
    }),
  );
  app.use('/assets/*', serveStatic({ root: artifactDir }));
  // Consumed design-system copies (agents/import-design-system.mjs writes <artifact>/_ds/).
  app.use('/_ds/*', serveStatic({ root: artifactDir }));

  const { default: routes } = await import(
    pathToFileURL(path.join(artifactDir, 'app.routes.js'))
  );
  for (const [method, routePath, handler] of routes) {
    app.on(method, routePath, (c) =>
      runForSession(c.get('kdh_session')?.id, () => handler(c, helpers)),
    );
  }

  app.notFound((c) => c.text(`404 — no route for ${c.req.method} ${c.req.path}`, 404));
  app.onError((err, c) => {
    console.error(err);
    return c.text(`500 — handler threw: ${err?.message ?? err}`, 500);
  });

  return app;
}
