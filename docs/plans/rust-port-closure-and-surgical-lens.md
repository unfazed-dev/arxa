# Rust-port closure + surgical lens — grill decisions 2026-08-21

**Status:** decisions locked 2026-08-21 (grill session, all answers confirmed).
Evidence: three research reports (FRB Aug-2026 state, Rust codegen/CDP
practices, repo ground-truth) + two follow-ups (Rust app-framework traction,
multi-target scaffolder feasibility) + one (feedback widget / a11y toolbar /
Supabase patterns). Advisor consult skipped — no API key in env, recorded
per convention, proceeded on primary sources.

## A. The Rust question — CLOSED

1. **No Rust port of the tooling.** The 2026-07-31 verdict in
   [appbox-dart-only-tooling.md](appbox-dart-only-tooling.md) stands
   (addendum appended there). Every recorded pain from the energize /
   normal-is-boring runs is language-independent; emitter language is
   orthogonal to emission targets (OpenAPI Generator precedent: Java
   emitting 50+ languages); FRB is a Dart↔Rust runtime bridge inside
   Flutter apps — irrelevant to a build-time CLI and to pure-Rust targets.
   Rust UI is not client-ready (94.4% of Rust GUI libs not
   production-ready, 2025 survey; a11y gaps; no consumer mobile flagship).
   No revisit trigger recorded — Flutter covers the platform ground.
   FRB stays back-pocket for app-side hybrid cores only.

2. **The three recorded causes get fixed in Dart, now** (W1 below):
   fresh-Chrome-per-invocation, page-settle variance, gate coverage holes.

## B. Surgical lens + designer↔lens tandem

3. **One capture, drill-down compare, uniform across media.** Every
   capture produces an *evidence bundle*: pixels + region tree + geometry
   + motion frames, whatever the source (live site, design artifact,
   static image, video clip). Region tree from DOM `inspectAttrs` when a
   DOM exists; from the existing skeleton/OCR analyzers when it doesn't.
   Compare runs coarse-to-fine on the SAME capture — whole view first,
   then down the region tree by cropping — zero extra Chrome passes.
   Verdicts are structured: divergent node + geometry/computed-style
   delta, never just a pixel score.

4. **The capture manifest is the tandem contract.** Designer emits, per
   surface: states × viewports × regions, each state carrying the
   interaction script that reaches it (promotes the `lens_click_burst`
   pattern to data). One lens verb runs the whole manifest; verdicts are
   machine-readable for the designer's fix pass.

5. **Bounded auto-loop.** Verdict → designer fix → lens re-verify,
   up to 3 rounds per surface. Humans see survivors + the auto-fix trail.

## C. Codegen tie-ins

6. **Region identity in emitted code:** scaffolder stamps stable widget
   keys / Semantics mirroring the same vocabulary, so built Flutter apps
   expose the same region tree via the VM service and design-vs-built
   drill-down compares node-to-node.
7. **Golden snapshot corpus for emitters:** committed emitted-file
   snapshots per fixture registry; CI regenerates and fails on diff
   (locks the existing sorted-emit discipline into a gate).
8. **Lens evidence may feed generation:** measured geometry/spacing from
   the design artifact can inform emitted layout values.

## D. The abx- vocabulary

9. **One controlled vocabulary, three consumers.** A versioned
   `dictionary.json` in the designer runtime; every emitted class/id is
   `abx-*` and drawn from it. Capture-manifest region keys and scaffolder
   widget keys use the same terms — the "unified mapped context".
10. **Enforced as design-lint gates, not docs:** (a) every class/id is
    `abx-*` or on the vendored-library allowlist; (b) provenance scan —
    no class/id string appearing in the scanned reference corpus may
    appear in output (the normal-is-boring verbatim-copy incident).
11. **Trail-leaving growth:** the designer never invents a term silently;
    it proposes, the dictionary gains the term + one-line rationale, then
    the gate passes.

> **Amendment 2026-08-21 (same day, later session):** the semantic prefix
> is **`arxa-`**, not `abx-`, and the vocabulary is the **arxa
> dictionary** — superseded by the arxa rename in
> [arxa-harness-and-distribution.md](arxa-harness-and-distribution.md)
> (decision 11 there). Decisions 9–10 above read with `arxa-` wherever
> `abx-` appears. Changed before the dictionary or its gates were built
> (W4 pending), so no artifacts migrate.

## E. Tooling discipline

12. **Using-sessions never write into appbox.** Gate-enforced read-only
    `appboxd/` during client-project work (the `tool/tmp_*.dart` and
    `/tmp` py/mjs scripts pattern ends). Gap-filler: a first-class
    `appbox lens eval <url> <js>` verb against the warm session, output
    under the project's evidence dir. Recurring evals are promotion
    candidates, promoted to real verbs only in appbox-dev sessions.

> **Amendment 2026-08-21 — scope is the headline, not the example.** This
> decision's headline ("never write into appbox") and its mechanism clause
> ("read-only `appboxd/`") disagreed on scope. Ratified in favour of the
> headline, and implemented as an **allowlist** rather than a wider denylist:
> in a using-session the whole checkout is read-only except `docs/`,
> `designs/`, `logs/`, where findings are recorded. `appboxd/` was only ever
> the example that produced the `tool/tmp_*.dart` litter — a using-session
> editing `skills/`, `gates/` or `appbox-studio/` is the same defect.
> Enforced per-tool-call by `hooks/appbox-guard.js` (`WRITABLE`) across all
> three harnesses; rationale and the holes this closed are in
> [arxa-harness-and-distribution.md](arxa-harness-and-distribution.md).
> The `lens eval` gap-filler above is unaffected and still owed by W1.

