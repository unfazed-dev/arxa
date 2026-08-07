// server.js — Vercel entry point for the ejected appbox-designer artifact.
//
// Vercel's zero-config Hono convention (2026): a root server.js whose default
// export is the app becomes the Function (Fluid compute) — no listening
// server, no legacy builds/routes config. Static files come from public/
// (serveStatic is ignored by the platform, so staticSetup is null here).
//
//   npx vercel dev      # local dev
//   npx vercel deploy   # production
//
// One-way eject: this tree is yours. appbox will never re-import it.
import { createArtifactApp } from './runtime/router.js';

const app = await createArtifactApp(process.cwd(), {
  staticSetup: null, // public/ is the static root on Vercel
});

export default app;
