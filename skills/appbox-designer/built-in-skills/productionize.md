---
name: "productionize"
description: "Eject an artifact into a self-contained, production-grade Hono app"
---

Transform an artifact (which runs on the skill's shared Runtime) into a standalone product: own `package.json`, Runtime inlined, MVVM structure preserved, baseline tests, deploy notes. The design prototype becomes the production front-end with zero rewrites — that was the point of the architecture.

## Run it

```sh
appbox design eject <artifact-dir> <out-dir>
cd <out-dir> && npm install && npm test && npm start   # http://localhost:4319 (PORT env to change)
```

## What you get

```
<out-dir>/
├── runtime/          # the vendored Runtime (serve.mjs, lib/, vendor/)
├── test/smoke.test.mjs
├── package.json      # start / test / lint scripts, pinned deps
├── README.md
└── …the artifact's own tree (app.routes.js, models/, services/, ui/, assets/)
```

## Hardening checklist (do these *in* the ejected app, in order)

1. **Config** — move env-sensitive values to environment variables (`PORT` is already supported; add others as they appear).
2. **Data layer** — swap fixture Repositories for real ones, one at a time, behind the existing Facade contracts. This is the seam the MVVM structure was built for: ViewModels touch only Facades, so no template or route changes.
3. **Session store** — the in-memory store is single-process; for multi-instance deploys swap `runtime/lib/state.mjs`'s Map for a shared store (cookie-signed or Redis) behind the same `sessionOf/prefsOf/setPrefs` helpers.
4. **Tests** — extend `test/smoke.test.mjs`: one request-level test per route (Hono's `app.request()` needs no listening server), plus the Playwright paths that matter.
5. **Security** — keep `appbox design lint` green in CI (the zero-custom-JS contract); add standard headers (Hono `secureHeaders` middleware); review cookies (`httpOnly` is already set on the session cookie).
6. **Deploy** — any Node ≥20 host. Minimal Dockerfile: `FROM node:22-slim`, copy, `npm ci --omit=dev`, `CMD ["npm","start"]`.

## Not included (by design — ADR-0008)

Auth, database provisioning/migrations, CI pipelines. Those are product decisions; the ejected app documents where each one lands.

## Verify

`npm test` passes, `npm run lint` clean, `appbox lens check http://localhost:4319/` clean after `npm start`, and a final Playwright screenshot review of the key surfaces.
