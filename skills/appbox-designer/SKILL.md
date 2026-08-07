---
name: appbox-designer
description: >-
  Design an application prototype whose structure the appbox pipeline
  consumes — server-rendered htmx + CSS with zero custom client-side
  JavaScript — named islands only: reusable, vendored, SRI-pinned runtimes
  and first-party glue islands in runtime/vendor/, in a genuine MVVM
  structure: app screens, shells,
  dashboards, interactive prototypes and wireframes, authored at every
  viewport in the active ladder. Use when the user asks to design, mock up,
  prototype, wireframe or visualize an application, product screen or user
  flow that will be scaffolded into a real app. Produces an authored
  `registry.json`, a `surfaceId` in every viewmodel and a route table the
  freeze step can read — one screen registry viewed through three lenses
  (views / flows / proto), flows authored as data edges over it. Not for slide decks or printable documents.
---

# appbox-designer

The design stage of the appbox pipeline. Every artifact is a Hono + htmx MVVM
app with **no ad-hoc client-side JavaScript — named islands only**. An
island is a reusable, vendored script in runtime/vendor/: a third-party
declarative web component (<model-viewer>, <dotlottie-wc>, <lottie-player>)
or a first-party data-attribute init module (canvas.js, drag.js, inspect.js,
dotlottie_island.js, rive_island.js, three_island.js, game_island.js).
Anything outside that registry is banned and linted — the same structure the
scaffolder later emits as Flutter, which is why the prototype can carry
structure rather than pixels.

**What makes this skill different from a generic design tool:** the prototype
you produce is a *typed input to a build pipeline*. Structure is authored while
designing, never back-filled. See
[`references/app-architecture.md`](references/app-architecture.md).

