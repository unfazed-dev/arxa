import { Hono } from 'hono';
import { serveStatic } from '@hono/node-server/serve-static';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { sessionMiddleware } from './state.mjs';
import { createHelpers } from './helpers.mjs';

const runtimeDir = path.dirname(path.dirname(fileURLToPath(import.meta.url)));

export async function createArtifactApp(artifactDir) {
  const app = new Hono();
  const helpers = createHelpers(artifactDir);

  app.use('*', sessionMiddleware);
  app.use('*', async (c, next) => {
    await next();
    c.header('Vary', 'HX-Request', { append: true });
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
    app.on(method, routePath, (c) => handler(c, helpers));
  }

  app.notFound((c) => c.text(`404 — no route for ${c.req.method} ${c.req.path}`, 404));
  app.onError((err, c) => {
    console.error(err);
    return c.text(`500 — ${err.message}`, 500);
  });

  return app;
}
