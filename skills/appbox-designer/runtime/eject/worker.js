// worker.js — Cloudflare Workers entry point for the ejected appbox-designer
// artifact.
//
//   npx wrangler dev     # local dev (http://localhost:8787)
//   npx wrangler deploy  # production
//
// Static assets (/assets/*, /assets/vendor/*) are served by the [assets]
// binding in wrangler.toml — they never enter the Worker. Templates, l10n
// catalogs, and fixtures are pre-bundled into runtime/preload.js at eject
// time (Workers have no filesystem).
//
// One-way eject: this tree is yours. appbox will never re-import it.
import { createArtifactApp } from './runtime/router.js';
import { preload } from './runtime/preload.js';
import routes from './app.routes.js';

const app = await createArtifactApp('.', {
  staticSetup: null, // [assets] binding handles static on Workers
  preload,
  routes,
});

export default app;
