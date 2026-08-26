---
name: "productionize"
description: "Eject an artifact into a self-contained, production-grade Hono app"
---

Transform an artifact (which runs on the skill's shared Runtime) into a standalone product: self-contained tree, own `package.json` with the Runtime inlined, vendored client libs, MVVM structure preserved, per-target deploy entry points. The design prototype becomes the production front-end with zero rewrites — that was the point of the architecture (ADR-0008; CONTEXT.md "Productionize").

## Run it

```sh
arxa design eject <artifact-dir> <out-dir> [--target=node|cloudflare|vercel] [--kits=a,b]
cd <out-dir>
npx wrangler dev      # target=cloudflare (or: node → node server.mjs · vercel → vercel dev)
```

Three targets, three entry points (all in `runtime/eject/`):

- **node** — own `package.json`, inlined Hono/Node runtime, server entry on port 4399 (env-overridable), preload stub for templates/l10n/fixtures.
- **cloudflare** (Workers) — `worker.js` fetch entry + `wrangler.toml` with the `[assets]` binding (directory root `./assets`, the fetch export strips the `/assets` prefix); templates/l10n/fixtures pre-bundled into `runtime/preload.js` (Workers have no filesystem); vendored libs mirrored into the assets tree. `npx wrangler dev` locally, `npx wrangler deploy` to ship.
- **vercel** — fetch-handler entry + `public/` static root for assets/vendor.

The Dart design server (`arxa design serve . --no-watch`) can still serve the ejected tree — useful for quick local checks — but production runs the ejected Node/Hono app, not Dart.

## kind "site" — the artifact IS the product

For a `kind: site` project there is no Flutter downstream: the artifact's eject is the build stage, and the ejected tree is what ships. That changes two things:

- **Structure is the deliverable.** The MVVM tree, the widget library, the styles law — they exist for maintainability of a living site, not as scaffolder input.
- **The dual-tree law.** The design tree (`<app-dir>/design/…`) stays the SOURCE OF TRUTH; the build tree (`<app-dir>/build/…`) is the deployed eject. Any change to an app module, widget, or style is made IDENTICALLY IN BOTH TREES; build-only extras (the compiled `runtime/render.js` — patch it in lockstep with the tsx it was built from; the `assets/styles/` mirror of `ui/styles/`) live only in the build tree. A re-eject does not carry local build-tree patches forward: re-apply them after any re-eject, or keep them as scripts. "One-way eject" means arxa never re-imports the tree — it does NOT mean the build tree is untouchable; it means YOU maintain both.

## Hardening checklist (do these *in* the ejected app, in order)

1. **Config** — move env-sensitive values to environment variables (port is already env-supported; add others as they appear).
2. **Data layer** — swap fixture Repositories for real ones, one at a time, behind the existing Facade contracts. This is the seam the MVVM structure was built for: ViewModels touch only Facades, so no template or route changes.
3. **Session store** — the dev server's in-memory store is single-process; for multi-instance deploys swap it for a shared store (cookie-signed or Redis) behind the same `sessionOf/prefsOf/setPrefs` helpers.
4. **Tests** — `arxa design selftest .` (structural contract) plus `arxa lens check http://localhost:<port>/…` on the paths that matter.
5. **Security** — keep `arxa design lint` green in CI (the ADR-0009 client-JS law: vendored libraries, first-party islands, artifact app modules — no inline handlers, no orphan scripts); add standard headers; review cookies.
6. **Deploy** — per target: `npx wrangler deploy` (cloudflare; needs `CLOUDFLARE_API_TOKEN`/`CLOUDFLARE_ACCOUNT_ID`), `vercel deploy --prod` (vercel), or any Node host (node). Localize the entry point per `runtime/eject/`.
7. **Verify the LIVE URL** — post-deploy live verification (curl a shipped asset hash + one lens probe against the deployment URL) before the deploy ledger closes — see `arxa-deployer` SKILL "Post-deploy live verification". Verification that stops at localhost stops before the user does.

## Locales — two legal patterns

The runtime's built-in switcher (`/prefs/lang` → prefs cookie → `Accept-Language`, ADR-0004) suits apps and internal tools. For marketing sites where each locale must be its own crawlable URL, use **locale-in-path routes** instead: one route table entry per locale (`/`, `/fr`, `/mfe` …) in `app.routes.js`, per-locale render contexts, and language links as plain anchors between the routes — the pattern the energize engagement shipped. Choose at design time; retrofitting routing after a cookie-switcher build is a rewrite of every link.

## Not included (by design — ADR-0008)

Auth, database provisioning/migrations, CI pipelines. Those are product decisions; the ejected app documents where each one lands.

## Verify

`arxa design lint .` clean, `arxa lens check http://localhost:<port>/` clean on the served eject, a final arxa-lens screenshot review of the key surfaces — and, after deploying, the live-URL verification above.