**The triad output.** Every artifact is *three switchable lenses over one
screen registry* — **prototype** (wired navigation over each entry's `route`),
**flows** (journeys as an edge graph), and **screens** (the tile inventory) —
never three separate artifacts. Flows are authored as **data**: `{from, to,
trigger}` edges over registry ids carried through the data spine and rendered
by a server template / named island — never bespoke per-flow markup, never a
separate file format. The freeze threads an optional top-level `flows` array
into `structure.json` (absent = no flows lens, valid for small artifacts); the
scaffolder emits surfaces from the registry screens, the builder wires
navigation from the edges. Binding contract:
[`DESIGN-ARCHITECTURE.md`](DESIGN-ARCHITECTURE.md) "The output triad".

## How to use this skill

**1. Load the methodology.** Read [`system-prompt.md`](system-prompt.md) — the
core design process and craft standards. Follow it for the whole job.
**Consume the brief when one is handed to you.** If the intake stage produced
a design brief, read its **Layout Template** section (the named containers +
per-rung `grid-template-areas`) and consume it **without rewriting** — surfaces
compose into those named containers as given; it is the structure, not a
suggestion.

**2. Load the architecture contract.** Read
[`DESIGN-ARCHITECTURE.md`](DESIGN-ARCHITECTURE.md) — the **binding** contract
for the data spine (seed SSOT → generated fixtures → repositories → facades →
viewmodels/views), the registry canon, the motion vocabulary mapped to CSS/htmx
mechanisms, provenance-not-shape fixtures, and **feedback & state placement**
("Feedback & state placement") — loading, retry, error and toast/snackbar
placement is decided automatically from the registry and flow edges on
*every* artifact this skill produces, never left for the brief to request.
Then read
[`references/app-architecture.md`](references/app-architecture.md) for the
authored layer the pipeline consumes. When the brief mentions
maps/payments/auth/deploy or any kit capability, also read
[`references/kit-catalog.md`](references/kit-catalog.md) — the designer-side
mirror of the kit (declaring `kits`, credentials by name, design-time islands).

**3. Load the viewport ladder.** Read
[`references/viewport-ladder.md`](references/viewport-ladder.md). **Which widths
you author at is derived from the project's targets and read from config — never
assumed, never hardcoded.** Authoring at phone width only is the single most
expensive mistake available here: everything the prototype omits gets invented
downstream by someone who never saw the design.

**4. Load the harness tool reference once.**
[`references/harness-tools.md`](references/harness-tools.md) maps capabilities
(asking questions, previewing, screenshots, verifying) to your harness's tools.

**5. Load the artifact contract.** Read
[`runtime/README.md`](runtime/README.md) and skim
[`examples/hello-hda/`](examples/hello-hda/) — the reference artifact. This is
how every artifact is structured (MVVM: Surface = view template + co-located
ViewModel), served, and kept JS-free.

**6. Load the right built-in skill(s)** from `built-in-skills/` (full list at
the bottom of `system-prompt.md`):
- **Declare structure** (always, while designing) → `declare-structure.md`
  (declare `kits` on surfaces that need a kit module — see its `kits` field section)
- **Wireframes / low-fi** → `wireframe.md`
- **Default (hi-fi / interactive)** → `hi-fi-design.md` + `interactive-prototype.md`
- **Mobile form factor** → `mobile-prototype.md`
- **Design system** setup/use → `design-system-authoring-guide.md` / `use-design-system.md`
- **Eject / productionize** an artifact → `productionize.md`

**7. Ask clarifying questions** (`AskUserQuestion`) for new or ambiguous work —
context, fidelity, variations (see "Asking questions" in `system-prompt.md`).

**8. Set up the output folder.** Ask **where to save** (default
`designs/<descriptive-project-name>/`) and **which design system(s) to use**.
Start every artifact by copying `examples/hello-hda/` and renaming; never
scatter design files in the repo root. Serve the artifact with the Dart
design server — `appbox design serve <artifact-dir> [--port N] [--json]`
(`appboxd/lib/design_server.dart`; artifact JS runs in a headless-Chrome
worker over CDP) — which works without referencing the skill path. Older
designs may still carry a `serve.mjs` shim at the artifact root: it is dead
(the Node runtime it delegated to is archived), so serve those with
`appbox design serve` too; new artifacts do not carry the shim. Import design systems with
`appbox design ds-import` and record deliverables with
`appbox design record-asset` as in `built-in-skills/use-design-system.md`.

**9. Build widgets-first, then serve and verify.** Before composing any
surface, author the artifact's widget library: inventory the design's
repeated patterns and define them as components at the tier their
consumers require (`ui/common/widgets/` cross-shell, `ui/views/<shell>/shared/widgets/`
intra-shell, `<surface>/widgets/` per-surface — see `references/app-architecture.md`),
starting from [`references/ui-recipes.md`](references/ui-recipes.md)
and the drop-in components in `starter-partials/widgets/` — surfaces compose
only from that library. **Auto Layout is default-ON for every widget in
the library** (DESIGN-ARCHITECTURE, "Auto Layout"): each component's container
carries the `data-layout` attribute set and its children size with
`data-resize-x` / `data-resize-y`. To turn it off per frame, omit
`data-layout` (art-directed frames); to exempt a single child, give it
`data-layout-ignore`. Then build the artifact per the contract, serve it with
`appbox design serve <artifact-dir> --port 4319` (background), then
verify: `appbox design lint <artifact-dir>` (no-ad-hoc-JS / named-islands),
`appbox lens check http://localhost:4319/…` (console
clean), and `appbox lens shoot http://localhost:4319/<route>` (**every width in the active ladder**, plus overflow and failed-request checks). Fix
before surfacing; give the user the served URL.

**10. Productionize on request.** `appbox design eject <artifact-dir>
<out-dir>` ejects a self-contained, hardened Hono app — see
`built-in-skills/productionize.md`.

## Requirements

The designer runtimes are **Dart** — the `appbox design` and `appbox lens`
commands (served, linted, captured over the Dart design server + the lens).
Run `appbox design doctor` to preflight the toolchain the gates use. This
requirement applies to the *designer's* machine only — the shipped
appbox desktop app serves prototypes without Node.

## Deliberately absent capabilities

These are JS-bound by nature — do not recreate them:
- **design-canvas pan/zoom** → use `starter-partials/artboards.tsx` (static
  side-by-side comparison page)
- **animation timeline engine**, **animated video**, **video export** → use
  scroll-driven CSS motion studies (`starter-partials/motion.css`)
- **image-slot drag/drop** → use a static placeholder plus the artifact's
  `assets/` folder

Slide decks and printable documents are out of scope. This skill designs
applications.

## Notes

- `system-prompt.md` is the craft SSOT; `runtime/README.md` is the artifact
  contract; `references/ui-recipes.md` is the widget catalog; `CONTEXT.md`
  is the vocabulary; `docs/adr/` holds the runtime decisions.
- **i18n**: when an artifact is localized, every chrome/surface string lives in
  `l10n/app_<locale>.arb` and renders via the `t` prop — never hardcode copy
  in views. Jargon variants are key suffixes (`keyPlain`/`keyTechnical`).
  Localized content is per-locale seeds (`<name>_seed.<locale>.json` is the
  SSOT) generating `<name>_fixtures.<locale>.json`. `appbox design pseudolocalize`
  derives the `qps-ploc` pseudo-locale from English — run it to catch
  truncation and hardcoded strings. Full contract: runtime/README.md "L10n".
- Keep artifacts self-contained: copy every referenced asset into the artifact
  folder; client libraries come only from the runtime's vendored, SRI-pinned set
  (`runtime/vendor/`).
- Licensed MIT — this skill is a fork. See `LICENSE` and the repository's
  `THIRD-PARTY-NOTICES.md`.
