// server.js — node entry point for the ejected appbox-designer artifact.
//
//   npm start           # → http://0.0.0.0:4399 (PORT/HOST env to change)
//   npm run typecheck   # tsc --checkJs (Phase 4)
//
// One-way eject: this tree is yours. appbox will never re-import it.
import { serve } from '@hono/node-server';
import { serveStatic } from '@hono/node-server/serve-static';
import { createArtifactApp } from './runtime/router.js';

const artifactDir = process.cwd();
const port = Number(process.env.PORT ?? 4399);
const hostname = process.env.HOST || '0.0.0.0';

const app = await createArtifactApp(artifactDir, {
  staticSetup(app) {
    app.use('/assets/vendor/*', serveStatic({
      root: './runtime/vendor',
      rewriteRequestPath: (requestPath) => requestPath.replace(/^\/assets\/vendor/, ''),
    }));
    app.use('/assets/*', serveStatic({ root: '.' }));
  },
});

serve({ fetch: app.fetch, port, hostname }, (info) => {
  const display = hostname === '0.0.0.0' || hostname === '::' ? 'localhost' : hostname;
  console.log(`→ http://${display}:${info.port}/`);
});
