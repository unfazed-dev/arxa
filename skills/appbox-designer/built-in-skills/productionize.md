---
name: "productionize"
description: "Eject an artifact into a self-contained, production-grade Hono app"
---

Transform an artifact (which runs on the skill's shared Runtime) into a standalone product: self-contained tree, vendored client libs inlined, MVVM structure preserved, deploy notes. The design prototype becomes the production front-end with zero rewrites — that was the point of the architecture.

## Run it

```sh
appbox design eject <artifact-dir> <out-dir>
cd <out-dir> && appbox design serve . --no-watch   # http://localhost:4319 (PORT env to change)
```

## What you get

```
<out-dir>/
├── runtime/vendor/   # the vendored client libs, narrowed to what this
│                     # artifact's HTML actually loads (htmx required),
│                     # + the narrowed manifest.json
├── README.md         # run/lint lines (appbox design serve / lint)
└── …the artifact's own tree (app.routes.js, models/, services/, ui/, assets/)
```

No `package.json`, no `serve.mjs`, no node anywhere — the ejected app runs on
the same Dart design server (`appboxd/lib/design_server.dart`) that serves
designs in-tree.

## Hardening checklist (do these *in* the ejected app, in order)

1. **Config** — move env-sensitive values to environment variables (`PORT` is already supported; add others as they appear).
2. **Data layer** — swap fixture Repositories for real ones, one at a time, behind the existing Facade contracts. This is the seam the MVVM structure was built for: ViewModels touch only Facades, so no template or route changes.
3. **Session store** — the Dart design server's in-memory store is single-process; for multi-instance deploys swap it for a shared store (cookie-signed or Redis) behind the same `sessionOf/prefsOf/setPrefs` helpers.
4. **Tests** — the ejected app carries no node test runner; use `appbox design selftest .` (structural contract) plus `appbox lens check http://localhost:4319/…` on the paths that matter.
5. **Security** — keep `appbox design lint` green in CI (the zero-custom-JS contract); add standard headers; review cookies (`httpOnly` is already set on the session cookie).
6. **Deploy** — any host with the Dart SDK: copy the tree, run `appbox design serve . --no-watch`.

## Not included (by design — ADR-0008)

Auth, database provisioning/migrations, CI pipelines. Those are product decisions; the ejected app documents where each one lands.

## Verify

`appbox design lint .` clean, `appbox lens check http://localhost:4319/` clean after `appbox design serve . --no-watch`, and a final appbox-lens screenshot review of the key surfaces.
