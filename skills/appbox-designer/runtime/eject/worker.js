// worker.js — Cloudflare Workers entry point for the ejected appbox-designer
// artifact.
//
//   npx wrangler dev     # local dev (http://localhost:8787)
//   npx wrangler deploy  # production
//
// Static assets (/assets/*, /assets/vendor/*) are served by the [assets]
// binding in wrangler.toml. The binding's directory root is ./assets, so the
// fetch export strips the /assets prefix before delegating to env.ASSETS.
// Templates, l10n catalogs, and fixtures are pre-bundled into
// runtime/preload.js at eject time (Workers have no filesystem).
//
// One-way eject: this tree is yours. appbox will never re-import it — but
// YOU maintain both trees: the design tree stays the source of truth, and
// every app/widget/style change is mirrored here identically (see the
// productionize doc's dual-tree law before editing).
import { createArtifactApp } from './runtime/router.js';
import { preload } from './runtime/preload.js';
import routes from './app.routes.js';

const app = await createArtifactApp('.', {
  staticSetup: null, // [assets] binding handles static on Workers
  preload,
  routes,
});

export default {
  fetch(request, env, ctx) {
    const url = new URL(request.url);

    // Locale routes are literal (/fr, /fr/about) — no trailing-slash twins
    // in the route table. 308 to the canonical slash-less form.
    if (url.pathname.length > 1 && url.pathname.endsWith('/')) {
      url.pathname = url.pathname.replace(/\/+$/, '');
      return Response.redirect(url.toString(), 308);
    }

    if (url.pathname.startsWith('/assets/')) {
      url.pathname = url.pathname.slice('/assets'.length);
      return env.ASSETS.fetch(new Request(url, request));
    }

    // Style barrels serve at /ui/styles/<owner>/ (the artifact styles law) —
    // mirrored into the [assets] root as assets/styles/ at eject time.
    if (url.pathname.startsWith('/ui/styles/')) {
      url.pathname = url.pathname.slice('/ui'.length);
      return env.ASSETS.fetch(new Request(url, request));
    }
    return app.fetch(request, env, ctx);
  },
};
