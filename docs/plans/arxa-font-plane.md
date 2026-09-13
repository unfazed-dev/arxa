# Arxa Font Plane — live typography, the palette plane's twin

Grilled and confirmed 2026-09-13. Seven decisions locked; the plane mirrors
design_palettes.dart's publication/transport law (its Q1–Q14) one seat over.

## Locked decisions

1. **Theme shape — INDEPENDENT PER-ROLE DROPDOWNS.** Not atomic pairing
   cards: each role (display, body, …) is its own dropdown that publishes
   alone. The axes cell is an OBJECT role → choice-id; a role flip never
   blanks the other roles (the merge law, enforced route-side and in the
   publish_font RPC).
2. **The seeded five per role (arxa-site, "curated contrast set").**
   Display: Fraunces (base), Instrument Serif, Playfair Display, DM Serif
   Display, Space Grotesk. Body: Inter (base), Archivo, Source Sans 3,
   DM Sans, Instrument Sans. Catalog picks append beyond them, the palette
   law. Energize/suczka seed from their own corpora when they adopt.
3. **Catalog source — SERVER-FETCHED + TRIMMED.** Google's
   fonts.google.com/metadata/fonts feed (1,946 families) is same-site-only
   (cross-origin-resource-policy, no ACAO — measured): the browser CANNOT
   fetch it. design_fonts.dart fetches server-side, trims to
   {family, category, weights, variableWght, italic, popularity} for
   latin-capable non-Noto families, caches at ~/.arxa/font-catalog.json
   (7-day staleness), and the dial searches via GET /__dial/font-catalog.
4. **Preview — LIVE css2 SPECIMEN.** css2 is CORS-open
   (access-control-allow-origin: *) and browsers fetch only faces they
   render, so the island batches preview families (≤8/link) into css2
   links and renders specimen text in the REAL font — the same CDN-by-name
   law the sites already load by. No binaries are ever vendored (the
   designer's no-redistribution law, type.css).
5. **Publish rights — AUTHOR + GUESTS, palette parity.** The share link is
   the authorization; publish_font (security definer) checks the author
   token hash OR a live guest link in SQL, exactly publish_palette's law.
6. **Legacy roles — PER-ARTIFACT ROLE MAP.** fonts.json declares the
   artifact's roles (arxa-site: display+body; suczka: display+body+
   editorial for its Fraunces/Archivo/Instrument Serif split; the starter:
   one body role on the system stack — css2 null = CDN-free at birth).
   Each role owns its token (--font-display, --font-body, --f-* aliases)
   and up to five seeded choices.
7. **Session scope — ENGINE + ARXA-SITE LOCAL ONLY.** No Workers deploy
   this session; the deployed half (worker template + island static
   branches + eject bake) is written and unit-verified, ships next.

## Architecture

- **fonts.json** (artifact root) — the declaration: {default: {role:
  choice}, roles: [{id, name, token, choices: [{id, family, category,
  css2, stack, seeded, sheet}]}]}. The DEFAULT choice per role is the base
  corpus (no sheet); every other choice ships a generated token-override
  sheet under assets/styles/fonts/font-<role>-<id>.css gating
  [data-font-<role>="<id>"] { <token>: <stack> }.
- **html[data-font-<role>]** — the apply seam, one attribute per role,
  stamped serve-time (?font= receipt > stored cell > default; unknown ids
  fall through silently) and baked worker-side at eject.
- **assets/app/font.js** — the artifact-owned applier (palette.js's
  shape): owns the attributes, the ONE css2 <link> (href rebuilt from the
  active choices' segments + display=swap), localStorage memory,
  receipts, the arxa:font broadcast, and the static-mode remote settle.
  The public font ear PIGGYBACKS palette.js's ONE Realtime channel via
  the arxa:axes-row DOM event (LEAST-CHANNEL law: no second connection
  per tab; palette.js dispatches the whole row it already receives).
- **lib/design_fonts.dart** — manifest loader/validator, serve seam
  (applyFontToServedHtml), ingestion (catalog entry → css2 segment +
  category-derived stack + sheet + manifest append, dedupe by family),
  delete (seeded/default refuse), and the FontCatalog fetch/trim/cache.
- **The axes cell** — arxa_dial_axes.font jsonb (migration
  20260913_arxa_dial_font.sql: object-typed column + publish_font RPC,
  author-token/service-role/guest-link auth, per-role MERGE over the
  stored cell). The local design server writes it with the service role;
  the deployed static dial calls the RPC.
- **The dial** — a Fonts slide, SECOND after Theme (tray: Theme, Fonts,
  Access-author-local; guests + static get Theme, Fonts when declared).
  Per role: choice cards with live specimens + the searchable catalog
  dropdown (author, design-time; guests pick declared choices only).
  Publish rides POST /__dial/axes {font: {role: id}} → one thin axes
  SSE frame; ingestion broadcasts a fonts frame.
- **The eject** — bakes ARXA_FONTS (the manifest) + the published font
  cell into ARXA_DIAL_STATIC; the worker template gained applyFontPlane
  (/fonts.json, per-role stamps, sheet wiring, __ARXA_FONT__ remote
  channel) chained after applyPalettePlane.
- **The F-gate** (gate_design_fonts.dart, wired into design lint): F1
  manifest valid, F2 font.js ships, F3 sheets on disk + role tokens are
  real corpus vocabulary. The starter (hello-hda) ships the plane at
  birth — one body role, system default, four GF alternates.

## Verification (2026-09-13, local)

- Suite 2041/2041 green (incl. 6 new design_fonts tests: manifest law,
  css2 segments, stacks, serve seam receipts + stale-stamp strip,
  ingest/dedupe/delete, catalog roundtrip). arxa_dial_serve_test updated:
  the starter now declares palette + font planes at birth (the old
  "only the palette plane" premise is stale by this plane's universality).
- Migration applied to the operator Supabase (font column + RPC); the
  publish round-trip proven live: POST {font:{display:playfair-display}}
  → row {palette:"marine", font:{display:...}} (merge law held), fresh
  pages stamp it, ?font= receipts beat published, and the row was reset
  to {} after (palette untouched — the custody law).
- Runtime proof under the lens: __arxaFont.set("display",
  "dm-serif-display") flipped the attribute, REBUILT the css2 link href
  (…family=DM+Serif+Display:ital@0;1&family=Inter:…&display=swap), the
  h1's computed font-family became "DM Serif Display", Georgia, serif,
  and the arxa:font event fired. lens check clean (zero console/page
  errors). arxa design lint: F1–F3 clean ("font plane: 2 role(s), 10
  choices").
- The catalog: first call fetched + trimmed the feed (1.4s), second call
  served from cache (0.13s); searches rank by popularity (q=lobster →
  Lobster, Lobster Two).

## Deploy residue (next session)

The Workers deploy chain (eject → diff → backup → rsync → wrangler) ships
ARXA_FONTS + font.js + sheets + the island to prod; then the palette-ear
probe pattern extends to fonts (public tab hears a font publish live over
the piggybacked channel). energize + suzska adopt the plane by authoring
their fonts.json against their corpora (energize: Fraunces + Source Sans
3 base; suzska: the three-family role map) — each needs its own seeded
sets + a deploy.