## F. Client-facing islands

13. **Feedback dial (the appbox FAB):** first-party island (ADR-0009
    form) baked into every design artifact. Default on; operator-only
    toggle; clients cannot hide it (watermark role). Art-dial design:
    radial icon-button options, draggable, animated. Supabase Auth
    sign-in gate: design locked until sign-in; on auth the dial animates
    in, with sign-out. Comment, change-list, draw-over (overlay shade +
    canvas), history sidebar. Model: the pub.dev `feedback` package's
    navigate/draw mode toggle, ported to a vanilla-JS shadow-DOM island.
14. **Central Supabase:** one operator-owned project, `design_feedback`
    table, rows tagged {client, project, artifact-version, route,
    viewport}; `auth.uid()`-keyed RLS; realtime `postgres_changes` for
    the operator moderation view. Chat and per-user features ride the
    same auth later.
15. **Lock depth — server-verified on deploys:** the Cloudflare Worker
    serving deployed previews verifies the Supabase JWT before serving
    artifact HTML; the island only owns the sign-in UX. Local
    `appbox design serve` stays open.
16. **Built apps join later:** the pub.dev `feedback` package wired to
    the same pipeline — separate stage, not now.
17. **A11y toolbox:** a SEPARATE, decoupled island (coffee-tech
    "UserAccess"-style: contrast modes, text scaling, stop animations,
    reading rail, dyslexia font, hide images, cursor size…), built for
    clients who request it. The dial may host a demo entry so a client
    can experience it and confirm the request. Framed strictly as a UX
    preference layer — never compliance (FTC fined accessiBe $1M for
    that claim; EAA auditors reject overlays); artifacts must pass the
    real a11y gates regardless.

## G. Media + content (added 2026-08-21, same session)

18. **Real media, licensed:** the designer always sources images/video from
    the stock APIs, never scrapes or copies reference-site media.
    **Pexels is primary** for images AND video — its license permits baking
    downloaded files into delivered client artifacts; one prominent
    "Photos provided by Pexels" credit per artifact + per-photo
    photographer credit. **Unsplash is secondary** (when Pexels search
    falls short) — always hotlinked from the Unsplash CDN (never vendored),
    with the download-event ping per placement and UTM-tagged
    photographer + Unsplash credits, per the API guidelines. Neither
    provider's assets may feed anything resembling a stock-gallery
    feature; avoid identifiable-people shots in endorsement-like contexts.
19. **Asset ledger:** every placed asset is recorded — provider, asset id,
    photographer name + profile URL, page URL, (Unsplash)
    download_location — so credits render from data and compliance is
    auditable per artifact.
20. **Credentials:** `UNSPLASH_ACCESS_KEY`, `UNSPLASH_SECRET_KEY`,
    `PEXELS_API_KEY` are cataloged under `designer/media` in
    `config/credentials.catalog.json`; values live in the OS vault via
    `appbox credentials set` (done 2026-08-21). Never in a tracked file.
21. **Content pass + LLM fallback:** the project's copy is generated ONCE
    at intake/story-map time into a `content.json` artifact (headlines,
    body, CTAs, empty-states per surface, keyed by abx dictionary terms);
    the designer consumes it deterministically. If a slot has no entry,
    the designer may ask the LLM once and MUST write the result back into
    `content.json` — the next run is deterministic. No generic lorem-style
    text library (canned filler is the content twin of the
    semantics-copying defect).

## Workstreams (ordering)

- **W1 — lens core (unblocks everything):** warm Chrome session owned by
  the daemon (kills launch-per-invocation), settle protocol
  (`document.fonts.ready`, double-rAF, animation freeze, optional CDP
  virtual time for gate captures), `lens eval` verb, read-only gate on
  `appboxd/` in using-sessions. Delete the `tool/tmp_*.dart` probes once
  eval lands; promote `lens_click_burst` / `lens_footer_states` into
  verbs or manifest states.
- **W2 — evidence bundle + drill-down compare**, uniform across the four
  media kinds; structured verdict format.
- **W3 — capture manifest:** designer emit + lens manifest runner +
  bounded auto-loop wiring.
- **W4 — abx dictionary + gates** + scaffolder region identity + emitter
  golden-snapshot gate.
- **W5 — feedback dial + Supabase** (schema, RLS, realtime, worker JWT
  middleware in the deployer, operator toggle).
- **W6 — a11y toolbox island** + dial demo entry (request-driven,
  build on first client request).
- **W7 — media + content:** Pexels/Unsplash fetch in the designer with
  the asset ledger + credit rendering; content pass at intake/story-map
  emitting `content.json`; designer consumes ledger + content
  deterministically (LLM fallback writes back).

W1→W3 is the dependency spine; W4 can run parallel after W2's region
tree exists; W5/W6/W7 are independent of W1–W4 (W7's content pass hooks
into the intake/story-map stage).
