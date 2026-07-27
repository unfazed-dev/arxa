---
name: "save-as-standalone-html"
description: "Eject / share an artifact\nSelf-contained Hono app via the Productionize eject"
---
"Standalone HTML" predates the server-first stack. Under HDA an artifact cannot collapse into a single HTML file — htmx needs its server for Named Fragment swaps, POSTs, sessions, and boosted navigation. The honest standalone deliverable is an **eject**: a self-contained Hono app.

## Eject

```sh
node <skill>/runtime/eject.mjs <artifact-dir> <out-dir>
```

This writes a self-contained Hono app to `<out-dir>`: its own package.json, the Runtime inlined, the artifact's MVVM structure preserved, and a baseline test. For the full hardening story — env-based config, deploy notes, the Repository DB-swap seam — see [`productionize.md`](productionize.md).

Verify before delivering: boot the ejected app, hit its routes, and keep `node <skill>/runtime/lint.mjs <out-dir>` clean. Then deliver the `<out-dir>` path to the user — don't ask whether they want it, just give it.

## If the user truly needs one offline file

A genuinely single-file, double-clickable, offline deliverable is the wrong fit for this stack — say so plainly, and point the user at the sibling `app-box-designer` skill, which produces exactly that.
