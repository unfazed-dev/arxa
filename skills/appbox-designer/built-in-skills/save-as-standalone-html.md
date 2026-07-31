---
name: "save-as-standalone-html"
description: "Eject / share an artifact\nSelf-contained Hono app via the Productionize eject"
---
"Standalone HTML" predates the server-first stack. Under HDA an artifact cannot collapse into a single HTML file — htmx needs its server for Named Fragment swaps, POSTs, sessions, and boosted navigation. The honest standalone deliverable is an **eject**: a self-contained Hono app.

## Eject

```sh
appbox design eject <artifact-dir> <out-dir>
```

This writes a self-contained Hono app to `<out-dir>`: its own package.json, the Runtime inlined, the artifact's MVVM structure preserved, and a baseline test. For the full hardening story — env-based config, deploy notes, the Repository DB-swap seam — see [`productionize.md`](productionize.md).

Only the vendored libraries the artifact's markup actually loads are copied. `vendor/` is the **allowlist** — the menu an artifact may enable — not the shipping manifest, and an ejected app has no business carrying a client-side template engine it never turned on. `vendor/manifest.json` travels with the copy, narrowed to what shipped, so provenance stays auditable; `SRI.md` and `fetch.mjs` do not, because the ejected app cannot re-vendor.

The eject **fails** rather than shipping if the markup names a library that is not vendored, or if no HTML loads htmx at all. An app with an empty `vendor/` boots clean, logs nothing, and is silently inert — the one failure mode this stack is worst at surfacing.

Verify before delivering: boot the ejected app, hit its routes, and keep `appbox design lint <out-dir>` clean. Then deliver the `<out-dir>` path to the user — don't ask whether they want it, just give it.

## If the user truly needs one offline file

A genuinely single-file, double-clickable, offline deliverable is the wrong fit for this stack — say so plainly, and point the user at the sibling `appbox-designer` skill, which produces exactly that.
