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

## The palette plane + deployed dial (VERIFY ADDENDUM 17)

When the design declares `palettes.json`, a cloudflare eject also bakes the
palette plane and ships the Arxa Dial to the deployed worker:

- **Bake inputs (env at eject time):** `ARXA_SUPABASE_URL` +
  `ARXA_SUPABASE_SERVICE_KEY` (or the `~/.arxa/supabase` file) resolve the
  registered design id + published palette; `ARXA_SUPABASE_PUBLISHABLE_KEY`
  is the ONLY key that ships to browsers (RLS: read + insert-only);
  `ARXA_DIAL_AUTHOR_TOKEN` sets a stable author token — without it the
  first eject mints one and prints it ONCE (later ejects reuse the stored
  hash). The service key never ships.
- **What the worker does:** stamps `data-palette` (?palette= > baked
  published > manifest default), serves `/palettes.json`, injects
  palette.js's remote channel, and injects the dial ONLY when the URL
  carries `?dial=` (guest share link — the island validates it via the
  `resolve_guest_link` RPC) or `?dial-author=` (hash-verified in the
  worker). No credential = no dial on the public site.
- **What the static dial can do:** comments (pins/replies ride
  PostgREST; Realtime repaints open dials), the Theme slide (palette
  publishes go through the `publish_palette` RPC, which checks the
  share-link/author capability in SQL — a guest's pick publishes for
  everyone, the author can reset the default), and AUTHOR LIVE EDITING
  (2026-09-11 redesign): the author link arms the Edit verb — double-click
  text to type, click an image to swap (paste URL) — every debounced save
  rides the `save_overlay` RPC into the `arxa_dial_overlays` row and
  streams to every open client dial in real time (undo is session-local;
  Revert-to-published empties the row). Design-time surfaces
  (ship/media/roster) refuse cleanly — they need the local design server.
- **Handing the client the themes (the two links):** the author link
  (`https://<site>/?dial-author=<token>`) is the master key — minted once
  at the first credentialed eject, printed ONCE; rotate with
  `ARXA_DIAL_AUTHOR_TOKEN` + re-deploy. For clients prefer PERSONAL guest
  links, minted on the LOCAL design server's dial (tray trim v2, grilled
  2026-09-10): dial → Studio tray → **Access** slide → "Client access —
  personal links" → client email → "Mint personal link" → copy the
  `?dial=<token>` URL. Per-email attribution, revocable (comments
  survive). The minted link works on the DEPLOYED site (the worker's
  `resolve_guest_link` RPC validates it). Either way the client clicks a
  palette card in the Theme slide and it publishes LIVE for every visitor
  — the pick itself is the authorization. The Access slide is author- and
  local-only: guests and the deployed dial get a one-slide tray, and the
  static store refuses `/guests` outright.
- **Automint at eject (grilled 2026-09-10):** a per-design toggle in the
  arxa.json `dial` block — `"dial": {"automint": true, "clientEmail":
  "client@co.com", "days": 90}` — mints the client link automatically at
  every credentialed cloudflare eject (env overrides:
  `ARXA_DIAL_AUTOMINT` 1/0 forces on/off, `ARXA_DIAL_CLIENT_EMAIL`,
  `ARXA_DIAL_CLIENT_DAYS`). Idempotent per email: a live link means the
  eject skips and says so; a NEW link prints ONCE like the author token.
  Off by default — with the toggle off, minting happens on the dial.
- **Schema (one-time, applied by the operator):** `arxa_dial_axes.palette`
  column, `arxa_dial_designs.author_token_hash` column, the RPCs, the
  anon RLS policies, and `arxa_dial_axes` + `arxa_dial_overlays` in the
  supabase_realtime publication — all recorded in
  `docs/plans/arxa-dial-palettes.md` and VERIFY ADDENDUM 17 in the
  design's evidence ledger.
- **The eject bake (2026-09-11):** every credentialed eject fetches the
  design's live overlay row, applies each patch through the design-patch
  machinery into artifact SOURCE, and clears the row on full success —
  refused patches stay live in the overlay and retry at the next eject,
  loudly. No commit ceremony ever; deploy is the checkpoint.
- **The static dial refuses palette editing:** `POST
  /__dial/palettes/update` answers the same clean refusal as the other
  design-time surfaces — in-dial palette editing needs the local design
  server; the deployed dial only switches and publishes.
- **One custom slot:** the manifest carries the seeded five plus at most
  ONE custom palette — editing the default forks into that slot and
  replaces the previous custom; non-default palettes edit in place under
  their stable id.
- **3–7 declaration law:** every palette declares 3–7 source hexes mapped
  over the five fixed roles (dark / accent / field / beige / paper) —
  N=5 keeps the lightness-rank law byte-for-byte; fewer interpolate the
  missing mid-roles in HSL, more decimate by lightness.
